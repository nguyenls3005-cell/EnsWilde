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

    private static var cacheLock = NSLock()
    private static var uuidCache: [String: String] = [:]
    private static var didWarmupCache = false

    private static func normalizedBundleID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("con.lemon.lvoverseas") == .orderedSame {
            return "com.lemon.lvoverseas"
        }
        return trimmed
    }

    var fastPreviewPath: String {
        if let cached = cachedDestinationPath, !cached.isEmpty {
            return cached
        }
        let cleanBundle = Self.normalizedBundleID(bundleID)
        let cleanRel = relativeDestPath.hasPrefix("/")
            ? String(relativeDestPath.dropFirst())
            : relativeDestPath

        if cleanBundle.hasPrefix("/var/") || cleanBundle.hasPrefix("/private/var/") {
            return cleanRel.isEmpty ? cleanBundle : (cleanBundle as NSString).appendingPathComponent(cleanRel)
        }

        let baseRoot = Self.baseContainerPrefix + cleanBundle
        return cleanRel.isEmpty ? baseRoot : (baseRoot as NSString).appendingPathComponent(cleanRel)
    }

    /// Tự quét UUID container cho Bundle ID một cách an toàn (có cache + giới hạn quét)
    static func autoScanContainerUUID(for rawBundleID: String) -> String? {
        let bid = normalizedBundleID(rawBundleID)
        guard !bid.isEmpty else { return nil }

        if bid.hasPrefix("/var/") || bid.hasPrefix("/private/var/") {
            let priv = bid.hasPrefix("/private/") ? bid : "/private" + bid
            return FileManager.default.fileExists(atPath: priv) ? priv : bid
        }

        if bid.hasPrefix("group."),
           let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: bid) {
            return groupURL.path
        }

        let key = bid.lowercased()
        cacheLock.lock()
        if let hit = uuidCache[key], !hit.isEmpty {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        var foundPath: String? = nil

        autoreleasepool {
            // 1. Nạp cache một lần từ JITEnableContext nếu có
            cacheLock.lock()
            let shouldWarmup = !didWarmupCache
            didWarmupCache = true
            cacheLock.unlock()

            if shouldWarmup {
                if let allApps = try? JITEnableContext.shared.getAllAppsInfo() as? [String: Any] {
                    var tempMap: [String: String] = [:]
                    for (appKey, val) in allApps {
                        if let dict = val as? [String: Any],
                           let rawContainer = dict["Container"] as? String,
                           !rawContainer.isEmpty {
                            let clean = rawContainer
                                .replacingOccurrences(of: "file://", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let std = (clean as NSString).standardizingPath
                            let priv = std.hasPrefix("/private/") ? std : "/private" + std
                            tempMap[appKey.lowercased()] = FileManager.default.fileExists(atPath: priv) ? priv : std
                        }
                    }
                    cacheLock.lock()
                    for (k, v) in tempMap {
                        uuidCache[k] = v
                    }
                    cacheLock.unlock()
                }
            }

            cacheLock.lock()
            foundPath = uuidCache[key]
            cacheLock.unlock()
            if foundPath != nil { return }

            // 2. Thử tra nhanh qua CSStoreEngine / fsHandlers
            let (_, fastHit) = CSStoreEngine.shared.lookupAppContainer(forBundleID: bid)
            if let fastHit, !fastHit.isEmpty, FileManager.default.fileExists(atPath: fastHit) {
                foundPath = fastHit
                return
            }

            fsHandlers.invalidateCache()
            let viaHandler = fsHandlers.getContainerPath(at: FSURL.appContainers, forMatch: bid)
            if !viaHandler.isEmpty && FileManager.default.fileExists(atPath: viaHandler) {
                foundPath = viaHandler
                return
            }

            // 3. Quét có giới hạn thư mục trong Data/Application để tìm UUID khớp Bundle ID
            let fm = FileManager.default
            let roots = [
                "/private/var/mobile/Containers/Data/Application",
                "/var/mobile/Containers/Data/Application"
            ]
            for root in roots {
                guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
                for entry in entries.prefix(150) {
                    let fullDir = (root as NSString).appendingPathComponent(entry)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: fullDir, isDirectory: &isDir), isDir.boolValue else { continue }

                    if let xbid = getBIDFromXattr(URL(fileURLWithPath: fullDir)),
                       xbid.caseInsensitiveCompare(bid) == .orderedSame {
                        foundPath = fullDir
                        return
                    }

                    let prefPath = (fullDir as NSString).appendingPathComponent("Library/Preferences/\(bid).plist")
                    if fm.fileExists(atPath: prefPath) {
                        foundPath = fullDir
                        return
                    }

                    let metaPath = (fullDir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                    if fm.fileExists(atPath: metaPath),
                       let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                       let str = String(data: data, encoding: .utf8),
                       str.contains(bid) {
                        foundPath = fullDir
                        return
                    }
                }
            }
        }

        if let foundPath, !foundPath.isEmpty {
            cacheLock.lock()
            uuidCache[key] = foundPath
            cacheLock.unlock()
            return foundPath
        }

        return nil
    }

    func resolveDestinationPathOnBackground() -> String {
        if let cached = cachedDestinationPath, !cached.isEmpty, !cached.contains("/\(Self.normalizedBundleID(bundleID))/") {
            return cached
        }

        let cleanBundle = Self.normalizedBundleID(bundleID)
        let cleanRel = relativeDestPath.hasPrefix("/")
            ? String(relativeDestPath.dropFirst())
            : relativeDestPath

        let baseRoot: String
        if let scannedUUIDDir = Self.autoScanContainerUUID(for: cleanBundle) {
            baseRoot = scannedUUIDDir
        } else if cleanBundle.hasPrefix("/var/") || cleanBundle.hasPrefix("/private/var/") {
            let privateAlt = cleanBundle.hasPrefix("/private/") ? cleanBundle : "/private" + cleanBundle
            baseRoot = FileManager.default.fileExists(atPath: privateAlt) ? privateAlt : cleanBundle
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
        }
    }
    @Published var pendingApply: Bool = false {
        didSet {
            UserDefaults.standard.set(pendingApply, forKey: Self.pendingApplyKey)
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
        isTweakEnabled = ud.bool(forKey: Self.enabledKey)
        pendingApply = ud.bool(forKey: Self.pendingApplyKey)
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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let targetPath = item.resolveDestinationPathOnBackground()
            DispatchQueue.main.async {
                guard let idx = self.patches.firstIndex(where: { $0.id == itemID }) else { return }
                self.patches[idx].cachedDestinationPath = targetPath
                self.savePatches()
                onLog?("[zPatch] Đã tự quét đích: \(targetPath)")
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
            DispatchQueue.global(qos: .utility).async { [weak self] in
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
        let ud = UserDefaults.standard
        let enabledSnapshot = ud.bool(forKey: Self.enabledKey)
        var snapshot: [zPatchItem] = []
        if let data = ud.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([zPatchItem].self, from: data) {
            snapshot = decoded
        }

        let hasPendingRevert = snapshot.contains { $0.pendingRevert }
        guard enabledSnapshot || hasPendingRevert else {
            onLog("[zPatch] Tweak đang tắt và không có mục chờ Revert, bỏ qua.")
            DispatchQueue.main.async {
                self.pendingApply = false
            }
            return
        }

        for idx in snapshot.indices {
            let targetPath = snapshot[idx].resolveDestinationPathOnBackground()
            snapshot[idx].cachedDestinationPath = targetPath
            let targetURL = URL(fileURLWithPath: targetPath)

            if snapshot[idx].pendingRevert {
                guard let backupPath = snapshot[idx].backupPath,
                      FileManager.default.fileExists(atPath: backupPath) else {
                    onLog("[zPatch] Thiếu file backup để revert: \(targetPath)")
                    snapshot[idx].pendingRevert = false
                    continue
                }

                let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
                let (ok, writeErr) = overwriteFileDirectly(backupData, to: targetURL)
                if ok {
                    snapshot[idx].pendingRevert = false
                    onLog("[zPatch] Đã ghi đè revert: \(targetPath)")
                } else {
                    onLog("[zPatch] Revert ghi đè lỗi: \(writeErr)")
                }
                continue
            }

            if enabledSnapshot && snapshot[idx].isEnabled {
                let bURL = backupFileURL(for: snapshot[idx], targetPath: targetPath)
                if (!snapshot[idx].hasInitialBackup || snapshot[idx].backupPath == nil),
                   FileManager.default.fileExists(atPath: targetPath),
                   let ogData = try? Data(contentsOf: targetURL) {
                    try? FileManager.default.createDirectory(at: bURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? ogData.write(to: bURL, options: .atomic)
                    snapshot[idx].backupPath = bURL.path
                    snapshot[idx].hasInitialBackup = true
                }

                let sourceData = try Data(contentsOf: URL(fileURLWithPath: snapshot[idx].sourcePath))
                let (ok, writeErr) = overwriteFileDirectly(sourceData, to: targetURL)
                if ok {
                    onLog("[zPatch] Đã ghi đè patch: \(targetPath)")
                } else {
                    onLog("[zPatch] Apply ghi đè lỗi: \(writeErr)")
                }
            }
        }

        let finalSnapshot = snapshot
        if let encoded = try? JSONEncoder().encode(finalSnapshot) {
            ud.set(encoded, forKey: Self.itemsKey)
        }

        DispatchQueue.main.async {
            self.patches = finalSnapshot
            self.pendingApply = false
        }
    }

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
