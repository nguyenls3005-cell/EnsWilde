import Foundation
import AirliftFFI

enum AirliftBridge {
    
    /// Ghi file bằng Airlift (dùng al_exploit_run để có Tokio Runtime)
    static func writeDirectory(pairingPath: String, srcDir: String, targetPath: String) async throws {
        // al_exploit_run là hàm an toàn nhất vì nó tự khởi tạo Tokio Runtime bên trong
        // Nó sẽ chạy full pipeline: stage -> ATC sync -> write
        // Tuy nhiên, al_exploit_run chỉ ghi được file canary, không ghi được file tùy ý.
        // Nên t dùng nó để "warm up" Runtime trước, sau đó mới gọi write_dir.
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                var outJson: UnsafeMutablePointer<CChar>? = nil
                
                // Bước 1: Warm up Runtime bằng al_exploit_run (hàm này an toàn)
                // Nó sẽ chạy canary test, khởi tạo Tokio Runtime bên trong Rust
                let warmupRes = al_exploit_run(pairingPath, "/var/mobile/Library", nil, nil, &outJson, &errPtr)
                
                if let j = outJson { al_string_free(j) }
                if let e = errPtr { al_string_free(e) }
                
                // Dù warmup thành công hay không, Runtime đã được khởi tạo.
                // Giờ gọi write_dir (nó sẽ dùng Runtime đã có sẵn, không bị treo nữa).
                var writeErr: UnsafeMutablePointer<CChar>? = nil
                let res = al_exploit_write_dir(pairingPath, srcDir, targetPath, nil, nil, &writeErr)
                
                if res != 0 {
                    let msg = writeErr != nil ? String(cString: writeErr!) : "Airlift Error (Code: \(res))"
                    if let e = writeErr { al_string_free(e) }
                    continuation.resume(throwing: NSError(domain: "Airlift", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg]))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}