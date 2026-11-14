//
//  MobileGestaltApplyTask.swift
//  EnsWilde
//
//  Rewritten: honest logging, no silent skip, pwrite + F_FULLFSYNC
//

import Foundation
import UIKit
import Darwin

enum MobileGestaltApplyTask {

    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    // MARK: - Access

    private static func ensureAccess() throws {
        let dir = MGURL.fsGestaltURL.deletingLastPathComponent().path
        if wq.hasActiveAccess(path: dir) {
            log("[MG] ✓ worse_query access already active for \(dir)")
            return
        }
        log("[MG] Requesting worse_query access: \(dir)")
        let (ok, handle, msg) = wq.grantAccess(path: dir)
        guard ok, handle > 0 else {
            throw NSError(domain: "MG", code: -1, userInfo: [NSLocalizedDescriptionKey:
                "worse_query grantAccess FAILED: \(msg) (handle=\(handle))"])
        }
        log("[MG] ✓ Access granted. handle=\(handle)")
    }

    // MARK: - Low-level in-place write

    /// Ghi data đè lên file tại offset 0 (không truncate trước), rồi cắt phần đuôi thừa,
    /// cuối cùng F_FULLFSYNC để iOS thấy thay đổi ngay.
    private static func writeInPlace(_ data: Data, to path: String) throws {
        let fd = open(path, O_RDWR)
        guard fd >= 0 else {
            let e = String(cString: strerror(errno))
            throw NSError(domain: "MG", code: -20, userInfo: [NSLocalizedDescriptionKey:
                "open(\(path)) FAILED: \(e) (errno=\(errno))"])
        }
        defer { close(fd) }

        let oldSize = lseek(fd, 0, SEEK_END)
        log("[MG] writeInPlace: old_size=\(oldSize) new_size=\(data.count)")

        // pwrite từ offset 0
        let written: Int = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return pwrite(fd, base, data.count, 0)
        }
        guard written == data.count else {
            let e = String(cString: strerror(errno))
            throw NSError(domain: "MG", code: -21, userInfo: [NSLocalizedDescriptionKey:
                "pwrite FAILED: wrote=\(written)/\(data.count) errno=\(errno) (\(e))"])
        }
        log("[MG] pwrite OK: \(written) bytes")

        // Cắt đuôi nếu file cũ dài hơn data mới
        if oldSize > off_t(data.count) {
            if ftruncate(fd, off_t(data.count)) != 0 {
                let e = String(cString: strerror(errno))
                log("[MG] ⚠️ ftruncate FAILED: errno=\(errno) (\(e)) — file sẽ dư \(oldSize - off_t(data.count)) byte rác ở đuôi")
            } else {
                log("[MG] ftruncate OK: \(oldSize) → \(data.count)")
            }
        }

