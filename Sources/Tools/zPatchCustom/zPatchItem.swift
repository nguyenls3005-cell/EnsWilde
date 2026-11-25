import Foundation
import Combine

struct zPatchItem: Identifiable, Codable {
    var id: UUID
    var bundleID: String
    var relativeDestPath: String
    var sourcePath: String
    var cachedDestinationPath: String?
    var backupPath: String?
    var hasInitialBackup: Bool
    var isEnabled: Bool
    var pendingRevert: Bool
    var createdDate: Date

    static let baseContainerPrefix = "/var/mobile/Containers/Data/Application/"

    var fastPreviewPath: String {
        if let cached = cachedDestinationPath, !cached.isEmpty {
            return cached
        }
        let cleanBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRel = relativeDestPath.hasPrefix("/")
            ? String(relativeDestPath.dropFirst())
            : relativeDestPath

        if cleanBundle.hasPrefix("/var/") || cleanBundle.hasPrefix("/private/var/") {
            return cleanRel.isEmpty ? cleanBundle : (cleanBundle as NSString).appendingPathComponent(cleanRel)
        }

        let baseRoot = Self.baseContainerPrefix + cleanBundle
        return cleanRel.isEmpty ? baseRoot : (baseRoot as NSString).appendingPathComponent(cleanRel)
    }

    private func findRealContainerPath(for bundleID: String) -> String? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("group."),
           let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: trimmed) {
            return groupURL.path
        }

        let (_, fastHit) = CSStoreEngine.shared.lookupAppContainer(forBundleID: trimmed)
        if let fastHit, !fastHit.isEmpty, FileManager.default.fileExists(atPath: fastHit) {
            return fastHit
        }

        fsHandlers.invalidateCache()
        let viaHandler = fsHandlers.getContainerPath(at: FSURL.appContainers, forMatch: trimmed)
        if !viaHandler.isEmpty && FileManager.default.fileExists(atPath: viaHandler) {
            return viaHandler
        }

        let roots = [
            "/var/mobile/Containers/Data/Application",
            "/private/var/mobile/Containers/Data/Application",
            "/var/mobile/Containers/Shared/AppGroup",
            "/private/var/mobile/Containers/Shared/AppGroup"
        ]
        let fm = FileManager.default

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries {
                let fullDir = (root as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullDir, isDirectory: &isDir), isDir.boolValue else { continue }

                if let xbid = getBIDFromXattr(URL(fileURLWithPath: fullDir)),
                   xbid.caseInsensitiveCompare(trimmed) == .orderedSame {
                    return fullDir
                }

                let metaCandidates = [
                    ".com.apple.mobile_container_manager.metadata.plist",
                    "Library/Preferences/\(trimmed).plist"
                ]
                for metaRel in metaCandidates {
                    let metaPath = (fullDir as NSString).appendingPathComponent(metaRel)
                    if fm.fileExists(atPath: metaPath) {
                        if metaRel.hasSuffix(".plist") && !metaRel.contains("metadata") {
                            return fullDir
                        }
                        if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                           let text = String(data: data, encoding: .utf8),
                           text.contains(trimmed) {
                            return fullDir
                        }
                    }
                }
            }
        }

        return nil
    }

    func resolveDestinationPathOnBackground() -> String {
        let cleanBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRel = relativeDestPath.hasPrefix("/")
            ? String(relativeDestPath.dropFirst())
            : relativeDestPath

        let baseRoot: String
        if cleanBundle.hasPrefix("/var/") || cleanBundle.hasPrefix("/private/var/") {
            let privateAlt = cleanBundle.hasPrefix("/private/") ? cleanBundle : "/private" + cleanBundle
            baseRoot = FileManager.default.fileExists(atPath: privateAlt) ? privateAlt : cleanBundle
        } else if let realContainer = findRealContainerPath(for: cleanBundle) {
            baseRoot = realContainer
        } else {
            let varPath = Self.baseContainerPrefix + cleanBundle
            let privateVarPath = "/private" + varPath
            baseRoot = FileManager.default.fileExists(atPath: privateVarPath) ? privateVarPath : varPath
        }

        if cleanRel.isEmpty { return baseRoot }
        return (baseRoot as NSString).appendingPathComponent(cleanRel)
    }

    init(
        id: UUID = UUID(),
        bundleID: String,
        relativeDestPath: String,
        sourcePath: String,
        cachedDestinationPath: String? = nil,
        backupPath: String? = nil,
        hasInitialBackup: Bool = false,
        isEnabled: Bool = true,
        pendingRevert: Bool = false
    ) {
        self.id = id
        self.bundleID = bundleID
        self.relativeDestPath = relativeDestPath
        self.sourcePath = sourcePath
        self.cachedDestinationPath = cachedDestinationPath
        self.backupPath = backupPath
        self.hasInitialBackup = hasInitialBackup
        self.isEnabled = isEnabled
        self.pendingRevert = pendingRevert
        self.createdDate = Date()
    }
}

