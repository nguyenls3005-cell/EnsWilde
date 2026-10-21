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
        featureFlagsStore: FeatureFlagsStore
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
                Section(header: Text("EnsWilde").font(.headline)) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("System Status").font(.body)
                            Text("Ready - Bad_query").font(.footnote).foregroundStyle(.green)
                        }
                    }.padding(.vertical, 4)
                }

                Section(header: Text("Tweaks").font(.headline)) {
                    toolNavigationLink(value: "MobileGestalt", title: "MobileGestalt", subtitle: "Modify MobileGestalt file", icon: "cpu", isEnabled: toolStore.replaceMobileGestaltEnabled)
                    toolNavigationLink(value: "ConfigTweaks", title: "Config Tweaks", subtitle: "Custom Lock Screen Footnote", icon: "textformat", isEnabled: toolStore.configTweaksEnabled)
                    toolNavigationLink(value: "PasscodeTheme", title: "Passcode Theme", subtitle: "Customize passcode screen", icon: "lock.rectangle", isEnabled: themeStore.passcodeThemeEnabled)
                    toolNavigationLink(value: "AppleWallet", title: "Apple Wallet", subtitle: "Manage wallet cards", icon: "wallet.pass", isEnabled: walletStore.appleWalletEnabled)
                }

                Section {
                    Toggle("Respring after apply", isOn: .constant(true))
                    Text("Using Neospring to Respring device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task {
                            await toolRunner.applyAll(
                                isSystemReady: true,
                                store: toolStore,
                                walletStore: walletStore,
                                themeStore: themeStore,
                                featureFlagsStore: featureFlagsStore
                            )
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Apply Enabled Tweaks")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
            }
            .navigationTitle("EnsWilde")
            .navigationDestination(for: String.self) { route in
                destinationView(for: route)
            }
        }
    }

    @ViewBuilder
    private func destinationView(for route: String) -> some View {
        if route == "MobileGestalt" { MobileGestaltView(toolStore: toolStore) }
        else if route == "ConfigTweaks" { ConfigView(toolStore: toolStore) }
        else if route == "AppleWallet" { AppleWalletView(walletStore: walletStore) }
        else if route == "PasscodeTheme" { PasscodeThemeView(themeStore: themeStore) }
    }

    @ViewBuilder
    private func toolNavigationLink(value: String, title: String, subtitle: String, icon: String, isEnabled: Bool) -> some View {
        NavigationLink(value: value) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } icon: { Image(systemName: icon) }
                Spacer()
                if isEnabled { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption) }
            }
        }
    }
}