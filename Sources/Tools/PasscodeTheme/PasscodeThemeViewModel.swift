import Foundation
import AirliftFFI

class PasscodeThemeViewModel: ObservableObject {
    
    // ✅ Hàm áp dụng Passcode Theme bằng AirLift
    func applyThemeWithAirLift(theme: PasscodeThemeModel, isAirLiftMode: Bool) throws {
        if !isAirLiftMode {
            // Gọi hàm Bad Query cũ của bạn ở đây
            // applyThemeOldWay(theme: theme)
            return
        }

        // 1. Khởi tạo AirLift
        let initResult = al_exploit_init()
        guard initResult else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lỗi kết nối AirLift (VPN/Pairing)"])
        }
        
        // 2. Đường dẫn gốc của TelephonyUI (Dialer)
        let basePath = "/var/mobile/Library/Caches/com.apple.TelephonyUI/TelephonyUI-10"
        
        // 3. Duyệt 10 nút và ghi bằng AirLift
        for i in 0..<10 {
            guard let imageData = theme.buttons[i].imageData else { continue }
            
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("btn_\(i).png")
            try imageData.write(to: tempFile)
            
            // Tên file thực tế có thể khác, bạn cần xem code Bad Query cũ của bạn
            let targetFile = "\(basePath)/\(i).png" 
            
            // Gọi hàm AirLift ghi file
            let ok = al_exploit_write_file(tempFile.path, targetFile)
            if !ok {
                print("Lỗi ghi nút \(i)")
            }
            try? FileManager.default.removeItem(at: tempFile)
        }
    }
}