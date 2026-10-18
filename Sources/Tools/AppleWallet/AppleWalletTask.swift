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
            print("[AppleWallet] Applying via AirLift...")
            ApplyLogger.shared.log("[AppleWallet] Starting AirLift apply...")
            
            guard let pairingPath = getPairingPath() else {
                throw ToolTaskError.generic("Không tìm thấy Pairing File.")
            }
            
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftWallet_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            for card in enabledCards {
                let cardBasePath = tempDir.appendingPathComponent("Passes/Cards/\(card.id)")
                try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("pkpass"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("cache"), withIntermediateDirectories: true)
                
                if let bgData = card.backgroundImageData {
                    let url = cardBasePath.appendingPathExtension("pkpass").appendingPathComponent(card.cardBackgroundFileName)
                    try bgData.write(to: url)
                    ApplyLogger.shared.log("[AppleWallet] Prepared background for card \(card.id)")
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
            
            ApplyLogger.shared.log("[AppleWallet] Pushing files via AirLift to system...")
            
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
            
            ApplyLogger.shared.log("[AppleWallet] AirLift apply successful.")
            print("[AppleWallet] AirLift apply successful.")
            
        } else {
            var allFiles: [BookRestoreFile] = []
            // ... (code Bad Query cũ) ...
        }
    }
    
    private static func getPairingPath() -> String? {
        let url = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }
}