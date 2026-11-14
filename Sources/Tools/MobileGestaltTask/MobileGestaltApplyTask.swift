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
        
        // Tự động tạo backup nếu chưa có
        if !FileManager.default.fileExists(atPath: MGURL.savedGestaltURL.path) || (try? Data(contentsOf: MGURL.savedGestaltURL))?.count ?? 0 < 256 {
            try? liveData.write(to: MGURL.savedGestaltURL, options: .atomic)
            try? FileManager.default.removeItem(at: MGURL.savedGestaltSHA256URL)
            onLogUpdate("[MG] 📦 Created pristine backup for the first time.")
        }
        
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

    // THUẬT TOÁN REVERT CHUẨN GESTALTX
    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -10, userInfo: [NSLocalizedDescriptionKey: "Failed to parse live MobileGestalt"])
        }
        
        guard let backupData = try? Data(contentsOf: MGURL.savedGestaltURL),
              backupData.count > 256,
              let backupDict = try? PropertyListSerialization.propertyList(from: backupData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -11, userInfo: [NSLocalizedDescriptionKey: "No valid backup file found. Please import a clean plist."])
        }
        
        // Đắp nguyên cục CacheExtra từ backup (bao gồm tên máy, Dynamic Island, Region)
        if let backupExtra = backupDict["CacheExtra"] as? NSMutableDictionary {
            liveDict["CacheExtra"] = backupExtra
        }
        
        // Đắp nguyên cục CacheData từ backup
        if let backupCacheData = backupDict["CacheData"] as? Data {
            liveDict["CacheData"] = backupCacheData
        }
        
        // Đắp UUID và Version live vào để bypass check
        if let liveUUID = liveDict["CacheUUID"] as? String {
            backupDict["CacheUUID"] = liveUUID
            liveDict["CacheUUID"] = liveUUID
        }
        if let liveVersion = liveDict["CacheVersion"] as? String {
            liveDict["CacheVersion"] = liveVersion
        }
        
        let finalData = try PropertyListSerialization.data(fromPropertyList: liveDict, format: .binary, options: 0)
        let (ok, msg) = mgWriteDetailed(finalData, allowVerifiedFactoryRestore: true)
        guard ok else {
            throw NSError(domain: "MG", code: -3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        onLogUpdate("[MG] ✅ Reverted to pristine factory settings.")
    }
}