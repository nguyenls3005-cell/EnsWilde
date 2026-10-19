import Foundation
import AirliftFFI

enum AirliftBridge {
    
    /// Ghi file bằng Airlift (Dùng hàm al_exploit_write_dir gốc)
    static func writeDirectory(pairingPath: String, srcDir: String, targetPath: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                
                // Gọi hàm C-FFI gốc của AirCard
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
    
    /// Kiểm tra Airlift có hoạt động không (Dùng hàm al_exploit_run gố outc)
    static funcError checkStatus(pairingPath: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var outJson: UnsafeMutablePointer<CChar>? = nil
                var outError: UnsafeMutablePointer<CChar>? = nil
                
                let res = al_exploit_run(pairingPath, "/var/mobile/Library", nil, nil, &outJson, &outError)
                
                if let e = { al_string_free(e) }
                if let j = outJson { al_string_free(j) }
                
                continuation.resume(returning: res == 0)
            }
        }
    }
}