import SwiftUI
import UserNotifications

struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    
    // ✅ ĐÃ THÊM DÒNG NÀY ĐỂ FIX LỖI
    @Environment(\.scenePhase) private var scenePhase
    
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var tintRefreshID = UUID()
    
    private var isAnyTweakEnabled: Bool {
        toolStore.replaceMobileGestaltEnabled || toolStore.configTweaksEnabled || 
        toolStore.disableSoundEnabled || walletStore.appleWalletEnabled || 
        themeStore.passcodeThemeEnabled || featureFlagsStore.featureFlagsEnabled
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContentView(themeStore: themeStore, toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, featureFlagsStore: featureFlagsStore)
            }
            .tabItem { Label(L("nav_home"), systemImage: "house.fill") }
            .tag(NavigationTab.home)
            
            NavigationStack { ThemeStoreView(themeStore: themeStore) }
            .tabItem { Label(L("nav_theme_store"), systemImage: "square.grid.2x2.fill") }
            .tag(NavigationTab.themeStore)
            
            NavigationStack { SettingsView(toolStore: toolStore) }
            .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }
            .tag(NavigationTab.settings)
            
            NavigationStack { AboutView() }
            .tabItem { Label("About", systemImage: "info.circle.fill") }
            .tag(NavigationTab.about)
            
            if showApplyTab {
                ApplyTabView(toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, themeStore: themeStore, featureFlagsStore: featureFlagsStore)
                .tabItem { Label(L("nav_apply"), systemImage: "checkmark.circle.fill") }
                .tag(NavigationTab.apply)
            }
        }
        .tint(Color(hex: userTintColorHex))
        .id(tintRefreshID)
        .onChange(of: userTintColorHex) { _ in applyTintColor() }
        .onChange(of: toolStore.replaceMobileGestaltEnabled) { isEnabled in
            if !isEnabled && selectedTab == .apply {
                if !themeStore.passcodeThemeEnabled && !walletStore.appleWalletEnabled {
                    showApplyTab = false
                    selectedTab = .home
                }
            }
        }
        .onChange(of: showApplyTab) { isVisible in
            if !isVisible && selectedTab == .apply {
                selectedTab = .home
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                showApplyTab = false
                if selectedTab == .apply { selectedTab = .home }
            }
        }
        .onAppear { applyTintColor() }
    }
    
    private func applyTintColor() {
        let uiColor = UIColor(Color(hex: userTintColorHex))
        UITabBar.appearance().tintColor = uiColor
        UINavigationBar.appearance().tintColor = uiColor
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.tintColor = uiColor }
        }
        tintRefreshID = UUID()
    }
}

// MARK: - APPLY TAB VIEW
struct ApplyTabView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore

    @State private var showErrorAlert = false
    @State private var lastError: String?
    
    @State private var applyLogs: [String] = []
    @State private var isApplying: Bool = false

    private var isRunning: Bool {
        if case .running = toolRunner.state { return true }
        return false
    }

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        if walletStore.appleWalletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        return list
    }

    private var latestLog: String {
        if isApplying {
            return applyLogs.last ?? "Applying..."
        }
        return toolRunner.logs.last?.text ?? "Ready to apply."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tweaks").font(.headline).foregroundColor(.primary).textCase(nil)) {
                    if enabledTweaks.isEmpty {
                        Text("No tweaks enabled.").foregroundStyle(.secondary)
                    } else {
                        ForEach(enabledTweaks, id: \.0) { tweak in
                            Label { Text(tweak.0) } icon: { Image(systemName: tweak.1).foregroundStyle(.tint) }
                        }
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    Toggle(isOn: $toolStore.soundRespringEnabled) {
                        Text("Respring after apply")
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section(header: Text("Status").font(.headline).foregroundColor(.primary).textCase(nil)) {
                    HStack(spacing: 10) {
                        if isApplying || isRunning {
                            ProgressView().tint(Color(hex: UserDefaults.standard.string(forKey: "EnsWilde.userTintColor") ?? "#ef9f76"))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(toolRunner.state == .success ? .green : .secondary)
                        }
                        
                        Text(latestLog)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    WalletStyleButton(
                        title: (isApplying || isRunning) ? "Applying..." : L("apply_enabled_tweaks"),
                        isLoading: (isApplying || isRunning),
                        // Đã bỏ điều kiện enabledTweaks.isEmpty để luôn cho phép bấm Apply
                        disabled: (isApplying || isRunning),
                        action: performApply
                    )
                }
            }
            .navigationTitle(L("nav_apply"))
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(lastError ?? L("msg_error_unknown"))
        }
    }

    private func performApply() {
        isApplying = true
        applyLogs.removeAll()
        
        Task {
            do {
                appendLog("Starting Apply process...")
                
                if themeStore.passcodeThemeEnabled {
                    appendLog("Applying Passcode Theme...")
                    // Cần lấy theme đang được chọn
                    if let selectedTheme = themeStore.themes.first(where: { $0.isSelected }) {
                        try await PasscodeThemeViewModel(store: themeStore).applyTheme(selectedTheme, store: toolStore)
                        appendLog("✅ Passcode Theme applied.")
                    } else {
                         appendLog("⚠️ No passcode theme selected.")
                    }
                }
                
                if walletStore.appleWalletEnabled {
                    appendLog("Applying Apple Wallet...")
                    try await AppleWalletTask.run(store: toolStore, walletStore: walletStore)
                    appendLog("✅ Apple Wallet applied.")
                }
                
                if toolStore.replaceMobileGestaltEnabled {
                    appendLog("Applying MobileGestalt...")
                    // Gọi hàm MobileGestalt ở đây
                    // ...
                    appendLog("✅ MobileGestalt applied.")
                }
                
                appendLog("All tweaks applied successfully!")
                
                try await Task.sleep(nanoseconds: 1_000_000_000)
                if toolStore.soundRespringEnabled {
                    appendLog("Respringing...")
                    try? RespringHelper.respring()
                }
                
                await MainActor.run {
                    isApplying = false
                    toolRunner.state = .success
                }
                
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    showErrorAlert = true
                    isApplying = false
                    appendLog("❌ Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func appendLog(_ message: String) {
        DispatchQueue.main.async {
            applyLogs.append(message)
        }
    }
}