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
        
        // ĐM ĐÂY RỒI: Tự động lấy UUID thật của máy đè vào cái cũ trước khi ghi
        if case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout() {
            store.mgCurrentDict["CacheUUID"] = layout.uuid
        }
        
        let data = try PropertyListSerialization.data(fromPropertyList: store.mgCurrentDict, format: .binary, options: 0)
        let (ok, msg) = mgWriteDetailed(data)
        guard ok else { throw NSError(domain: "MG", code: -2, userInfo: [NSLocalizedDescriptionKey: msg]) }
        onLogUpdate("[MG] ✅ Applied successfully.")
    }

    static func restoreGestalt(record: MobileGestaltBackupManager.BackupRecord, onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        let backupData = try MobileGestaltBackupManager.shared.backupData(record)
        let (ok, msg) = mgWriteDetailed(backupData, allowVerifiedFactoryRestore: true)
        guard ok else { throw NSError(domain: "MG", code: -3, userInfo: [NSLocalizedDescriptionKey: msg]) }
        onLogUpdate("[MG] ✅ Restored successfully.")
    }
}