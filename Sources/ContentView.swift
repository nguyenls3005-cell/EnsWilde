import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore

    var onNavigateToApply: (() -> Void)? = nil

    @State private var path = NavigationPath()

    private var hasAnyTweakEnabled: Bool {
        toolStore.replaceMobileGestaltEnabled
            || toolStore.disableSoundEnabled
            || toolStore.walletEnabled
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                statusSection
                tweaksSection
                applySection
            }
            .headerProminence(.increased)
            .navigationTitle("EnsWilde")
            .navigationDestination(for: String.self) { route in
                destinationView(for: route)
            }
        }
    }

    // MARK: - Status
    @ViewBuilder
    private var statusSection: some View {
        Section(header: Text(L("section_status"))) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("bad_query")
                        .font(.subheadline.bold())
                    Text("iOS 26.0 – 27.0b4 sandbox escape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Tweaks
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
                isEnabled: toolStore.walletEnabled
            )
        }
    }

    // MARK: - Apply button
    @ViewBuilder
    private var applySection: some View {
        Section {
            Button {
                onNavigateToApply?()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text(L("apply_enabled_tweaks"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .disabled(!hasAnyTweakEnabled)
            .opacity(hasAnyTweakEnabled ? 1.0 : 0.5)
        }
    }

    // MARK: - Navigation Destination
    @ViewBuilder
    private func destinationView(for route: String) -> some View {
        if route == "MobileGestalt" {
            MobileGestaltView(toolStore: toolStore)
        } else if route == "DisableSound" {
            DisableSoundView()
        } else if route == "AppleWallet" {
            AppleWalletView(walletStore: walletStore)
        }
    }

    // MARK: - Row
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