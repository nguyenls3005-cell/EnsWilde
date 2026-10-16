import SwiftUI
import UserNotifications

enum NavigationTab: String, CaseIterable {
    case home, settings, about, apply
}

struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
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
                SettingsView()
            }
            .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }
            .tag(NavigationTab.settings)

            NavigationStack {
                AboutView()
            }
            .tabItem { Label(L("nav_about"), systemImage: "info.circle.fill") }
            .tag(NavigationTab.about)

            ApplyTabView(
                toolStore: toolStore,
                toolRunner: toolRunner,
                themeStore: themeStore
            )
            .tabItem { Label(L("nav_apply"), systemImage: "checkmark.circle.fill") }
            .tag(NavigationTab.apply)
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

struct ApplyTabView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var themeStore: PasscodeThemeStore

    @State private var showErrorAlert = false
    @State private var lastError: String?
    @State private var showSuccessOverlay = false

    private var isRunning: Bool {
        if case .running = toolRunner.state { return true }
        return false
    }

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []
        if toolStore.replaceMobileGestaltEnabled {
            list.append((L("tool_mobile_gestalt"), "cpu"))
        }
        if themeStore.passcodeThemeEnabled {
            list.append((L("tool_passcode_theme"), "lock.rectangle"))
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    enabledTweaksSection
                    optionsSection
                    statusSection
                    applyButtonSection
                }
                .headerProminence(.increased)
                .navigationTitle(L("nav_apply"))

                if showSuccessOverlay {
                    successOverlay
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSuccessOverlay)
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(lastError ?? L("msg_error_unknown"))
        }
    }

    // MARK: - Success Overlay
    @ViewBuilder
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 110, height: 110)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(.green)
                }

                VStack(spacing: 8) {
                    Text("Tweak Successfully Applied")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text("Respringing…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: .black.opacity(0.3), radius: 20)
            )
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Sections
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
            if enabledTweaks.isEmpty { return L("apply_enable_first") }
            return L("apply_ready").replacingOccurrences(of: "{count}", with: "\(enabledTweaks.count)")
        case .running(let toolName):
            return L("apply_running").replacingOccurrences(of: "{toolName}", with: toolName)
        case .success:
            return L("apply_done")
        case .failed(let message):
            return L("apply_failed").replacingOccurrences(of: "{message}", with: message)
        }
    }

    // MARK: - Apply
    private func performApply() {
        Task {
            await toolRunner.applyAll(store: toolStore, themeStore: themeStore)

            if case .success = toolRunner.state {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSuccessOverlay = true
                    }
                }

                // Chờ 2.5 giây để user thấy overlay
                try? await Task.sleep(nanoseconds: 2_500_000_000)

                // Respring
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