final class zPatchStore: ObservableObject {
    static let shared = zPatchStore()

    static let itemsKey = "zPatchCustomItems_v3"
    static let enabledKey = "zPatchCustomEnabled"
    static let pendingApplyKey = "zPatchPendingApply"

    @Published var patches: [zPatchItem] = []
    @Published var isTweakEnabled: Bool = false
    @Published var pendingApply: Bool = false
    private var hasLoaded = false

    init() {
        isTweakEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        pendingApply = UserDefaults.standard.bool(forKey: Self.pendingApplyKey)
    }

    func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reloadFromStorage()
    }

    func reloadFromStorage() {
        isTweakEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        pendingApply = UserDefaults.standard.bool(forKey: Self.pendingApplyKey)
        if let data = UserDefaults.standard.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([zPatchItem].self, from: data) {
            patches = decoded
        } else {
            patches = []
        }
        hasLoaded = true
    }

    func savePatches() {
        if let encoded = try? JSONEncoder().encode(patches) {
            UserDefaults.standard.set(encoded, forKey: Self.itemsKey)
        }
    }

    private func backupFileURL(for item: zPatchItem, targetPath: String) -> URL {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupDir = docsURL
            .appendingPathComponent("zPatchBackups", isDirectory: true)
            .appendingPathComponent(item.id.uuidString, isDirectory: true)
        let name = URL(fileURLWithPath: targetPath).lastPathComponent
        return backupDir.appendingPathComponent(name.isEmpty ? "target.bin" : name)
    }

    private func grantAccessForAnySupportPath(_ targetPath: String, requireWrite: Bool) -> (Bool, [String], String) {
        var grantedPaths: [String] = []
        var lastErr = ""

        let (okDirect, _, errDirect) = wq.grantAccess(path: targetPath, requireWrite: requireWrite)
        if okDirect {
            grantedPaths.append(targetPath)
            return (true, grantedPaths, "succeeded")
        }
        lastErr = errDirect

        var cur = URL(fileURLWithPath: targetPath).resolvingSymlinksInPath().path
        while !cur.isEmpty && cur != "/" {
            let parent = (cur as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == cur { break }
            if FileManager.default.fileExists(atPath: parent) {
                let (okParent, _, errParent) = wq.grantAccess(path: parent, requireWrite: requireWrite)
                if okParent {
                    grantedPaths.append(parent)
                    return (true, grantedPaths, "succeeded")
                }
                lastErr = errParent
            }
            cur = parent
        }

        return (false, grantedPaths, lastErr)
    }

    private func releaseGrantedPaths(_ paths: [String]) {
        for p in paths {
            wq.releaseAccess(path: p)
        }
    }

    func saveNewPatch(bundleID: String, relativeDestPath: String, sourcePath: String, onLog: ((String) -> Void)? = nil) {
        let item = zPatchItem(
            bundleID: bundleID,
            relativeDestPath: relativeDestPath,
            sourcePath: sourcePath,
            hasInitialBackup: false,
            isEnabled: true,
            pendingRevert: false
        )

        patches.append(item)
        savePatches()

        let itemID = item.id
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let targetPath = item.resolveDestinationPathOnBackground()
            let bURL = self.backupFileURL(for: item, targetPath: targetPath)

            var backupSavedPath: String? = nil
            let (granted, usedPaths, errMsg) = self.grantAccessForAnySupportPath(targetPath, requireWrite: false)
            defer { self.releaseGrantedPaths(usedPaths) }

            if granted, FileManager.default.fileExists(atPath: targetPath),
               let originalData = try? Data(contentsOf: URL(fileURLWithPath: targetPath)) {
                do {
                    try FileManager.default.createDirectory(at: bURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try originalData.write(to: bURL, options: .atomic)
                    backupSavedPath = bURL.path
                    onLog?("[zPatch/wq] Đã backup lần đầu: \(targetPath)")
                } catch {
                    onLog?("[zPatch/wq] Ghi backup lỗi: \(error.localizedDescription)")
                }
            } else {
                onLog?("[zPatch/wq] Chưa có file gốc để backup tại: \(targetPath) (\(errMsg))")
            }

            DispatchQueue.main.async {
                guard let idx = self.patches.firstIndex(where: { $0.id == itemID }) else { return }
                self.patches[idx].cachedDestinationPath = targetPath
                if let backupSavedPath {
                    self.patches[idx].backupPath = backupSavedPath
                    self.patches[idx].hasInitialBackup = true
                }
                self.savePatches()
            }
        }
    }

    func updatePatch(_ patch: zPatchItem) {
        if let idx = patches.firstIndex(where: { $0.id == patch.id }) {
            var updated = patch
            updated.cachedDestinationPath = nil
            patches[idx] = updated
            savePatches()

            let itemID = updated.id
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let resolved = updated.resolveDestinationPathOnBackground()
                DispatchQueue.main.async {
                    if let currentIdx = self.patches.firstIndex(where: { $0.id == itemID }) {
                        self.patches[currentIdx].cachedDestinationPath = resolved
                        self.savePatches()
                    }
                }
            }
        }
    }

    func removePatch(_ patch: zPatchItem) {
        if let backupPath = patch.backupPath {
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        patches.removeAll { $0.id == patch.id }
        savePatches()
    }

    func togglePatch(_ patch: zPatchItem) {
        if let idx = patches.firstIndex(where: { $0.id == patch.id }) {
            patches[idx].isEnabled.toggle()
            if patches[idx].isEnabled {
                patches[idx].pendingRevert = false
            }
            savePatches()
        }
    }

    func requestRevert(_ patch: zPatchItem) {
        guard let idx = patches.firstIndex(where: { $0.id == patch.id }) else { return }
        patches[idx].isEnabled = false
        patches[idx].pendingRevert = true
        savePatches()
        setPendingApply(true)
    }

    func saveChange(enableTweak: Bool) {
        isTweakEnabled = enableTweak
        UserDefaults.standard.set(enableTweak, forKey: Self.enabledKey)
        savePatches()
        setPendingApply(true)
    }

    func applyAllUsingWorseQuery(onLog: @escaping (String) -> Void) throws {
        reloadFromStorage()
        let hasPendingRevert = patches.contains { $0.pendingRevert }
        guard isTweakEnabled || hasPendingRevert else {
            onLog("[zPatch] Tweak đang tắt và không có mục chờ Revert, bỏ qua.")
            setPendingApply(false)
            return
        }

        for idx in patches.indices {
            let targetPath = patches[idx].resolveDestinationPathOnBackground()
            patches[idx].cachedDestinationPath = targetPath
            let targetURL = URL(fileURLWithPath: targetPath)

            if patches[idx].pendingRevert {
                guard let backupPath = patches[idx].backupPath,
                      FileManager.default.fileExists(atPath: backupPath) else {
                    onLog("[zPatch/wq] Thiếu file backup để revert: \(targetPath)")
                    patches[idx].pendingRevert = false
                    continue
                }

                let (granted, usedPaths, errMsg) = grantAccessForAnySupportPath(targetPath, requireWrite: false)
                defer { releaseGrantedPaths(usedPaths) }
                guard granted else {
                    onLog("[zPatch/wq] Không xin được quyền revert (\(targetPath)): \(errMsg)")
                    continue
                }

                let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
                let (ok, writeErr) = writePayload(backupData, to: targetURL)
                if ok {
                    patches[idx].pendingRevert = false
                    onLog("[zPatch/wq] Đã revert về bản gốc: \(targetPath)")
                } else {
                    onLog("[zPatch/wq] Revert ghi file thất bại: \(writeErr)")
                }
                continue
            }

            if isTweakEnabled && patches[idx].isEnabled {
                let (granted, usedPaths, errMsg) = grantAccessForAnySupportPath(targetPath, requireWrite: false)
                defer { releaseGrantedPaths(usedPaths) }
                guard granted else {
                    onLog("[zPatch/wq] Không xin được quyền (\(targetPath)): \(errMsg)")
                    continue
                }

                let bURL = backupFileURL(for: patches[idx], targetPath: targetPath)
                if (!patches[idx].hasInitialBackup || patches[idx].backupPath == nil),
                   FileManager.default.fileExists(atPath: targetPath),
                   let ogData = try? Data(contentsOf: targetURL) {
                    try? FileManager.default.createDirectory(at: bURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? ogData.write(to: bURL, options: .atomic)
                    patches[idx].backupPath = bURL.path
                    patches[idx].hasInitialBackup = true
                }

                let sourceData = try Data(contentsOf: URL(fileURLWithPath: patches[idx].sourcePath))
                let (ok, writeErr) = writePayload(sourceData, to: targetURL)
                if ok {
                    onLog("[zPatch/wq] Đã apply patch: \(targetPath)")
                } else {
                    onLog("[zPatch/wq] Apply ghi file thất bại: \(writeErr)")
                }
            }
        }

        savePatches()
        setPendingApply(false)
    }

    private func writePayload(_ data: Data, to url: URL) -> (Bool, String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            return writeFileAtomically(data, to: url, allowEmpty: false)
        } else {
            return writeFileTemp(data, to: url)
        }
    }

    func clearPendingApply() {
        setPendingApply(false)
    }

    private func setPendingApply(_ value: Bool) {
        pendingApply = value
        UserDefaults.standard.set(value, forKey: Self.pendingApplyKey)
    }
}
