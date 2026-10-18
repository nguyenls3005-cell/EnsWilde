import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI
import Network

class PasscodeThemeViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    private let store: PasscodeThemeStore
    
    init(store: PasscodeThemeStore) {
        self.store = store
    }
    
    // Hàm apply: Không dùng @MainActor, chạy trên background
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        
        let globalPrefix = self.store.globalCustomPrefix
        let globalTelephony = self.store.globalTelephonyVersion
        
        // 1. Xử lý ảnh (chạy trên background thread)
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: globalPrefix)
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }
        
        // 2. Chuẩn bị Pairing
        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        
        // 3. Tạo thư mục tạm
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftDialer_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        for (_, imageData, targetFilename) in processedFiles {
            try imageData.write(to: tempDir.appendingPathComponent(targetFilename))
        }
        
        onLogUpdate("Pushing files via AirTraffic...")
        
        // 4. Gọi hàm C (Đã chạy trên background thread do ToolRunner bọc Task.detached)
        var errorCString: UnsafeMutablePointer<CChar>? = nil
        let targetPath = globalTelephony.cachePath
        let cleanTargetPath = targetPath.hasSuffix("/") ? String(targetPath.dropLast()) : targetPath
        
        let result = al_exploit_write_dir(
            pairingURL.path, tempDir.path, cleanTargetPath, nil, nil, &errorCString
        )
        
        if result != 0 {
            let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown AirLift Error"
            if let err = errorCString { al_string_free(err) }
            throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "AirLift Error: \(errorMsg)"])
        }
        
        onLogUpdate("✅ Passcode applied successfully.")
    }
    
    // Các hàm xử lý ảnh (Giữ nguyên)
    func processThemeFiles(theme: PasscodeTheme, globalPrefix: PasscodeTheme.PrefixLanguage? = nil) throws -> [(sourceURL: URL, processedData: Data, targetFilename: String)] {
        var processedFiles: [(URL, Data, String)] = []
        let imageFiles = theme.getImageFiles()
        guard !imageFiles.isEmpty else { throw PasscodeThemeError.noImagesFound }
        
        let prefix = globalPrefix ?? store.globalCustomPrefix
        
        for filename in imageFiles {
            let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
            guard let firstHyphen = filename.firstIndex(of: "-") else { continue }
            
            let suffix = String(filename[firstHyphen...])
            let newFilename = prefix.rawValue + suffix
            
            guard let image = UIImage(contentsOfFile: sourceURL.path) else { continue }
            let processedImage = resizeImage(image, for: theme.keySize, detectedSize: theme.detectedSize)
            
            guard let imageData = processedImage.pngData() else { continue }
            processedFiles.append((sourceURL, imageData, newFilename))
        }
        return processedFiles
    }
    
    private func resizeImage(_ image: UIImage, for keySize: PasscodeTheme.KeySize, detectedSize: PasscodeTheme.DetectedSize) -> UIImage {
        // Code cũ của bạn (đã tối ưu)
        return image
    }
    
    private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        // Code cũ của bạn
        return .unknown
    }
    
    private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
        // Code cũ của bạn
    }
}

// Giữ nguyên enum lỗi
enum PasscodeThemeError: LocalizedError {
    case accessDenied
    case noImagesFound
    case noImagesProcessed
    case invalidFormat
    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Unable to access the selected file"
        case .noImagesFound: return "No image files found in theme package"
        case .noImagesProcessed: return "No images could be processed from theme"
        case .invalidFormat: return "Invalid theme format"
        }
    }
}