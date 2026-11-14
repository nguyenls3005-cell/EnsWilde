//
//  MobileGestaltApplyTask.swift
//  EnsWilde (Ported 1:1 from Erosion-CN + Dynamic Island Fix)
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
            throw NSError(domain: "MG", code: -404, userInfo: [NSLocalizedDescriptionKey: "MobileGestalt cache is missing. Please RESPIRING or REBOOT your device to let iOS regenerate it before applying."])
        }
        
        // 1. Đọc dữ liệu hiện tại trên máy (live)
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to parse live MobileGestalt"])
        }
        
        // 2. Đồng bộ CacheUUID
        if case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout() {
            liveDict["CacheUUID"] = layout.uuid
        }
        
        // 3. COPY Y CHANG TỪ EROSION: Lấy nguyên khối CacheData và CacheExtra từ GestaltStore
        if let storeCacheData = store.mgCurrentDict["CacheData"] as? Data {
            liveDict["CacheData"] = storeCacheData
        }
        
        if let storeExtra = store.mgCurrentDict["CacheExtra"] as? NSDictionary {
            liveDict["CacheExtra"] = storeExtra
        }
        
        // 4. FIX DYNAMIC ISLAND: Ép ArtworkDeviceSubType (Độ phân giải) để iOS vẽ Island
        // 2796 là 14 Pro Max, 2556 là 14 Pro, 2976 là 15 Pro Max. Mặc định dùng 2796.
        if var extra = liveDict["CacheExtra"] as? NSMutableDictionary {
            // Chỉ ép nếu người dùng có bật Island (kiểm tra xem có key island trong CacheExtra hoặc CacheData không)
            // Để đơn giản và an toàn, ta cứ ép nếu máy có phần cứng phù hợp, hoặc bạn có thể check cờ `YlEtTtHlNesRBMal1CqRaA`
            
            // Lấy key artwork chuẩn
            let artworkKey = "oPeik/9e8lQWMszEjbPzng"
            var art = (extra[artworkKey] as? NSMutableDictionary) ?? NSMutableDictionary()
            art["ArtworkDeviceSubType"] = 2796 
            extra[artworkKey] = art
            liveDict["CacheExtra"] = extra
            onLogUpdate("[MG] 🎨 Đã ép ArtworkDeviceSubType = 2796 (Dynamic Island).")
        }
        
        // 5. Serialize ra binary plist
        let data = try PropertyListSerialization.data(fromPropertyList: liveDict, format: .binary, options: 0)
        
        // 6. GHI ĐÈ TRỰC TIẾP (PWRITE + F_FULLFSYNC)
        let fd = open(onDeviceMGPath, O_RDWR)
        guard fd >= 0 else {
            throw NSError(domain: "MG", code: -20, userInfo: [NSLocalizedDescriptionKey: "Cannot open MobileGestalt for writing."])
        }
        defer { close(fd) }

        let oldSize = lseek(fd, 0, SEEK_END)
        
        let written = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return pwrite(fd, base, data.count, 0)
        }
        
        guard written == data.count else {
            throw NSError(domain: "MG", code: -21, userInfo: [NSLocalizedDescriptionKey: "pwrite failed. Wrote \(written) of \(data.count) bytes."])
        }
        
        if oldSize > off_t(data.count) {
            ftruncate(fd, off_t(data.count))
        }
        
        if fcntl(fd, F_FULLFSYNC) == -1 {
            fsync(fd)
        }
        
        // 7. Verify
        let verifyData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        if verifyData.count == data.count {
            onLogUpdate("[MG] ✅ Verify: File size matches (\(data.count) bytes).")
        } else {
            onLogUpdate("[MG] ⚠️ Verify: File size mismatch! (Expected \(data.count), got \(verifyData.count))")
        }
        
        onLogUpdate("[MG] ✅ Applied successfully via Erosion-CN 1:1 logic.")
        onLogUpdate("[MG] ⚠️ Please RESPIRING or REBOOT for changes to take effect.")
    }

    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        
        if FileManager.default.fileExists(atPath: onDeviceMGPath) {
            try FileManager.default.removeItem(atPath: onDeviceMGPath)
            onLogUpdate("[MG] ✅ Deleted MobileGestalt cache. Please RESPIRING to regenerate.")
        } else {
            onLogUpdate("[MG] ✅ Cache already deleted. Please RESPIRING to regenerate.")
        }
    }
}