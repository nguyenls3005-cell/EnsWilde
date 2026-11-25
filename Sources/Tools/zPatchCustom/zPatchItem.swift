import Foundation
import Combine
import Darwin

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
        var cleanBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBundle == "con.lemon.lvoverseas" {
            cleanBundle = "com.lemon.lvoverseas"
        }
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

        // 1. Ưu tiên lấy trực tiếp Container UUID từ JITEnableContext.getAllAppsInfo()
        if let allApps = try? JITEnableContext.shared.getAllAppsInfo() as? [String: [String: Any]] {
            let matchedEntry = allApps[trimmed] ?? allApps.first {
                $0.key.caseInsensitiveCompare(trimmed) == .orderedSame
            }?.value

            if let appInfo = matchedEntry,
               let rawContainer = appInfo["Container"] as? String,
               !rawContainer.isEmpty {
                let cleanContainer = rawContainer
                    .replacingOccurrences(of: "file://", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let stdPath = (cleanContainer as NSString).standardizingPath
                if FileManager.default.fileExists(atPath: stdPath) {
                    return stdPath
                }
                let privateAlt = stdPath.hasPrefix("/private/") ? stdPath : "/private" + stdPath
                if FileManager.default.fileExists(atPath: privateAlt) {
                    return privateAlt
                }
                return stdPath
            }
        }

        // 2. Fallback qua CSStoreEngine
        let (_, fastHit) = CSStoreEngine.shared.lookupAppContainer(forBundleID: trimmed)
        if let fastHit, !fastHit.isEmpty, FileManager.default.fileExists(atPath: fastHit) {
            return fastHit
        }

        // 3. Fallback qua fsHandlers
        fsHandlers.invalidateCache()
        let viaHandler = fsHandlers.getContainerPath(at: FSURL.appContainers, forMatch: trimmed)
        if !viaHandler.isEmpty && FileManager.default.fileExists(atPath: viaHandler) {
            return viaHandler
        }

        // 4. Quét trực tiếp thư mục container nếu có quyền đọc danh sách
        let roots = [
            "/private/var/mobile/Containers/Data/Application",
            "/var/mobile/Containers/Data/Application",
            "/private/var/mobile/Containers/Shared/AppGroup",
            "/var/mobile/Containers/Shared/AppGroup"
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

                let metaPath = (fullDir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                if fm.fileExists(atPath: metaPath),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                   let text = String(data: data, encoding: .utf8),
                   text.contains(trimmed) {
                    return fullDir
                }

                let prefPath = (fullDir as NSString).appendingPathComponent("Library/Preferences/\(trimmed).plist")
                if fm.fileExists(atPath: prefPath) {
                    return fullDir
                }
            }
        }

        return nil
    }

    func resolveDestinationPathOnBackground() -> String {
        var cleanBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBundle == "con.lemon.lvoverseas" {
            cleanBundle = "com.lemon.lvoverseas"
        }

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
    @Published var isTweakEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isTweakEnabled, forKey: Self.enabledKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published var pendingApply: Bool = false {
        didSet {
            UserDefaults.standard.set(pendingApply, forKey: Self.pendingApplyKey)
            UserDefaults.standard.synchronize()
        }
    }

    private var hasLoaded = false

    init() {
        reloadFromStorage()
    }

    func ensureLoaded() {
        guard !hasLoaded else { return }
        reloadFromStorage()
    }

    func reloadFromStorage() {
        let ud = UserDefaults.standard
        _isTweakEnabled = Published(initialValue: ud.bool(forKey: Self.enabledKey))
        _pendingApply = Published(initialValue: ud.bool(forKey: Self.pendingApplyKey))
        if let data = ud.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([zPatchItem].self, from: data) {
            patches = decoded
        } else {
            patches = []
        }
        hasLoaded = true
    }

    func setTweakEnabledImmediate(_ enabled: Bool) {
        isTweakEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        UserDefaults.standard.synchronize()
    }

    func savePatches() {
        if let encoded = try? JSONEncoder().encode(patches) {
            UserDefaults.standard.set(encoded, forKey: Self.itemsKey)
            UserDefaults.standard.synchronize()
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

    private func grantAccessForOverwrite(_ targetPath: String) -> (Bool, [String], String) {
        var grantedPaths: [String] = []
        var lastErr = ""

        // 1. Xin quyền trực tiếp trên file đích để ghi đè
        let (okDirect, _, errDirect) = wq.grantAccess(path: targetPath, requireWrite: false)
        if okDirect {
            grantedPaths.append(targetPath)
            return (true, grantedPaths, "succeeded")
        }
        lastErr = errDirect

        // 2. Xin quyền thư mục cha gần nhất
        var cur = URL(fileURLWithPath: targetPath).resolvingSymlinksInPath().path
        while !cur.isEmpty && cur != "/" {
            let parent = (cur as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == cur { break }
            if FileManager.default.fileExists(atPath: parent) {
                let (okParent, _, errParent) = wq.grantAccess(path: parent, requireWrite: false)
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
            let (granted, usedPaths, errMsg) = self.grantAccessForOverwrite(targetPath)
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
                onLog?("[zPatch/wq] Target resolved: \(targetPath) (\(errMsg))")
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
        pendingApply = true
    }

    func saveChange(enableTweak: Bool) {
        setTweakEnabledImmediate(enableTweak)
        savePatches()
        pendingApply = true
    }

    func applyAllUsingWorseQuery(onLog: @escaping (String) -> Void) throws {
        reloadFromStorage()
        let hasPendingRevert = patches.contains { $0.pendingRevert }
        guard isTweakEnabled || hasPendingRevert else {
            onLog("[zPatch] Tweak đang tắt và không có mục chờ Revert, bỏ qua.")
            pendingApply = false
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

                let (granted, usedPaths, errMsg) = grantAccessForOverwrite(targetPath)
                defer { releaseGrantedPaths(usedPaths) }
                if !granted {
                    onLog("[zPatch/wq] Cảnh báo grant (\(targetPath)): \(errMsg)")
                }

                let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
                let (ok, writeErr) = overwriteFileDirectly(backupData, to: targetURL)
                if ok {
                    patches[idx].pendingRevert = false
                    onLog("[zPatch/wq] Đã ghi đè revert về bản gốc: \(targetPath)")
                } else {
                    onLog("[zPatch/wq] Revert ghi đè thất bại: \(writeErr)")
                }
                continue
            }

            if isTweakEnabled && patches[idx].isEnabled {
                let (granted, usedPaths, errMsg) = grantAccessForOverwrite(targetPath)
                defer { releaseGrantedPaths(usedPaths) }
                if !granted {
                    onLog("[zPatch/wq] Cảnh báo grant (\(targetPath)): \(errMsg)")
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
                let (ok, writeErr) = overwriteFileDirectly(sourceData, to: targetURL)
                if ok {
                    onLog("[zPatch/wq] Đã ghi đè patch: \(targetPath)")
                } else {
                    onLog("[zPatch/wq] Apply ghi đè thất bại: \(writeErr)")
                }
            }
        }

        savePatches()
        pendingApply = false
    }

    /// Ghi đè trực tiếp lên file đích bằng open + pwrite + ftruncate + fsync
    private func overwriteFileDirectly(_ data: Data, to url: URL) -> (Bool, String) {
        let path = url.path
        let fm = FileManager.default

        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let createdFd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if createdFd >= 0 {
                defer { close(createdFd) }
                let ok = writeAllBytes(data, toFd: createdFd)
                if ok {
                    fsync(createdFd)
                    return (true, "OK")
                }
            }
            if fm.createFile(atPath: path, contents: data) {
                return (true, "OK")
            }
            return (false, "Không tạo được file mới tại \(path) (errno=\(errno): \(String(cString: strerror(errno))))")
        }

        let fd = open(path, O_WRONLY)
        if fd >= 0 {
            defer { close(fd) }
            guard writeAllBytes(data, toFd: fd) else {
                return (false, "pwrite lỗi tại \(path) (errno=\(errno): \(String(cString: strerror(errno))))")
            }
            if ftruncate(fd, off_t(data.count)) != 0 {
                return (false, "ftruncate lỗi tại \(path) (errno=\(errno): \(String(cString: strerror(errno))))")
            }
            fsync(fd)
            return (true, "OK")
        }

        let openErr = String(cString: strerror(errno))
        do {
            try data.write(to: url, options: .noFileProtection)
            return (true, "OK")
        } catch {
            return (false, "open(\(path)) lỗi: \(openErr) | write lỗi: \(error.localizedDescription)")
        }
    }

    private func writeAllBytes(_ data: Data, toFd fd: Int32) -> Bool {
        return data.withUnsafeBytes { rawBuf -> Bool in
            guard let base = rawBuf.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < rawBuf.count {
                let written = pwrite(fd, base.advanced(by: offset), rawBuf.count - offset, off_t(offset))
                if written <= 0 {
                    return false
                }
                offset += written
            }
            return true
        }
    }

    func clearPendingApply() {
        pendingApply = false
    }
}
