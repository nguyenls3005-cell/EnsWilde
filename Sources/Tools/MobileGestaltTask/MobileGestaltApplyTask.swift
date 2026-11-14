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
        
        // Xóa cache để iOS tự rebuild
        let outcome = mgExecuteCleanCacheRebuild(alsoResetConfigAndKeypad: false)
        switch outcome {
        case .success:
            onLogUpdate("[MG] ✅ Cleared cache. Please REBOOT to regenerate factory settings.")
        case .failure(let err):
            throw NSError(domain: "MG", code: -3, userInfo: [NSLocalizedDescriptionKey: "Clean rebuild failed: \(err.localizedDescription)"])
        }
    }
}