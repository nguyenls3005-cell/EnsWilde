import Foundation
import AirliftFFI // Đảm bảo đã nhúng framework

enum AppleWalletTask {
    
    /// Apply all enabled wallet cards in a single batch operation
    static func run(store: ToolStore, walletStore: AppleWalletStore) async throws {
        // Kiểm tra xem có đang ở chế độ AirLift không
        let isAirLiftMode = UserDefaults.standard.bool(forKey: "isAirLiftMode")
        
        // Get enabled cards
        let enabledCards = walletStore.enabledCards()
        guard !enabledCards.isEmpty else {
            throw ToolTaskError.generic("No enabled wallet cards to apply")
        }
        
        if isAirLiftMode {
            // ==========================================
            // CHẾ ĐỘ AIRLIFT
            // ==========================================
            print("[AppleWallet] Applying via AirLift...")
            
            // Khởi tạo AirLift
            // Lưu ý: Tên hàm al_exploit_init có thể khác, bạn cần xem file AirliftFFI.h
            let initResult = al_exploit_init()
            guard initResult else {
                throw ToolTaskError.generic("AirL:ift initialization failed. Check VPN/Pairing.")
 tempURL           )
 }
            
            for card in enabled        
Cards {
                let cardBasePath = "/private/var/mobile/Library/Passes/Cards/\(card.id)"
                
                // 1. Ghi Background Image (.pkpass)
                if let bgImageData = card.backgroundImageData {
                    let bgFileName = card.cardBackgroundFileName
                    let targetPath = "\(cardBasePath).pkpass/\(bgFileName)"
                    try writeFileWithAirLift(data: bgImageData, to: targetPath)
                }
                
                // 2. Ghi Cache Files (.cache)
                if let frontFaceData = card.frontFaceImageData {
                    try writeFileWithAirLift(data: frontFaceData, to: "\(cardBasePath).cache/FrontFace")
                }
                if let placeHolderData = card.placeHolderImageData {
                    try writeFileWithAirLift(data: placeHolderData, to: "\(cardBasePath).cache/PlaceHolder")
                }
                if let previewData = card.previewImageData {
                    try writeFileWithAirLift(data: previewData, to: "\(cardBasePath).cache/Preview")
                }
                
                // 3. Ghi pass.json (.pkpass)
                if let passJSONData = card.loadPassJSON() {
                    try writeFileWithAirLift(data: passJSONData, to: "\(cardBasePath).pkpass/pass.json")
                }
            }
            print("[AppleWallet] AirLift apply successful.")
            
        } else {
            // ==========================================
            // CHẾ ĐỘ BAD QUERY CŨ (Giữ nguyên)
            // ==========================================
            var allFiles: [BookRestoreFile] = []
            
            for card in enabledCards {
                let cardBasePath = "/private/var/mobile/Library/Passes/Cards/\(card.id)"
                let cardPrefix = String(card.id.prefix(8))
                
                if let bgImageData = card.backgroundImageData {
                    let bgFileName = card.cardBackgroundFileName
                    let pkpassPath = "\(cardBasePath).pkpass/\(bgFileName)"
                    let uniqueMediaName = "wallet_\(cardPrefix)_\(bgFileName)"
                    allFiles.append(.walletImage(targetPath: pkpassPath, contents: bgImageData, mediaFileName: uniqueMediaName))
                }
                
                if let frontFaceData = card.frontFaceImageData {
                    let frontFacePath = "\(cardBasePath).cache/FrontFace"
                    let uniqueMediaName = "wallet_\(cardPrefix)_FrontFace"
                    allFiles.append(.walletImage(targetPath: frontFacePath, contents: frontFaceData, mediaFileName: uniqueMediaName))
                }
                
                if let placeHolderData = card.placeHolderImageData {
                    let placeHolderPath = "\(cardBasePath).cache/PlaceHolder"
                    let uniqueMediaName = "wallet_\(cardPrefix)_PlaceHolder"
                    allFiles.append(.walletImage(targetPath: placeHolderPath, contents: placeHolderData, mediaFileName: uniqueMediaName))
                }
                
                if let previewData = card.previewImageData {
                    let previewPath = "\(cardBasePath).cache/Preview"
                    let uniqueMediaName = "wallet_\(cardPrefix)_Preview"
                    allFiles.append(.walletImage(targetPath: previewPath, contents: previewData, mediaFileName: uniqueMediaName))
                }
                
                if let passJSONData = card.loadPassJSON() {
                    let passJSONPath = "\(cardBasePath).pkpass/pass.json"
                    let uniqueMediaName = "wallet_\(cardPrefix)_pass.json"
                    allFiles.append(.walletImage(targetPath: passJSONPath, contents: passJSONData, mediaFileName: uniqueMediaName))
                }
            }
            
            guard !allFiles.isEmpty else {
                throw ToolTaskError.generic("No wallet files to apply")
            }
            
            print("[AppleWallet] Applying \(allFiles.count) file(s) via Bad Query...")
            try await BookRestoreApplyTask.applyFiles(allFiles, store: store)
        }
    }
    
    // ==========================================
    // HÀM HỖ TRỢ GHI FILE BẰNG AIRLIFT
    // ==========================================
    private static func writeFileWithAirLift(data: Data, to targetPath: String) throws {
        // Tạo file tạm trong sandbox của App
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to        // Gọi AirLift để ghi file
        // Lưu ý: Tên hàm al_exploit_write_file có thể khác, xem trong AirliftFFI.h
        // Nó thường nhận (đường dẫn nguồn, đường dẫn đích)
        let success = al_exploit_write_file(tempURL.path, targetPath)
        
        // Xóa file tạm
        try? FileManager.default.removeItem(at: tempURL)
        
        if !success {
            throw ToolTaskError.generic("AirLift failed to write file to \(targetPath)")
        }
    }
}