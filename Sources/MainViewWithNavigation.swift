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
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @State private var tintRefreshID = UUID()

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
                SettingsView()
            }
            .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }
            .tag(NavigationTab.settings)

            NavigationStack {
                AboutView()
            }
            .tabItem { Label(L("nav_about"), systemImage: "info.circle.fill") }
            .tag(NavigationTab.about)

            if showApplyTab {
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
        .onChange(of: showApplyTab) { enabled in
            if !enabled && selectedTab == .apply {
                withAnimation { selectedTab = .home }
            }
        }
        .onChange(of: toolStore.replaceMobileGestaltEnabled) { _ in updateShowApplyTab() }
        .onChange(of: toolStore.disableSoundEnabled) { _ in updateShowApplyTab() }
        .onChange(of: toolStore.walletEnabled) { _ in updateShowApplyTab() }
        .onChange(of: themeStore.passcodeThemeEnabled) { _ in updateShowApplyTab() }
        .onAppear { applyTintColor() }
    }

    private func updateShowApplyTab() {
        let hasAny = toolStore.replaceMobileGestaltEnabled
            || toolStore.disableSoundEnabled
            || toolStore.walletEnabled
            || themeStore.passcodeThemeEnabled

        if !hasAny {
            showApplyTab = false
            if selectedTab == .apply {
                selectedTab = .home
            }
        }
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
    @State private var displayedLogs: [String] = []
    @State private var logRevealTask: Task<Void, Never>? = nil

    private var isRunning: Bool {
        if case .running = toolRunner.state { return true }
        return false
    }

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        if toolStore.disableSoundEnabled { list.append((L("tool_disable_sound"), "speaker.slash")) }
        if toolStore.walletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        if toolStore.configTweaksEnabled { list.append(("Config Tweaks", "textformat")) }
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
        .onAppear {
            displayedLogs = toolRunner.logs.map { $0.text }
        }
        .onChange(of: toolRunner.logs.count) { _ in
            revealNewLogs()
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

                if !displayedLogs.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(displayedLogs.enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(idx)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                        .onChange(of: displayedLogs.count) { _ in
                            if let last = displayedLogs.indices.last {
                                withAnimation {
                                    proxy.scrollTo(last, anchor: .bottom)
                                }
                            }
                        }
                    }
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
                    Text(isRunning ? L("applying") : L("apply_enabled_tweaks"))
                        .font(.headline)
                    if isRunning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
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

    private func revealNewLogs() {
        logRevealTask?.cancel()
        logRevealTask = Task {
            let allLogs = toolRunner.logs.map { $0.text }
            while displayedLogs.count < allLogs.count {
                if Task.isCancelled { return }
                let nextIndex = displayedLogs.count
                await MainActor.run {
                    displayedLogs.append(allLogs[nextIndex])
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func performApply() {
        displayedLogs.removeAll()
        let shouldRespring = toolStore.soundRespringEnabled

        Task {
            await toolRunner.applyAll(store: toolStore, themeStore: themeStore)

            if case .success = toolRunner.state {
                await MainActor.run {
                    toolRunner.log("✓ Tweak applied successfully")
                    if shouldRespring {
                        toolRunner.log("Respringing after 3 seconds...")
                    } else {
                        toolRunner.log("Respring skipped (toggle off)")
                    }
                }

                try? await Task.sleep(nanoseconds: 800_000_000)

                if shouldRespring {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    do {
                        try RespringHelper.respring()
                    } catch {
                        await MainActor.run {
                            lastError = "Respring failed: \(error.localizedDescription)"
                            showErrorAlert = true
                        }
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