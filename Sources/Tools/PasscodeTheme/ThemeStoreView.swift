import SwiftUI

struct ThemeStoreView: View {
    @StateObject private var storeManager = ThemeStoreManager()
    @ObservedObject var themeStore: PasscodeThemeStore
    @State private var showAddSheet = false
    
    var body: some View {
        Group {
            if let repo = storeManager.selectedRepository {
                ThemesListView(
                    title: repo.name,
                    themeStore: themeStore,
                    storeManager: storeManager,
                    backAction: { storeManager.backToRepositories() }
                )
            } else {
                RepositoriesListView(storeManager: storeManager)
            }
        }
        .navigationTitle(L("theme_store_title"))
        .toolbar {
            if storeManager.selectedRepository == nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddRepoSheet(storeManager: storeManager)
        }
    }
}

// MARK: - Repos List

struct RepositoriesListView: View {
    @ObservedObject var storeManager: ThemeStoreManager
    
    var body: some View {
        Form {
            if storeManager.isLoading && storeManager.repositories.isEmpty {
                Section { HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 20) }
            } else if storeManager.repositories.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "folder").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text(L("theme_store_empty")).font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            } else {
                Section(header: Text(L("theme_store_repos"))) {
                    ForEach(storeManager.repositories) { repo in
                        RepoRow(repo: repo, storeManager: storeManager)
                            .contextMenu {
                                Button(role: .destructive) { storeManager.removeRepo(repo) } label: {
                                    Label(repo.parentIndex != nil ? L("theme_store_delete_group") : L("theme_store_delete_repo"), systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .headerProminence(.increased)
    }
}

struct RepoRow: View {
    let repo: ThemeRepository
    @ObservedObject var storeManager: ThemeStoreManager
    @State private var themeCount: Int?
    
    var body: some View {
        Button {
            Task { await storeManager.fetchThemes(from: repo) }
        } label: {
            HStack(spacing: 12) {
                iconView.frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.name)
                        .foregroundColor(.primary)     // ← chữ trắng, không cam
                        .font(.body)
                    if let c = themeCount {
                        Text(String(format: L("theme_store_theme_count"), c)).font(.caption).foregroundColor(.secondary)
                    } else {
                        Text(L("theme_store_loading")).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())               // ← loại bỏ tint cam của Button
        .task { await fetchCount() }
    }
    
    @ViewBuilder private var iconView: some View {
        if let s = repo.iconURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else { fallback }
            }
        } else { fallback }
    }
    
    private var fallback: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 22))
            .foregroundColor(.secondary)               // ← xám
            .frame(width: 40, height: 40)
    }
    
    private func fetchCount() async {
        guard let url = repo.jsonURL else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return }
        if let d = json as? [String: Any] {
            themeCount = (d["themes"] as? [[String: Any]] ?? d["packages"] as? [[String: Any]])?.count
        } else if let a = json as? [[String: Any]] {
            themeCount = a.count
        }
    }
}

// MARK: - Themes Grid

struct ThemesListView: View {
    let title: String
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var storeManager: ThemeStoreManager
    let backAction: () -> Void
    
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    
    var body: some View {
        ScrollView {
            if storeManager.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            } else if let error = storeManager.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.red)
                    Text(error).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button(L("theme_store_retry")) {
                        if let r = storeManager.selectedRepository {
                            Task { await storeManager.fetchThemes(from: r) }
                        }
                    }
                }.padding(.top, 60)
            } else if storeManager.remoteThemes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(L("theme_store_no_themes")).foregroundColor(.secondary)
                }.padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(storeManager.remoteThemes) { theme in
                        ThemeCard(theme: theme, themeStore: themeStore, storeManager: storeManager)
                    }
                }.padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: backAction) {
                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text(L("theme_store_title")) }
                }
            }
        }
    }
}

struct ThemeCard: View {
    let theme: RemoteTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var storeManager: ThemeStoreManager
    @State private var previewImage: UIImage?
    @State private var isDownloading = false
    @State private var showError = false
    @State private var errorMsg = ""
    
    private var isDownloaded: Bool { themeStore.themes.contains { $0.name == theme.name } }
    
    var body: some View {
        VStack(spacing: 8) {
            if let img = previewImage {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 120).clipped().cornerRadius(10)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15))
                    .frame(height: 120).overlay(ProgressView())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name).font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(1)
                Text(String(format: L("theme_store_by_author"), theme.authors)).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            
            if isDownloaded {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.caption2)
                    Text(L("theme_store_downloaded")).font(.caption2.weight(.semibold))
                }.foregroundColor(.green).frame(maxWidth: .infinity).frame(height: 32)
            } else {
                Button { download() } label: {
                    HStack(spacing: 4) {
                        if isDownloading { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "arrow.down.circle.fill").font(.caption2) }
                        Text(isDownloading ? L("theme_store_downloading") : L("theme_store_download_btn")).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(AppTheme.accent).foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(isDownloading)
            }
        }
        .padding(10).background(Color(.secondarySystemGroupedBackground)).cornerRadius(14)
        .task { await loadPreview() }
        .alert(L("alert_error"), isPresented: $showError) { Button(L("alert_ok")) {} } message: { Text(errorMsg) }
    }
    
    private func loadPreview() async {
        guard let url = theme.previewURL else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) {
            await MainActor.run { previewImage = img }
        }
    }
    
    private func download() {
        isDownloading = true
        Task {
            do {
                try await storeManager.downloadAndImportTheme(theme, themeStore: themeStore)
                await MainActor.run { isDownloading = false }
            } catch {
                await MainActor.run { isDownloading = false; errorMsg = error.localizedDescription; showError = true }
            }
        }
    }
}

// MARK: - Add Repo Sheet

struct AddRepoSheet: View {
    @ObservedObject var storeManager: ThemeStoreManager
    @Environment(\.dismiss) var dismiss
    @State private var urlText = ""
    @State private var isAdding = false
    @State private var errorText: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://...", text: $urlText)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                } header: { Text(L("theme_store_json_url")) } footer: {
                    Text(L("theme_store_json_desc"))
                }
                if let err = errorText {
                    Section { Text(err).foregroundColor(.red).font(.footnote) }
                }
            }
            .navigationTitle(L("add_repo")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("alert_cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding { ProgressView() }
                    else {
                        Button(L("button_add")) { Task { await add() } }
                            .bold().disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
    
    private func add() async {
        isAdding = true; errorText = nil; defer { isAdding = false }
        do { try await storeManager.addRepo(urlString: urlText); dismiss() }
        catch { errorText = error.localizedDescription }
    }
}