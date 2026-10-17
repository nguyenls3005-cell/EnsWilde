import SwiftUI
import UserNotifications

// MARK: - Navigation Tab
enum NavigationTab: String, CaseIterable {
    case home = "nav_home"
    case themeStore = "nav_theme_store"
    case settings = "nav_settings"
    case about = "nav_about"
    case apply = "nav_apply"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .themeStore: return "square.grid.2x2.fill"
        case .settings: return "gearshape.fill"
        case .apply: return "checkmark.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var localizedTitle: String { return L(self.rawValue) }
}

// MARK: - Main View with Navigation
struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    
    @State private var isSystemReady = false
    @State private var heartbeatRunning = false
    @State private var ddiMounted = false
    @State private var isInNestedView = false
    @State private var showApplySheet = false
    @State private var showStatusSheet = false
    
    // Cờ quyết định ẩn/hiện Tab Apply (Mặc định ẩn)
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var tintRefreshID = UUID()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 1. HOME TAB
            NavigationStack {
                ContentView(
                    themeStore: themeStore,
                    toolStore: toolStore,
                    toolRunner: toolRunner,
                    walletStore: walletStore,
                    featureFlagsStore: featureFlagsStore,
                    showApplySheetBinding: $showApplySheet,
                    showStatusSheetBinding: $showStatusSheet,
                    hideBottomApplyButton: true,
                    isInNestedViewBinding: $isInNestedView,
                    isSystemReadyBinding: $isSystemReady,
                    heartbeatRunningBinding: $heartbeatRunning,
                    ddiMountedBinding: $ddiMounted
                )
            }
            .tabItem { Label(L("nav_home"), systemImage: "house.fill") }
            .tag(NavigationTab.home)
            
            // 2. THEME STORE
            NavigationStack {
                ThemeStoreView(themeStore: themeStore)
            }
            .tabItem { Label(L("nav_theme_store"), systemImage: "square.grid.2x2.fill") }
            .tag(NavigationTab.themeStore)
            
            // 3. SETTINGS
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }
            .tag(NavigationTab.settings)
            
            // 4. ABOUT
            NavigationStack {
                AboutView()
            }
            .tabItem { Label(L("nav_about"), systemImage: "info.circle.fill") }
            .tag(NavigationTab.about)
            
            // 5. APPLY TAB (Chỉ hiện khi cờ ShowApplyTab == true)
            if showApplyTab {
                ApplyTabView(
                    toolStore: toolStore,
                    toolRunner: toolRunner,
                    walletStore: walletStore,
                    themeStore: themeStore,
                    featureFlagsStore: featureFlagsStore,
                    isSystemReady: isSystemReady
                )
                .tabItem { Label(L("nav_apply"), systemImage: "checkmark.circle.fill") }
                .tag(NavigationTab.apply)
            }
        }
        .tint(Color(hex: userTintColorHex))
        .id(tintRefreshID)
        .onChange(of: userTintColorHex) { _ in applyTintColor() }
        .onAppear { applyTintColor() }
    }
    
    private func applyTintColor() {
        let uiColor = UIColor(Color(hex: userTintColorHex))
        UITabBar.appearance().tintColor = uiColor
        UINavigationBar.appearance().tintColor = uiColor
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.tintColor = uiColor
            }
        }
        tintRefreshID = UUID()
    }
}

// MARK: - Apply Tab View (Đúng giao diện ảnh)
struct ApplyTabView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore
    var isSystemReady: Bool

    @State private var showUUIDAlert = false
    @State private var showErrorAlert = false
    @State private var lastError: String?

    private var isRunning: Bool {
        if case .running = toolRunner.state { return true }
        return false
    }

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        if toolStore.disableSoundEnabled { list.append((L("tool_disable_sound"), "speaker.slash")) }
        if walletStore.appleWalletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        if toolStore.themesUIEnabled { list.append((L("tool_themes_ui"), "paintbrush")) }
        if toolStore.zPatchCustomEnabled { list.append((L("tool_zpatch_custom"), "wrench.and.screwdriver")) }
        if featureFlagsStore.featureFlagsEnabled { list.append((L("tool_feature_flags"), "flag")) }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tweaks").font(.headline).foregroundColor(.primary).textCase(nil)) {
                    if enabledTweaks.isEmpty {
                        Text("No tweaks enabled.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(enabledTweaks, id: \.0) { tweak in
                            Label {
                                Text(tweak.0)
                            } icon: {
                                Image(systemName: tweak.1).foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section(header: Text("Options").font(.headline).foregroundColor(.primary).textCase(nil)) {
                    Toggle(isOn: $toolStore.soundRespringEnabled) {
                        Label(L("respring_after_apply"), systemImage: "arrow.clockwise")
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    WalletStyleButton(
                        title: isRunning ? L("applying") : L("apply_enabled_tweaks"),
                        isLoading: isRunning,
                        disabled: isRunning || enabledTweaks.isEmpty,
                        action: performApply
                    )
                }

                if !toolRunner.logs.isEmpty {
                    Section(header: Text("Log").font(.headline)) {
                        ForEach(toolRunner.logs, id: \.text) { log in
                            Text(log.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(L("nav_apply"))
        }
        .alert(L("alert_uuid_required"), isPresented: $showUUIDAlert) {
            Button(L("alert_cancel"), role: .cancel) { }
            Button(L("alert_ok")) { captureUUID() }
        } message: {
            Text(L("alert_uuid_instruction"))
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(lastError ?? L("msg_error_unknown"))
        }
    }

    private func performApply() {
        Task {
            if toolStore.bookassetdUUID == nil || toolStore.bookassetdUUID?.isEmpty == true {
                showUUIDAlert = true
                return
            }

            await toolRunner.applyAll(
                isSystemReady: isSystemReady,
                store: toolStore,
                walletStore: walletStore,
                themeStore: themeStore,
                featureFlagsStore: featureFlagsStore
            )

            if case .success = toolRunner.state {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if toolStore.soundRespringEnabled {
                    try? RespringHelper.respring()
                } else {
                    if let bundleID = Bundle.main.bundleIdentifier {
                        LSApplicationWorkspaceDefaultWorkspace().openApplication(withBundleID: bundleID)
                    }
                }
            }

            if case .failed(let message) = toolRunner.state {
                lastError = message
                showErrorAlert = true
            }
        }
    }

    private func captureUUID() {
        LSApplicationWorkspaceDefaultWorkspace().openApplication(withBundleID: "com.apple.iBooks")
        Task {
            do {
                let uuid = try await BookassetdUUIDHelper.captureUUID(
                    timeout: 120, openBooksFirst: false, returnToAppAfterCapture: true
                )
                toolStore.bookassetdUUID = uuid
                performApply()
            } catch {
                lastError = L("msg_uuid_capture_failed").replacingOccurrences(of: "{error}", with: error.localizedDescription)
                showErrorAlert = true
            }
        }
    }
}