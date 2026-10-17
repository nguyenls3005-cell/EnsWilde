import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Network

// MARK: - Main ContentView

struct ContentView: View {
    // Localization
    @ObservedObject private var localizationManager = LocalizationManager.shared
    
    // UI state
    @State private var showErrorAlert = false
    @State private var lastError: String?
    @State private var showStatusSheet = false
    @State private var _showApplySheet = false
    @State private var path = NavigationPath()
    
    // Binding for external control of apply sheet (default to internal state)
    var showApplySheetBinding: Binding<Bool>? = nil
    var showStatusSheetBinding: Binding<Bool>? = nil
    var hideBottomApplyButton: Bool = false
    var isInNestedViewBinding: Binding<Bool>?
    var isSystemReadyBinding: Binding<Bool>?
    var heartbeatRunningBinding: Binding<Bool>?
    var ddiMountedBinding: Binding<Bool>?
    
    // Internal state for when used standalone
    @State private var _isInNestedView = false
    
    // Computed bindings
    private var isInNestedView: Binding<Bool> {
        isInNestedViewBinding ?? $_isInNestedView
    }
    
    private var showApplySheet: Binding<Bool> {
        showApplySheetBinding ?? $_showApplySheet
    }
    
    private var statusSheet: Binding<Bool> {
        showStatusSheetBinding ?? $showStatusSheet
    }
    
    // Luôn luôn Ready vì dùng bad_query
    private var _isSystemReady: Bool { return true }

    // Tools (shared from MainViewWithNavigation)
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore

    init(
        themeStore: PasscodeThemeStore,
        toolStore: ToolStore,
        toolRunner: ToolRunner,
        walletStore: AppleWalletStore,
        featureFlagsStore: FeatureFlagsStore,
        showApplySheetBinding: Binding<Bool>? = nil,
        showStatusSheetBinding: Binding<Bool>? = nil,
        hideBottomApplyButton: Bool = false,
        isInNestedViewBinding: Binding<Bool>? = nil,
        isSystemReadyBinding: Binding<Bool>? = nil,
        heartbeatRunningBinding: Binding<Bool>? = nil,
        ddiMountedBinding: Binding<Bool>? = nil
    ) {
        self.themeStore = themeStore
        self.toolStore = toolStore
        self.toolRunner = toolRunner
        self.walletStore = walletStore
        self.featureFlagsStore = featureFlagsStore
        self.showApplySheetBinding = showApplySheetBinding
        self.showStatusSheetBinding = showStatusSheetBinding
        self.hideBottomApplyButton = hideBottomApplyButton
        self.isInNestedViewBinding = isInNestedViewBinding
        self.isSystemReadyBinding = isSystemReadyBinding
        self.heartbeatRunningBinding = heartbeatRunningBinding
        self.ddiMountedBinding = ddiMountedBinding
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                statusSection
                tweaksSection
            }
            .headerProminence(.increased)
            .navigationTitle("EnsWilde")
            .navigationDestination(for: String.self) { route in
                destinationView(for: route)
            }
        } // NavigationStack End
        .onChange(of: path) { newPath in
            isInNestedView.wrappedValue = !newPath.isEmpty
        }
        .onAppear {
            isSystemReadyBinding?.wrappedValue = true
            heartbeatRunningBinding?.wrappedValue = true
            ddiMountedBinding?.wrappedValue = true
        }
        .sheet(isPresented: statusSheet) {
            statusSheetContent
        }
        .sheet(isPresented: showApplySheet) {
            applySheetContent
        }
        .alert("System Message", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(lastError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Body Sections

    @ViewBuilder
    private var statusSection: some View {
        Section(header: Text(L("section_status"))) {
            CardRow(
                title: L("system_status"),
                subtitle: "Ready\nBad_query",
                ok: true,
                showChevron: false,
                trailing: nil
            )
        }
    }

    @ViewBuilder
    private var tweaksSection: some View {
        Section(header: Text(L("section_tweaks"))) {
            toolNavigationLink(
                value: "MobileGestalt",
                title: L("tool_mobile_gestalt"),
                subtitle: L("tool_mobile_gestalt_desc"),
                icon: "cpu",
                isEnabled: toolStore.replaceMobileGestaltEnabled
            )

            toolNavigationLink(
                value: "ThemesUI",
                title: L("tool_themes_ui"),
                subtitle: L("tool_themes_ui_desc"),
                icon: "paintbrush",
                isEnabled: toolStore.themesUIEnabled
            )

            toolNavigationLink(
                value: "PasscodeTheme",
                title: L("tool_passcode_theme"),
                subtitle: L("tool_passcode_theme_desc"),
                icon: "lock.rectangle",
                isEnabled: themeStore.passcodeThemeEnabled
            )

            toolNavigationLink(
                value: "DisableSound",
                title: L("tool_disable_sound"),
                subtitle: L("tool_disable_sound_desc"),
                icon: "speaker.slash",
                isEnabled: toolStore.disableSoundEnabled
            )

            toolNavigationLink(
                value: "AppleWallet",
                title: L("tool_apple_wallet"),
                subtitle: L("tool_apple_wallet_desc"),
                icon: "wallet.pass",
                isEnabled: walletStore.appleWalletEnabled
            )

            toolNavigationLink(
                value: "FeatureFlags",
                title: L("tool_feature_flags"),
                subtitle: L("tool_feature_flags_desc"),
                icon: "flag",
                isEnabled: featureFlagsStore.featureFlagsEnabled
            )

            toolNavigationLink(
                value: "zPatchCustom",
                title: L("tool_zpatch_custom"),
                subtitle: L("tool_zpatch_custom_desc"),
                icon: "wrench.and.screwdriver",
                isEnabled: toolStore.zPatchCustomEnabled
            )
        }
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    private func destinationView(for route: String) -> some View {
        if route == "DisableSound" {
            DisableSoundView()
        } else if route == "MobileGestalt" {
            MobileGestaltView(toolStore: toolStore)
        } else if route == "AppleWallet" {
            AppleWalletView(walletStore: walletStore)
        } else if route == "PasscodeTheme" {
            PasscodeThemeView(themeStore: themeStore)
        } else if route == "ThemesUI" {
            ThemesUIView(toolStore: toolStore)
        } else if route == "zPatchCustom" {
            zPatchCustomView()
        } else if route == "FeatureFlags" {
            FeatureFlagsView(store: featureFlagsStore)
        }
    }

    // MARK: - Sheet Contents

    private var statusSheetContent: some View {
        StatusSheet(
            pairingFileLoaded: .constant(true),
            heartbeatRunning: .constant(true),
            ddiMounted: .constant(true),
            onImportPairing: { },
            onResetPairing: { },
            onMountDDI: { },
            onClose: { statusSheet.wrappedValue = false }
        )
        .presentationDetents([.medium, .large])
    }

    private var applySheetContent: some View {
        ApplySheet(
            logs: .constant(toolRunner.logs.map { $0.text }),
            isRunning: .constant(isApplyRunning(toolRunner.state)),
            progressText: .constant(applyStatusText(toolRunner.state)),
            enableRespring: $toolStore.soundRespringEnabled,
            bookassetdUUID: .constant("N/A"),
            onApply: {
                Task {
                    await toolRunner.applyAll(
                        isSystemReady: true,
                        store: toolStore,
                        walletStore: walletStore,
                        themeStore: themeStore,
                        featureFlagsStore: featureFlagsStore
                    )
                    
                    if case .success = toolRunner.state {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
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
            },
            onClearUUID: { },
            onClose: { showApplySheet.wrappedValue = false }
        )
        .presentationDetents([.large])
    }

    // MARK: - Tool Navigation Link

    @ViewBuilder
    private func toolNavigationLink(value: String, title: String, subtitle: String, icon: String, isEnabled: Bool) -> some View {
        NavigationLink(value: value) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } icon: {
                    Image(systemName: icon)
                }
                Spacer()
                if isEnabled {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Logic Functions

    private func isApplyRunning(_ state: ToolRunState) -> Bool {
        if case .running = state { return true }
        return false
    }

    private func applyStatusText(_ state: ToolRunState) -> String {
        switch state {
        case .idle: return "Ready. This will run all enabled tools in order."
        case .running(let toolName): return "Running \(toolName)…"
        case .success: return "Done."
        case .failed(let message): return "Failed: \(message)"
        }
    }
}

// MARK: - Status Sheet (Feather-style)
struct StatusSheet: View {
    @Binding var pairingFileLoaded: Bool
    @Binding var heartbeatRunning: Bool
    @Binding var ddiMounted: Bool
    var onImportPairing: () -> Void
    var onResetPairing: () -> Void
    var onMountDDI: () -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("system_status"))) {
                    CardRow(title: L("status_pairing_file"), subtitle: "Ready\nBad_query", ok: true, showChevron: false, trailing: nil)
                }
            }
            .headerProminence(.increased)
            .navigationTitle(L("system_status"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Apply Sheet (Feather-style)
struct ApplySheet: View {
    @Binding var logs: [String]
    @Binding var isRunning: Bool
    @Binding var progressText: String
    @Binding var enableRespring: Bool
    @Binding var bookassetdUUID: String
    var onApply: () -> Void
    var onClearUUID: () -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L("respring_after_apply"), isOn: $enableRespring)
                }
                Section(header: Text(L("section_status"))) {
                    HStack(spacing: 12) {
                        if isRunning { ProgressView() }
                        Text(progressText).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !logs.isEmpty {
                    Section(header: Text(L("logs"))) {
                        ForEach(logs, id: \.self) { log in
                            Text(log).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    WalletStyleButton(
                        title: isRunning ? L("applying") : L("apply_enabled_tweaks"),
                        isLoading: isRunning,
                        disabled: isRunning,
                        action: onApply
                    )
                }
            }
            .headerProminence(.increased)
            .navigationTitle(L("apply_tweaks"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}