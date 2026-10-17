import Foundation
import SwiftUI

@MainActor
final class ToolRunner: ObservableObject {

    @Published var state: ToolRunState = .idle
    @Published var logs: [ToolRunLogLine] = []

    func resetLogs() {
        logs.removeAll()
    }

    func log(_ s: String) {
        logs.append(.init(text: s))
        print("[APPLY] \(s)")
    }

    /// Run enabled tools using unified BookRestore approach.
    func applyAll(isSystemReady: Bool, store: ToolStore, walletStore: AppleWalletStore, themeStore: PasscodeThemeStore, featureFlagsStore: FeatureFlagsStore) async {
        guard isSystemReady else {
            state = .failed(message: "System not ready (Pairing + Heartbeat + DDI required). DDI auto-mount may still be in progress.")
            return
        }

        // Check which tools are enabled
        let hasDisableSound = store.disableSoundEnabled
        let hasMobileGestalt = store.replaceMobileGestaltEnabled
        let hasZPatchCustom = store.zPatchCustomEnabled
        let hasAppleWallet = walletStore.appleWalletEnabled
        let hasPasscodeTheme = themeStore.passcodeThemeEnabled
        let hasThemesUI = store.themesUIEnabled
        let hasFeatureFlags = featureFlagsStore.featureFlagsEnabled
        
        if !hasDisableSound && !hasMobileGestalt && !hasZPatchCustom && !hasAppleWallet && !hasPasscodeTheme && !hasThemesUI && !hasFeatureFlags {
            state = .failed(message: "No tools enabled.")
            return
        }

        resetLogs()
        
        var enabledToolNames: [String] = []
        if hasDisableSound { enabledToolNames.append("Disable Sound") }
        if hasMobileGestalt { enabledToolNames.append("Replace MobileGestalt") }
        if hasZPatchCustom { enabledToolNames.append("zPatch Custom") }
        if hasAppleWallet { enabledToolNames.append("Apple Wallet") }
        if hasPasscodeTheme { enabledToolNames.append("Passcode Theme") }
        if hasThemesUI { enabledToolNames.append("Themes UI") }
        if hasFeatureFlags { enabledToolNames.append("Feature Flags") }
        
        log("Apply started. Enabled tools: \(enabledToolNames.joined(separator: ", "))")

        do {
            // Collect files from all enabled tools
            var allFiles: [BookRestoreFile] = []
            
            if hasDisableSound {
                state = .running(toolName: "Disable Sound")
                log("Collecting files from: Disable Sound")
                let soundFiles = try collectDisableSoundFiles()
                allFiles.append(contentsOf: soundFiles)
                log("Collected \(soundFiles.count) file(s) from Disable Sound")
            }
            
            if hasMobileGestalt {
                state = .running(toolName: "Replace MobileGestalt")
                log("Collecting files from: Replace MobileGestalt")
                let mgFiles = try collectMobileGestaltFiles()
                allFiles.append(contentsOf: mgFiles)
                log("Collected \(mgFiles.count) file(s) from Replace MobileGestalt")
            }
            
            if hasZPatchCustom {
                state = .running(toolName: "zPatch Custom")
                log("Collecting files from: zPatch Custom")
                let customFiles = try collectZPatchCustomFiles()
                allFiles.append(contentsOf: customFiles)
                log("Collected \(customFiles.count) file(s) from zPatch Custom")
            }
            
            if hasAppleWallet {
                state = .running(toolName: "Apple Wallet")
                log("Collecting files from: Apple Wallet")
                let walletFiles = try collectAppleWalletFiles(walletStore: walletStore)
                allFiles.append(contentsOf: walletFiles)
                log("Collected \(walletFiles.count) file(s) from Apple Wallet")
            }
            
            if hasPasscodeTheme {
                state = .running(toolName: "Passcode Theme")
                log("Collecting files from: Passcode Theme")
                let themeFiles = try collectPasscodeThemeFiles(themeStore: themeStore)
                allFiles.append(contentsOf: themeFiles)
                log("Collected \(themeFiles.count) file(s) from Passcode Theme")
            }
            
            if hasThemesUI {
                state = .running(toolName: "Themes UI")
                log("Collecting files from: Themes UI")
                let themesUIFiles = try collectThemesUIFiles()
                allFiles.append(contentsOf: themesUIFiles)
                log("Collected \(themesUIFiles.count) file(s) from Themes UI")
            }
            
            if hasFeatureFlags {
                state = .running(toolName: "Feature Flags")
                log("Collecting files from: Feature Flags")
                let featureFlagsFiles = try collectFeatureFlagsFiles(featureFlagsStore: featureFlagsStore)
                allFiles.append(contentsOf: featureFlagsFiles)
                log("Collected \(featureFlagsFiles.count) file(s) from Feature Flags")
            }
            
            // Apply all files together using unified BookRestore task
            state = .running(toolName: "Applying files")
            log("Applying \(allFiles.count) file(s) via BookRestore...")
            
            try await BookRestoreApplyTask.applyFiles(allFiles, store: store) { logMessage in
                // Update UI with exploit verification logs
                self.log(logMessage)
            }
            
            state = .success
            log("Apply completed successfully.")
        } catch {
            // Log the failure
            ApplyLogger.shared.log("Apply operation FAILED: \(error.localizedDescription)")
            ApplyLogger.shared.endSession()
            
            state = .failed(message: "\(error)")
            log("Apply failed: \(error)")
        }
    }

