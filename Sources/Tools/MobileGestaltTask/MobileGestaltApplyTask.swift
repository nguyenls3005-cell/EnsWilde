import Foundation
import UIKit

enum MobileGestaltApplyTask {
    // Đường dẫn chuẩn iOS 27 (lấy từ GestaltStore)
    static var onDeviceMGPath: String {
        return MGURL.fsGestaltURL.path
    }

    static func applyGestalt(store: GestaltStore) async throws {
        let mgURL = MGURL.fsGestaltURL
        let bq = BadQuery()
        
        // 1. Xin quyền ghi file qua bad_query
        let res = bq.grantAccess(atPath: mgURL.deletingLastPathComponent().path, toFileName: mgURL.lastPathComponent)
        if !res.0 {
            throw NSError(domain: "MGError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể xin quyền ghi file MobileGestalt."])
        }
        
        // 2. Lưu bản gốc nếu chưa có (để Reset sau này)
        if !FileManager.default.fileExists(atPath: MGURL.savedGestaltURL.path) {
            let currentData = try Data(contentsOf: mgURL)
            try currentData.write(to: MGURL.savedGestaltURL)
        }
        
        // 3. Ghi file đã sửa
        let data = try PropertyListSerialization.data(fromPropertyList: store.mgCurrentDict, format: .binary, options: 0)
        try data.write(to: mgURL)
        
        print("[MG] Applied MobileGestalt tweaks successfully via Erosion logic.")
    }
}