import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Network

struct ContentView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var path = NavigationPath()
    
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore
    
    @AppStorage("isAirLiftMode") private var isAirLiftMode: Bool = false
    
    // Trạng thái kết nối để hiển thị lên Home
    @AppStorage("PairingFile") private var pairingFile: String?
    @State private var vpnActive: Bool = false
    @State private var monitor: NWPathMonitor?
    @State private var showPairingFileImporter = false

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
        .onAppear {
            if !isAirLiftMode {
                startMonitoringVPN()
            }
        }
        .onDisappear { monitor?.cancel() }
        .fileImporter(
            isPresented: $showPairingFileImporter,
            allowedContentTypes: [
                .propertyList,
                UTType(filenameExtension: "mobiledevicepairing") ?? .data,
                UTType(filenameExtension: "rppairing") ?? .data
            ]
        ) { handlePairingImport($0) }
    }
    
    private var isSystemReady: Bool {
        if isAirLiftMode { return true }
        return pairingFile != nil && vpnActive
    }

    @ViewBuilder
    private var statusSection: some View {
        Section(header: Text(L("section_status")).font(.headline).foregroundColor(.primary).textCase(nil)) {
            // Dòng System Status chính
            HStack(spacing: 12) {
                if isSystemReady {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("system_status")).font(.body)
                        Text(isAirLiftMode ? "Ready - Airlift" : "Ready - Bad_query")
                            .font(.footnote).foregroundStyle(.green)
                    }
                } else {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("system_status")).font(.body)
                        Text("Not Ready").font(.footnote).foregroundStyle(.red)
                    }
                }
            }.padding(.vertical, 4)
            
            // Khung cảnh báo (Bấm vào để chọn file hoặc hướng dẫn bật VPN)
            if !isAirLiftMode && !isSystemReady {
                if pairingFile == nil {
                    Button(action: { showPairingFileImporter = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Missing pairing file").font(.subheadline.bold()).foregroundColor(.primary)
                                Text("Tap here to import a pairing file").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                } else if !vpnActive {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Heartbeat not running").font(.subheadline.bold()).foregroundColor(.primary)
                            Text("Enable LocalDevVPN or StikDebug and reopen app").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
            }
        }.listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var tweaksSection: some View {
        Section(header: Text(L("section_tweaks")).font(.headline).foregroundColor(.primary).textCase(nil)) {
            if !isAirLiftMode {
                toolNavigationLink(value: "MobileGestalt", title: L("tool_mobile_gestalt"), subtitle: L("tool_mobile_gestalt_desc"), icon: "cpu", isEnabled: toolStore.replaceMobileGestaltEnabled)
                toolNavigationLink(value: "ConfigTweaks", title: L("tool_config_tweaks"), subtitle: L("tool_config_tweaks_desc"), icon: "textformat", isEnabled: toolStore.configTweaksEnabled)
            }
            
            toolNavigationLink(value: "PasscodeTheme", title: L("tool_passcode_theme"), subtitle: L("tool_passcode_theme_desc"), icon: "lock.rectangle", isEnabled: themeStore.passcodeThemeEnabled)
            toolNavigationLink(value: "AppleWallet", title: L("tool_apple_wallet"), subtitle: L("tool_apple_wallet_desc"), icon: "wallet.pass", isEnabled: walletStore.appleWalletEnabled)
        }.listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private func destinationView(for route: String) -> some View {
        if route == "MobileGestalt" { MobileGestaltView(toolStore: toolStore) }
        else if route == "ConfigTweaks" { ConfigView(toolStore: toolStore) }
        else if route == "AppleWallet" { AppleWalletView(walletStore: walletStore) }
        else if route == "PasscodeThememark" { PasscodeThemeView(theme.shStore: themeStore) }
    }

ield.fill").    @ViewBuilder
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

    private func startMonitoringVPN() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                let hasVPN = path.availableInterfaces.contains { $0.type == .other || $0.name.hasPrefix("utun") || $0.name.hasPrefix("ipsec") }
                self.vpnActive = hasVPN
            }
        }
        monitor?.start(queue: DispatchQueue(label: "VPNMonitor"))
    }
    
    private func handlePairingImport(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            
            do {
                let data = try Data(contentsOf: url)
                let saveURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
                try data.write(to: saveURL)
                pairingFile = url.lastPathComponent
            } catch {
                print("Lỗi khi import Pairing File: \(error.localizedDescription)")
            }
        }
    }
}