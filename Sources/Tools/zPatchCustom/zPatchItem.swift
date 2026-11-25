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

    func resolveDestinationPathOnBackground() -> String {
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
            let privateAlt = cleanBundle.hasPrefix("/private/") ? cleanBundle : "/private" + cleanBundle
            let baseRoot = FileManager.default.fileExists(atPath: privateAlt) ? privateAlt : cleanBundle
            return cleanRel.isEmpty ? baseRoot : (baseRoot as NSString).appendingPathComponent(cleanRel)
        }

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
                onLog?("[zPatch] Đã lưu patch: \(targetPath)")
            }
        }
    }

    func updatePatch(_ patch: zPatchItem) {
        if let idx = patches.firstIndex(where: { $0.id == patch.id }) {
            var updated = patch
            updated.cachedDestinationPath = updated.resolveDestinationPathOnBackground()
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
