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
        var sizeMultiplier: CGFloat = 1.0
        if detectedSize == .small && keySize == .big { sizeMultiplier = 287.0 / 202.0 }
        else if detectedSize == .big && keySize == .small { sizeMultiplier = 202.0 / 287.0 }
        else { return image }
        
        if abs(sizeMultiplier - 1.0) < PasscodeTheme.KeySize.resizeThreshold { return image }
        
        let currentSize = image.size
        guard currentSize.width > 0 && currentSize.height > 0 else { return image }
        
        let targetPixelSize = CGSize(width: currentSize.width * sizeMultiplier * image.scale, height: currentSize.height * sizeMultiplier * image.scale)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetPixelSize)) }
    }
    
    private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            for entry in archive { if entry.path.hasSuffix("_small") { return .small } }
            for entry in archive { if entry.path.hasSuffix("_big") { return .big } }
            return .unknown
        } catch { return .unknown }
    }
    
    private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) else { return }
        guard let telephonyFolder = contents.first(where: { $0.hasPrefix("Telephony") || $0.hasPrefix("TelephonyUI") }) else { return }
        
        let telephonyFolderURL = themeFolder.appendingPathComponent(telephonyFolder)
        guard let imageFiles = try? fm.contentsOfDirectory(atPath: telephonyFolderURL.path) else { return }
        
        for filename in imageFiles {
            let ext = (filename as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            
            let sourceURL = telephonyFolderURL.appendingPathComponent(filename)
            let destURL = themeFolder.appendingPathComponent(filename)
            try? fm.moveItem(at: sourceURL, to: destURL)
        }
        try? fm.removeItem(at: telephonyFolderURL)
    }
    
    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        // Code import default của bạn
    }
    
    // ✅ HÀM APPLY: BỎ QUA HOÀN TOÀN HTTP SERVER, CHỈ GỌI AIRLIFT
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: ((String) -> Void)? = nil) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        let isAirLiftMode = UserDefaults.standard.bool(forKey: "isAirLiftMode")
        let globalPrefix = self.store.globalCustomPrefix
        let globalTelephony = self.store.globalTelephonyVersion
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: globalPrefix)
        
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }
        
        if isAirLiftMode {
            let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
            guard FileManager.default.fileExists(atPath: pairingURL.path) else {
                throw PasscodeThemeError.accessDenied
            }
            
            // Dò IP
            let targetIP = await findActiveLoopbackIP()
            guard let validIP = targetIP else {
                throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không thể kết nối tới LocalDevVPN. Hãy bật VPN."])
            }
            _ = al_set_target_host(validIP)
            
            // Chuẩn bị file
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftDialer_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            for (_, imageData, targetFilename) in processedFiles {
                try imageData.write(to: tempDir.appendingPathComponent(targetFilename))
            }
            
            // Gọi AirLift
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
            onLogUpdate?("[PasscodeTheme] AirLift applied successfully.")
            
        } else {
            // Bad Query
            var bookRestoreFiles: [BookRestoreFile] = []
            for (_, imageData, targetFilename) in processedFiles {
                let targetPath = "\(globalTelephony.cachePath)\(targetFilename)"
                bookRestoreFiles.append(.custom(targetPath: targetPath, contents: imageData))
            }
            try await BookRestoreApplyTask.applyFiles(bookRestoreFiles, store: store, onLogUpdate: onLogUpdate)
        }
    }
    
    private func findActiveLoopbackIP() async -> String? {
        let candidates = ["10.7.0.1", "127.0.0.1"]
        for ip in candidates {
            if let url = URL(string: "http://\(ip)") {
                var request = URLRequest(url: url)
                request.timeoutInterval = 1.0
                if let (_, _) = try? await URLSession.shared.data(for: request) { return ip }
            }
        }
        return nil
    }
}

// MARK: - Errors
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