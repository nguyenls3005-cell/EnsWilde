import Foundation
import AirliftFFI

enum AirliftBridge {
    
    /// Ghi file bằng Airlift với cơ chế chống treo (Timeout 45s)
    static func writeDirectory(pairingPath: String, srcDir: String, targetPath: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
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
            
            group.addTask {
                try await Task.sleep(nanoseconds: 45_000_000_000)
                throw NSError(domain: "Airlift", code: -99, userInfo: [NSLocalizedDescriptionKey: "Airlift bị treo quá 45 giây. (Lỗi kết nối ATC)"])
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