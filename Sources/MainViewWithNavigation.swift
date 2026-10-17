import SwiftUI
import UserNotifications

// MARK: - Main View with Navigation (Feather-style TabView)
struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    @State private var showApplySheet = false
    @State private var showStatusSheet = false
    @State private var isInNestedView = false
    @State private var isSystemReady = false
    @State private var heartbeatRunning = false
    @State private var ddiMounted = false
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var tintRefreshID = UUID()
    
    var body: some View {
        TabView(selection: $selectedTab) {
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
            .tabItem { Label(L("nav_home"), systemImage: "house.fill") }
            .tag(NavigationTab.home)
            
            NavigationStack {
                ThemeStoreView(themeStore: themeStore)
            }
            .tabItem { Label(L("nav_theme_store"), systemImage: "square.grid.2x2.fill") }
            .tag(NavigationTab.themeStore)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }
            .tag(NavigationTab.settings)
            
            NavigationStack {
                AboutView()
            }
            .tabItem { Label(L("nav_about"), systemImage: "info.circle.fill") }
            .tag(NavigationTab.about)
            
            if isSystemReady {
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

// MARK: - Apply Tab View (inline)
struct ApplyTabView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
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
                enabledTweaksSection
                optionsSection
                statusSection
                applyButtonSection
            }
            .headerProminence(.increased)
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
        .onReceive(NotificationCenter.default.publisher(for: .applyTweaksFromShortcut)) { _ in
            if !isRunning && !enabledTweaks.isEmpty {
                performApply()
            }
        }
    }

    @ViewBuilder
    private var enabledTweaksSection: some View {
        Section(header: Text(L("section_tweaks"))) {
            if enabledTweaks.isEmpty {
                Label {
                    Text(L("apply_no_tweaks_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(enabledTweaks, id: \.0) { tweak in
                    Label {
                        Text(tweak.0)
                    } icon: {
                        Image(systemName: tweak.1)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section(header: Text(L("section_options"))) {
            Toggle(isOn: $toolStore.soundRespringEnabled) {
                Label(L("respring_after_apply"), systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                toolStore.bookassetdUUID = nil
            } label: {
                Label(L("clear_uuid"), systemImage: "xmark.circle")
            }
            .disabled(toolStore.bookassetdUUID == nil || toolStore.bookassetdUUID?.isEmpty == true)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if isRunning || statusText != "" {
            Section {
                HStack(spacing: 12) {
                    if isRunning {
                        ProgressView()
                    }
                    Text(latestLogOrStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var latestLogOrStatus: String {
        if isRunning, let lastLog = toolRunner.logs.last?.text {
            return lastLog
        }
        return statusText
    }

    @ViewBuilder
    private var applyButtonSection: some View {
        Section {
            WalletStyleButton(
                title: isRunning ? L("applying") : L("apply_enabled_tweaks"),
                isLoading: isRunning,
                disabled: isRunning || enabledTweaks.isEmpty,
                action: performApply
            )
        }
    }

    private var statusText: String {
        switch toolRunner.state {
        case .idle:
            if enabledTweaks.isEmpty {
                return L("apply_enable_first")
            } else {
                return L("apply_ready").replacingOccurrences(of: "{count}", with: "\(enabledTweaks.count)")
            }
        case .running(let toolName):
            return L("apply_running").replacingOccurrences(of: "{toolName}", with: toolName)
        case .success:
            return L("apply_done")
        case .failed(let message):
            return L("apply_failed").replacingOccurrences(of: "{message}", with: message)
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
                sendLocalNotification(title: "EnsWilde", body: L("apply_done"))
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
                sendLocalNotification(title: "EnsWilde", body: L("apply_failed").replacingOccurrences(of: "{message}", with: message))
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

    private func sendLocalNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}