    // MARK: - File Collection
    
    /// Collect files for DisableSound tool
    private func collectDisableSoundFiles() throws -> [BookRestoreFile] {
        return [
            .sound(
                targetPath: "/var/mobile/Library/CallServices/Greetings/default/StartDisclosureWithTone.m4a",
                localFileName: "StartDisclosureWithTone.m4a"
            ),
            .sound(
                targetPath: "/var/mobile/Library/CallServices/Greetings/default/StopDisclosure.caf",
                localFileName: "StopDisclosure.caf"
            )
        ]
    }
    
    /// Collect files for MobileGestalt tool
    private func collectMobileGestaltFiles() throws -> [BookRestoreFile] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")
        
        guard FileManager.default.fileExists(atPath: modMGURL.path) else {
            throw ToolTaskError.generic("Missing ModifiedMobileGestalt.plist. Open MobileGestalt tool and press \"Save to ModifiedMobileGestalt.plist\" first.")
        }
        
        let mgData = try Data(contentsOf: modMGURL)
        // Use obfuscated path from MobileGestaltApplyTask
        let targetPath = MobileGestaltApplyTask.onDeviceMGPath
        
        var files: [BookRestoreFile] = [
            .mobileGestalt(targetPath: targetPath, contents: mgData)
        ]
        
        // Add Resolution.plist if it exists (for RDAR fix)
        let resolutionURL = docs.appendingPathComponent("Resolution.plist")
        if FileManager.default.fileExists(atPath: resolutionURL.path) {
            let resolutionData = try Data(contentsOf: resolutionURL)
            let resolutionTargetPath = "/var/Managed Preferences/mobile/com.apple.iokit.IOMobileGraphicsFamily.plist"
            files.append(.mobileGestalt(targetPath: resolutionTargetPath, contents: resolutionData))
        }
        
