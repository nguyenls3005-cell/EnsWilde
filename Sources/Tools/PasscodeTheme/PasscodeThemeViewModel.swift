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
    
    // Hàm Import Theme
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
    
    // Process files
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
    
    // Hàm fix lỗi syntax tại đây (theme quaFolder -> themeFolder)
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
    
    // Hàm Import Default
    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        // Code cũ của bạn
    }
    
    // Hàm Apply Theme - FULL REWRITE
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        let globalPrefix = self.store.globalCustomPrefix
        let globalTelephony = self.store.globalTelephonyVersion
        
        onLogUpdate("Preparing Passcode Theme...")
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: globalPrefix)
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }
        
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "Không phát hiện tunnel VPN. Bật LocalDevVPN hoặc StikDebug VPN rồi thử lại."])
        }
        
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
        onLogUpdate("Wrote \(processedFiles.count) file(s) to temp.")
        
        onLogUpdate("Đang dò tunnel IP...")
        guard let host = await AirliftHostResolver.bestAvailable(log: onLogUpdate) else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy RSD tunnel. Kiểm tra: (1) VPN đang bật, (2) Developer Mode đã bật, (3) Apple Books đã cài."])
        }
        onLogUpdate("✅ Tunnel: \(host)")
        
        let observer = NotificationCenter.default.addObserver(forName: .airliftLog, object: nil, queue: .main) { note in
            if let line = note.userInfo?["line"] as? String {
                onLogUpdate("[Airlift] \(line)")
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        
        onLogUpdate("Đang ghi qua AirTraffic...")
        let targetPath = globalTelephony.cachePath
        let cleanTargetPath = targetPath.hasSuffix("/") ? String(targetPath.dropLast()) : targetPath
        let pairingPath = pairingURL.path
        let srcDir = tempDir.path
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorCString: UnsafeMutablePointer<CChar>? = nil
                let result = al_exploit_write_dir(pairingPath, srcDir, cleanTargetPath, nil, nil, &errorCString)
                if result != 0 {
                    let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown AirLift Error"
                    if let err = errorCString { al_string_free(err) }
                    continuation.resume(throwing: NSError(domain: "AirLift", code: Int(result), userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                } else {
                    continuation.resume()
                }
            }
        }
        onLogUpdate("✅ Passcode applied successfully.")
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