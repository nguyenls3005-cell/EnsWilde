//
//  MobileGestaltApplyTask.swift
//  EnsWilde
//

import Foundation
import UIKit
import Darwin
import CryptoKit

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    private static func ensureAccess() throws {
        let dir = MGURL.fsGestaltURL.deletingLastPathComponent().path
        if wq.hasActiveAccess(path: dir) { return }
        let (ok, handle, msg) = wq.grantAccess(path: dir)
        guard ok, handle > 0 else {
            throw NSError(domain: "MG", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func saveVerifiedBackup(data: Data, to url: URL, shaURL: URL? = nil) throws {
        try data.write(to: url, options: .atomic)
        let digest = sha256Hex(data)
        let readback = try Data(contentsOf: url)
        guard readback == data, sha256Hex(readback) == digest else {
            throw NSError(domain: "MG", code: -10, userInfo: [NSLocalizedDescriptionKey: L("mg_verify_failed")])
        }
        if let shaURL {
            try Data(digest.utf8).write(to: shaURL, options: .atomic)
        }
    }

    static func applyGestalt(store: GestaltStore, onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()

        let liveURL = MGURL.fsGestaltURL
        guard FileManager.default.fileExists(atPath: liveURL.path) else {
            throw NSError(domain: "MG", code: -404, userInfo: [NSLocalizedDescriptionKey: L("mg_err_cache_missing")])
        }

        onLogUpdate(L("mg_log_reading"))
        let liveData = try Data(contentsOf: liveURL)
        guard let liveDict = try PropertyListSerialization.propertyList(
            from: liveData,
            options: [.mutableContainersAndLeaves],
            format: nil
        ) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey: L("mg_err_parse_failed")])
        }

        try saveVerifiedBackup(data: liveData, to: MGURL.preApplyGestaltURL)
        if !FileManager.default.fileExists(atPath: MGURL.savedGestaltURL.path) {
            try saveVerifiedBackup(data: liveData, to: MGURL.savedGestaltURL, shaURL: MGURL.savedGestaltSHA256URL)
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
        let liveExtra: NSMutableDictionary = {
            if let existing = liveDict["CacheExtra"] as? NSMutableDictionary {
                return existing
            }
            if let dict = liveDict["CacheExtra"] as? [String: Any] {
                return NSMutableDictionary(dictionary: dict)
            }
            return NSMutableDictionary()
        }()

        if let storeExtra = store.mgCurrentDict["CacheExtra"] as? NSDictionary {
            let allowedExtraKeys: [String] = [
                MGKey.artwork,
                MGKey.island,
                MGKey.productType, MGKey.regionCode, MGKey.regionSysconfig,
                MGKey.regModelNumber, MGKey.modelNameOuter1, MGKey.modelNameOuter2,
                MGKey.liquidGlassLowPower, MGKey.AOTime, MGKey.AOD,
                MGKey.AODVibrancy, MGKey.chargeLim, MGKey.bootChime, MGKey.intInstall,
                MGKey.intBuild, MGKey.srd, MGKey.crashDet, MGKey.pwm, MGKey.appPencil,
                MGKey.camButton, MGKey.grapPefr, MGKey.actButton, MGKey.tapToWake,
                MGKey.stageMgr,
                "A62OafQ85EJAiiqKn4agtg", "a3n5T9sFtlyQ74NEp9ESxg", "O/7gbXWA5X2IRPVtDRU+bw",
                "rb2tKZxlj0Gm2tBmUQSLqQ", "M1n2sAqf33NAOgZRGxQYBA", "XNCjqOupLM/S8fNyxRNQTA",
                "YgYIIViDt1kgzyIsIV61vA", "U+73bmG4kBGj6kpreQXUTQ",
                "h63QSdBCiT/z0WU6rdQv6Q", "yK+xavymRGZ3xWc1tb8XDg"
            ] + MGKey.ipadosCacheEx

            for key in allowedExtraKeys {
                if let newVal = storeExtra[key] {
                    liveExtra[key] = newVal
                } else {
                    liveExtra.removeObject(forKey: key)
                }
            }
        }

        let blockedKeys = ["RegionInfo", "green-tea", "not-green-tea", "wapi"]
        for blocked in blockedKeys {
            liveExtra.removeObject(forKey: blocked)
        }

        candidateDict["CacheExtra"] = liveExtra

        guard PropertyListSerialization.propertyList(candidateDict, isValidFor: .binary) else {
            throw NSError(domain: "MG", code: -9, userInfo: [NSLocalizedDescriptionKey: L("mg_err_parse_failed")])
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

        let readback = try Data(contentsOf: liveURL)
        guard readback == finalData else {
            throw NSError(domain: "MG", code: -22, userInfo: [NSLocalizedDescriptionKey: L("mg_verify_failed")])
        }

        store.mgCurrentDict = NSMutableDictionary(dictionary: candidateDict)
        onLogUpdate(L("mg_log_write_success"))
    }

    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()

        let liveURL = MGURL.fsGestaltURL
        if FileManager.default.fileExists(atPath: MGURL.savedGestaltURL.path) {
            let savedData = try Data(contentsOf: MGURL.savedGestaltURL)
            if let shaData = try? Data(contentsOf: MGURL.savedGestaltSHA256URL),
               let expectedHash = String(data: shaData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !expectedHash.isEmpty {
                guard sha256Hex(savedData) == expectedHash else {
                    throw NSError(domain: "MG", code: -30, userInfo: [NSLocalizedDescriptionKey: L("mg_verify_failed")])
                }
            }

            let fd = open(onDeviceMGPath, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
            guard fd >= 0 else {
                throw NSError(domain: "MG", code: -31, userInfo: [NSLocalizedDescriptionKey: L("mg_err_open_failed")])
            }
            defer { close(fd) }

            let oldSize = lseek(fd, 0, SEEK_END)
            let written = savedData.withUnsafeBytes { ptr -> Int in
                guard let base = ptr.baseAddress else { return -1 }
                return pwrite(fd, base, savedData.count, 0)
            }
            guard written == savedData.count else {
                throw NSError(domain: "MG", code: -32, userInfo: [NSLocalizedDescriptionKey: String(format: L("mg_err_pwrite_failed"), written, savedData.count)])
            }
            if oldSize > off_t(savedData.count) {
                ftruncate(fd, off_t(savedData.count))
            }
            if fcntl(fd, F_FULLFSYNC) == -1 {
                fsync(fd)
            }

            let readback = try Data(contentsOf: liveURL)
            guard readback == savedData else {
                throw NSError(domain: "MG", code: -33, userInfo: [NSLocalizedDescriptionKey: L("mg_verify_failed")])
            }

            if let dict = try? PropertyListSerialization.propertyList(
                from: savedData,
                options: [.mutableContainersAndLeaves],
                format: nil
            ) as? NSMutableDictionary {
                GestaltStore.shared.mgCurrentDict = dict
            }
            onLogUpdate(L("mg_log_restored"))
            return
        }

        if FileManager.default.fileExists(atPath: onDeviceMGPath) {
            try FileManager.default.removeItem(atPath: onDeviceMGPath)
            onLogUpdate(L("mg_log_restored"))
        }
    }
}
