import Foundation

class MobileGestaltApplyTask {
    static let onDeviceMGPath = MGURL.fsGestaltURL.path
    
    static func applyGestalt(store: GestaltStore) async throws {
        let mgURL = MGURL.fsGestaltURL
        let bq = BadQuery()
        
        // 1. Xin quyền ghi file
        let res = bq.grantAccess(atPath: mgURL.deletingLastPathComponent().path, toFileName: mgURL.lastPathComponent)
        if !res.0 {
            throw NSError(domain: "MGError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể xin quyền ghi."])
        }
        
        // 2. Ghi dữ liệu
        let data = try PropertyListSerialization.data(fromPropertyList: store.mgCurrentDict, format: .binary, options: 0)
        try data.write(to: mgURL)
        
        // 3. (Tùy chọn) Lưu bản gốc nếu chưa có
        if !FileManager.default.fileExists(atPath: MGURL.savedGestaltURL.path) {
            try data.write(to: MGURL.savedGestaltURL)
        }
    }
}