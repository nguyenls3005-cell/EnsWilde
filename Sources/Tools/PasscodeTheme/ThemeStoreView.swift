import SwiftUI

struct ThemeStoreView: View {
    @ObservedObject var themeStore: PasscodeThemeStore
    @StateObject private var storeManager = ThemeStoreManager()
    @State private var selectedRemoteTheme: RemoteTheme?
    
    // SỬA LỖI 1: Truyền themeStore vào khởi tạo ViewModel
    @StateObject private var viewModel: PasscodeThemeViewModel
    
    init(themeStore: PasscodeThemeStore) {
        self.themeStore = themeStore
        _viewModel = StateObject(wrappedValue: PasscodeThemeViewModel(store: themeStore))
    }

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
                        selectedRemoteTheme = theme
                    } label: {
                        HStack(spacing: 12) {
                            // Sửa lại URL preview cho đúng (nếu cần)
                            AsyncImage(url: URL(string: theme.preview)) { image in
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
        // SỬA LỖI 2: Hiển thị sheet tải theme từ xa
        .sheet(item: $selectedRemoteTheme) { remoteTheme in
            RemoteThemeDownloadView(remoteTheme: remoteTheme, themeStore: themeStore, viewModel: viewModel)
        }
    }
}

// Thêm View mới để xử lý việc tải RemoteTheme
struct RemoteThemeDownloadView: View {
    let remoteTheme: RemoteTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var viewModel: PasscodeThemeViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var isDownloading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                AsyncImage(url: URL(string: remoteTheme.preview)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .frame(height: 200)
                .cornerRadius(12)
                
                Text(remoteTheme.name).font(.title2.bold())
                Text(remoteTheme.description ?? "").foregroundStyle(.secondary)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                
                if isDownloading {
                    ProgressView("Downloading and Importing...")
                } else {
                    Button("Download & Import Theme") {
                        Task {
                            await downloadAndImport()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Theme Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private func downloadAndImport() async {
        isDownloading = true
        errorMessage = nil
        
        do {
            guard let url = URL(string: remoteTheme.url) else {
                throw PasscodeThemeError.invalidFormat
            }
            
            // Tải file ZIP về bộ nhớ tạm
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            
            // Gọi hàm import có sẵn trong ViewModel của bạn
            try await viewModel.importTheme(from: tempURL, name: remoteTheme.name)
            
            // Import thành công, đóng view
            dismiss()
            
        } catch {
            errorMessage = "Failed to import: \(error.localizedDescription)"
        }
        
        isDownloading = false
    }
}