import Foundation
import SwiftUI
import Combine
import Darwin
import AirliftFFI

@MainActor
class ToolRunner: ObservableObject {
    @Published var state: ToolState = .idle

    private let stepDelayNs: UInt64 = 1_000_000_000

    private func paceStep() async {
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: stepDelayNs)
    }

    /// Chuẩn hóa đường dẫn tương đối để loại bỏ lặp thư mục (vd: Library/Cookies/Library/Cookies/...)
    static func normalizeRelativePath(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix("/") {
            cleaned.removeFirst()
        }
        let parts = cleaned.components(separatedBy: "/").filter { !$0.isEmpty }
        var result: [String] = []
        var i = 0
        while i < parts.count {
            if i + 3 < parts.count,
               parts[i] == parts[i + 2],
               parts[i + 1] == parts[i + 3] {
                result.append(parts[i])
                result.append(parts[i + 1])
                i += 4
            } else if i + 1 < parts.count,
                      parts[i] == parts[i + 1] {
                result.append(parts[i])
                i += 2
            } else {
                result.append(parts[i])
                i += 1
            }
        }
        return result.joined(separator: "/")
    }

    /// Chuẩn hóa đường dẫn tuyệt đối đầy đủ nếu bị ghép lặp đuôi (vd: .../UUID/Library/Cookies/Library/Cookies/file)
    static func normalizeFullDestinationPath(_ fullPath: String) -> String {
        let std = (fullPath as NSString).standardizingPath
        let parts = std.components(separatedBy: "/")
        var result: [String] = []
        var i = 0
        while i < parts.count {
            if i + 3 < parts.count,
               !parts[i].isEmpty,
               parts[i] == parts[i + 2],
               parts[i + 1] == parts[i + 3] {
                result.append(parts[i])
                result.append(parts[i + 1])
                i += 4
            } else if i + 1 < parts.count,
                      !parts[i].isEmpty,
                      parts[i] == parts[i + 1] {
                result.append(parts[i])
                i += 2
            } else {
                result.append(parts[i])
                i += 1
            }
        }
        let joined = result.joined(separator: "/")
        return std.hasPrefix("/") && !joined.hasPrefix("/") ? "/" + joined : joined
    }

    func applyAll(
        isSystemReady: Bool,
        store: ToolStore,
        walletStore: AppleWalletStore,
        themeStore: PasscodeThemeStore,
        featureFlagsStore: FeatureFlagsStore,
        onLogUpdate: @escaping (String) -> Void
    ) async {
        GLOBAL_LOG.beginNewSession(header: "=== Phiên chạy mới: \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)) ===")

        guard isSystemReady else {
            let msg = "System not ready. Check Pairing & VPN."
            state = .failed(msg)
            onLogUpdate("Chạy không thành công")
            onLogUpdate("Chi tiết lỗi: \(msg)")
            return
        }

        state = .running
        onLogUpdate("Starting tweaks...")
        await paceStep()

        do {
            if store.replaceMobileGestaltEnabled {
                onLogUpdate(">> Applying MobileGestalt...")
                try await MobileGestaltApplyTask.applyGestalt(store: GestaltStore.shared, onLogUpdate: onLogUpdate)
                onLogUpdate(">> MobileGestalt Done.")
                await paceStep()
            }

            if themeStore.passcodeThemeEnabled {
                onLogUpdate(">> Applying Passcode Theme...")
                let selectedTheme = themeStore.getSelectedTheme() ?? PasscodeTheme(name: "Default")
                let vm = PasscodeThemeViewModel(store: themeStore)
                try await vm.applyTheme(selectedTheme, store: store, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Passcode Theme Done.")
                await paceStep()
            }

            if walletStore.appleWalletEnabled {
                onLogUpdate(">> Applying Apple Wallet...")
                try await AppleWalletTask.run(store: store, walletStore: walletStore, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Wallet Done.")
                await paceStep()
            }

            if store.configTweaksEnabled {
                onLogUpdate(">> Applying Config Tweaks...")
                try await ConfigTweaksApplyTask.apply(store: store, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Config Tweaks Done.")
                await paceStep()
            }

            if store.disableCallRecordingSoundEnabled {
                onLogUpdate(">> Applying Disable Call Recording Sound...")
                let vm = DisableCallRecordingSoundViewModel()
                try await vm.apply(store: store, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Disable Call Recording Sound Done.")
                await paceStep()
            }

            let zPatch = zPatchStore.shared
            if zPatch.isTweakEnabled || zPatch.pendingApply || zPatch.patches.contains(where: { $0.pendingRevert }) {
                onLogUpdate(">> Applying zPatch Custom...")
                try applyZPatchDirectly(store: zPatch, onLog: onLogUpdate)
                onLogUpdate(">> zPatch Custom Done.")
                await paceStep()
            }

            state = .success
            onLogUpdate("All tweaks applied successfully.")

        } catch {
            let reason = error.localizedDescription.isEmpty ? "Lỗi không xác định" : error.localizedDescription
            state = .failed(reason)
            onLogUpdate("Chạy không thành công")
            onLogUpdate("Chi tiết lỗi: \(reason)")
        }
    }

    /// Ghi đè trực tiếp các file của zPatch bằng pwrite + F_FULLFSYNC (tránh lỗi .tmp của .atomic và tránh lặp đường dẫn)
    private func applyZPatchDirectly(store: zPatchStore, onLog: @escaping (String) -> Void) throws {
        let fm = FileManager.default
        let activePatches = store.patches.filter { $0.isEnabled || $0.pendingRevert }

        guard !activePatches.isEmpty else {
            onLog("[zPatch] Không có patch nào đang bật.")
            return
        }

        for idx in store.patches.indices {
            var patch = store.patches[idx]
            guard patch.isEnabled || patch.pendingRevert else { continue }

            let cleanRel = Self.normalizeRelativePath(patch.relativeDestPath)
            patch.relativeDestPath = cleanRel

            // Tìm container của app
            let containerPath = resolveContainerPath(for: patch)
            guard !containerPath.isEmpty else {
                throw NSError(
                    domain: "zPatchCustom",
                    code: -51,
                    userInfo: [NSLocalizedDescriptionKey: "[zPatch] Không tìm thấy thư mục container cho \(patch.bundleID)"]
                )
            }

            let rawDest = (containerPath as NSString).appendingPathComponent(cleanRel)
            let destPath = Self.normalizeFullDestinationPath(rawDest)
            let destDir = (destPath as NSString).deletingLastPathComponent
            patch.cachedDestinationPath = destPath

            if patch.pendingRevert {
                guard let backupPath = patch.backupPath, fm.fileExists(atPath: backupPath) else {
                    throw NSError(
                        domain: "zPatchCustom",
                        code: -52,
                        userInfo: [NSLocalizedDescriptionKey: "[zPatch] Không có file backup để Revert cho \(patch.bundleID)"]
                    )
                }
                let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
                try overwriteFileViaPwrite(data: backupData, destPath: destPath, destDir: destDir)
                patch.pendingRevert = false
                store.patches[idx] = patch
                onLog("[zPatch] Đã Revert thành công: \(destPath)")
                continue
            }

            guard !patch.sourcePath.isEmpty, fm.fileExists(atPath: patch.sourcePath) else {
                throw NSError(
                    domain: "zPatchCustom",
                    code: -53,
                    userInfo: [NSLocalizedDescriptionKey: "[zPatch] File nguồn không tồn tại: \(patch.sourcePath)"]
                )
            }

            // Tạo backup lần đầu nếu chưa có
            if !patch.hasInitialBackup, fm.fileExists(atPath: destPath) {
                _ = wq.grantAccess(path: destDir, requireWrite: false, allowFsgetpathFallback: true)
                _ = wq.grantAccess(path: destPath, requireWrite: false, allowFsgetpathFallback: true)
                if let origData = try? Data(contentsOf: URL(fileURLWithPath: destPath)) {
                    let backupDir = URL.documentsDirectory.appendingPathComponent("zPatchBackups", isDirectory: true)
                    try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                    let backupURL = backupDir.appendingPathComponent("\(patch.id.uuidString)_backup.bin")
                    try origData.write(to: backupURL, options: .atomic)
                    patch.backupPath = backupURL.path
                    patch.hasInitialBackup = true
                }
            }

            let sourceData = try Data(contentsOf: URL(fileURLWithPath: patch.sourcePath))
            try overwriteFileViaPwrite(data: sourceData, destPath: destPath, destDir: destDir)
            store.patches[idx] = patch
            onLog("[zPatch] Ghi đè thành công: \(destPath)")
        }

        store.pendingApply = false
        store.savePatches()
    }

    private func resolveContainerPath(for patch: zPatchItem) -> String {
        let bid = zPatchItem.normalizedBundleID(patch.bundleID)
        // 1. Kiểm tra nếu bundleID thực chất là UUID thư mục container
        if UUID(uuidString: bid) != nil {
            let candidate = "/private/var/mobile/Containers/Data/Application/\(bid)"
            return candidate
        }
        // 2. Lấy từ cachedDestinationPath nếu đã có đường dẫn UUID hợp lệ
        if let cached = patch.cachedDestinationPath, !cached.isEmpty {
            let norm = Self.normalizeFullDestinationPath(cached)
            let comps = norm.components(separatedBy: "/")
            if let appIdx = comps.firstIndex(of: "Application"), appIdx + 1 < comps.count {
                let uuid = comps[appIdx + 1]
                if UUID(uuidString: uuid) != nil {
                    return comps[0...(appIdx + 1)].joined(separator: "/")
                }
            }
        }
        // 3. Tìm qua CSStoreEngine
        if let rec = CSStoreEngine.shared.allAppRecords().first(where: {
            zPatchItem.normalizedBundleID($0.bundleID).caseInsensitiveCompare(bid) == .orderedSame && !$0.dataContainerPath.isEmpty
        }) {
            return CSStoreEngine.normalizeVarPath(rec.dataContainerPath)
        }
        return ""
    }

    private func overwriteFileViaPwrite(data: Data, destPath: String, destDir: String) throws {
        _ = wq.grantAccess(path: destDir, requireWrite: true, allowFsgetpathFallback: true)
        _ = wq.grantAccess(path: destPath, requireWrite: true, allowFsgetpathFallback: true)
        _ = NativeWorseQuery.shared.grantViaFsgetpath(targetFile: destPath, requireWrite: true, allowRecursiveWq: true)

        var st = stat()
        if stat(destPath, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
            _ = chflags(destPath, st.st_flags & ~UInt32(UF_IMMUTABLE))
        }

        let fd = open(destPath, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard fd >= 0 else {
            let err = errno
            throw NSError(
                domain: "zPatchCustom",
                code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: "[zPatch] Ghi đè thất bại (\(destPath)): Không mở được file (errno: \(err))"]
            )
        }
        defer { close(fd) }

        let oldSize = lseek(fd, 0, SEEK_END)
        let written = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return pwrite(fd, base, data.count, 0)
        }
        guard written == data.count else {
            let err = errno
            throw NSError(
                domain: "zPatchCustom",
                code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: "[zPatch] Ghi đè thất bại (\(destPath)): pwrite lỗi (errno: \(err))"]
            )
        }
        if oldSize > off_t(data.count) {
            ftruncate(fd, off_t(data.count))
        }
        if fcntl(fd, F_FULLFSYNC) == -1 {
            fsync(fd)
        }
    }
}

enum ToolState: Equatable {
    case idle
    case running
    case success
    case failed(String)
}
