import Foundation
import AirliftFFI
import Network

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
            
            guard let pairingPath = getPairingPath() else {
                throw ToolTaskError.generic("Không tìm thấy Pairing File.")
            }
            
            // 1. Dò tìm IP Loopback
            let targetIP = await findActiveLoopbackIP()
            guard let validIP = targetIP else {
                throw ToolTaskError.generic("Không thể kết nối tới LocalDevVPN. Hãy bật VPN và thử lại.")
            }
            
            print("[AppleWallet] Using Loopback IP: \(validIP)")
            _ = al_set_target_host(validIP)
            
            // 2. Tạo thư mục tạm
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftWallet_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            // 3. Chuẩn bị file
            for card in enabledCards {
                let cardBasePath = tempDir.appendingPathComponent("Passes/Cards/\(card.id)")
                try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("pkpass"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("cache"), withIntermediateDirectories: true)
                
                if let bgData = card.backgroundImageData {
                    let url = cardBasePath.appendingPathExtension("pkpass").appendingPathComponent(card.cardBackgroundFileName)
                    try bgData.write(to: url)
                }
                if let frontFaceData = card.frontFaceImageData {
                    try frontFaceData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("FrontFace"))
                }
                if let placeHolderData = card.placeHolderImageData {
                    try placeHolderData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("PlaceHolder"))
                }
                if let previewData = card.previewImageData {
                    try previewData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("Preview"))
                }
                if let passJSON = card.loadPassJSON() {
                    try passJSON.write(to: cardBasePath.appendingPathExtension("pkpass").appendingPathComponent("pass.json"))
                }
            }
            
            // 4. Gọi AirLift
            var errorCString: UnsafeMutablePointer<CChar>? = nil
            let targetSystemPath = "/var/mobile/Library/Passes/Cards"
            
            let result = al_exploit_write_dir(
                pairingPath,
                tempDir.path + "/Passes/Cards",
                targetSystemPath,
                nil,
                nil,
                &errorCString
            )
            
            if result != 0 {
                let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown AirLift Error"
                if let err = errorCString { al_string_free(err) }
                throw ToolTaskError.generic("AirLift Error: \(errorMsg)")
            }
            
            print("[AppleWallet] AirLift apply successful.")
            
        } else {
            // ==========================================
            // CHẾ ĐỘ BAD QUERY CŨ (Đã khôi phục đầy đủ)
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
    
    private static func getPairingPath() -> String? {
        let url = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }
    
    private static func findActiveLoopbackIP() async -> String? {
        let candidates = ["10.7.0.1", "127.0.0.1"]
        for ip in candidates {
            if await isHostReachable(ip: ip) {
                return ip
            }
        }
        return nil
    }
    
    private static func isHostReachable(ip: String) async -> Bool {
        guard let url = URL(string: "http://\(ip)") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode > 0 {
                return true
            }
        } catch {
            return false
        }
        return false
    }
}