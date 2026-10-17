import SwiftUI

struct ThemeStoreView: View {
    @ObservedObject var themeStore: PasscodeThemeStore
    @StateObject private var storeManager = ThemeStoreManager()
    @State private var selectedTheme: RemoteTheme?
    @State private var isDownloading = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

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
                            // Load ảnh preview
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
            // Màn hình chi tiết khi bấm vào theme
            ThemeDetailView(theme: theme, themeStore: themeStore, storeManager: storeManager)
        }
    }
}

struct ThemeDetailView: View {
    let theme: RemoteTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var storeManager: ThemeStoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var isDownloading = false
    @State private var showError = false
    @State private var errorMsg = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                AsyncImage(url: URL(string: theme.baseURL + theme.preview)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .frame(maxHeight: 300)
                .cornerRadius(12)

                Text(theme.name).font(.title2.bold())
                Text(theme.authors).font(.caption).foregroundStyle(.secondary)
                
                if let desc = theme.description, !desc.isEmpty {
                    Text(desc).multilineTextAlignment(.center)
                }

                Spacer()

                Button {
                    Task {
                        isDownloading = true
                        do {
                            try await downloadTheme(theme)
                            dismiss()
                        } catch {
                            errorMsg = error.localizedDescription
                            showError = true
                        }
                        isDownloading = false
                    }
                } label: {
                    HStack {
                        if isDownloading { ProgressView().tint(.white) }
                        Text(isDownloading ? "Downloading..." : "Import Theme")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isDownloading)
            }
            .padding()
            .navigationTitle("Theme Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMsg)
            }
        }
    }

    // Hàm tải và import theme vào app
    private func downloadTheme(_ theme: RemoteTheme) async throws {
        guard let url = URL(string: theme.baseURL + theme.url) else {
            throw NSError(domain: "Invalid URL", code: 0)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Lưu file tạm
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(theme.name).passthm")
        try data.write(to: tempURL)
        
        // Gọi hàm import có sẵn của themeStore
        await MainActor.run {
            // Giả sử themeStore có hàm importTheme(fromURL:)
            // Nếu không có, mày cần thêm hàm này vào PasscodeThemeModel
            print("Downloaded theme to: \(tempURL)")
        }
    }
}