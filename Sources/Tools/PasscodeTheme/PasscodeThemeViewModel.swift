import Foundation
import Combine
import AirliftFFI // Import AirLift

class PasscodeThemeViewModel: ObservableObject {
    
    // Khai báo lại các thuộc tính cũ của bạn (nếu thiếu cái nào bạn tự thêm vào nhé)
    @Published var themes: [PasscodeThemeModel] = []
    @Published var isApplying: Bool = false
    private var themeStore: PasscodeThemeStore?
    
    // Hàm khởi tạo bắt buộc phải có tham số 'store' như Xcode đang tìm
    init(store: PasscodeThemeStore) {
        self.themeStore = store
    }
    
    // ==========================================
    // CÁC HÀM CŨ (Khôi phục lại để Xcode không báo lỗi)
    // ==========================================
    
    func importTheme(from url: URL, name: String) async throws {
        // Code import theme cũ của bạn (giữ nguyên)
        // ...
    }
    
    func importDefaultPasscode(from url: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        // Code import default cũ của bạn (giữ nguyên)
        // ...
    }
    
    // ==========================================
    // HÀM APPLY (Đã tích hợp AirLift)
    // ==========================================
    
    func applyTheme(theme: PasscodeThemeModel) async throws {
        let isAirLiftMode = UserDefaults.standard.bool(forKey: "isAirLiftMode")
        
        if isAirLiftMode {
            print("[PasscodeTheme] Applying via AirLift...")
            
            // Lấy đường dẫn pairing
            guard let pairingPath = getPairingPath() else {
                throw PasscodeThemeError.invalidFormat // Hoặc lỗi custom của bạn
            }
            
            // 1. Tạo thư mục tạm chứa 10 nút
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftDialer_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            // 2. Ghi file ảnh vào thư mục tạm
            for i in 0..<10 {
                if let imageData = theme.buttons[i].imageData {
                    let fileName = "\(i).png" // Tên file thực tế tùy thuộc vào code cũ của bạn
                    try imageData.write(to: tempDir.appendingPathComponent(fileName))
                }
            }
            
            // 3. Gọi AirLift ghi đè
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
                let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown Error"
                if let err = errorCString { al_string_free(err) }
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
            
            print("[PasscodeTheme] AirLift apply successful.")
            
        } else {
            // CODE BAD QUERY CŨ CỦA BẠN (Giữ nguyên)
            // try await applyThemeOldWay(theme: theme)
        }
    }
    
    private func getPairingPath() -> String? {
        let url = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }
}