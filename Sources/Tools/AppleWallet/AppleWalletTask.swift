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
        
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw ToolTaskError.generic("Không phát hiện tunnel VPN. Bật LocalDevVPN hoặc StikDebug VPN rồi thử lại.")
        }
        
        guard let pairingPath = getPairingPath() else {
            throw ToolTaskError.generic("Không tìm thấy Pairing File.")
        }
        
        onLogUpdate("Đang dò tunnel IP...")
        guard let host = await AirliftHostResolver.bestAvailable(log: onLogUpdate) else {
            throw ToolTaskError.generic("Không tìm thấy RSD tunnel. Kiểm tra: (1) VPN đang bật, (2) Developer Mode đã bật, (3) Apple Books đã cài.")
        }
        onLogUpdate("✅ Tunnel: \(host)")
        
        let observer = NotificationCenter.default.addObserver(forName: .airliftLog, object: nil, queue: .main) { note in
            if let line = note.userInfo?["line"] as? String {
                onLogUpdate("[Airlift] \(line)")
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftWallet_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        for card in enabledCards {
            let cardBasePath = tempDir.appendingPathComponent("Passes/Cards").appendingPathComponent(card.id)
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
        let srcDir = tempDir.appendingPathComponent("Passes/Cards").path
        let targetSystemPath = "/var/mobile/Library/Passes/Cards"
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorCString: UnsafeMutablePointer<CChar>? = nil
                let result = al_exploit_write_dir(pairingPath, srcDir, targetSystemPath, nil, nil, &errorCString)
                if result != 0 {
                    let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown AirLift Error"
                    if let err = errorCString { al_string_free(err) }
                    continuation.resume(throwing: ToolTaskError.generic("AirLift Error: \(errorMsg)"))
                } else {
                    continuation.resume()
                }
            }
        }
        
        onLogUpdate("✅ Wallet applied via AirLift.")
    }
    
    private static func getPairingPath() -> String? {
        let url = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }
}