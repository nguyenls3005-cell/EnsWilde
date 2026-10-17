import SwiftUI

struct ThemeStoreView: View {
    @ObservedObject var themeStore: PasscodeThemeStore
    @StateObject private var storeManager = ThemeStoreManager()
    @State private var selectedTheme: RemoteTheme?
    
    // ViewModel để truyền vào ThemeDetailView
    @StateObject private var viewModel = PasscodeThemeViewModel()

    var body: some View {
        Group {
            if storeManager.isLoading {
                ProgressView("Loading themes...")
            } else if let error = storeManager.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await storeManager.fetchThemes() }
                    }
                }
                .padding()
            } else if storeManager.themes.isEmpty {
                ContentUnavailableView("No Themes", systemImage: "paintpalette", description: Text("No themes found in the store."))
            } else {
                List(storeManager.themes) { theme in
                    Button {
                        selectedTheme = theme
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: theme.baseURL + theme.preview)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(theme.name).font(.headline)
                                Text(theme.authors).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Theme Store")
        .task {
            if storeManager.themes.isEmpty {
                await storeManager.fetchThemes()
            }
        }
        .sheet(item: $selectedTheme) { theme in
            // Gọi ThemeDetailView với đúng tham số viewModel
            ThemeDetailView(theme: theme, themeStore: themeStore, viewModel: viewModel)
        }
    }
}