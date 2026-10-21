import Foundation
import AirliftFFI
import Network

enum AirliftBridge {
    
    static func writeDirectory(pairingPath: String, srcDir: String, targetPath: String) async throws {
        // 1. Kiểm tra VPN (Bắt buộc LocalDevVPN phải bật)
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "Airlift", code: -10, userInfo: [NSLocalizedDescriptionKey: "Lỗi: LocalDevVPN đang Not Ready. Hãy bật VPN rồi thử lại."])
        }
        
        // 2. Kiểm tra Pairing file
        guard FileManager.default.fileExists(atPath: pairingPath) else {
            throw NSError(domain: "Airlift", code: -11, userInfo: [NSLocalizedDescriptionKey: "Lỗi: Không tìm thấy Pairing File."])
        }
        
        let pairingData = try Data(contentsOf: URL(fileURLWithPath: pairingPath))
        let pairingStr = String(data: pairingData, encoding: .utf8) ?? ""
        guard pairingStr.contains("public_key") && pairingStr.contains("alt_irk") else {
            throw NSError(domain: "Airlift", code: -12, userInfo: [NSLocalizedDescriptionKey: "Lỗi: Pairing File không phải RPPairing (thiếu public_key/alt_irk)."])
        }

        // 3. Chạy Airlift trong Thread riêng với Timeout 45s
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        var errPtr: UnsafeMutablePointer<CChar>? = nil
                        
                        // Gọi hàm C-FFI gốc
                        let res = al_exploit_write_dir(pairingPath, srcDir, targetPath, nil, nil, &errPtr)
                        
                        if res != 0 {
                            let msg = errPtr != nil ? String(cString: errPtr!) : "Airlift Error (Code: \(res))"
                            if let e = errPtr { al_string_free(e) }
                            continuation.resume(throwing: NSError(domain: "Airlift", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg]))
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: 45_000_000_000)
                throw NSError(domain: "Airlift", code: -99, userInfo: [NSLocalizedDescriptionKey: "Airlift bị treo quá 45s. (Kiểm tra lại VPN và Pairing File)"])
            }
            
            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}