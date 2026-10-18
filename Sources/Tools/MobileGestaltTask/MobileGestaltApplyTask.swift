import Foundation
import UIKit

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String {
        return MGURL.fsGestaltURL.path
    }

    static func applyGestalt(store: GestaltStore) async throws {
        let mgURL = MGURL.fsGestaltURL
        let bq = BadQuery()
        
        // Xin quyền ghi vào thư mục chứa file
        let res = bq.grantAccess(atPath: mgURL.deletingLastPathComponent().path, toFileName: mgURL.lastPathComponent)
        if !res.0 {
            throw NSError(domain: "MGError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể xin quyền ghi."])
        }
        
        // Nếu file đã tồn tại, đọc và lưu bản gốc (chỉ lưu 1 lần)
        if !FileManager.default.fileExists(atPath: MGURL.savedGestaltURL.path) {
            if let currentData = try? Data(contentsOf: mgURL) {
                try? currentData.write(to: MGURL.savedGestaltURL)
            }
        }
        
        // Ghi đè file plist
        let data = try PropertyListSerialization.data(fromPropertyList: store.mgCurrentDict, format: .binary, options: 0)
        try data.write(to: mgURL)
    }
}