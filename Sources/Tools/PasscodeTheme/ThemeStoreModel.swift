import Foundation

// MARK: - Remote Theme Model
struct RemoteTheme: Identifiable, Codable {
    var id: String { url } // Dùng url làm id
    let name: String
    let description: String
    let url: String
    let preview: String
    let authors: String
    
    // Base URL được gán vào lúc tải để biết đường dẫn tải file
    var baseURL: String = ""
}

// MARK: - Theme Store Manager
@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var themes: [RemoteTheme] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Link index.json trên repo của bạn (chỉ chứa source SerStars)
    private let indexURL = URL(string: "https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde/refs/heads/main/themes-store/index.json")!

    func fetchThemes() async {
        isLoading = true
        errorMessage = nil
        themes = []

        do {
            // 1. Tải danh sách các nguồn từ index.json
            let (data, _) = try await URLSession.shared.data(from: indexURL)
            let sources = try JSONDecoder().decode([ThemeSource].self, from: data)
            
            var allThemes: [RemoteTheme] = []
            
            // 2. Tải từng nguồn
            for source in sources {
                guard let themesURL = URL(string: source.themesURL) else { continue }
                let (themesData, _) = try await URLSession.shared.data(from: themesURL)
                
                var fetchedThemes = try JSONDecoder().decode([RemoteTheme].self, from: themesData)
                
                // Gắn baseURL cho mỗi theme để sau này tải file zip
                for i in 0..<fetchedThemes.count {
                    fetchedThemes[i].baseURL = source.baseURL
                }
                
                allThemes.append(contentsOf: fetchedThemes)
            }
            
            self.themes = allThemes
            self.isLoading = false
            
        } catch {
            self.errorMessage = "Failed to load themes: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
}

// MARK: - Theme Source Model
struct ThemeSource: Codable {
    let name: String
    let baseURL: String
    let themesURL: String
}