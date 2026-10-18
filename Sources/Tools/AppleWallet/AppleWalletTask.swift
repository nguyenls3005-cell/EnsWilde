import Foundation
import AirliftFFI
import Network

enum AppleWalletTask {
    
    static func run(store: ToolStore, walletStore: AppleWalletStore, onLogUpdate: @escaping (String) -> Void) async throws {
        let enabledCards = walletStore.enabledCards()
        
        guard !enabledCards.isEmpty else {
            throw ToolTaskError.generic("No enabled wallet cards to apply")
        }
        
        onLogUpdate("Preparing AirLift for Wallet...")
        
        guard let pairingPath = getPairingPath() else {
            throw ToolTaskError.generic("Không tìm thấy Pairing File.")
        }
        
        let targetIP = await findActiveLoopbackIP()
        guard let validIP = targetIP else {
            throw ToolTaskError.generic("Không thể kết nối tới LocalDevVPN. Hãy bật VPN và thử lại.")
        }
        onLogUpdate("Using Loopback IP: \(validIP)")
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
        
        onLogUpdate("Pushing files via AirTraffic...")
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
        
        onLogUpdate("✅ Wallet applied via AirLift.")
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