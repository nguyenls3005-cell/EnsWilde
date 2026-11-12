import Foundation
import UIKit
import AirliftFFI
import Darwin
import Security
import XPC

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    // ============================================================
    // 🔥 PORT Y CHANG bq_write_data (BQCore.m) của Gester
    // ============================================================
    static func bqWriteData(path: String, data: Data) throws {
        let originalData = try? Data(contentsOf: URL(fileURLWithPath: path))
        
        // In-place write với O_NOFOLLOW (giống Gester)
        let fd = open(path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        if fd >= 0 {
            let truncOK = ftruncate(fd, 0) == 0
            
            var writeOK = false
            if truncOK {
                writeOK = data.withUnsafeBytes { buf -> Bool in
                    guard let base = buf.baseAddress else { return false }
                    var off = 0
                    let len = data.count
                    while off < len {
                        let n = write(fd, base + off, len - off)
                        if n <= 0 { return false }
                        off += n
                    }
                    return true
                }
            }
            
            let syncOK = writeOK && fsync(fd) == 0
            
            // Rollback nếu fail (giống Gester)
            if !(truncOK && writeOK && syncOK), let original = originalData, original.count > 0 {
                ftruncate(fd, 0)
                lseek(fd, 0, SEEK_SET)
                _ = original.withUnsafeBytes { buf -> Bool in
                    guard let base = buf.baseAddress else { return false }
                    var off = 0
                    let len = original.count
                    while off < len {
                        let n = write(fd, base + off, len - off)
                        if n <= 0 { return false }
                        off += n
                    }
                    return true
                }
                fsync(fd)
            }
            close(fd)
            
            if truncOK && writeOK && syncOK { return }
            print("[MG] In-place write failed, falling back to atomic")
        } else {
            print("[MG] In-place open failed: \(String(cString: strerror(errno)))")
        }
        
        // Fallback atomic: tmp + rename (giống Gester)
        let tmpPath = path + ".bqtmp"
        try data.write(to: URL(fileURLWithPath: tmpPath), options: .atomic)
        let tmpFD = open(tmpPath, O_RDONLY)
        if tmpFD >= 0 {
            fsync(tmpFD)
            close(tmpFD)
        }
        if rename(tmpPath, path) != 0 {
            let err = String(cString: strerror(errno))
            unlink(tmpPath)
            throw NSError(domain: "MGWrite", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "rename failed: \(err)"
            ])
        }
    }

    // ============================================================
    // 🔥 PORT Y CHANG BQSaveGestalt (BQCore.m) của Gester
    // ============================================================
    static func applyGestalt(store: GestaltStore,
                             onLogUpdate: @escaping (String) -> Void) async throws {
        // 1. Load store nếu rỗng
        if store.mgCurrentDict.count == 0 {
            let modURL = URL.documentsDirectory.appendingPathComponent("ModifiedMobileGestalt.plist")
            store.loadFromPlist(url: modURL)
        }
        guard store.mgCurrentDict.count > 0 else {
            throw mgError(-1, "Store rỗng. Hãy bấm Reset Original hoặc lưu lại trước khi Apply.")
        }

        // 2. Serialize (không cần escape)
        onLogUpdate("[MG] Đang serialize plist...")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: store.mgCurrentDict, format: .binary, options: 0
        )

        // 3. Escape TRƯỚC (giống Gester BQEscape)
        onLogUpdate("[MG] Đang xin quyền ghi (Native WorseQuery)...")
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              let group = entitlements.first else {
            throw mgError(-5, "Không tìm thấy App Group!")
        }
        let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        let (handle, accessMsg) = NativeWorseQuery.shared.grantAccess(targetPath: targetDir, appGroupID: group)
        guard handle > 0 else {
            throw mgError(-5, "Xin quyền MCM thất bại: \(accessMsg). Hãy chắc chắn cert có App Group hợp lệ.")
        }
        onLogUpdate("[MG] ✅ Đã được cấp quyền ghi.")
        defer { NativeWorseQuery.shared.releaseAll() }

        // 4. Backup (giống Gester BQLoadGestalt logic)
        let mgURL = URL(fileURLWithPath: onDeviceMGPath)
        guard FileManager.default.fileExists(atPath: onDeviceMGPath) else {
            throw mgError(-2, "Không tìm thấy MobileGestalt.plist.")
        }
        if !MobileGestaltBackupManager.shared.hasBackup {
            onLogUpdate("[MG] Đang backup pristine (lần đầu)...")
            let originalData = try Data(contentsOf: mgURL)
            try MobileGestaltBackupManager.shared.ensureBackup(from: originalData)
            onLogUpdate("[MG] ✅ Đã backup pristine.")
        }

        // 5. Ghi in-place (giống Gester bq_write_data)
        onLogUpdate("[MG] Đang ghi đè MobileGestalt.plist (In-place)...")
        try bqWriteData(path: onDeviceMGPath, data: plistData)

        // 6. Verify
        onLogUpdate("[MG] Verify file sau khi ghi...")
        do {
            let writtenData = try Data(contentsOf: mgURL)
            guard let writtenDict = try PropertyListSerialization.propertyList(from: writtenData, format: nil) as? NSDictionary,
                  writtenDict["CacheExtra"] != nil || writtenDict["CacheData"] != nil else {
                throw mgError(-8, "File sau khi ghi không hợp lệ.")
            }
        } catch {
            onLogUpdate("[MG] ⚠️ Verify thất bại — rollback...")
            let pristineData = try MobileGestaltBackupManager.shared.restoreData()
            try? bqWriteData(path: onDeviceMGPath, data: pristineData)
            throw mgError(-9, "File sau khi ghi corrupt, đã rollback.")
        }

        onLogUpdate("[MG] ✅ MobileGestalt đã apply thành công. Respring để thay đổi.")
    }

    // ============================================================
    // 🔥 PORT Y CHANG BQRestoreGestalt (BQCore.m) của Gester
    // ============================================================
    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        // 1. Đọc backup
        guard MobileGestaltBackupManager.shared.hasBackup else {
            throw mgError(-10, "Chưa có backup. Bấm Apply ít nhất 1 lần trước.")
        }
        let backupData = try MobileGestaltBackupManager.shared.restoreData()
        guard backupData.count > 0 else {
            throw mgError(-11, "Backup rỗng.")
        }

        // 2. Escape
        onLogUpdate("[MG] Đang xin quyền ghi (Native WorseQuery)...")
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              let group = entitlements.first else {
            throw mgError(-5, "Không tìm thấy App Group!")
        }
        let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        let (handle, accessMsg) = NativeWorseQuery.shared.grantAccess(targetPath: targetDir, appGroupID: group)
        guard handle > 0 else {
            throw mgError(-5, "Xin quyền MCM thất bại: \(accessMsg).")
        }
        onLogUpdate("[MG] ✅ Đã được cấp quyền ghi.")
        defer { NativeWorseQuery.shared.releaseAll() }

        // 3. Ghi backup xuống máy (giống Gester)
        onLogUpdate("[MG] Đang restore MobileGestalt.plist (In-place)...")
        try bqWriteData(path: onDeviceMGPath, data: backupData)

        // 4. Verify
        let writtenData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let writtenDict = try PropertyListSerialization.propertyList(from: writtenData, format: nil) as? NSDictionary,
              writtenDict["CacheExtra"] != nil || writtenDict["CacheData"] != nil else {
            throw mgError(-8, "File sau khi restore không hợp lệ.")
        }

        onLogUpdate("[MG] ✅ Restore OK (\(backupData.count) bytes). Respring để áp dụng.")
    }

    private static func mgError(_ code: Int, _ msg: String) -> NSError {
        NSError(domain: "MobileGestalt", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}