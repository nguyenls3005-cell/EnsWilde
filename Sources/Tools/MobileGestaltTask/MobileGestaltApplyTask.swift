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
        
        // 1. Đọc file MobileGestalt thật đang chạy trên máy
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to parse live MobileGestalt"])
        }
        
        // 2. Tự động lưu backup nếu chưa có
        _ = try? MobileGestaltBackupManager.shared.ensureBackup(from: liveData)
        
        // 3. Đồng bộ CacheUUID
        if case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout() {
            liveDict["CacheUUID"] = layout.uuid
        }
        
        // 4. Ghi đè CacheExtra
        let liveExtra = (liveDict["CacheExtra"] as? NSMutableDictionary) ?? NSMutableDictionary()
        let storeExtra = store.cacheExtra
        for (k, v) in storeExtra {
            liveExtra[k as! String] = v
        }
        liveDict["CacheExtra"] = liveExtra
        
        // 5. Ghi đè CacheData (Chỉ lấy đúng trạng thái trên UI của mày đè vào)
        guard let liveCacheData = liveDict["CacheData"] as? Data else {
            throw NSError(domain: "MG", code: -9, userInfo: [NSLocalizedDescriptionKey: "Live MobileGestalt missing CacheData"])
        }
        var targetCacheData = liveCacheData
        
        if case .success((let layout, _)) = MGCacheDataCoordinator.shared.resolveValidated(for: liveDict),
           let storeData = store.mgCurrentDict["CacheData"] as? Data {
            
            let allToggleKeys = MGKey.appIntellAllKeys + MGKey.mediaHealthAllKeys + MGKey.experimentalCacheSlotKeys + [
                MGKey.island, MGKey.AOD, MGKey.AOTime, MGKey.AODVibrancy,
                MGKey.chargeLim, MGKey.bootChime, MGKey.crashDet, MGKey.pwm,
                MGKey.appPencil, MGKey.camButton, MGKey.actButton,
                MGKey.tapToWake, MGKey.stageMgr
            ]
            
            for key in allToggleKeys {
                if let slotIdx = layout.featureSlotIndices[key] {
                    let offset = slotIdx * 8
                    if offset < targetCacheData.count && offset < storeData.count {
                        targetCacheData[offset] = storeData[offset]
                    }
                }
            }
        }
        liveDict["CacheData"] = targetCacheData

        // 6. Ghi xuống file
        let data = try PropertyListSerialization.data(fromPropertyList: liveDict, format: .binary, options: 0)
        let (ok, msg) = mgWriteDetailed(data)
        guard ok else {
            throw NSError(domain: "MG", code: -2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        onLogUpdate("[MG] ✅ Applied successfully.")
    }

    static func restoreGestalt(record: MobileGestaltBackupManager.BackupRecord, onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        
        let backupData = try MobileGestaltBackupManager.shared.backupData(record)
        guard let backupDict = try PropertyListSerialization.propertyList(from: backupData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -11, userInfo: [NSLocalizedDescriptionKey: "Failed to parse backup data"])
        }
        
        // Lấy UUID hiện tại của máy đắp vào file backup để bypass check
        if case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout() {
            backupDict["CacheUUID"] = layout.uuid
        }
        
        let finalData = try PropertyListSerialization.data(fromPropertyList: backupDict, format: .binary, options: 0)
        let (ok, msg) = mgWriteDetailed(finalData, allowVerifiedFactoryRestore: true)
        guard ok else { throw NSError(domain: "MG", code: -3, userInfo: [NSLocalizedDescriptionKey: msg]) }
        onLogUpdate("[MG] ✅ Restored successfully.")
    }
}