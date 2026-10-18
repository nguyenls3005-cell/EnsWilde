import Foundation
import UIKit

enum MobileGestaltApplyTask {
    // Đường dẫn chuẩn của iOS 27 (từ Erosion)
    static var onDeviceMGPath: String {
        return "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    }

    static func applyGestalt(store: GestaltStore) async throws {
        let mgPath = onDeviceMGPath
        let mgURL = URL(fileURLWithPath: mgPath)
        let bq = BadQuery()
        
        // 1. Xin quyền ghi file qua bad_query
        let res = bq.grantAccess(atPath: mgURL.deletingLastPathComponent().path, toFileName: mgURL.lastPathComponent)
        if !res.0 {
            throw NSError(domain: "MGError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể xin quyền ghi file MobileGestalt."])
        }
        
        // 2. Lưu bản gốc nếu chưa có (để Reset)
        let backupURL = URL.documentsDirectory.appendingPathComponent("OriginalGestalt.plist")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            let currentData = try Data(contentsOf: mgURL)
            try currentData.write(to: backupURL)
        }
        
        // 3. Ghi file đã sửa
        let data = try PropertyListSerialization.data(fromPropertyList: store.mgCurrentDict, format: .binary, options: 0)
        try data.write(to: mgURL)
        
        print("[MG] Applied MobileGestalt tweaks successfully via Erosion logic.")
    }
}