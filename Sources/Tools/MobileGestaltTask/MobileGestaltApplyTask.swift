import Foundation
import UIKit
import AirliftFFI
import Darwin
import Security

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    private static func writeGestalt(data: Data) throws {
        let fd = open(onDeviceMGPath, O_WRONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else {
            throw NSError(domain: "MG", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mở file thất bại (errno=\(errno))"])
        }
        
        let originalData = try? Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        
        let wrote = ftruncate(fd, 0) == 0 &&
                    lseek(fd, 0, SEEK_SET) == 0 &&
                    writeAll(fd: fd, data: data) &&
                    fsync(fd) == 0
                    
        if !wrote {
            ftruncate(fd, 0)
            lseek(fd, 0, SEEK_SET)
            if let original = originalData {
                _ = writeAll(fd: fd, data: original)
                fsync(fd)
            }
            close(fd)
            throw NSError(domain: "MG", code: -2, userInfo: [NSLocalizedDescriptionKey: "Ghi file thất bại, đã rollback."])
        }
        close(fd)
        
        let verification = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard verification == data else {
            throw NSError(domain: "MG", code: -3, userInfo: [NSLocalizedDescriptionKey: "Verify thất bại: dữ liệu không khớp."])
        }
    }
    
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

    static func commit(expectedData: Data, editedData: Data, reason: String) throws -> Data {
        let currentData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard currentData == expectedData else {
            throw NSError(domain: "MG", code: -10, userInfo: [NSLocalizedDescriptionKey: "MobileGestalt đã thay đổi kể từ khi tải. Hãy refresh trước khi ghi."])
        }
        
        _ = try MobileGestaltBackupManager.shared.createBackup(from: currentData, reason: reason)
        
        try writeGestalt(data: editedData)
        
        return editedData
    }

    static func applyGestalt(store: GestaltStore, onLogUpdate: @escaping (String) -> Void) async throws {
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              let group = entitlements.first else {
            throw NSError(domain: "MG", code: -4, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy App Group"])
        }
        
        let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        let (handle, msg) = NativeWorseQuery.shared.grantAccess(targetPath: targetDir, appGroupID: group)
        guard handle > 0 else {
            throw NSError(domain: "MG", code: -5, userInfo: [NSLocalizedDescriptionKey: "Xin quyền thất bại: \(msg)"])
        }
        defer { NativeWorseQuery.shared.releaseAll() }
        
        let expectedData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        let plistData = try PropertyListSerialization.data(fromPropertyList: store.mgCurrentDict, format: .binary, options: 0)
        
        _ = try commit(expectedData: expectedData, editedData: plistData, reason: "Before applying")
        onLogUpdate("[MG] ✅ Apply thành công.")
    }
    
    static func restoreGestalt(record: MobileGestaltBackupManager.BackupRecord, onLogUpdate: @escaping (String) -> Void) async throws {
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              let group = entitlements.first else {
            throw NSError(domain: "MG", code: -4, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy App Group"])
        }
        
        let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        let (handle, msg) = NativeWorseQuery.shared.grantAccess(targetPath: targetDir, appGroupID: group)
        guard handle > 0 else {
            throw NSError(domain: "MG", code: -5, userInfo: [NSLocalizedDescriptionKey: "Xin quyền thất bại: \(msg)"])
        }
        defer { NativeWorseQuery.shared.releaseAll() }
        
        let backupData = try MobileGestaltBackupManager.shared.backupData(record)
        let expectedData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        
        _ = try commit(expectedData: expectedData, editedData: backupData, reason: "Before restoring")
        onLogUpdate("[MG] ✅ Restore thành công.")
    }
}