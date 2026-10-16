import SwiftUI
import UserNotifications

struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var tintRefreshID = UUID()

    private var hasAnyTweakEnabled: Bool {
        toolStore.replaceMobileGestaltEnabled
            || toolStore.disableSoundEnabled
            || toolStore.walletEnabled
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContentView(
                    themeStore: themeStore,
                    toolStore: toolStore,
                    toolRunner: toolRunner,
                    walletStore: walletStore,
                    featureFlagsStore: featureFlagsStore
                )
            }
            .tabItem { Label(L("nav_home"), systemImage: "house.fill") }
            .tag(NavigationTab.home)

            NavigationStack {
                ThemeStoreView(themeStore: themeStore)
            }
            .tabItem { Label(L("nav_theme_store"), systemImage: "square.grid.2x2.fill") }
            .tag(NavigationTab.themeStore)

            NavigationStack {
                SettingsView(heartbeatRunning: false, ddiMounted: false)
            }
            .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }
            .tag(NavigationTab.settings)

            NavigationStack {
                AboutView()
            }
            .tabItem { Label(L("nav_about"), systemImage: "info.circle.fill") }
            .tag(NavigationTab.about)

            if hasAnyTweakEnabled {
                ApplyTabView(
                    toolStore: toolStore,
                    toolRunner: toolRunner,
                    themeStore: themeStore
                )
                .tabItem { Label(L("nav_apply"), systemImage: "checkmark.circle.fill") }
                .tag(NavigationTab.apply)
            }
        }
        .tint(Color(hex: userTintColorHex))
        .id(tintRefreshID)
        .onChange(of: userTintColorHex) { _ in applyTintColor() }
        .onChange(of: hasAnyTweakEnabled) { enabled in
            if !enabled && selectedTab == .apply {
                withAnimation { selectedTab = .home }
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
            for window in windowScene.windows {
                window.tintColor = uiColor
            }
        }
        tintRefreshID = UUID()
    }
}

// MARK: - Apply Tab
struct ApplyTabView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var themeStore: PasscodeThemeStore

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
        if toolStore.walletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                enabledTweaksSection
                optionsSection
                logSection
                applyButtonSection
            }
            .headerProminence(.increased)
            .navigationTitle(L("nav_apply"))
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(lastError ?? L("msg_error_unknown"))
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
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
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
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section(header: Text(L("section_options"))) {
            Toggle(isOn: $toolStore.soundRespringEnabled) {
                Label(L("respring_after_apply"), systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var logSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !toolRunner.logs.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(toolRunner.logs.enumerated()), id: \.offset) { _, line in
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var applyButtonSection: some View {
        Section {
            Button(action: performApply) {
                HStack(spacing: 10) {
                    if isRunning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(isRunning ? L("applying") : L("apply_enabled_tweaks"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isRunning ? Color.gray : Color(hex: "#ef9f76"))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRunning || enabledTweaks.isEmpty)
            .opacity((isRunning || enabledTweaks.isEmpty) ? 0.6 : 1.0)
        }
    }

    private var statusText: String {
        switch toolRunner.state {
        case .idle:
            if enabledTweaks.isEmpty { return L("apply_enable_first") }
            return L("apply_ready").replacingOccurrences(of: "{count}", with: "\(enabledTweaks.count)")
        case .running(let name):
            return L("apply_running").replacingOccurrences(of: "{toolName}", with: name)
        case .success:
            return L("apply_done")
        case .failed(let msg):
            return L("apply_failed").replacingOccurrences(of: "{message}", with: msg)
        }
    }

    private func performApply() {
        Task {
            await toolRunner.applyAll(store: toolStore, themeStore: themeStore)

            if case .success = toolRunner.state {
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                if toolStore.soundRespringEnabled {
                    do {
                        try RespringHelper.respring()
                    } catch {
                        print("[RESPRING] Failed: \(error)")
                    }
                }
            }

            if case .failed(let message) = toolRunner.state {
                await MainActor.run {
                    lastError = message
                    showErrorAlert = true
                }
            }
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
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
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
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section(header: Text(L("section_options"))) {
            Toggle(isOn: $toolStore.soundRespringEnabled) {
                Label(L("respring_after_apply"), systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if isRunning || !statusText.isEmpty {
            Section {
                HStack(spacing: 12) {
                    if isRunning { ProgressView() }
                    Text(latestLogOrStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var latestLogOrStatus: String {
        if isRunning, let lastLog = toolRunner.logs.last?.text { return lastLog }
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
            if enabledTweaks.isEmpty { return L("apply_enable_first") }
            return L("apply_ready").replacingOccurrences(of: "{count}", with: "\(enabledTweaks.count)")
        case .running(let name):
            return L("apply_running").replacingOccurrences(of: "{toolName}", with: name)
        case .success:
            return L("apply_done")
        case .failed(let msg):
            return L("apply_failed").replacingOccurrences(of: "{message}", with: msg)
        }
    }

    private func performApply() {
        Task {
            await toolRunner.applyAll(store: toolStore, themeStore: themeStore)

            if case .success = toolRunner.state {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSuccessOverlay = true
                    }
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                try? RespringHelper.respring()
            }

            if case .failed(let message) = toolRunner.state {
                await MainActor.run {
                    lastError = message
                    showErrorAlert = true
                }
            }
        }
    }
}