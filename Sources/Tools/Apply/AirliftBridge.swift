import Foundation
import AirliftFFI

enum AirliftBridge {
    
    static func writeDirectory(pairingPath: String, srcDir: String, targetPath: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                
                // 1. "Warm-up" bằng al_exploit_run để tạo Tokio Runtime bên trong Rust
                var outJson: UnsafeMutablePointer<CChar>? = nil
                var warmupErr: UnsafeMutablePointer<CChar>? = nil
                _ = al_exploit_run(pairingPath, "/var/mobile/Library", nil, nil, &outJson, &warmupErr)
                
                if let j = outJson { al_string_free(j) }
                if let e = warmupErr { al_string_free(e) }
                
                // 2. Bây giờ gọi write_dir (Runtime đã có sẵn, không bị treo nữa)
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
}