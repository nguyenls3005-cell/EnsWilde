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
                statusSection
                tweaksSection
                respringSection
                applySection
            }
            .headerProminence(.increased)
            .navigationTitle("EnsWilde")
            .navigationDestination(for: String.self) { route in
                destinationView(for: route)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section(header: Text(L("section_status")).font(.headline).foregroundColor(.primary).textCase(nil)) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("system_status")).font(.body)
                    Text("Ready - Bad_query")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }.padding(.vertical, 4)
        }.listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var tweaksSection: some View {
        Section(header: Text(L("section_tweaks")).font(.headline).foregroundColor(.primary).textCase(nil)) {
            toolNavigationLink(value: "MobileGestalt", title: L("tool_mobile_gestalt"), subtitle: L("tool_mobile_gestalt_desc"), icon: "cpu", isEnabled: toolStore.replaceMobileGestaltEnabled)
            toolNavigationLink(value: "ConfigTweaks", title: L("tool_config_tweaks"), subtitle: L("tool_config_tweaks_desc"), icon: "textformat", isEnabled: toolStore.configTweaksEnabled)
            toolNavigationLink(value: "PasscodeTheme", title: L("tool_passcode_theme"), subtitle: L("tool_passcode_theme_desc"), icon: "lock.rectangle", isEnabled: themeStore.passcodeThemeEnabled)
            toolNavigationLink(value: "AppleWallet", title: L("tool_apple_wallet"), subtitle: L("tool_apple_wallet_desc"), icon: "wallet.pass", isEnabled: walletStore.appleWalletEnabled)
        }.listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var respringSection: some View {
        Section {
            Toggle("Respring after apply", isOn: .constant(true))
            
            Text("Using Neospring to Respring device")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
        }
    }

    @ViewBuilder
    private var applySection: some View {
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
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            
            if case .running(let toolName) = toolRunner.state {
                HStack {
                    ProgressView().padding(.trailing, 8)
                    Text("Applying: \(toolName)")
                }
            } else if case .failed(let message) = toolRunner.state {
                Text(message)
                    .foregroundColor(.red)
            } else if case .success = toolRunner.state {
                Text("✅ Applied successfully!")
                    .foregroundColor(.green)
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