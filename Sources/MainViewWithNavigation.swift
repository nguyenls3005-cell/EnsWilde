import SwiftUI
import UserNotifications

struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var tintRefreshID = UUID()
    
    private var hasEnabledTweaks: Bool {
        toolStore.replaceMobileGestaltEnabled || toolStore.configTweaksEnabled || 
        toolStore.disableSoundEnabled || walletStore.appleWalletEnabled || 
        themeStore.passcodeThemeEnabled || featureFlagsStore.featureFlagsEnabled || 
        toolStore.zPatchCustomEnabled
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
            
            NavigationStack { SettingsView() }
            .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }
            .tag(NavigationTab.settings)
            
            NavigationStack { AboutView() }
            .tabItem { Label("About", systemImage: "info.circle.fill") }
            .tag(NavigationTab.about)
            
            if showApplyTab && hasEnabledTweaks {
                ApplyTabView(toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, themeStore: themeStore, featureFlagsStore: featureFlagsStore)
                .tabItem { Label(L("nav_apply"), systemImage: "checkmark.circle.fill") }
                .tag(NavigationTab.apply)
            }
        }
        .tint(Color(hex: userTintColorHex))
        .id(tintRefreshID)
        .onChange(of: userTintColorHex) { _ in applyTintColor() }
        .onChange(of: hasEnabledTweaks) { newValue in
            if !newValue { selectedTab = .home } // Tự văng về Home nếu tắt hết
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

struct ApplyTabView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore

    @State private var showErrorAlert = false
    @State private var lastError: String?

    private var isRunning: Bool {
        if case .running = toolRunner.state { return true }
        return false
    }

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        if toolStore.configTweaksEnabled { list.append(("Config Tweaks", "slider.horizontal.3")) }
        if walletStore.appleWalletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        if featureFlagsStore.featureFlagsEnabled { list.append((L("tool_feature_flags"), "flag")) }
        if toolStore.zPatchCustomEnabled { list.append((L("tool_zpatch_custom"), "wrench.and.screwdriver")) }
        return list
    }

    private var latestLog: String {
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

                // Sát lên
                Section {
                    Text("Using Neospring to Respring device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                .listRowBackground(Color.clear)

                Section(header: Text("Status").font(.headline).foregroundColor(.primary).textCase(nil)) {
                    HStack(spacing: 10) {
                        if isRunning {
                            ProgressView().tint(Color(hex: UserDefaults.standard.string(forKey: "EnsWilde.userTintColor") ?? "#ef9f76"))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(toolRunner.state == .success ? .green : .secondary)
                        }
                        
                        Text(latestLog)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    WalletStyleButton(
                        title: isRunning ? "Applying..." : L("apply_enabled_tweaks"),
                        isLoading: isRunning,
                        disabled: isRunning || enabledTweaks.isEmpty,
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
        Task {
            await toolRunner.applyAll(isSystemReady: true, store: toolStore, walletStore: walletStore, themeStore: themeStore, featureFlagsStore: featureFlagsStore)

            if case .success = toolRunner.state {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if toolStore.soundRespringEnabled {
                    try? RespringHelper.respring()
                }
            }

            if case .failed(let message) = toolRunner.state {
                lastError = message
                showErrorAlert = true
            }
        }
    }
}