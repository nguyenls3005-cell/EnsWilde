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
            guard let pairingPath = getPairingPath() else {
                throw ToolTaskError.generic("Không tìm thấy Pairing File.")
            }
            
            let targetIP = await findActiveLoopbackIP()
            guard let validIP = targetIP else {
                throw ToolTaskError.generic("Không thể kết nối tới LocalDevVPN. Hãy bật VPN và thử lại.")
            }
            _ = al_set_target_host(validIP)
            
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftWallet_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            for card in enabledCards {
                let cardBasePath = tempDir.appendingPathComponent("Passes/Cards/\(card.id)")
                try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("pkpass"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("cache"), withIntermediateDirectories: true)
                
                if let bgData = card.backgroundImageData {
                    try bgData.write(to: cardBasePath.appendingPathExtension("pkpass").appendingPathComponent(card.cardBackgroundFileName))
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
            
            var errorCString: UnsafeMutablePointer<CChar>? = nil
            let targetSystemPath = "/var/mobile/Library/Passes/Cards"
            
            let result = al_exploit_write_dir(
                pairingPath, tempDir.path + "/Passes/Cards", targetSystemPath, nil, nil, &errorCString
            )
            
            if result != 0 {
                let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown AirLift Error"
                if let err = errorCString { al_string_free(err) }
                throw ToolTaskError.generic("AirLift Error: \(errorMsg)")
            }
            
        } else {
            // Bad Query
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
                    allFiles.append(.walletImage(targetPath: frontFacePath, contents: frontFaceData, mediaFileName: "wallet_\(cardPrefix)_FrontFace"))
                }
                if let placeHolderData = card.placeHolderImageData {
                    let placeHolderPath = "\(cardBasePath).cache/PlaceHolder"
                    allFiles.append(.walletImage(targetPath: placeHolderPath, contents: placeHolderData, mediaFileName: "wallet_\(cardPrefix)_PlaceHolder"))
                }
                if let previewData = card.previewImageData {
                    let previewPath = "\(cardBasePath).cache/Preview"
                    allFiles.append(.walletImage(targetPath: previewPath, contents: previewData, mediaFileName: "wallet_\(cardPrefix)_Preview"))
                }
                if let passJSONData = card.loadPassJSON() {
                    let passJSONPath = "\(cardBasePath).pkpass/pass.json"
                    allFiles.append(.walletImage(targetPath: passJSONPath, contents: passJSONData, mediaFileName: "wallet_\(cardPrefix)_pass.json"))
                }
            }
            
            guard !allFiles.isEmpty else { throw ToolTaskError.generic("No wallet files to apply") }
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
            if let url = URL(string: "http://\(ip)") {
                var request = URLRequest(url: url)
                request.timeoutInterval = 1.0
                if let (_, _) = try? await URLSession.shared.data(for: request) { return ip }
            }
        }
        return nil
    }
}