        return files
    }
    
    /// Collect files for zPatch Custom tool
    private func collectZPatchCustomFiles() throws -> [BookRestoreFile] {
        // Load patches from UserDefaults
        let storageKey = "zPatchCustomItems"
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let patches = try? JSONDecoder().decode([zPatchItem].self, from: data) else {
            return []
        }
        
        // Filter only enabled patches
        let enabledPatches = patches.filter { $0.isEnabled }
        
        guard !enabledPatches.isEmpty else {
            throw ToolTaskError.generic("zPatch Custom is enabled but no patches are active. Enable at least one patch.")
        }
        
        // Create BookRestoreFile for each enabled patch
        var files: [BookRestoreFile] = []
        for patch in enabledPatches {
            guard FileManager.default.fileExists(atPath: patch.sourcePath) else {
                throw ToolTaskError.generic("Source file not found: \(patch.sourcePath)")
            }
            
            // Determine if this is a sound file based on target path
            let isSoundFile = patch.destinationPath.contains("/Library/CallServices/Greetings/")
                || patch.destinationPath.hasSuffix(".caf")
                || patch.destinationPath.hasSuffix(".m4a")
                || patch.destinationPath.hasSuffix(".mp3")
                || patch.destinationPath.hasSuffix(".wav")
            
            if isSoundFile {
                // Use sound approach - serve via HTTP
                let fileName = (patch.sourcePath as NSString).lastPathComponent
                files.append(.sound(targetPath: patch.destinationPath, localFileName: fileName))
            } else {
                // Use .zassetpath approach for other files
                let fileData = try Data(contentsOf: URL(fileURLWithPath: patch.sourcePath))
                files.append(.custom(targetPath: patch.destinationPath, contents: fileData))
            }
        }
        
        return files
    }
    
    /// Collect files for Apple Wallet tool
    /// Important: Files must be collected in specific order for proper rendering:
    /// 1. Background images (.pkpass) MUST be processed first
    /// 2. Cache files (FrontFace, PlaceHolder, Preview) processed after
    /// 3. pass.json (if imported) applied last
    private func collectAppleWalletFiles(walletStore: AppleWalletStore) throws -> [BookRestoreFile] {
        // Get enabled cards
        let enabledCards = walletStore.enabledCards()
        guard !enabledCards.isEmpty else {
            throw ToolTaskError.generic("Apple Wallet is enabled but no cards are enabled. Enable at least one card.")
        }
        
        // Collect ALL files from all enabled cards in proper order
        var allFiles: [BookRestoreFile] = []
        
        for card in enabledCards {
            let cardBasePath = "/private/var/mobile/Library/Passes/Cards/\(card.id)"
            let cardPrefix = String(card.id.prefix(8))
            
            // CRITICAL ORDERING: Background image MUST come first for proper rendering!
            // The order of these if-let statements ensures correct file processing sequence.
            // Step 1: Add background image (.pkpass) first
            if let bgImageData = card.backgroundImageData {
                let bgFileName = card.cardBackgroundFileName
                let pkpassPath = "\(cardBasePath).pkpass/\(bgFileName)"
                let uniqueMediaName = "wallet_\(cardPrefix)_\(bgFileName)"
                allFiles.append(.walletImage(targetPath: pkpassPath, contents: bgImageData, mediaFileName: uniqueMediaName))
            }
            
            // Step 2: Then add cache files (FrontFace, PlaceHolder, Preview)
            if let frontFaceData = card.frontFaceImageData {
                let frontFacePath = "\(cardBasePath).cache/FrontFace"
                let uniqueMediaName = "wallet_\(cardPrefix)_FrontFace"
                allFiles.append(.walletImage(targetPath: frontFacePath, contents: frontFaceData, mediaFileName: uniqueMediaName))
            }
            
            if let placeHolderData = card.placeHolderImageData {
                let placeHolderPath = "\(cardBasePath).cache/PlaceHolder"
                let uniqueMediaName = "wallet_\(cardPrefix)_PlaceHolder"
                allFiles.append(.walletImage(targetPath: placeHolderPath, contents: placeHolderData, mediaFileName: uniqueMediaName))
            }
            
            if let previewData = card.previewImageData {
                let previewPath = "\(cardBasePath).cache/Preview"
                let uniqueMediaName = "wallet_\(cardPrefix)_Preview"
                allFiles.append(.walletImage(targetPath: previewPath, contents: previewData, mediaFileName: uniqueMediaName))
            }
            
            // Step 3: Add pass.json after card images (if imported)
            if let passJSONData = card.loadPassJSON() {
                let passJSONPath = "\(cardBasePath).pkpass/pass.json"
                let uniqueMediaName = "wallet_\(cardPrefix)_pass.json"
                allFiles.append(.walletImage(targetPath: passJSONPath, contents: passJSONData, mediaFileName: uniqueMediaName))
            }
        }
        
        guard !allFiles.isEmpty else {
            throw ToolTaskError.generic("No wallet files to apply. Please add images to your cards.")
        }
        
        return allFiles
    }
    
    /// Collect files for Passcode Theme tool
    private func collectPasscodeThemeFiles(themeStore: PasscodeThemeStore) throws -> [BookRestoreFile] {
        // Get selected theme
        guard let selectedTheme = themeStore.getSelectedTheme() else {
            throw ToolTaskError.generic("Passcode Theme is enabled but no theme is selected. Please select a theme.")
        }
        
        // Use global settings from store
        let globalPrefix = themeStore.globalCustomPrefix
        let globalTelephony = themeStore.globalTelephonyVersion
        
        // Get all image files from the theme
        let imageFiles = selectedTheme.getImageFiles()
        guard !imageFiles.isEmpty else {
            throw ToolTaskError.generic("Selected theme has no image files.")
        }
        
        var files: [BookRestoreFile] = []
        
        for filename in imageFiles {
            let sourceURL = selectedTheme.themeFolderURL.appendingPathComponent(filename)
            
            // Extract prefix and suffix from filename
            guard let firstHyphen = filename.firstIndex(of: "-") else {
                // Skip files without hyphen (not in expected format)
                continue
            }
            
            let suffix = String(filename[firstHyphen...])
            let newFilename = globalPrefix.rawValue + suffix
            
            // Load and process image
            guard let image = UIImage(contentsOfFile: sourceURL.path) else {
                continue
            }
            
            // FIXED: Resize based on key size setting and detected size (matches Python logic exactly)
            let processedImage = resizePasscodeImage(
                image,
                for: selectedTheme.keySize,
                detectedSize: selectedTheme.detectedSize
            )
            
            // Convert to PNG data
            guard let imageData = processedImage.pngData() else {
                continue
            }
            
            // Target path in TelephonyUI cache (use global telephony version)
            let targetPath = globalTelephony.cachePath + newFilename
            
            // Use .custom file type (zassetpath approach)
            files.append(.custom(targetPath: targetPath, contents: imageData))
        }
        
        guard !files.isEmpty else {
            throw ToolTaskError.generic("No passcode theme files could be processed.")
        }
        
        return files
    }
    
    /// Collect files for Themes UI tool (Global Preferences + Springboard Preferences)
    private func collectThemesUIFiles() throws -> [BookRestoreFile] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let globalPrefsURL = docs.appendingPathComponent("GlobalPreferences.plist")
        
        guard FileManager.default.fileExists(atPath: globalPrefsURL.path) else {
            throw ToolTaskError.generic("Missing GlobalPreferences.plist. Open Themes UI tool first.")
        }
        
        let globalPrefsData = try Data(contentsOf: globalPrefsURL)
        var files: [BookRestoreFile] = [
            .custom(targetPath: "/var/Managed Preferences/mobile/.GlobalPreferences.plist", contents: globalPrefsData)
        ]
        
        // SpringboardPreferences.plist is always written by autoSave() with the current
        // SBSuppressDynamicIslandCompletely value (true or false). Sending `false` explicitly
        // ensures the device removes DI suppression when the toggle is turned off.
        let springboardPrefsURL = docs.appendingPathComponent("SpringboardPreferences.plist")
        if FileManager.default.fileExists(atPath: springboardPrefsURL.path) {
            let springboardData = try Data(contentsOf: springboardPrefsURL)
            files.append(.custom(targetPath: "/var/Managed Preferences/mobile/com.apple.springboard.plist", contents: springboardData))
        }
        
        return files
    }
    
    /// FIXED: Resize passcode image based on detected size and target size (matching Python logic exactly)
    /// Python logic:
    /// if self.current_size == 1 and self.big_keys:
    ///     size_multiplier = 287/202  # Small → Big
    /// elif self.current_size == 2 and not self.big_keys:
    ///     size_multiplier = 202/287  # Big → Small
    /// else:
    ///     size_multiplier = 1  # No change
    private func resizePasscodeImage(_ image: UIImage, for keySize: PasscodeTheme.KeySize, detectedSize: PasscodeTheme.DetectedSize) -> UIImage {
        // Calculate size_multiplier exactly like Python code
        var sizeMultiplier: CGFloat = 1.0
        
        if detectedSize == .small && keySize == .big {
            // Convert small to big (Python: if self.current_size == 1 and self.big_keys)
            sizeMultiplier = 287.0 / 202.0  // ≈ 1.42
            print("[PasscodeTheme] Scaling Small → Big (×\(String(format: "%.2f", sizeMultiplier)))")
        } else if detectedSize == .big && keySize == .small {
            // Convert big to small (Python: elif self.current_size == 2 and not self.big_keys)
            sizeMultiplier = 202.0 / 287.0  // ≈ 0.70
            print("[PasscodeTheme] Scaling Big → Small (×\(String(format: "%.2f", sizeMultiplier)))")
        } else {
            // No scaling needed - sizes match or unknown (Python: else: size_multiplier = 1)
            print("[PasscodeTheme] No scaling needed (detected: \(detectedSize), target: \(keySize))")
            return image
        }
        
        // Check if scaling is needed (avoid unnecessary scaling for very similar sizes)
        if abs(sizeMultiplier - 1.0) < PasscodeTheme.KeySize.resizeThreshold {
            print("[PasscodeTheme] Scale factor very close to 1.0, skipping resize")
            return image
        }
        
        let currentSize = image.size
        
        // Guard against invalid image dimensions
        guard currentSize.width > 0 && currentSize.height > 0 else {
            print("[PasscodeTheme] Warning: Invalid image dimensions \(currentSize), returning original")
            return image
        }
        
        // Get actual pixel dimensions by accounting for image scale
        let currentPixelWidth = currentSize.width * image.scale
        let currentPixelHeight = currentSize.height * image.scale
        
        // Calculate target size in PIXELS by multiplying both dimensions
        // This matches Python exactly:
        // new_width = int(width * size_multiplier)
        // new_height = int(height * size_multiplier)
        let targetPixelSize = CGSize(
            width: currentPixelWidth * sizeMultiplier,
            height: currentPixelHeight * sizeMultiplier
        )
        
        print("[PasscodeTheme] Resizing from \(Int(currentPixelWidth))×\(Int(currentPixelHeight))px to \(Int(targetPixelSize.width))×\(Int(targetPixelSize.height))px (multiplier: \(String(format: "%.2f", sizeMultiplier)))")
        
        // Perform the resize using UIGraphicsImageRenderer with scale 1.0 to work in pixels
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Force 1x scale to work in actual pixels, not points
        
        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: targetPixelSize))
        }
    }
}

// MARK: - Feature Flags Extension

extension ToolRunner {
    /// Collect files for Feature Flags tool
    func collectFeatureFlagsFiles(featureFlagsStore: FeatureFlagsStore) throws -> [BookRestoreFile] {
        var files: [BookRestoreFile] = []
        
        // If folder creation is enabled, create the FeatureFlags directory via BookRestore.
        // Using .featureFlags type ensures the entry is included in ZBLDOWNLOADINFO so that
        // bookassetd actually writes the placeholder and creates /var/preferences/FeatureFlags/.
        if featureFlagsStore.folderCreated {
            files.append(.featureFlags(targetPath: "/var/preferences/FeatureFlags/Placeholder", contents: Data()))
        }
        
        // Generate Feature Flags plist (now allows empty for reset)
        guard let plistData = featureFlagsStore.generateFeatureFlagsPlist() else {
            throw ToolTaskError.generic("Failed to generate Feature Flags plist.")
        }
        
        // Use obfuscated path for Feature Flags
        let targetPath = ObfuscatedPaths.featureFlags
        files.append(.featureFlags(targetPath: targetPath, contents: plistData))
        
        return files
    }
}