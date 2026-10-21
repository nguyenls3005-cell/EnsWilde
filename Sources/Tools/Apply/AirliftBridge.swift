import Foundation
import AirliftFFI
import Network

enum AirliftBridge {
    
    static func writeDirectory(pairingPath: String, srcDir: String, targetPath: String) async throws {
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "Airlift", code: -10, userInfo: [NSLocalizedDescriptionKey: "LocalDevVPN đang Not Ready. Hãy bật VPN và thử lại."])
        }
        
        guard FileManager.default.fileExists(atPath: pairingPath) else {
            throw NSError(domain: "Airlift", code: -11, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        
        let pairingData = try Data(contentsOf: URL(fileURLWithPath: pairingPath))
        let pairingStr = String(data: pairingData, encoding: .utf8) ?? ""
        guard pairingStr.contains("public_key") && pairingStr.contains("alt_irk") else {
            throw NSError(domain: "Airlift", code: -12, userInfo: [NSLocalizedDescriptionKey: "Pairing File không phải RPPairing."])
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let semaphore = DispatchSemaphore(value: 0)
            var threadError: Error? = nil
            
            let thread = Thread {
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                let res = al_exploit_write_dir(pairingPath, srcDir, targetPath, nil, nil, &errPtr)
                
                if res != 0 {
                    let msg = errPtr != nil ? String(cString: errPtr!) : "Airlift Error (Code: \(res))"
                    if let e = errPtr { al_string_free(e) }
                    threadError = NSError(domain: "Airlift", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg])
                }
                semaphore.signal()
            }
            thread.name = "AirliftWorker"
            thread.stackSize = 8 * 1024 * 1024
            thread.start()
            
            let timeout = DispatchTime.now() + .seconds(60)
            if semaphore.wait(timeout: timeout) == .timedOut {
                continuation.resume(throwing: NSError(domain: "Airlift", code: -99, userInfo: [NSLocalizedDescriptionKey: "Airlift bị treo quá 60 giây."]))
            } else if let error = threadError {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}