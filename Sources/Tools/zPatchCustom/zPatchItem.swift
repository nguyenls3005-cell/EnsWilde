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

    static func normalizedBundleID(_ raw: String) -> String {
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

        if let mappedContainer = zPatchStore.shared.cachedContainer(for: cleanBundle) {
            return cleanRel.isEmpty ? mappedContainer : (mappedContainer as NSString).appendingPathComponent(cleanRel)
        }

        if cleanBundle.hasPrefix("/") {
            return cleanRel.isEmpty ? cleanBundle : (cleanBundle as NSString).appendingPathComponent(cleanRel)
        }

        let baseRoot = Self.baseContainerPrefix + cleanBundle
        return cleanRel.isEmpty ? baseRoot : (baseRoot as NSString).appendingPathComponent(cleanRel)
    }

    func resolveDestinationPath() -> String {
        let cleanBundle = Self.normalizedBundleID(bundleID)
        let cleanRel = relativeDestPath.hasPrefix("/")
            ? String(relativeDestPath.dropFirst())
            : relativeDestPath

        // 1. Nếu đã có đường dẫn UUID thật trong cache thì ưu tiên dùng ngay
        if let cached = cachedDestinationPath,
           !cached.isEmpty,
           !cached.contains("/\(cleanBundle)/") {
            return cached
        }

        // 2. Lấy từ bảng map container đã nạp an toàn trong zPatchStore
        if let mappedContainer = zPatchStore.shared.cachedContainer(for: cleanBundle),
           !mappedContainer.isEmpty {
            return cleanRel.isEmpty ? mappedContainer : (mappedContainer as NSString).appendingPathComponent(cleanRel)
        }

        // 3. Nếu người dùng nhập sẵn đường dẫn tuyệt đối (chứa UUID)
        if cleanBundle.hasPrefix("/") {
            let priv = cleanBundle.hasPrefix("/private/") ? cleanBundle : "/private" + cleanBundle
            let root = FileManager.default.fileExists(atPath: priv) ? priv : cleanBundle
            return cleanRel.isEmpty ? root : (root as NSString).appendingPathComponent(cleanRel)
        }

        // 4. App Group chuẩn của hệ thống
        if cleanBundle.hasPrefix("group."),
           let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: cleanBundle) {
            return cleanRel.isEmpty ? groupURL.path : (groupURL.path as NSString).appendingPathComponent(cleanRel)
        }

        let varPath = Self.baseContainerPrefix + cleanBundle
        let privateVarPath = "/private" + varPath
        let baseRoot = FileManager.default.fileExists(atPath: privateVarPath) ? privateVarPath : varPath
        return cleanRel.isEmpty ? baseRoot : (baseRoot as NSString).appendingPathComponent(cleanRel)
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
    static let containerMapKey = "zPatchContainerMap_v1"

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

    private let mapLock = NSLock()
    private var containerMap: [String: String] = [:]
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

        if let savedMap = ud.dictionary(forKey: Self.containerMapKey) as? [String: String] {
            mapLock.lock()
            containerMap = savedMap
            mapLock.unlock()
        }

        if let data = ud.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([zPatchItem].self, from: data) {
            patches = decoded
        } else {
            patches = []
        }
        hasLoaded = true
    }

    /// Gọi từ AppListView khi danh sách app đã load xong để lưu cache bundleID -> Container UUID
    func updateContainerCache(from appsInfo: [String: [String: Any]]) {
        var updated: [String: String] = [:]
        for (bid, info) in appsInfo {
            if let raw = info["Container"] as? String, !raw.isEmpty {
                let clean = raw
                    .replacingOccurrences(of: "file://", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let std = (clean as NSString).standardizingPath
                if !std.isEmpty {
                    updated[bid.lowercased()] = std
                }
            }
        }
        guard !updated.isEmpty else { return }

        mapLock.lock()
        for (k, v) in updated {
            containerMap[k] = v
        }
        let snapshot = containerMap
        mapLock.unlock()

        UserDefaults.standard.set(snapshot, forKey: Self.containerMapKey)
    }

    func registerContainer(bundleID: String, containerPath: String) {
        let key = zPatchItem.normalizedBundleID(bundleID).lowercased()
        let clean = containerPath
            .replacingOccurrences(of: "file://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !clean.isEmpty else { return }

        mapLock.lock()
        containerMap[key] = (clean as NSString).standardizingPath
        let snapshot = containerMap
        mapLock.unlock()

        UserDefaults.standard.set(snapshot, forKey: Self.containerMapKey)
    }

    func cachedContainer(for bundleID: String) -> String? {
        let key = zPatchItem.normalizedBundleID(bundleID).lowercased()
        mapLock.lock()
        let val = containerMap[key]
        mapLock.unlock()
        return val
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

    private func isResolvedContainerPath(_ path: String, bundleID: String) -> Bool {
        let cleanBundle = zPatchItem.normalizedBundleID(bundleID)
        if cleanBundle.hasPrefix("/") { return true }
        return !path.contains("/\(cleanBundle)/")
    }

    private func grantAccessSafely(_ targetPath: String, bundleID: String) -> (Bool, [String], String) {
        guard isResolvedContainerPath(targetPath, bundleID: bundleID) else {
            return (false, [], "Chưa có UUID container cho \(bundleID). Hãy mở danh sách App trong app một lần để nạp UUID.")
        }

        var granted: [String] = []
        let (okFile, _, errFile) = wq.grantAccess(path: targetPath, requireWrite: false)
        if okFile {
            granted.append(targetPath)
            return (true, granted, "OK")
        }

        let parent = (targetPath as NSString).deletingLastPathComponent
        if !parent.isEmpty && parent != "/" {
            let (okParent, _, errParent) = wq.grantAccess(path: parent, requireWrite: false)
            if okParent {
                granted.append(parent)
                return (true, granted, "OK")
            }
            return (false, granted, errParent)
        }

        return (false, granted, errFile)
    }

    private func releaseAccessSafely(_ paths: [String]) {
        for p in paths {
            wq.releaseAccess(path: p)
        }
    }

    func saveNewPatch(bundleID: String, relativeDestPath: String, sourcePath: String, onLog: ((String) -> Void)? = nil) {
        var item = zPatchItem(
            bundleID: bundleID,
            relativeDestPath: relativeDestPath,
            sourcePath: sourcePath,
            hasInitialBackup: false,
            isEnabled: true,
            pendingRevert: false
        )
        let resolved = item.resolveDestinationPath()
        item.cachedDestinationPath = resolved

        patches.append(item)
        savePatches()
        onLog?("[zPatch] Đã lưu patch: \(resolved)")
    }

    func updatePatch(_ patch: zPatchItem) {
        if let idx = patches.firstIndex(where: { $0.id == patch.id }) {
            var updated = patch
            updated.cachedDestinationPath = nil
            updated.cachedDestinationPath = updated.resolveDestinationPath()
            patches[idx] = updated
            savePatches()
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

        let fm = FileManager.default
        for idx in snapshot.indices {
            let targetPath = snapshot[idx].resolveDestinationPath()
            snapshot[idx].cachedDestinationPath = targetPath
            let targetURL = URL(fileURLWithPath: targetPath)

            if snapshot[idx].pendingRevert {
                guard let backupPath = snapshot[idx].backupPath, fm.fileExists(atPath: backupPath) else {
                    onLog("[zPatch] Thiếu file backup để revert: \(targetPath)")
                    snapshot[idx].pendingRevert = false
                    continue
                }

                let (granted, usedPaths, grantMsg) = grantAccessSafely(targetPath, bundleID: snapshot[idx].bundleID)
                defer { releaseAccessSafely(usedPaths) }
                if !granted {
                    onLog("[zPatch] Cảnh báo quyền (\(targetPath)): \(grantMsg)")
                }

                do {
                    let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
                    try overwriteDirectly(backupData, to: targetURL)
                    snapshot[idx].pendingRevert = false
                    onLog("[zPatch] Đã revert: \(targetPath)")
                } catch {
                    onLog("[zPatch] Revert lỗi: \(error.localizedDescription)")
                }
                continue
            }

            if enabledSnapshot && snapshot[idx].isEnabled {
                guard fm.fileExists(atPath: snapshot[idx].sourcePath) else {
                    onLog("[zPatch] File nguồn không tồn tại: \(snapshot[idx].sourcePath)")
                    continue
                }

                let (granted, usedPaths, grantMsg) = grantAccessSafely(targetPath, bundleID: snapshot[idx].bundleID)
                defer { releaseAccessSafely(usedPaths) }
                if !granted {
                    onLog("[zPatch] Cảnh báo quyền (\(targetPath)): \(grantMsg)")
                }

                do {
                    let bURL = backupFileURL(for: snapshot[idx], targetPath: targetPath)
                    if (!snapshot[idx].hasInitialBackup || snapshot[idx].backupPath == nil),
                       fm.fileExists(atPath: targetPath),
                       let ogData = try? Data(contentsOf: targetURL) {
                        try? fm.createDirectory(at: bURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? ogData.write(to: bURL)
                        snapshot[idx].backupPath = bURL.path
                        snapshot[idx].hasInitialBackup = true
                    }

                    let sourceData = try Data(contentsOf: URL(fileURLWithPath: snapshot[idx].sourcePath))
                    try overwriteDirectly(sourceData, to: targetURL)
                    onLog("[zPatch] Đã ghi đè thành công: \(targetPath)")
                } catch {
                    onLog("[zPatch] Ghi đè thất bại (\(targetPath)): \(error.localizedDescription)")
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

    private func overwriteDirectly(_ data: Data, to url: URL) throws {
        let path = url.path
        let fm = FileManager.default

        if !fm.fileExists(atPath: path) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let createdFd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if createdFd >= 0 {
                defer { close(createdFd) }
                try writeAll(data, fd: createdFd)
                fsync(createdFd)
                return
            }
            try data.write(to: url, options: .noFileProtection)
            return
        }

        let fd = open(path, O_WRONLY)
        if fd >= 0 {
            defer { close(fd) }
            try writeAll(data, fd: fd)
            if ftruncate(fd, off_t(data.count)) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                    NSLocalizedDescriptionKey: "ftruncate lỗi: \(String(cString: strerror(errno)))"
                ])
            }
            fsync(fd)
            return
        }

        try data.write(to: url, options: .noFileProtection)
    }

    private func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var offset = 0
            while offset < rawBuf.count {
                let written = pwrite(fd, base.advanced(by: offset), rawBuf.count - offset, off_t(offset))
                if written <= 0 {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                        NSLocalizedDescriptionKey: "pwrite lỗi: \(String(cString: strerror(errno)))"
                    ])
                }
                offset += written
            }
        }
    }

    func clearPendingApply() {
        pendingApply = false
    }
}
