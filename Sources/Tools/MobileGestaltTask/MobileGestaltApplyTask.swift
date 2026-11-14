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

    // THUẬT TOÁN REVERT MỚI: Quét sạch các nút đã bật, trả về trạng thái gốc (baseline)
    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -10, userInfo: [NSLocalizedDescriptionKey: "Failed to parse live MobileGestalt"])
        }
        
        // 1. Xóa sạch các key tuỳ chỉnh trong CacheExtra
        if let extra = liveDict["CacheExtra"] as? NSMutableDictionary {
            let keysToRemove = MGKey.appIntellAllKeys + MGKey.mediaHealthAllKeys + MGKey.experimentalCacheSlotKeys + [
                MGKey.island, MGKey.AOD, MGKey.AOTime, MGKey.AODVibrancy,
                MGKey.chargeLim, MGKey.bootChime, MGKey.crashDet, MGKey.pwm,
                MGKey.appPencil, MGKey.camButton, MGKey.actButton,
                MGKey.tapToWake, MGKey.stageMgr
            ]
            for key in keysToRemove {
                extra.removeObject(forKey: key)
            }
            
            // Xóa region và internal
            extra.removeObject(forKey: MGKey.regionCode)
            extra.removeObject(forKey: MGKey.regionInfo)
            extra.removeObject(forKey: MGKey.regionSysconfig)
            extra.removeObject(forKey: MGKey.regModelNumber)
            extra.removeObject(forKey: MGKey.intInstall)
            extra.removeObject(forKey: MGKey.intBuild)
            
            // Xóa tên máy custom
            if let artwork = extra[MGKey.artwork] as? NSMutableDictionary {
                artwork.removeObject(forKey: "ArtworkDeviceProductDescription")
            }
        }
        
        // 2. Đưa CacheData về trạng thái baseline (gốc)
        if let layout = try? MGCacheDataCoordinator.shared.libraryLayout().get(),
           let liveCacheData = liveDict["CacheData"] as? Data {
            var targetCacheData = liveCacheData
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            
            let allToggleKeys = MGKey.appIntellAllKeys + MGKey.mediaHealthAllKeys + MGKey.experimentalCacheSlotKeys + [
                MGKey.island, MGKey.AOD, MGKey.AOTime, MGKey.AODVibrancy,
                MGKey.chargeLim, MGKey.bootChime, MGKey.crashDet, MGKey.pwm,
                MGKey.appPencil, MGKey.camButton, MGKey.actButton,
                MGKey.tapToWake, MGKey.stageMgr
            ]
            
            for key in allToggleKeys {
                if let slotIdx = layout.featureSlotIndices[key] {
                    let offset = slotIdx * 8
                    if offset < targetCacheData.count {
                        let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
                        targetCacheData[offset] = origVal ? 1 : 0
                    }
                }
            }
            
            // Reset green-tea, not-green-tea, wapi
            let origFlags = MGCacheDataCoordinator.shared.originalFlags(for: layout, savedOriginalDict: savedOrig)
            if layout.greenTeaOffset < targetCacheData.count {
                targetCacheData[layout.greenTeaOffset] = (origFlags?.greenTea ?? false) ? 1 : 0
            }
            if layout.notGreenTeaOffset < targetCacheData.count {
                targetCacheData[layout.notGreenTeaOffset] = (origFlags?.notGreenTea ?? false) ? 1 : 0
            }
            if let wOff = layout.wapiOffset, wOff < targetCacheData.count {
                targetCacheData[wOff] = (origFlags?.wapi ?? false) ? 1 : 0
            }
            
            liveDict["CacheData"] = targetCacheData
        }
        
        let finalData = try PropertyListSerialization.data(fromPropertyList: liveDict, format: .binary, options: 0)
        let (ok, msg) = mgWriteDetailed(finalData, allowVerifiedFactoryRestore: true)
        guard ok else {
            throw NSError(domain: "MG", code: -3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        onLogUpdate("[MG] ✅ Reverted all tweaks successfully.")
    }
}