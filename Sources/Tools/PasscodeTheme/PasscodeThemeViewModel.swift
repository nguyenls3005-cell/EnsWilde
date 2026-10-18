import Foundation
import AirliftFFI

class PasscodeThemeViewModel: ObservableObject {
    
    // ... (Các biến State cũ giữ nguyên) ...

    func applyTheme(theme: PasscodeThemeModel) async throws {
        let isAirLiftMode = UserDefaults.standard.bool(forKey: "isAirLiftMode")
        
        if isAirLiftMode {
            print("[PasscodeTheme] Applying via AirLift...")
            
            guard let pairingPath = getPairingPath() else {
                throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
            }
            
            // 1. Tạo thư mục tạm
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftDialer_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            // 2. Chuẩn bị dữ liệu
            // Giả sử theme.buttons có 10 nút. Bạn cần điều chỉnh lại tên file cho đúng với cấu trúc TelephonyUI-10
            for i in 0..<10 {
                if let imageData = theme.buttons[i].imageData {
                    let fileName = "\(i).png" // Thay bằng tên file thực tế
                    try imageData.write(to: tempDir.appendingPathComponent(fileName))
                }
            }
            
            // 3. Gọi AirLift ghi thư mục
            var errorCString: UnsafeMutablePointer<CChar>? = nil
            let targetPath = "/var/mobile/Library/Caches/com.apple.TelephonyUI/TelephonyUI-10"
            
            let result = al_exploit_write_dir(
                pairingPath,
                tempDir.path,
                targetPath,
                nil,
                nil,
                &errorCString
            )
            
            if result != 0 {
                let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown AirLift Error"
                if let err = errorCString { al_string_free(err) }
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "AirLift Error: \(errorMsg)"])
            }
            
            print("[PasscodeTheme] AirLift apply successful.")
            
        } else {
            // ... (Code Bad Query cũ của bạn) ...
        }
    }
    
    private func getPairingPath() -> String? {
        let url = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }
}