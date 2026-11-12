import Foundation
import UIKit
import AirliftFFI
import Darwin
import Security
import XPC

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    // PORT GestaltAccess.saveGestalt: O_WRONLY → ftruncate(0) → lseek(0) → writeAll → fsync
    // Verify bằng isEqualToData (raw bytes)
    static func writeGestalt(data: Data, original: Data) throws {
        let path = onDeviceMGPath
        let fd = open(path, O_WRONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else {
            throw mgError(-6, "Mở file thất bại (errno=\(errno))")
        }

        let truncOK = ftruncate(fd, 0) == 0
        let seekOK  = truncOK && lseek(fd, 0, SEEK_SET) == 0
        let writeOK = seekOK && writeAll(fd: fd, data: data)
        let syncOK  = writeOK && fsync(fd) == 0
        let savedErrno = errno

        if !syncOK {
            // Rollback
            ftruncate(fd, 0)
            lseek(fd, 0, SEEK_SET)
            _ = writeAll(fd: fd, data: original)
            fsync(fd)
            close(fd)
            throw mgError(-7, "Ghi file thất bại (errno=\(savedErrno))")
        }
        close(fd)

        // Verify raw bytes (giống isEqualToData)
        let verification = try Data(contentsOf: URL(fileURLWithPath: path))
        guard verification == data else {
            throw mgError(-8, "Verify thất bại: byte không khớp")
        }
    }

    // PORT GestaltWriteAll: xử lý EINTR
    private static func writeAll(fd: Int32, data: Data) -> Bool {
        if data.isEmpty { return true }
        var remaining = data.count
        var offset = 0
        return data.withUnsafeBytes { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            while remaining > 0 {
                let written = write(fd, base + offset, remaining)
                if written < 0 && errno == EINTR { continue }
                if written <= 0 { return false }
                offset += written
                remaining -= written
            }
            return true
        }
    }

    // PORT GestaltViewModel.save(): escape → backup current (timestamped) → write → verify
    static func applyGestalt(store: GestaltStore,
                             onLogUpdate: @escaping (String) -> Void) async throws {
        if store.mgCurrentDict.count == 0 {
            let modURL = URL.documentsDirectory.appendingPathComponent("ModifiedMobileGestalt.plist")
            store.loadFromPlist(url: modURL)
        }
        guard store.mgCurrentDict.count > 0 else {
            throw mgError(-1, "Store rỗng. Bấm Save trước khi Apply.")
        }

        onLogUpdate("[MG] Serialize plist...")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: store.mgCurrentDict, format: .binary, options: 0
        )

        onLogUpdate("[MG] Xin quyền ghi (Native WorseQuery)...")
        let (handle, msg) = grantEscape()
        guard handle > 0 else {
            throw mgError(-5, "Xin quyền MCM thất bại: \(msg)")
        }
        onLogUpdate("[MG] ✅ Đã cấp quyền.")
        defer { NativeWorseQuery.shared.releaseAll() }

        let sysURL = URL(fileURLWithPath: onDeviceMGPath)
        guard FileManager.default.fileExists(atPath: onDeviceMGPath) else {
            throw mgError(-2, "Không tìm thấy MobileGestalt.plist.")
        }
        let originalData = try Data(contentsOf: sysURL)

        // Tạo pristine backup lần đầu nếu chưa có
        if !MobileGestaltBackupManager.shared.hasBackup {
            _ = try MobileGestaltBackupManager.shared.ensureBackup(from: originalData)
            onLogUpdate("[MG] ✅ Pristine backup.")
        }
        // Backup timestamped mỗi lần (giống GestaltBackupStore.create)
        _ = try? MobileGestaltBackupManager.shared.createBackup(from: originalData)
        onLogUpdate("[MG] ✅ Backup current (\(originalData.count) bytes).")

        onLogUpdate("[MG] Ghi in-place...")
        try writeGestalt(data: plistData, original: originalData)
        onLogUpdate("[MG] ✅ Apply OK (\(plistData.count) bytes).")
    }

    // PORT GestaltViewModel.restore: đọc backup → save() với data đó
    static func restoreGestalt(backupData: Data,
                               onLogUpdate: @escaping (String) -> Void) async throws {
        guard backupData.count > 0 else { throw mgError(-11, "Backup rỗng.") }
        guard (try? PropertyListSerialization.propertyList(from: backupData, format: nil) as? NSDictionary) != nil else {
            throw mgError(-12, "Backup không phải plist hợp lệ.")
        }

        onLogUpdate("[MG] Xin quyền ghi...")
        let (handle, msg) = grantEscape()
        guard handle > 0 else {
            throw mgError(-5, "Xin quyền MCM thất bại: \(msg)")
        }
        onLogUpdate("[MG] ✅ Đã cấp quyền.")
        defer { NativeWorseQuery.shared.releaseAll() }

        let sysURL = URL(fileURLWithPath: onDeviceMGPath)
        guard FileManager.default.fileExists(atPath: onDeviceMGPath) else {
            throw mgError(-2, "Không tìm thấy MobileGestalt.plist.")
        }
        let originalData = try Data(contentsOf: sysURL)

        _ = try? MobileGestaltBackupManager.shared.createBackup(from: originalData)
        onLogUpdate("[MG] ✅ Backup current.")

        onLogUpdate("[MG] Ghi in-place...")
        try writeGestalt(data: backupData, original: originalData)
        onLogUpdate("[MG] ✅ Restore OK (\(backupData.count) bytes).")
    }

    private static func grantEscape() -> (Int64, String) {
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              let group = entitlements.first else {
            return (-5, "Không tìm thấy App Group")
        }
        let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        let (handle, msg) = NativeWorseQuery.shared.grantAccess(targetPath: targetDir, appGroupID: group)
        return (Int64(handle), msg)
    }

    private static func mgError(_ code: Int, _ msg: String) -> NSError {
        NSError(domain: "MobileGestalt", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}