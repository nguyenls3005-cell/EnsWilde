import Foundation
import AirliftFFI
import Network

enum AirliftBridge {
    
    static func writeDirectory(pairingPath: String, srcDir: String, targetPath: String) async throws {
        // 1. Kiểm tra VPN
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "Airlift", code: -10, userInfo: [NSLocalizedDescriptionKey: "LocalDevVPN chưa bật. Hãy bật VPN."])
        }
        
        // 2. Kiểm tra Pairing
        let pairingData = try Data(contentsOf: URL(fileURLWithPath: pairingPath))
        let pairingStr = String(data: pairingData, encoding: .utf8) ?? ""
        guard pairingStr.contains("public_key") && pairingStr.contains("alt_irk") else {
            throw NSError(domain: "Airlift", code: -12, userInfo: [NSLocalizedDescriptionKey: "Sai Pairing File."])
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                
                // BƯỚC QUAN TRỌNG: Warm-up Runtime bằng al_exploit_run
                var outJson: UnsafeMutablePointer<CChar>? = nil
                var warmupErr: UnsafeMutablePointer<CChar>? = nil
                _ = al_exploit_run(pairingPath, "/var/mobile/Library", nil, nil, &outJson, &warmupErr)
                if let j = outJson { al_string_free(j) }
                if let e = warmupErr { al_string_free(e) }
                
                // Sau khi warm-up, gọi write_dir
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                let res = al_exploit_write_dir(pairingPath, srcDir, targetPath, nil, nil, &errPtr)
                
                if res != 0 {
                    let msg = errPtr != nil ? String(cString: errPtr!) : "Lỗi Airlift (\(res))"
                    if let e = errPtr { al_string_free(e) }
                    continuation.resume(throwing: NSError(domain: "Airlift", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg]))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}