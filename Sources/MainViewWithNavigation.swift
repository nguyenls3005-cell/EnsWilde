import SwiftUI
import UserNotifications
import AirliftFFI

struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var tintRefreshID = UUID()

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

    // ✅ ĐÃ THÊM DÒNG NÀY ĐỂ FIX LỖI
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"

    @State private var showErrorAlert = false
    @State private var lastError: String?
    @State private var applyLogs: [String] = []
    @State private var isApplying = false

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        if walletStore.appleWalletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tweaks").font(.headline).textCase(nil)) {
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
                        if isApplying {
                            ProgressView().tint(Color(hex: userTintColorHex))
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                        message }
                        Text(isApplying ? (applyLogs.last ?? "Applying...") : "Ready to apply.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
                
                if !applyLogs.isEmpty && isApplying {
                    Section(header: Text("Logs")) {
                        ForEach(applyLogs, id: \.self) { log in
                            Text(log).font(.caption).foregroundStyle(log.contains("❌") ? .red : .secondary)
                        }
                    }
                }

                Section {
                    // ✅ DÙNG LẠI NÚT CŨ (WALLETSTYLEBUTTON)
                    WalletStyleButton(
                        title: isApplying ? "Applying..." : L("apply_enabled_tweaks"),
                        isLoading: isApplying,
                        disabled: isApplying,
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
                
                // 1. Dò IP Loopback
                let targetIP = await getLoopbackIP()
                appendLog("Using Loopback IP: \(targetIP)")
                _ = al_set_target_host(targetIP)
                
                // 2. Apply Passcode
                if themeStore.passcodeThemeEnabled {
                    appendLog("Applying Passcode Theme...")
                    if let selectedTheme = themeStore.themes.first(where: { $0.isSelected }) {
                        try await PasscodeThemeViewModel(store: themeStore).applyTheme(selectedTheme, store: toolStore)
                        appendLog("✅ Passcode applied.")
                    } else {
                        appendLog("⚠️ No passcode theme selected.")
                    }
                }
                
                // 3. Apply Wallet
                if walletStore.appleWalletEnabled {
                    appendLog("Applying Wallet...")
                    try await AppleWalletTask.run(store: toolStore, walletStore: walletStore)
                    appendLog("✅ Wallet applied.")
                }
                
                appendLog("Done! Respringing...")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                if toolStore.soundRespringEnabled {
                    try? RespringHelper.respring()
                }
                
                await MainActor.run {
                    isApplying = false
                    toolRunner.state = .success
                }
                
            } catch {
                await MainActor.run {
                    appendLog("❌ Error: \(error.localizedDescription)")
                    lastError = error.localizedDescription
                    showErrorAlert = true
                    isApplying = false
                }
            }
        }
    }

    private func appendLog(_: String) {
        DispatchQueue.main.async { applyLogs.append(message) }
    }

    private func getLoopbackIP() async -> String {
        let candidates = ["10.7.0.1", "127.0.0.1"]
        for ip in candidates {
            if let url = URL(string: "http://\(ip)") {
                var request = URLRequest(url: url)
                request.timeoutInterval = 1.0
                if let (_, _) = try? await URLSession.shared.data(for: request) {
                    return ip
                }
            }
        }
        return "127.0.0.1"
    }
}