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
        
        // 1. Đọc file MobileGestalt thật đang nằm trên máy
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to parse live MobileGestalt"])
        }
        
        // 2. Đồng bộ CacheUUID chuẩn của máy
        if case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout() {
            liveDict["CacheUUID"] = layout.uuid
        }
        
        // 3. Ghi đè CacheExtra (Các nút switch thông thường)
        let liveExtra = (liveDict["CacheExtra"] as? NSMutableDictionary) ?? NSMutableDictionary()
        let storeExtra = store.cacheExtra
        for (k, v) in storeExtra {
            liveExtra[k as! String] = v
        }
        liveDict["CacheExtra"] = liveExtra
        
        // 4. Ghi đè CacheData (Các nút switch dạng slot)
        guard let liveCacheData = liveDict["CacheData"] as? Data else {
            throw NSError(domain: "MG", code: -9, userInfo: [NSLocalizedDescriptionKey: "Live MobileGestalt missing CacheData"])
        }
        let targetCacheData = NSMutableData(data: liveCacheData)
        
        let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
        if case .success((let layout, _)) = MGCacheDataCoordinator.shared.resolveValidated(for: liveDict) {
            // Danh sách toàn bộ các key có slot
            let allToggleKeys = MGKey.appIntellAllKeys + MGKey.mediaHealthAllKeys + MGKey.experimentalCacheSlotKeys + [MGKey.island, MGKey.AOD, MGKey.AOTime, MGKey.AODVibrancy, MGKey.chargeLim, MGKey.bootChime, MGKey.crashDet, MGKey.pwm, MGKey.appPencil, MGKey.camButton, MGKey.actButton, MGKey.tapToWake, MGKey.stageMgr]
            
            for key in allToggleKeys {
                if let slotIdx = layout.featureSlotIndices[key] {
                    let offset = slotIdx * 8
                    if offset < targetCacheData.length {
                        var desiredBit: UInt8 = liveCacheData[offset] // Mặc định giữ nguyên trạng thái của máy
                        
                        // So sánh UI hiện tại với file gốc để xem thằng user có bấm đổi nút này không
                        if let storeData = store.mgCurrentDict["CacheData"] as? Data, offset < storeData.count {
                            let storeBit = storeData[offset]
                            if let origData = savedOrig?["CacheData"] as? Data, offset < origData.count {
                                // Nếu user bấm đổi (khác với trạng thái gốc) thì mới ghi đè
                                if storeBit != origData[offset] {
                                    desiredBit = storeBit
                                }
                            } else {
                                desiredBit = storeBit
                            }
                        }
                        targetCacheData[offset] = desiredBit
                    }
                }
            }
        }
        liveDict["CacheData"] = targetCacheData

        // 5. Ghi xuống file
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
        let (ok, msg) = mgWriteDetailed(backupData, allowVerifiedFactoryRestore: true)
        guard ok else { throw NSError(domain: "MG", code: -3, userInfo: [NSLocalizedDescriptionKey: msg]) }
        onLogUpdate("[MG] ✅ Restored successfully.")
    }
}