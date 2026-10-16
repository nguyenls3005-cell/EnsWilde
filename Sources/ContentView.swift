import SwiftUI 
import UniformTypeIdentifiers 
import UIKit

struct ContentView: View { 
@ObservedObject var themeStore: PasscodeThemeStore 
@ObservedObject var toolStore: ToolStore 
@ObservedObject var toolRunner: ToolRunner 
@ObservedObject var walletStore: AppleWalletStore 
@ObservedObject var featureFlagsStore: FeatureFlagsStore

@State private var path = NavigationPath()

var body: some View {
    NavigationStack(path: $path) {
        Form {
            statusSection
            tweaksSection
        }
        .headerProminence(.increased)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("EnsWilde")
                        .font(.headline)
                    Text("Status Exploit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationDestination(for: String.self) { route in
            destinationView(for: route)
        }
    }
}

@ViewBuilder
private var statusSection: some View {
    Section {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("bad_query")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Sandbox Escape • Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
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
            isEnabled: toolStore.walletEnabled
        )
        toolNavigationLink(
            value: "ConfigTweaks",
            title: "Config Tweaks",
            subtitle: "Custom Lock Screen Footnote",
            icon: "textformat",
            isEnabled: toolStore.configTweaksEnabled
        )
    }
}

@ViewBuilder
private func destinationView(for route: String) -> some View {
    if route == "MobileGestalt" {
        MobileGestaltView(toolStore: toolStore)
    } else if route == "PasscodeTheme" {
        PasscodeThemeView(themeStore: themeStore)
    } else if route == "DisableSound" {
        DisableSoundView()
    } else if route == "AppleWallet" {
        AppleWalletView(walletStore: walletStore)
    } else if route == "ConfigTweaks" {
        ConfigView(toolStore: toolStore)
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