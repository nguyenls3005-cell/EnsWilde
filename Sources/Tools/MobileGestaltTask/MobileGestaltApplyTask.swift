import Foundation
import UIKit
import AirliftFFI
import Darwin
import Security
import XPC

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    // PORT Y CHANG GestaltAccess.saveGestalt:
    // ftruncate(0) → lseek(0) → write_all → fsync → verify bằng isEqualToData
    static func writeGestalt(data: Data, onLogUpdate: @escaping (String) -> Void) throws {
        let url = URL(fileURLWithPath: onDeviceMGPath)

        // Backup current state (tạo file timestamp mới mỗi lần, giống GestaltBackupStore)
        if FileManager.default.fileExists(atPath: onDeviceMGPath),
           let currentData = try? Data(contentsOf: url) {
            _ = try? MobileGestaltBackupManager.shared.createBackup(from: currentData)
        }

        // Open O_WRONLY (không O_RDWR), giống GestaltAccess
        let fd = open(onDeviceMGPath, O_WRONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else {
            throw mgError(-6, "Mở file thất bại (errno=\(errno))")
        }

        // ftruncate(0) + lseek + write + fsync
        let truncOK = ftruncate(fd, 0) == 0
        let seekOK = truncOK && lseek(fd, 0, SEEK_SET) == 0
        let writeOK = seekOK && writeAll(fd: fd, data: data)
        let syncOK = writeOK && fsync(fd) == 0
        let writeErrno = errno
        close(fd)

        if !syncOK {
            // Rollback: ghi lại currentData
            if let currentData = try? Data(contentsOf: url) {
                let rbFD = open(onDeviceMGPath, O_WRONLY | O_CLOEXEC)
                if rbFD >= 0 {
                    ftruncate(rbFD, 0)
                    lseek(rbFD, 0, SEEK_SET)
                    _ = writeAll(fd: rbFD, data: currentData)
                    fsync(rbFD)
                    close(rbFD)
                }
            }
            throw mgError(-7, "Ghi file thất bại (errno=\(writeErrno))")
        }

        // Verify RAW BYTES (giống [verification isEqualToData:data])
        let verification = try Data(contentsOf: url)
        guard verification == data else {
            throw mgError(-8, "Verify thất bại: byte không khớp")
        }
        onLogUpdate("[MG] ✅ Verify OK (\(data.count) bytes).")
    }

    // PORT Y CHANG GestaltWriteAll: write toàn bộ, xử lý EINTR
    private static func writeAll(fd: Int32, data: Data) -> Bool {
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

    // PORT Y CHANG GestaltViewModel.save():
    // 1. Serialize state
    // 2. Escape (connect)
    // 3. writeGestalt (bao gồm backup current + write + verify)
    // 4. Read back verify các key (nếu cần)
    static func applyGestalt(store: GestaltStore,
                             onLogUpdate: @escaping (String) -> Void) async throws {
        if store.mgCurrentDict.count == 0 {
            let modURL = URL.documentsDirectory.appendingPathComponent("ModifiedMobileGestalt.plist")
            store.loadFromPlist(url: modURL)
        }
        guard store.mgCurrentDict.count > 0 else {
            throw mgError(-1, "Store rỗng. Bấm Save trước khi Apply.")
        }

        onLogUpdate("[MG] Đang serialize plist...")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: store.mgCurrentDict, format: .binary, options: 0
        )

        onLogUpdate("[MG] Đang xin quyền ghi (Native WorseQuery)...")
        let (handle, accessMsg) = grantEscape()
        guard handle > 0 else {
            throw mgError(-5, "Xin quyền MCM thất bại: \(accessMsg)")
        }
        onLogUpdate("[MG] ✅ Đã được cấp quyền ghi.")
        defer { NativeWorseQuery.shared.releaseAll() }

        try writeGestalt(data: plistData, onLogUpdate: onLogUpdate)
        onLogUpdate("[MG] ✅ Apply thành công. Respring để thay đổi.")
    }

    // PORT Y CHANG GestaltViewModel.restore(_:) + save():
    // Restore = đọc backup → ghi qua cùng flow (backup current + write + verify)
    static func restoreGestalt(backupData: Data,
                               onLogUpdate: @escaping (String) -> Void) async throws {
        guard backupData.count > 0 else {
            throw mgError(-11, "Backup rỗng.")
        }

        // Validate trước khi ghi
        guard (try? PropertyListSerialization.propertyList(from: backupData, format: nil) as? NSDictionary) != nil else {
            throw mgError(-12, "Backup không phải plist hợp lệ.")
        }

        onLogUpdate("[MG] Đang xin quyền ghi (Native WorseQuery)...")
        let (handle, accessMsg) = grantEscape()
        guard handle > 0 else {
            throw mgError(-5, "Xin quyền MCM thất bại: \(accessMsg)")
        }
        onLogUpdate("[MG] ✅ Đã được cấp quyền ghi.")
        defer { NativeWorseQuery.shared.releaseAll() }

        try writeGestalt(data: backupData, onLogUpdate: onLogUpdate)
        onLogUpdate("[MG] ✅ Restore OK. Respring để áp dụng.")
    }

    // Escape wrapper
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