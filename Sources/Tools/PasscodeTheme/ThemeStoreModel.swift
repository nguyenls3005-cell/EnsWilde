import Foundation

class ThemeStoreModel: ObservableObject {
    @Published var sources: [ThemeSource] = []
    @Published var themes: [PasscodeTheme] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init() {
        // Khởi tạo cứng source của SerStars, không load từ link index.json
        self.sources = [
            ThemeSource(
                name: "SerStars - Nugget Passcode",
                baseURL: "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/refs/heads/main/",
                themesURL: "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/refs/heads/main/wallpapers-passthemes.json"
            )
        ]
    }

    @MainActor
    func fetchThemes() async {
        isLoading = true
        errorMessage = nil

        do {
            var allThemes: [PasscodeTheme] = []

            // Duyệt qua danh sách source đã khởi tạo cứng
            for source in sources {
                guard let themesURL = URL(string: source.themesURL) else { continue }
                let (themesData, _) = try await URLSession.shared.data(from: themesURL)
                
                let decodedThemes = try JSONDecoder().decode([PasscodeTheme].self, from: themesData)
                
                for var theme in decodedThemes {
                    theme.baseURL = source.baseURL
                    allThemes.append(theme)
                }
            }

            self.themes = allThemes
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to load themes: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
}

// MARK: - Models
struct ThemeSource: Identifiable, Codable {
    var id = UUID()
    let name: String
    let baseURL: String
    let themesURL: String
}

struct PasscodeTheme: Identifiable, Codable {
    var id = UUID()
    let name: String
    let description: String?
    let url: String
    let preview: String
    let authors: String
    var baseURL: String? = nil
}