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
                        }
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
            // Gọi ToolRunner xử lý toàn bộ
            await toolRunner.applyAll(
                isSystemReady: true,
                store: toolStore,
                walletStore: walletStore,
                themeStore: themeStore,
                featureFlagsStore: featureFlagsStore
            )
            
            // Đồng bộ log từ ToolRunner ra giao diện
            await MainActor.run {
                for log in toolRunner.logs {
                    applyLogs.append(log.text)
                }
                
                if case .failed(let msg) = toolRunner.state {
                    lastError = msg
                    showErrorAlert = true
                }
                
                isApplying = false
            }
            
            // Respring
            if toolStore.soundRespringEnabled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                try? RespringHelper.respring()
            }
        }
    }
}