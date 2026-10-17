import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var path = NavigationPath()
    
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

    // MARK: - System Status (Giao diện y hệt ảnh gốc)
    @ViewBuilder
    private var statusSection: some View {
        Section(header: Text("Status").font(.headline).foregroundColor(.primary).textCase(nil)) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Status")
                        .font(.body)
                    Text("Ready - Bad_query")
                        .font(.footnote) // Cỡ chữ nhỏ màu xám y hệt ảnh
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Tweaks
    @ViewBuilder
    private var tweaksSection: some View {
        Section(header: Text("Tweaks").font(.headline).foregroundColor(.primary).textCase(nil)) {
            toolNavigationLink(
                value: "MobileGestalt",
                title: L("tool_mobile_gestalt"),
                subtitle: L("tool_mobile_gestalt_desc"),
                icon: "cpu",
                isEnabled: toolStore.replaceMobileGestaltEnabled
            )

            toolNavigationLink(
                value: "PasscodeTheme",
                title: L("tool_passcode_theme"),
                subtitle: L("tool_passcode_theme_desc"),
                icon: "lock.rectangle",
                isEnabled: themeStore.passcodeThemeEnabled
            )

            toolNavigationLink(
                value: "AppleWallet",
                title: L("tool_apple_wallet"),
                subtitle: L("tool_apple_wallet_desc"),
                icon: "wallet.pass",
                isEnabled: walletStore.appleWalletEnabled
            )

            toolNavigationLink(
                value: "zPatchCustom",
                title: L("tool_zpatch_custom"),
                subtitle: L("tool_zpatch_custom_desc"),
                icon: "wrench.and.screwdriver",
                isEnabled: toolStore.zPatchCustomEnabled
            )
        }
        .listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private func destinationView(for route: String) -> some View {
        if route == "MobileGestalt" {
            MobileGestaltView(toolStore: toolStore)
        } else if route == "AppleWallet" {
            AppleWalletView(walletStore: walletStore)
        } else if route == "PasscodeTheme" {
            PasscodeThemeView(themeStore: themeStore)
        } else if route == "zPatchCustom" {
            zPatchCustomView()
        }
    }

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