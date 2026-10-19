import Foundation
import AirliftFFI
import Network

enum AppleWalletTask {
    static func run(store: ToolStore, walletStore: AppleWalletStore, onLogUpdate: @escaping (String) -> Void) async throws {
        let enabledCards = walletStore.enabledCards()
        guard !enabledCards.isEmpty else { throw ToolTaskError.generic("No enabled wallet cards to apply") }
        
        guard NetworkStatus.isVPNTunnelPresent() else { throw ToolTaskError.generic("VPN chưa bật.") }
        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw ToolTaskError.generic("Không tìm thấy Pairing File.")
        }
        let pairingPath = pairingURL.path
        
        onLogUpdate("Đang dò tunnel IP...")
        guard let _ = await AirliftHostResolver.bestAvailable(log: onLogUpdate) else {
            throw ToolTaskError.generic("Không tìm thấy RSD tunnel.")
        }
        
        let observer = NotificationCenter.default.addObserver(forName: .airliftLog, object: nil, queue: .main) { note in
            if let line = note.userInfo?["line"] as? String { onLogUpdate("[Airlift] \(line)") }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        
        let tempFolderName = "AirLiftWallet_\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(tempFolderName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        for card in enabledCards {
            let cardBasePath = tempDir.appendingPathComponent("Passes/Cards").appendingPathComponent(card.id)
            try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("pkpass"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("cache"), withIntermediateDirectories: true)
            
            if let bgData = card.backgroundImageData { try bgData.write(to: cardBasePath.appendingPathExtension("pkpass").appendingPathComponent(card.cardBackgroundFileName)) }
            if let fData = card.frontFaceImageData { try fData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("FrontFace")) }
            if let pData = card.placeHolderImageData { try pData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("PlaceHolder")) }
            if let prData = card.previewImageData { try prData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("Preview")) }
            if let passJSON = card.loadPassJSON() { try passJSON.write(to: cardBasePath.appendingPathExtension("pkpass").appendingPathComponent("pass.json")) }
        }
        
        onLogUpdate("Pushing files via AirTraffic...")
        let srcDir = tempDir.appendingPathComponent("Passes/Cards").path
        let targetParentDir = "/var/mobile/Library/Passes"
        
        _ = BadQuery().grantAccess(atPath: targetParentDir)
        
        let resultCode: Int32 = try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                return await withCheckedContinuation { continuation in
                    let worker = Thread {
                        var errPtr: UnsafeMutablePointer<CChar>? = nil
                        let res = al_exploit_inject_folder(pairingPath, srcDir, targetParentDir, "Cards", nil, nil, &errPtr)
                        if let e = errPtr {
                            let msg = String(cString: e)
                            onLogUpdate("[Airlift Error] \(msg)")
                            al_string_free(e)
                        }
                        continuation.resume(returning: res)
                    }
                    worker.name = "AirliftWalletWorker"
                    worker.stackSize = 8 * 1024 * 1024
                    worker.start()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                throw NSError(domain: "AirLift", code: -99, userInfo: [NSLocalizedDescriptionKey: "Quá thời gian 60s."])
            }
            let res = try await group.next()!
            group.cancelAll()
            return res
        }
        
        if resultCode != 0 {
            throw NSError(domain: "AirLift", code: Int(resultCode), userInfo: [NSLocalizedDescriptionKey: "AirLift thất bại mã \(resultCode)."])
        }
        
        onLogUpdate("✅ Wallet applied.")
    }
}