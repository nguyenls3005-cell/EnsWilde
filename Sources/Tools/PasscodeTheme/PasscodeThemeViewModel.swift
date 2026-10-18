import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI
import Network

@MainActor
class PasscodeThemeViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    private let store: PasscodeThemeStore
    
    init(store: PasscodeThemeStore) {
        self.store = store
    }
    
    // Import Theme (Giữ nguyên)
    func importTheme(from sourceURL: URL, name: String) async throws {
        isProcessing = true
        defer { isProcessing = false }
        // ... (Giữ nguyên code import của bạn) ...
        
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
        try? FileManager.default.removeItem(at: tempFileURL)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: tempFileURL)
        } catch {
            throw PasscodeThemeError.accessDenied
        }
        
        let newTheme = PasscodeTheme(name: name)
        let themeFolder = newTheme.themeFolderURL
        
        if !FileManager.default.fileExists(atPath: themeFolder.path) {
            try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        }
        
        let detectedSize = detectSizeFromZIP(at: tempFileURL)
        
        do {
            try FileManager.default.unzipItem(at: tempFileURL, to: themeFolder)
        } catch {
            try? FileManager.default.removeItem(at: themeFolder)
            throw PasscodeThemeError.invalidFormat
        }
        
        try extractImagesFromTelephonySubfolder(themeFolder: themeFolder)
        try? FileManager.default.removeItem(at: tempFileURL)
        
        var themeWithSize = newTheme
        themeWithSize.detectedSize = detectedSize
        store.addTheme(themeWithSize)
    }
    
    // Process files (Giữ nguyên)
    func processThemeFiles(theme: PasscodeTheme, globalPrefix: PasscodeTheme.PrefixLanguage? = nil) throws -> [(sourceURL: URL, processedData: Data, targetFilename: String)] {
        // ... (Giữ nguyên code xử lý ảnh của bạn) ...
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
        // ... (Giữ nguyên code resize của bạn) ...
        return image // Placeholder
    }
    
    private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        // ... (Giữ nguyên code detect của bạn) ...
        return .unknown // Placeholder
    }
    
    private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
        // ... (Giữ nguyên code extract của bạn) ...
    }
    
    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        // Code cũ
    }
    
    // ✅ HÀM APPLY: CHẠY THẬT TRÊN BACKGROUND THREAD
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        let globalPrefix = self.store.globalCustomPrefix
        let globalTelephony = self.store.globalTelephonyVersion
        
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: globalPrefix)
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }
        
        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftDialer_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        for (_, imageData, targetFilename) in processedFiles {
            try imageData.write(to: tempDir.appendingPathComponent(targetFilename))
        }
        
        // Ép cứng IP
        _ = al_set_target_host("127.0.0.1")
        
        // CHẠY HÀM C TRÊN BACKGROUND THREAD
        try await Task.detached(priority: .high) {
            var errorCString: UnsafeMutablePointer<CChar>? = nil
            let targetPath = globalTelephony.cachePath
            let cleanTargetPath = targetPath.hasSuffix("/") ? String(targetPath.dropLast()) : targetPath
            
            // Hàm C sẽ block thread này cho đến khi xong hoặc lỗi
            let result = al_exploit_write_dir(
                pairingURL.path, tempDir.path, cleanTargetPath, nil, nil, &errorCString
            )
            
            if result != 0 {
                let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown AirLift Error"
                if let err = errorCString { al_string_free(err) }
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "AirLift Error: \(errorMsg)"])
            }
        }.value
        
        onLogUpdate("✅ Passcode applied successfully.")
    }
}

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