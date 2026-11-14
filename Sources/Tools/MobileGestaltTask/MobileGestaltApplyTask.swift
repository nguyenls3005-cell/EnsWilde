//
//  MobileGestaltApplyTask.swift
//  EnsWilde
//

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
        
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to parse live MobileGestalt"])
        }
        
        if case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout() {
            liveDict["CacheUUID"] = layout.uuid
        }
        
        let liveExtra = (liveDict["CacheExtra"] as? NSMutableDictionary) ?? NSMutableDictionary()
        let storeExtra = store.cacheExtra
        for (k, v) in storeExtra {
            liveExtra[k as! String] = v
        }
        liveDict["CacheExtra"] = liveExtra
        
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

        let data = try PropertyListSerialization.data(fromPropertyList: liveDict, format: .binary, options: 0)
        let (ok, msg) = mgWriteDetailed(data)
        guard ok else {
            throw NSError(domain: "MG", code: -2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        onLogUpdate("[MG] ✅ Applied successfully.")
    }

    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        
        // 1. Đọc live để lấy UUID/Version hiện tại
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -10, userInfo: [NSLocalizedDescriptionKey: "Failed to parse live MobileGestalt"])
        }
        
        // 2. Đọc file backup
        guard let backupData = try? Data(contentsOf: MGURL.savedGestaltURL),
              let backupDict = try? PropertyListSerialization.propertyList(from: backupData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -11, userInfo: [NSLocalizedDescriptionKey: "No backup file found. Please import a clean plist or reinstall the app."])
        }
        
        // 3. Đắp UUID và Version của live vào backup để hệ thống không chặn
        if let liveUUID = liveDict["CacheUUID"] as? String {
            backupDict["CacheUUID"] = liveUUID
        }
        if let liveVersion = liveDict["CacheVersion"] as? String {
            backupDict["CacheVersion"] = liveVersion
        }
        
        // Đảm bảo ProductType khớp với máy để tránh lỗi verify
        if let liveProd = (liveDict["CacheExtra"] as? NSDictionary)?[MGKey.prodType] as? String {
            var backupExtra = backupDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            backupExtra[MGKey.prodType] = liveProd
            backupDict["CacheExtra"] = backupExtra
        }
        
        // 4. Ghi file với allowVerifiedFactoryRestore = true
        let finalData = try PropertyListSerialization.data(fromPropertyList: backupDict, format: .binary, options: 0)
        let (ok, msg) = mgWriteDetailed(finalData, allowVerifiedFactoryRestore: true)
        guard ok else {
            throw NSError(domain: "MG", code: -3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        onLogUpdate("[MG] ✅ Restored successfully.")
    }
}