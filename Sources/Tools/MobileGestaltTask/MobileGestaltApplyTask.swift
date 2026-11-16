//
//  MobileGestaltApplyTask.swift
//  EnsWilde
//

import Foundation
import UIKit
import Darwin

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
        
        guard FileManager.default.fileExists(atPath: onDeviceMGPath) else {
            throw NSError(domain: "MG", code: -404, userInfo: [NSLocalizedDescriptionKey: L("mg_err_cache_missing")])
        }
        
        onLogUpdate(L("mg_log_reading"))
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey: L("mg_err_parse_failed")])
        }
        
        let candidateDict = NSMutableDictionary(dictionary: liveDict)
        
        onLogUpdate(L("mg_log_syncing_cachedata"))
        if let liveCacheData = liveDict["CacheData"] as? Data,
           let storeCacheData = store.mgCurrentDict["CacheData"] as? Data,
           liveCacheData.count == storeCacheData.count {
            
            var patchedData = liveCacheData
            var patchedBytes = 0
            
            for i in 0..<patchedData.count {
                if patchedData[i] != storeCacheData[i] {
                    patchedData[i] = storeCacheData[i]
                    patchedBytes += 1
                }
            }
            
            candidateDict["CacheData"] = patchedData
            onLogUpdate(String(format: L("mg_log_patched_bytes"), patchedBytes))
        } else {
            onLogUpdate(L("mg_log_cache_size_mismatch"))
        }
        
        onLogUpdate(L("mg_log_syncing_cacheextra"))
        if let liveExtra = liveDict["CacheExtra"] as? NSMutableDictionary,
           let storeExtra = store.mgCurrentDict["CacheExtra"] as? NSDictionary {
            
            let allowedExtraKeys = [
                MGKey.artwork, MGKey.prodType, MGKey.regionCode, MGKey.regionSysconfig,
                MGKey.regModelNumber, MGKey.modelNameOuter1, MGKey.modelNameOuter2,
                MGKey.liquidGlassLowPower, MGKey.island, MGKey.AOTime, MGKey.AOD,
                MGKey.AODVibrancy, MGKey.chargeLim, MGKey.bootChime, MGKey.intInstall,
                MGKey.intBuild, MGKey.srd, MGKey.crashDet, MGKey.pwm, MGKey.appPencil,
                MGKey.camButton, MGKey.grapPefr, MGKey.actButton, MGKey.tapToWake,
                MGKey.stageMgr,
                "A62OafQ85EJAiiqKn4agtg", "a3n5T9sFtlyQ74NEp9ESxg", "O/7gbXWA5X2IRPVtDRU+bw",
                "rb2tKZxlj0Gm2tBmUQSLqQ", "M1n2sAqf33NAOgZRGxQYBA", "XNCjqOupLM/S8fNyxRNQTA",
                "YgYIIViDt1kgzyIsIV61vA", "U+73bmG4kBGj6kpreQXUTQ", "h63QSdBCiT/z0WU6rdQv6Q", "yK+xavymRGZ3xWc1tb8XDg"
            ] + MGKey.appIntellAllKeys + MGKey.ipadosCacheEx
            
            for key in allowedExtraKeys {
                if let newVal = storeExtra[key] {
                    liveExtra[key] = newVal
                } else {
                    liveExtra.removeObject(forKey: key)
                }
            }
            
            let blockedKeys = ["RegionInfo", "zHeENZu+wbg7PUprwNwBWg", "green-tea", "not-green-tea", "wapi"]
            for blocked in blockedKeys {
                liveExtra.removeObject(forKey: blocked)
            }
            
            candidateDict["CacheExtra"] = liveExtra
        }
        
        let finalData = try PropertyListSerialization.data(fromPropertyList: candidateDict, format: .binary, options: 0)
        onLogUpdate(String(format: L("mg_log_new_size"), finalData.count, liveData.count))
        
        onLogUpdate(L("mg_log_writing"))
        let fd = open(onDeviceMGPath, O_RDWR)
        guard fd >= 0 else {
            throw NSError(domain: "MG", code: -20, userInfo: [NSLocalizedDescriptionKey: L("mg_err_open_failed")])
        }
        defer { close(fd) }

        let oldSize = lseek(fd, 0, SEEK_END)
        
        let written = finalData.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return pwrite(fd, base, finalData.count, 0)
        }
        
        guard written == finalData.count else {
            throw NSError(domain: "MG", code: -21, userInfo: [NSLocalizedDescriptionKey: String(format: L("mg_err_pwrite_failed"), written, finalData.count)])
        }
        
        if oldSize > off_t(finalData.count) {
            ftruncate(fd, off_t(finalData.count))
        }
        
        if fcntl(fd, F_FULLFSYNC) == -1 {
            fsync(fd)
            onLogUpdate(L("mg_log_fullfsync_failed"))
        } else {
            onLogUpdate(L("mg_log_fullfsync_success"))
        }
        
        onLogUpdate(L("mg_log_write_success"))
    }

    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        if FileManager.default.fileExists(atPath: onDeviceMGPath) {
            try FileManager.default.removeItem(atPath: onDeviceMGPath)
            onLogUpdate(L("mg_log_restored"))
        }
    }
}