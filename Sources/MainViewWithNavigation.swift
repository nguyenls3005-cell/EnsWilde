import SwiftUI
import UIKit
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
                ContentView(
                    themeStore: themeStore,
                    toolStore: toolStore,
                    toolRunner: toolRunner,
                    walletStore: walletStore,
                    featureFlagsStore: featureFlagsStore,
                    onNavigateToApply: {
                        showApplyTab = true
                        selectedTab = .apply
                    }
                )
            }
            .tabItem { Label(L("nav_home"), systemImage: "house.fill") }.tag(NavigationTab.home)

            NavigationStack { ThemeStoreView(themeStore: themeStore) }
                .tabItem { Label(L("nav_theme_store"), systemImage: "square.grid.2x2.fill") }.tag(NavigationTab.themeStore)

            NavigationStack { SettingsView(toolStore: toolStore) }
                .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }.tag(NavigationTab.settings)

            NavigationStack { AboutView() }
                .tabItem { Label(L("nav_about"), systemImage: "info.circle.fill") }.tag(NavigationTab.about)

            if showApplyTab {
                ApplyTabView(toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, themeStore: themeStore, featureFlagsStore: featureFlagsStore)
                    .tabItem { Label(L("nav_apply"), systemImage: "checkmark.circle.fill") }.tag(NavigationTab.apply)
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
    @ObservedObject private var patchStore = zPatchStore.shared

    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @AppStorage("manualCacheEditorEnabled") private var manualCacheEditorEnabled: Bool = false

    @State private var showErrorAlert = false
    @State private var lastError: String?
    @State private var statusLogs: [String] = [L("msg_apply_status_ready")]
    @State private var currentLine: String = L("msg_apply_status_ready")
    @State private var isApplyingUI: Bool = false
    @State private var copiedLog: Bool = false
    @State private var applyTask: Task<Void, Never>?

    private var isApplying: Bool {
        if isApplyingUI { return true }
        if case .running = toolRunner.state { return true }
        return false
    }

    private var isFailed: Bool {
        if case .failed = toolRunner.state { return true }
        return false
    }

    private var isSuccess: Bool {
        !isApplying && toolRunner.state == .success
    }

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []

        if toolStore.disableCallRecordingSoundEnabled { list.append((L("tool_disable_sound"), "speaker.slash")) }
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        if walletStore.appleWalletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        if manualCacheEditorEnabled { list.append((L("manual_editor_title"), "pencil.and.list.clipboard")) }
        if toolStore.configTweaksEnabled { list.append((L("tool_config_tweaks"), "textformat")) }
        if patchStore.isTweakEnabled || patchStore.patches.contains(where: { $0.pendingRevert }) {
            list.append(("zPatch Custom", "wrench.and.screwdriver"))
        }
        return list
    }

    private var statusTextColor: Color {
        if isFailed { return .red }
        if isSuccess { return .green }
        if isApplying { return .primary }
        return .secondary
    }

    private var fullLogString: String {
        var lines = statusLogs
        let globalText = GLOBAL_LOG.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !globalText.isEmpty {
            lines.append(globalText)
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("section_tweaks")).font(.headline).textCase(nil)) {
                    if enabledTweaks.isEmpty {
                        Text(L("apply_no_tweaks")).foregroundStyle(.secondary)
                    } else {
                        ForEach(enabledTweaks, id: \.0) { tweak in
                            Label { Text(tweak.0) } icon: { Image(systemName: tweak.1).foregroundStyle(.tint) }
                        }
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    Toggle(isOn: $toolStore.soundRespringEnabled) {
                        Text(L("respring_after_apply"))
                    }
                    Text(L("using_neospring")).font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    HStack(spacing: 10) {
                        if isApplying {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(hex: userTintColorHex))
                        } else if isFailed {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.body)
                                .foregroundStyle(.red)
                        } else if isSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        Text(currentLine)
                            .font(.subheadline)
                            .foregroundStyle(statusTextColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                } header: {
                    HStack {
                        Text(L("section_status"))
                            .font(.headline)
                            .textCase(nil)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = fullLogString
                            withAnimation {
                                copiedLog = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation {
                                    copiedLog = false
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedLog ? "checkmark" : "doc.on.doc")
                                Text(copiedLog ? "Copied" : "Copy Log")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(copiedLog ? .green : .secondary)
                            .textCase(nil)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    WalletStyleButton(
                        title: isApplying ? L("applying") : L("apply_enabled_tweaks"),
                        isLoading: isApplying,
                        disabled: isApplying,
                        action: performApply
                    )
                }
            }
            .navigationTitle(L("nav_apply"))
            .onAppear {
                patchStore.reloadFromStorage()
            }
            .onDisappear {
                applyTask?.cancel()
            }
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(lastError ?? L("msg_error_unknown"))
        }
    }

    private func pushStep(_ message: String) async {
        await MainActor.run {
            self.statusLogs.append(message)
            self.currentLine = message
            GLOBAL_LOG.step(message)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func performApply() {
        guard !isApplying else { return }

        let startMsg = L("apply_starting")
        statusLogs = [startMsg]
        currentLine = startMsg
        isApplyingUI = true
        GLOBAL_LOG.step(startMsg)

        applyTask?.cancel()
        applyTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            await toolRunner.applyAll(
                isSystemReady: true,
                store: toolStore,
                walletStore: walletStore,
                themeStore: themeStore,
                featureFlagsStore: featureFlagsStore,
                onLogUpdate: { message in
                    Task { @MainActor in
                        self.statusLogs.append(message)
                        self.currentLine = message
                        GLOBAL_LOG.step(message)
                    }
                }
            )

            await MainActor.run {
                patchStore.reloadFromStorage()
                isApplyingUI = false

                if case .failed(let msg) = toolRunner.state {
                    let errLine = "\(L("alert_error")): \(msg)"
                    self.lastError = msg
                    self.statusLogs.append(errLine)
                    self.currentLine = errLine
                    GLOBAL_LOG.error(msg)
                    self.showErrorAlert = true
                } else if toolRunner.state == .success {
                    let doneLine = L("apply_done")
                    self.statusLogs.append(doneLine)
                    self.currentLine = doneLine
                    GLOBAL_LOG.success(doneLine)
                } else {
                    if let last = self.statusLogs.last {
                        self.currentLine = last
                    }
                }
            }

            if toolStore.soundRespringEnabled && toolRunner.state == .success {
                await pushStep("Respringing device...")
                try? RespringHelper.respring()
            }
        }
    }
}
