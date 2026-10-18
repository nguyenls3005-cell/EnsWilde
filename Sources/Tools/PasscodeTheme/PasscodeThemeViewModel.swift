import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI // Thêm import AirLift

// MARK: - Passcode Theme ViewModel
@MainActor
class PasscodeThemeViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    private let store: PasscodeThemeStore
    
    init(store: PasscodeThemeStore) {
        self.store = store
    }
    
    // Import a .passthm file (ZIP archive)
    func importTheme(from sourceURL: URL, name: String) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
        
        try? FileManager.default.removeItem(at: tempFileURL)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: tempFileURL)
        } catch {
            print("[PasscodeTheme] Copy to temp failed: \(error.localizedDescription)")
            throw PasscodeThemeError.accessDenied
        }
        
        let newTheme = PasscodeTheme(name: name)
        let themeFolder = newTheme.themeFolderURL
        
        if !FileManager.default.fileExists(atPath: themeFolder.path) {
            try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        }
        
        let detectedSize = detectSizeFromZIP(at: tempFileURL)
        print("[PasscodeTheme] Auto-detected size: \(detectedSize)")
        
        do {
            try FileManager.default.unzipItem(at: tempFileURL, to: themeFolder)
        } catch {
            print("[PasscodeTheme] Unzip failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: themeFolder)
            throw PasscodeThemeError.invalidFormat
        }
        
        try extractImagesFromTelephonySubfolder(themeFolder: themeFolder)
        
        try? FileManager.default.removeItem(at: tempFileURL)
        
        var themeWithSize = newTheme
        themeWithSize.detectedSize = detectedSize
        store.addTheme(themeWithSize)
    }
    
    // Process and prepare files for apply
    func processThemeFiles(theme: PasscodeTheme, globalPrefix: PasscodeTheme.PrefixLanguage? = nil) throws -> [(sourceURL: URL, processedData: Data, targetFilename: String)] {
        var processedFiles: [(URL, Data, String)] = []
        
        let imageFiles = theme.getImageFiles()
        guard !imageFiles.isEmpty else {
            throw PasscodeThemeError.noImagesFound
        }
        
        let prefix = globalPrefix ?? store.globalCustomPrefix
        
        print("[PasscodeTheme] Processing \(imageFiles.count) files with detected size: \(theme.detectedSize), target size: \(theme.keySize)")
        
        for filename in imageFiles {
            let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
            
            guard let firstHyphen = filename.firstIndex(of: "-") else {
                print("[PasscodeTheme] Skipping \(filename) - no hyphen found")
                continue
            }
            
            let suffix = String(filename[firstHyphen...])
            let newFilename = prefix.rawValue + suffix
            
            guard let image = UIImage(contentsOfFile: sourceURL.path) else {
                print("[PasscodeTheme] Failed to load image: \(filename)")
                continue
            }
            
            print("[PasscodeTheme] Processing: \(filename) -> \(newFilename), size: \(image.size)")
            
            let processedImage = resizeImage(image, for: theme.keySize, detectedSize: theme.detectedSize)
            
            guard let imageData = processedImage.pngData() else {
                print("[PasscodeTheme] Failed to convert to PNG: \(filename)")
                continue
            }
            
            print("[PasscodeTheme] Successfully processed: \(newFilename), new size: \(processedImage.size)")
            processedFiles.append((sourceURL, imageData, newFilename))
        }
        
        print("[PasscodeTheme] Total processed files: \(processedFiles.count)")
        return processedFiles
    }
    
    private func resizeImage(_ image: UIImage, for keySize: PasscodeTheme.KeySize, detectedSize: PasscodeTheme.DetectedSize) -> UIImage {
        var sizeMultiplier: CGFloat = 1.0
        
        if detectedSize == .small && keySize == .big {
            sizeMultiplier = 287.0 / 202.0
            print("[PasscodeTheme] Scaling Small → Big (×\(sizeMultiplier))")
        } else if detectedSize == .big && keySize == .small {
            sizeMultiplier = 202.0 / 287.0
            print("[PasscodeTheme] Scaling Big → Small (×\(sizeMultiplier))")
        } else {
            print("[PasscodeTheme] No scaling needed (detected: \(detectedSize), target: \(keySize))")
            return image
        }
        
        if abs(sizeMultiplier - 1.0) < PasscodeTheme.KeySize.resizeThreshold {
            print("[PasscodeTheme] Scale factor very close to 1.0, skipping resize")
            return image
        }
        
        let currentSize = image.size
        
        guard currentSize.width > 0 && currentSize.height > 0 else {
            print("[PasscodeTheme] Warning: Invalid image dimensions \(currentSize), returning original")
            return image
        }
        
        let currentPixelWidth = currentSize.width * image.scale
        let currentPixelHeight = currentSize.height * image.scale
        
        let targetPixelSize = CGSize(
            width: currentPixelWidth * sizeMultiplier,
            height: currentPixelHeight * sizeMultiplier
        )
        
        print("[PasscodeTheme] Resizing from \(currentPixelWidth)×\(currentPixelHeight)px to \(targetPixelSize.width)×\(targetPixelSize.height)px (multiplier: \(sizeMultiplier))")
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: targetPixelSize))
        }
    }
    
    private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            
            for entry in archive {
                if entry.path.hasSuffix("_small") {
                    return .small
                }
            }
            
            for entry in archive {
                if entry.path.hasSuffix("_big") {
                    return .big
                }
            }
            
            return .unknown
        } catch {
            print("[PasscodeTheme] Failed to detect size from ZIP: \(error.localizedDescription)")
            return .unknown
        }
    }
    
    private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) else {
            print("[PasscodeTheme] Cannot read theme folder contents")
            return
        }
        
        guard let telephonyFolder = contents.first(where: { $0.hasPrefix("Telephony") || $0.hasPrefix("TelephonyUI") }) else {
            print("[PasscodeTheme] No Telephony subfolder found, images may be at root level")
            return
        }
        
        let telephonyFolderURL = themeFolder.appendingPathComponent(telephonyFolder)
        print("[PasscodeTheme] Found Telephony subfolder: \(telephonyFolder)")
        
        guard let imageFiles = try? fm.contentsOfDirectory(atPath: telephonyFolderURL.path) else {
            print("[PasscodeTheme] Cannot read Telephony subfolder contents")
            return
        }
        
        var movedCount = 0
        for filename in imageFiles {
            let ext = (filename as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            
            let sourceURL = telephonyFolderURL.appendingPathComponent(filename)
            let destURL = themeFolder.appendingPathComponent(filename)
            
            do {
                try fm.moveItem(at: sourceURL, to: destURL)
                movedCount += 1
            } catch {
                print("[PasscodeTheme] Failed to move \(filename): \(error.localizedDescription)")
            }
        }
        
        print("[PasscodeTheme] Moved \(movedCount) images from \(telephonyFolder) to theme root")
        
        try? fm.removeItem(at: telephonyFolderURL)
    }
    
    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
        try? FileManager.default.removeItem(at: tempFileURL)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: tempFileURL)
        } catch {
            throw PasscodeThemeError.accessDenied
        }
        defer { try? FileManager.default.removeItem(at: tempFileURL) }
        
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
        
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) {
            for folderName in contents {
                if folderName.contains("Telephony") {
                    if folderName.contains("10") {
                        await MainActor.run { themeStore.globalTelephonyVersion = .telephony10 }
                    } else if folderName.contains("9") {
                        await MainActor.run { themeStore.globalTelephonyVersion = .telephony9 }
                    } else if folderName.contains("8") {
                        await MainActor.run { themeStore.globalTelephonyVersion = .telephony8 }
                    }
                    break
                }
            }
        }
        
        try extractImagesFromTelephonySubfolder(themeFolder: themeFolder)
        
        if let extractedFiles = try? fm.contentsOfDirectory(atPath: themeFolder.path) {
            for filename in extractedFiles {
                let ext = (filename as NSString).pathExtension.lowercased()
                guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
                
                if let firstHyphen = filename.firstIndex(of: "-") {
                    let prefix = String(filename[filename.startIndex..<firstHyphen])
                    if !prefix.isEmpty {
                        if let knownPrefix = PasscodeTheme.PrefixLanguage(rawValue: prefix) {
                            await MainActor.run { themeStore.globalCustomPrefix = knownPrefix }
                        } else {
                            await MainActor.run { themeStore.globalCustomPrefix = .other }
                        }
                        break
                    }
                }
            }
        }
        
        var themeWithSize = newTheme
        themeWithSize.detectedSize = detectedSize
        store.addTheme(themeWithSize)
    }
    
    // ==========================================
    // ✅ HÀM APPLY THEME (ĐÃ TÍCH HỢP AIRLIFT)
    // ==========================================
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: ((String) -> Void)? = nil) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        let isAirLiftMode = UserDefaults.standard.bool(forKey: "isAirLiftMode")
        
        // Xử lý ảnh (dùng chung cho cả 2 chế độ)
        let globalPrefix = self.store.globalCustomPrefix
        let globalTelephony = self.store.globalTelephonyVersion
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: globalPrefix)
        
        guard !processedFiles.isEmpty else {
            throw PasscodeThemeError.noImagesProcessed
        }
        
        if isAirLiftMode {
            // --- CHẾ ĐỘ AIRLIFT ---
            print("[PasscodeTheme] Applying via AirLift...")
            
            // Lấy Pairing File
            let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
            guard FileManager.default.fileExists(atPath: pairingURL.path) else {
                throw PasscodeThemeError.accessDenied
            }
            
            // Tạo thư mục tạm chứa ảnh đã xử lý
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftDialer_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            // Ghi ảnh vào thư mục tạm
            for (_, imageData, targetFilename) in processedFiles {
                let fileURL = tempDir.appendingPathComponent(targetFilename)
                try imageData.write(to: fileURL)
            }
            
            // Gọi AirLift
            var errorCString: UnsafeMutablePointer<CChar>? = nil
            let targetPath = globalTelephony.cachePath // Ví dụ: /var/mobile/Library/Caches/com.apple.TelephonyUI/TelephonyUI-10/
            
            // Đảm bảo targetPath không có dấu "/" ở cuối để tránh lỗi
            let cleanTargetPath = targetPath.hasSuffix("/") ? String(targetPath.dropLast()) : targetPath
            
            let result = al_exploit_write_dir(
                pairingURL.path,
                tempDir.path,
                cleanTargetPath,
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
            onLogUpdate?("[PasscodeTheme] AirLift applied successfully.")
            
        } else {
            // --- CHẾ ĐỘ BAD QUERY CŨ ---
            var bookRestoreFiles: [BookRestoreFile] = []
            
            for (_, imageData, targetFilename) in processedFiles {
                let targetPath = "\(globalTelephony.cachePath)\(targetFilename)"
                let file = BookRestoreFile.custom(targetPath: targetPath, contents: imageData)
                bookRestoreFiles.append(file)
            }
            
            print("[PasscodeTheme] Applying \(bookRestoreFiles.count) files via Bad Query...")
            
            if bookRestoreFiles.count > 0 {
                ApplyLogger.shared.log("[PasscodeTheme] Applying theme '\(theme.name)' with \(bookRestoreFiles.count) files to Passcode - \(globalTelephony.rawValue)")
            }
            
            try await BookRestoreApplyTask.applyFiles(bookRestoreFiles, store: store, onLogUpdate: onLogUpdate)
        }
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
        case .accessDenied:
            return "Unable to access the selected file"
        case .noImagesFound:
            return "No image files found in theme package"
        case .noImagesProcessed:
            return "No images could be processed from theme"
        case .invalidFormat:
            return "Invalid theme format"
        }
    }
}