        // F_FULLFSYNC — bắt buộc để APFS đẩy xuống flash
        if fcntl(fd, F_FULLFSYNC) == -1 {
            let e = String(cString: strerror(errno))
            // F_FULLFSYNC có thể không được hỗ trợ trên 1 số FS — fallback fsync
            if fsync(fd) != 0 {
                let e2 = String(cString: strerror(errno))
                throw NSError(domain: "MG", code: -22, userInfo: [NSLocalizedDescriptionKey:
                    "F_FULLFSYNC FAILED (\(e)), fsync cũng FAILED (\(e2)). iOS có thể không thấy thay đổi."])
            }
            log("[MG] ⚠️ F_FULLFSYNC FAILED (\(e)) — dùng fsync OK")
        } else {
            log("[MG] ✓ F_FULLFSYNC OK")
        }
    }

    // MARK: - Apply

    static func applyGestalt(store: GestaltStore, onLogUpdate: @escaping (String) -> Void) async throws {
        logSink = onLogUpdate
        defer { logSink = nil }

        log("[MG] ===== APPLY START =====")
        try ensureAccess()

        log("[MG] Checking live cache at \(onDeviceMGPath)")
        guard FileManager.default.fileExists(atPath: onDeviceMGPath) else {
            throw NSError(domain: "MG", code: -404, userInfo: [NSLocalizedDescriptionKey:
                "MobileGestalt cache is missing. RESPIRING/REBOOT to regenerate, then retry."])
        }

        // 1. Đọc live
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        log("[MG] Live cache read: \(liveData.count) bytes")
        guard let liveDict = try PropertyListSerialization.propertyList(
            from: liveData, options: [.mutableContainersAndLeaves], format: nil
        ) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey:
                "Live MobileGestalt parse FAILED — plist corrupt?"])
        }

        // 2. CacheUUID
        if case .success(let libLayout) = MGCacheDataCoordinator.shared.libraryLayout() {
            let oldUUID = liveDict["CacheUUID"] as? String ?? "<nil>"
            if oldUUID != libLayout.uuid {
                liveDict["CacheUUID"] = libLayout.uuid
                log("[MG] CacheUUID: \(oldUUID) → \(libLayout.uuid)")
            } else {
                log("[MG] CacheUUID unchanged: \(oldUUID)")
            }
        } else {
            log("[MG] ⚠️ libraryLayout() returned failure — skipping CacheUUID update")
        }

        // 3. Whitelist toggle keys
        let allToggleKeys = MGKey.appIntellAllKeys + MGKey.mediaHealthAllKeys
            + MGKey.experimentalCacheSlotKeys + [
            MGKey.island, MGKey.AOD, MGKey.AOTime, MGKey.AODVibrancy,
            MGKey.chargeLim, MGKey.bootChime, MGKey.crashDet, MGKey.pwm,
            MGKey.appPencil, MGKey.camButton, MGKey.actButton,
            MGKey.tapToWake, MGKey.stageMgr
        ]
        log("[MG] Toggle keys in scope: \(allToggleKeys.count)")

        // 4. Merge cacheExtra (whitelist-only)
        let liveExtra = (liveDict["CacheExtra"] as? NSMutableDictionary) ?? NSMutableDictionary()
        let storeExtra = store.cacheExtra
        var extraMerged = 0
        for key in allToggleKeys {
            if let v = storeExtra[key] {
                let before = liveExtra[key].map { "\($0)" } ?? "<nil>"
                liveExtra[key] = v
                if before != "\(v)" {
                    log("[MG]   cacheExtra[\(key)]: \(before) → \(v)")
                    extraMerged += 1
                }
            }
        }
        liveDict["CacheExtra"] = liveExtra
        log("[MG] cacheExtra merged: \(extraMerged) key(s) changed")

        // 5. CacheData — resolve live layout
        guard let liveCacheData = liveDict["CacheData"] as? Data else {
            throw NSError(domain: "MG", code: -9, userInfo: [NSLocalizedDescriptionKey:
                "Live MobileGestalt missing CacheData key — cannot patch any toggle"])
        }
        log("[MG] Live CacheData: \(liveCacheData.count) bytes")

        guard case .success((let liveLayout, _)) = MGCacheDataCoordinator.shared.resolveValidated(for: liveDict) else {
            throw NSError(domain: "MG", code: -10, userInfo: [NSLocalizedDescriptionKey:
                "resolveValidated(live) FAILED — this iOS build isn't supported by the current worse_query layout table. Dynamic Island cannot be applied."])
        }
        log("[MG] Live layout resolved OK")

        // 6. CacheData — resolve store layout
        let storeDict = store.mgCurrentDict
        guard case .success((let storeLayout, _)) = MGCacheDataCoordinator.shared.resolveValidated(for: storeDict),
              let storeData = storeDict["CacheData"] as? Data else {
            log("[MG] ⚠️ Store layout unresolved OR store CacheData missing — cannot patch slots")
            log("[MG] ⚠️ Chỉ ghi cacheExtra (island/AOD sẽ KHÔNG đổi)")
            let out = try PropertyListSerialization.data(fromPropertyList: liveDict, format: .binary, options: 0)
            try writeInPlace(out, to: onDeviceMGPath)
            log("[MG] ✅ Applied (CacheExtra only). Respring required.")
            log("[MG] ===== APPLY END (degraded) =====")
            return
        }
        log("[MG] Store layout resolved OK. Store CacheData: \(storeData.count) bytes")

        // 7. Patch từng slot — full 8 byte, dùng offset riêng
        var targetCacheData = liveCacheData
        var patched = 0
        var skipped: [(key: String, why: String)] = []

        for key in allToggleKeys {
            guard let liveSlot = liveLayout.featureSlotIndices[key] else {
                skipped.append((key, "no live slot"))
                continue
            }
            guard let storeSlot = storeLayout.featureSlotIndices[key] else {
                skipped.append((key, "no store slot"))
                continue
            }
            let lo = liveSlot * 8
            let so = storeSlot * 8
            guard lo + 8 <= targetCacheData.count else {
                skipped.append((key, "live offset \(lo)+8 > \(targetCacheData.count)"))
                continue
            }
            guard so + 8 <= storeData.count else {
                skipped.append((key, "store offset \(so)+8 > \(storeData.count)"))
                continue
            }
            let oldBytes = Array(targetCacheData[lo..<lo+8])
            let newBytes = Array(storeData[so..<so+8])
            targetCacheData.replaceSubrange(lo..<lo+8, with: storeData[so..<so+8])
            let changed = oldBytes != newBytes
            let mark = changed ? "CHANGED" : "same"
            log(String(format: "[MG]   %@ slot live=%d store=%d %@ old=%@ new=%@",
                       key, liveSlot, storeSlot, mark,
                       hex(oldBytes), hex(newBytes)))
            patched += 1
        }

        log("[MG] Patched \(patched)/\(allToggleKeys.count) slot(s), skipped \(skipped.count)")
        for s in skipped {
            log("[MG]   SKIP \(s.key): \(s.why)")
        }

        if patched == 0 {
            throw NSError(domain: "MG", code: -11, userInfo: [NSLocalizedDescriptionKey:
                "0 slots patched — live layout and store layout share no toggle keys. Import plist from the SAME device/iOS."])
        }

        liveDict["CacheData"] = targetCacheData

        // 8. Serialize + write
        let out = try PropertyListSerialization.data(fromPropertyList: liveDict, format: .binary, options: 0)
        log("[MG] Serialized new plist: \(out.count) bytes")
        try writeInPlace(out, to: onDeviceMGPath)

        // 9. Verify — đọc lại file, so byte island
        log("[MG] Verifying write...")
        let verifyData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let verifyDict = try PropertyListSerialization.propertyList(
            from: verifyData, options: [], format: nil
        ) as? NSDictionary, let verifyCache = verifyDict["CacheData"] as? Data else {
            log("[MG] ⚠️ Verify: cannot re-read cache after write")
            log("[MG] ===== APPLY END (unverified) =====")
            return
        }
        let islandSlot = liveLayout.featureSlotIndices[MGKey.island]
        if let s = islandSlot {
            let off = s * 8
            if off + 8 <= verifyCache.count {
                let onDisk = Array(verifyCache[off..<off+8])
                let intended = Array(targetCacheData[off..<off+8])
                if onDisk == intended {
                    log("[MG] ✓ Verify island slot @\(off): on-disk=\(hex(onDisk)) == intended")
                } else {
                    log("[MG] ❌ Verify FAILED island slot: on-disk=\(hex(onDisk)) ≠ intended=\(hex(intended))")
                    log("[MG] ❌ Write did not stick — cache likely invalidated by iOS. Respring and retry.")
                }
            } else {
                log("[MG] ⚠️ Verify: island offset \(off) out of verifyCache bounds")
            }
        } else {
            log("[MG] ⚠️ Verify: island slot not in live layout (device isn't iPhone 14 Pro+/15/16?)")
        }

        // 10. Cảnh báo stale store
        if patched > 0 {
            log("[MG] ⚠️ Nếu verify OK mà island VẪN không hiện: kiểm tra GestaltStore đã cập nhật CacheData ngay khi bạn toggle island (không chỉ lưu preference).")
        }

        log("[MG] ✅ Applied. Respring required for UI.")
        log("[MG] ===== APPLY END =====")
    }

    // MARK: - Restore

    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        logSink = onLogUpdate
        defer { logSink = nil }

        log("[MG] ===== RESTORE START =====")
        try ensureAccess()

        if FileManager.default.fileExists(atPath: onDeviceMGPath) {
            try FileManager.default.removeItem(atPath: onDeviceMGPath)
            log("[MG] ✓ Deleted \(onDeviceMGPath)")
            log("[MG] → RESPIRING now so iOS regenerates a clean cache.")
        } else {
            log("[MG] Cache already gone — nothing to delete.")
        }
        log("[MG] ===== RESTORE END =====")
    }

    // MARK: - Log helpers

    private static var logSink: ((String) -> Void)?

    private static func log(_ s: String) {
        NSLog("%@", s)
        logSink?(s)
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}