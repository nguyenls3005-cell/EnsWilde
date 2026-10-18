import Foundation
import AirliftFFI

enum AppleWalletTask {
    
    static func run(store: ToolStore, walletStore: AppleWalletStore) async throws {
        let isAirLiftMode = UserDefaults.standard.bool(forKey: "isAirLiftMode")
        let enabledCards = walletStore.enabledCards()
        guard !enabledCards.isEmpty else {
            throw ToolTaskError.generic("No enabled wallet cards to apply")
        }
        
        if isAirLiftMode {
            // ==========================================
            // CHẾ ĐỘ AIRLIFT
            // ==========================================
            print("[AppleWallet] Applying via AirLift...")
            
            // 1. Lấy đường dẫn pairing file
            guard let pairingPath = getPairingPath() else {
                throw ToolTaskError.generic("Không tìm thấy Pairing File.")
            }
            
            // 2. Tạo thư mục tạm để chứa các file cần ghi
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftWallet_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) } // Dọn dẹp sau khi xong
            
            // 3. Chuẩn bị cấu trúc thư mục y hệt trên máy
            for card in enabledCards {
                // Tạo thư mục đích trên máy tạm (giả lập)
                let cardBasePath = tempDir.appendingPathComponent("Passes/Cards/\(card.id)")
                try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("pkpass"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("cache"), withIntermediateDirectories: true)
                
                // Ghi Background (.pkpass)
                if let bgData = card.backgroundImageData {
                    let url = cardBasePath.appendingPathExtension("pkpass").appendingPathComponent(card.cardBackgroundFileName)
                    try bgData.write(to: url)
                }
                
                // Ghi Cache
                if let frontFaceData = card.frontFaceImageData {
                    try frontFaceData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("FrontFace"))
                }
                if let placeHolderData = card.placeHolderImageData {
                    try placeHolderData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("PlaceHolder"))
                }
                if let previewData = card.previewImageData {
                    try previewData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("Preview"))
                }
                
                // Ghi pass.json
                if let passJSON = card.loadPassJSON() {
                    try passJSON.write(to: cardBasePath.appendingPathExtension("pkpass").appendingPathComponent("pass.json"))
                }
            }
            
            // 4. Gọi hàm AirLift để bơm toàn bộ thư mục
            var errorCString: UnsafeMutablePointer<CChar>? = nil
            // Đường dẫn đích trên hệ thống iOS
            let targetSystemPath = "/var/mobile/Library/Passes/Cards"
            
            let result = al_exploit_write_dir(
                pairingPath,
                tempDir.path + "/Passes/Cards", // Nguồn: thư mục chứa các card
                targetSystemPath,               // Đích: thư mục hệ thống
                nil,                            // log_cb
                nil,                            // ctx
                &errorCString                   // out_error
            )
            
            if result != 0 {
                let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown AirLift Error"
                if let err = errorCString { al_string_free(err) }
                throw ToolTaskError.generic("AirLift Error: \(errorMsg)")
            }
            
            print("[AppleWallet] AirLift apply successful.")
            
        } else {
            // ==========================================
            // CHẾ ĐỘ BAD QUERY CŨ (Giữ nguyên)
            // ==========================================
            var allFiles: [BookRestoreFile] = []
            // ... (Giữ nguyên toàn bộ code Bad Query cũ của bạn ở đây) ...
            // ...
        }
    }
    
    // Hàm phụ để lấy đường dẫn Pairing File
    private static func getPairingPath() -> String? {
        // Thường file pairing được lưu trong Documents với tên "pairingFile.plist"
        let url = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        if FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }
        return nil
    }
}