import Foundation
import UIKit

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    private static func ensureAccess() throws {
        let dir = MGURL.fsGestaltURL.deletingLastPathComponent().path
        if wq.hasActiveAccess(path: dir) { return }
        let (ok, handle, msg) = wq.grantAccess(path: dir)
        guard ok, handle > 0 else { throw NSError(domain: "MG", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]) }
    }

    static func applyGestalt(store: GestaltStore, onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        let data = try PropertyListSerialization.data(fromPropertyList: store.mgCurrentDict, format: .binary, options: 0)
        let (ok, msg) = mgWriteDetailed(data) // Gọi hàm ghi pwrite+F_FULLFSYNC chuẩn Erosion
        guard ok else { throw NSError(domain: "MG", code: -2, userInfo: [NSLocalizedDescriptionKey: msg]) }
        onLogUpdate("[MG] ✅ Apply thành công.")
    }

    static func restoreGestalt(record: MobileGestaltBackupManager.BackupRecord, onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        let backupData = try MobileGestaltBackupManager.shared.backupData(record)
        let (ok, msg) = mgWriteDetailed(backupData, allowVerifiedFactoryRestore: true)
        guard ok else { throw NSError(domain: "MG", code: -3, userInfo: [NSLocalizedDescriptionKey: msg]) }
        onLogUpdate("[MG] ✅ Restore thành công.")
    }
}