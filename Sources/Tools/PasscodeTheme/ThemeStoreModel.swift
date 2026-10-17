import Foundation
import ZIPFoundation

// MARK: - Theme Repository Index Models
struct ThemeRepository: Codable, Identifiable {
    let name: String
    let baseURL: String
    let themesURL: String
    
    var id: String { baseURL }
    
    var cleanBaseURL: String {
        if baseURL.hasSuffix("/") {
            return baseURL
        }
        return baseURL + "/"
    }
    
    var themesJSONURL: URL? {
        return URL(string: themesURL)
    }
}

// MARK: - Remote Theme Store Models
struct RemoteTheme: Identifiable {
    let name: String
    let description: String
    let url: String
    let preview: String
    let authors: String
    let baseURL: String
    
    var id: String { url }
    
    var fullURL: URL? {
        let cleanBase = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        return URL(string: cleanBase + url)
    }
    
    var previewURL: URL? {
        let cleanBase = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        return URL(string: cleanBase + preview)
    }
}

// Helper struct for decoding themes from JSON
struct RemoteThemeCodable: Codable {
    let name: String
    let description: String
    let url: String
    let preview: String
    let authors: String
}

// MARK: - Theme Store Manager
@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var repositories: [ThemeRepository] = []
    @Published var remoteThemes: [RemoteTheme] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var downloadingThemes: Set<String> = []
    @Published var selectedRepository: ThemeRepository?
    
    func fetchRepositories() async {
        isLoading = true
        errorMessage = nil
        repositories = []
        
        do {
            let (data, _) = try await URLSession.shared.data(from: indexURL)
            let repos = try JSONDecoder().decode([ThemeRepository].self, from: data)
            repositories = repos
        } catch {
            errorMessage = "Failed to load theme repositories: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func fetchThemes(from repository: ThemeRepository) async {
        isLoading = true
        errorMessage = nil
        remoteThemes = []
        selectedRepository = repository
        
        guard let themesURL = repository.themesJSONURL else {
            errorMessage = "Invalid repository URL"
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: themesURL)
            let themesData = try JSONDecoder().decode([RemoteThemeCodable].self, from: data)
            // Convert to RemoteTheme with baseURL
            remoteThemes = themesData.map { themeData in
                RemoteTheme(
                    name: themeData.name,
                    description: themeData.description,
                    url: themeData.url,
                    preview: themeData.preview,
                    authors: themeData.authors,
                    baseURL: repository.cleanBaseURL
                )
            }
        } catch {
            errorMessage = "Failed to load themes: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func backToRepositories() {
        selectedRepository = nil
        remoteThemes = []
    }
    
    func downloadAndImportTheme(_ theme: RemoteTheme, themeStore: PasscodeThemeStore) async throws {
        // Use the stored baseURL from the theme
        guard let downloadURL = theme.fullURL else {
            throw ThemeStoreError.invalidURL
        }
        
        downloadingThemes.insert(theme.id)
        defer { downloadingThemes.remove(theme.id) }
        
        // Download the .passthm file
        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        
        // Create a permanent location in temp directory with proper extension
        let permanentTempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("passthm")
        
        // Copy the downloaded file
        try FileManager.default.copyItem(at: tempURL, to: permanentTempURL)
        
        // Import directly without using the file picker import path
        try await importThemeDirectly(from: permanentTempURL, name: theme.name, store: themeStore)
        
        // Clean up
        try? FileManager.default.removeItem(at: permanentTempURL)
    }
    
    // Direct import for downloaded files (no security-scoped resource access needed)
    private func importThemeDirectly(from sourceURL: URL, name: String, store: PasscodeThemeStore) async throws {
        // Create target theme folder
        let newTheme = PasscodeTheme(name: name)
        let themeFolder = newTheme.themeFolderURL
        
        if !FileManager.default.fileExists(atPath: themeFolder.path) {
            try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        }
        
        // Detect size from ZIP
        let detectedSize = detectSizeFromZIP(at: sourceURL)
        
        // Unzip the file
        do {
            try FileManager.default.unzipItem(at: sourceURL, to: themeFolder)
        } catch {
            // Clean up created folder if unzip fails
            try? FileManager.default.removeItem(at: themeFolder)
            throw ThemeStoreError.unzipFailed
        }
        
        // Extract images from Telephony subfolder
        try extractImagesFromTelephonySubfolder(themeFolder: themeFolder)
        
        // Add theme to store
        var themeWithSize = newTheme
        themeWithSize.detectedSize = detectedSize
        store.addTheme(themeWithSize)
    }
    
    // Detect size from ZIP file
    private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            
            // Check for size indicators
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
            return .unknown
        }
    }
    
    // Extract images from Telephony subfolder to theme root
    private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) else {
            return
        }
        
        // Find Telephony subfolder
        guard let telephonyFolder = contents.first(where: { $0.hasPrefix("Telephony") || $0.hasPrefix("TelephonyUI") }) else {
            return
        }
        
        let telephonyFolderURL = themeFolder.appendingPathComponent(telephonyFolder)
        
        // Get all image files
        guard let imageFiles = try? fm.contentsOfDirectory(atPath: telephonyFolderURL.path) else {
            return
        }
        
        // Move each image file to theme root
        for filename in imageFiles {
            let ext = (filename as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            
            let sourceURL = telephonyFolderURL.appendingPathComponent(filename)
            let destURL = themeFolder.appendingPathComponent(filename)
            
            try? fm.moveItem(at: sourceURL, to: destURL)
        }
        
        // Clean up empty Telephony folder
        try? fm.removeItem(at: telephonyFolderURL)
    }
}

enum ThemeStoreError: LocalizedError {
    case invalidURL
    case unzipFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid theme URL"
        case .unzipFailed:
            return "Failed to extract theme file"
        }
    }
}
