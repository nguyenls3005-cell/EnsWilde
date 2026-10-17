import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Main ContentView

struct ContentView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    
    @State private var path = NavigationPath()
    @State private var showErrorAlert = false
    @State private var lastError: String?
    
    // Tools
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
        }
    }

    // MARK: - Body Sections

    @ViewBuilder
    private var statusSection: some View {
        Section(header: Text(L("section_status"))) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("system_status"))
                        .font(.headline)
                    Text("Ready - Bad_query")
                        .font(.system(size: 15, weight: .medium)) // To hơn 1 xíu, nằm cùng hàng
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
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
}