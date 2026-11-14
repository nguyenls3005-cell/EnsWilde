//
//  MobileGestaltApplyTask.swift
//  EnsWilde (Exact Erosion-CN Write Mechanism + Real Logs)
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
        
        // 1. Đọc dữ liệu hiện tại (Live)
        onLogUpdate("[MG] Đang đọc file MobileGestalt hiện tại...")
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to parse live MobileGestalt"])
        }
        
        // 2. Tạo Candidate từ dữ liệu của Store (Đã được UI cập nhật)
        onLogUpdate("[MG] Đang lấy dữ liệu cấu hình từ Store...")
        let candidateDict = NSMutableDictionary(dictionary: liveDict)
        
        if let storeExtra = store.mgCurrentDict["CacheExtra"] as? NSDictionary {
            candidateDict["CacheExtra"] = storeExtra
        }
        if let storeCacheData = store.mgCurrentDict["CacheData"] as? Data {
            candidateDict["CacheData"] = storeCacheData
        }
        
        // 3. Kiểm tra nghiêm ngặt (Erosion-CN ValidateTransition) - Chống ghi bậy byte
        onLogUpdate("[MG] Đang kiểm tra tính hợp lệ của các byte thay đổi...")
        if case .failure(let cacheErr) = MGCacheDataCoordinator.shared.validateTransition(from: liveDict, to: candidateDict) {
            onLogUpdate("[MG] ❌ LỖI VALIDATE: \(cacheErr.localizedDescription)")
            throw NSError(domain: "MG", code: -10, userInfo: [NSLocalizedDescriptionKey: "Từ chối ghi: \(cacheErr.localizedDescription)"])
        }
        
        // 4. Serialize ra binary plist
        let data = try PropertyListSerialization.data(fromPropertyList: candidateDict, format: .binary, options: 0)
        onLogUpdate("[MG] Dữ liệu mới: \(data.count) bytes (Cũ: \(liveData.count) bytes)")
        
        // 5. GHI ĐÈ TRỰC TIẾP (PWRITE + F_FULLFSYNC) - Y NHƯ EROSION-CN
        onLogUpdate("[MG] Đang ghi đè file (pwrite + F_FULLFSYNC)...")
        let fd = open(onDeviceMGPath, O_RDWR)
        guard fd >= 0 else {
            let err = String(cString: strerror(errno))
            onLogUpdate("[MG] ❌ Lỗi open file: \(err)")
            throw NSError(domain: "MG", code: -20, userInfo: [NSLocalizedDescriptionKey: "Cannot open MobileGestalt for writing. \(err)"])
        }
        defer { close(fd) }

        let oldSize = lseek(fd, 0, SEEK_END)
        
        // Ghi đè không truncate
        let written = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return pwrite(fd, base, data.count, 0)
        }
        
        guard written == data.count else {
            onLogUpdate("[MG] ❌ Lỗi pwrite: Ghi được \(written)/\(data.count) bytes")
            throw NSError(domain: "MG", code: -21, userInfo: [NSLocalizedDescriptionKey: "pwrite failed. Wrote \(written) of \(data.count) bytes."])
        }
        
        // Cắt phần đuôi thừa nếu file cũ dài hơn
        if oldSize > off_t(data.count) {
            ftruncate(fd, off_t(data.count))
        }
        
        // Ép hệ thống lưu xuống Flash
        if fcntl(fd, F_FULLFSYNC) == -1 {
            fsync(fd)
            onLogUpdate("[MG] ⚠️ F_FULLFSYNC thất bại, dùng fsync thay thế.")
        } else {
            onLogUpdate("[MG] ✅ F_FULLFSYNC thành công (Đã ép xuống ổ cứng).")
        }
        
        // 6. Verify lại file ngay sau khi ghi
        let verifyData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        if verifyData == data {
            onLogUpdate("[MG] ✅ Verify: File trên đĩa khớp 100% với dữ liệu mới.")
        } else {
            onLogUpdate("[MG] ❌ Verify thất bại: File trên đĩa KHÔNG khớp.")
        }
        
        onLogUpdate("[MG] 🎉 GHI THÀNH CÔNG. Hãy TẮT NGUỒN (Hard Reboot) để iOS nạp lại cấu hình.")
    }

    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        
        if FileManager.default.fileExists(atPath: onDeviceMGPath) {
            try FileManager.default.removeItem(atPath: onDeviceMGPath)
            onLogUpdate("[MG] ✅ Đã xóa MobileGestalt cache. Hãy Respring để iOS tạo lại file gốc.")
        } else {
            onLogUpdate("[MG] ✅ Cache đã bị xóa từ trước.")
        }
    }
}