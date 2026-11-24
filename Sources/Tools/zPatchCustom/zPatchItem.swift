import Foundation
import Combine

struct zPatchItem: Identifiable, Codable {
    var id: UUID
    var bundleID: String
    var relativeDestPath: String
    var sourcePath: String
    var backupPath: String?
    var hasInitialBackup: Bool
    var isEnabled: Bool
    var pendingRevert: Bool
    var createdDate: Date

    static let baseContainerPrefix = "/var/mobile/Containers/Data/Application/"

    /// Tự động resolve container UUID qua fsHandlers nếu có, fallback sang bundleID
    func resolvedDestinationPath() -> String {
        let cleanBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRel = relativeDestPath.hasPrefix("/")
            ? String(relativeDestPath.dropFirst())
            : relativeDestPath

        let containerPath = fsHandlers.getContainerPath(at: FSURL.appContainers, forMatch: cleanBundle)
        let baseRoot = containerPath.isEmpty
            ? (Self.baseContainerPrefix + cleanBundle)
            : containerPath

        if cleanRel.isEmpty { return baseRoot }
        return (baseRoot as NSString).appendingPathComponent(cleanRel)
    }

    var fullDestinationPath: String {
        resolvedDestinationPath()
    }

    init(
        id: UUID = UUID(),
        bundleID: String,
        relativeDestPath: String,
        sourcePath: String,
        backupPath: String? = nil,
        hasInitialBackup: Bool = false,
        isEnabled: Bool = true,
        pendingRevert: Bool = false
    ) {
        self.id = id
        self.bundleID = bundleID
        self.relativeDestPath = relativeDestPath
        self.sourcePath = sourcePath
        self.backupPath = backupPath
        self.hasInitialBackup = hasInitialBackup
        self.isEnabled = isEnabled
        self.pendingRevert = pendingRevert
        self.createdDate = Date()
    }
}

final class zPatchStore: ObservableObject {
    @Published var patches: [zPatchItem] = []
    @Published var pendingApply: Bool = false

    private let itemsKey = "zPatchCustomItems_v3"
    private let enabledKey = "zPatchCustomEnabled"
    private let pendingApplyKey = "zPatchPendingApply"

    var isTweakEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            objectWillChange.send()
        }
    }

    init() {
        pendingApply = UserDefaults.standard.bool(forKey: pendingApplyKey)
        loadPatches()
    }

    func loadPatches() {
        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([zPatchItem].self, from: data) {
            patches = decoded
        }
    }

    func savePatches() {
        if let encoded = try? JSONEncoder().encode(patches) {
            UserDefaults.standard.set(encoded, forKey: itemsKey)
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

    /// Ấn Save Patch: xin quyền qua wq và backup lần đầu file đích
    func saveNewPatch(bundleID: String, relativeDestPath: String, sourcePath: String, onLog: ((String) -> Void)? = nil) {
        var item = zPatchItem(
            bundleID: bundleID,
            relativeDestPath: relativeDestPath,
            sourcePath: sourcePath,
            hasInitialBackup: false,
            isEnabled: true,
            pendingRevert: false
        )

        let targetPath = item.resolvedDestinationPath()
        let bURL = backupFileURL(for: item, targetPath: targetPath)

        let (granted, _, errMsg) = wq.grantAccess(path: targetPath, requireWrite: false)
        defer { wq.releaseAccess(path: targetPath) }

        if granted, FileManager.default.fileExists(atPath: targetPath),
           let originalData = try? Data(contentsOf: URL(fileURLWithPath: targetPath)) {
            do {
                try FileManager.default.createDirectory(at: bURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try originalData.write(to: bURL, options: .atomic)
                item.backupPath = bURL.path
                item.hasInitialBackup = true
                onLog?("[zPatch/wq] Đã backup lần đầu: \(targetPath)")
            } catch {
                onLog?("[zPatch/wq] Ghi backup lỗi: \(error.localizedDescription)")
            }
        } else {
            onLog?("[zPatch/wq] Không đọc được file gốc để backup (\(targetPath)): \(errMsg)")
        }

        patches.append(item)
        savePatches()
    }

    func updatePatch(_ patch: zPatchItem) {
        if let idx = patches.firstIndex(where: { $0.id == patch.id }) {
            patches[idx] = patch
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

    /// Ấn Revert: đánh dấu pendingRevert, qua tab Apply sẽ khôi phục bản backup qua wq
    func requestRevert(_ patch: zPatchItem) {
        guard let idx = patches.firstIndex(where: { $0.id == patch.id }) else { return }
        patches[idx].isEnabled = false
        patches[idx].pendingRevert = true
        savePatches()
        setPendingApply(true)
    }

    /// Chạy ở tab Apply (ToolRunner): xử lý pendingRevert trước, sau đó apply các patch đang bật
    func applyAllUsingWorseQuery(onLog: @escaping (String) -> Void) throws {
        loadPatches()
        guard isTweakEnabled else {
            onLog("[zPatch] Tweak chưa bật, bỏ qua.")
            return
        }

        for idx in patches.indices {
            let targetPath = patches[idx].resolvedDestinationPath()
            let targetURL = URL(fileURLWithPath: targetPath)

            if patches[idx].pendingRevert {
                guard let backupPath = patches[idx].backupPath,
                      FileManager.default.fileExists(atPath: backupPath) else {
                    onLog("[zPatch/wq] Thiếu file backup để revert: \(targetPath)")
                    patches[idx].pendingRevert = false
                    continue
                }

                let (granted, _, errMsg) = wq.grantAccess(path: targetPath, requireWrite: true)
                defer { wq.releaseAccess(path: targetPath) }
                guard granted else {
                    onLog("[zPatch/wq] Không xin được quyền ghi revert (\(targetPath)): \(errMsg)")
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

            if patches[idx].isEnabled {
                let (granted, _, errMsg) = wq.grantAccess(path: targetPath, requireWrite: true)
                defer { wq.releaseAccess(path: targetPath) }
                guard granted else {
                    onLog("[zPatch/wq] Không xin được quyền ghi (\(targetPath)): \(errMsg)")
                    continue
                }

                // Backup lần đầu nếu chưa có
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
        if FileManager.default.fileExists(atPath: url.path) {
            return writeFileAtomically(data, to: url, allowEmpty: false)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return writeFileTemp(data, to: url)
        }
    }

    func saveChange(enableTweak: Bool) {
        UserDefaults.standard.set(enableTweak, forKey: enabledKey)
        savePatches()
        setPendingApply(true)
        objectWillChange.send()
    }

    func clearPendingApply() {
        setPendingApply(false)
    }

    private func setPendingApply(_ value: Bool) {
        pendingApply = value
        UserDefaults.standard.set(value, forKey: pendingApplyKey)
    }
}
