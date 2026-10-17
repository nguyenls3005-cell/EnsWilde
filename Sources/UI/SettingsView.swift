import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network // Import Network để check VPN

struct SettingsView: View {
    @AppStorage("PairingFile") private var pairingFile: String?
    @State private var showPairingFileImporter = false
    @State private var vpnActive: Bool = false
    @State private var monitor: NWPathMonitor?

    var body: some View {
        Form {
            Section(header: Text("System Status")) {
                HStack(spacing: 12) {
                    if pairingFile != nil && vpnActive {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(.green)
                        Text("Ready").font(.body)
                    } else {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.red)
                        Text("Not Ready").font(.body)
                    }
                }.padding(.vertical, 4)
            }

            Section(header: Text("Connection Status")) {
                statusRow(title: "Pairing File", subtitle: pairingFile != nil ? "Ready" : "Not Ready", ok: pairingFile != nil)
                statusRow(title: "LocalDevVPN", subtitle: vpnActive ? "Ready" : "Not Ready", ok: vpnActive)
            }

            Section(header: Text("Pairing File")) {
                if pairingFile != nil {
                    Button(role: .destructive) {
                        pairingFile = nil
                        try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                    } label: { Label("Reset Pairing", systemImage: "trash") }
                } else {
                    Button { showPairingFileImporter = true } label: { Label("Import Pairing", systemImage: "doc.badge.plus") }
                }

                Button {
                    checkVPNNow()
                } label: {
                    HStack {
                        Label("Check LocalDevVPN", systemImage: "wifi")
                        Spacer()
                        if vpnActive { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
            }

            Section(header: Text("Maintenance")) {
                Button(role: .destructive) {
                    let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
                    let access = bq.grantAccess(atPath: mgPath)
                    if access.0 {
                        try? FileManager.default.removeItem(atPath: mgPath)
                        Alertinator.shared.alert(title: "Success", body: "Cache cleared.")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reset MobileGestalt Cache")
                        Text("Reset cache").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { try? RespringHelper.respring() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Respring")
                        Text("Clean all environment").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text(L("settings_app_info"))) {
                HStack { Label("EnsWilde", systemImage: "sparkles"); Spacer(); Text("v\(appVersion)").font(.footnote).foregroundStyle(.secondary) }
                HStack { Label("iOS", systemImage: "iphone"); Spacer(); Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary) }
                HStack { Label("Device", systemImage: "apps.iphone"); Spacer(); Text(settingsDeviceModelName()).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(L("nav_settings"))
        .onAppear { startMonitoringVPN() }
        .onDisappear { monitor?.cancel() }
        .fileImporter(isPresented: $showPairingFileImporter, allowedContentTypes: [.propertyList]) { handlePairingImport($0) }
    }

    @ViewBuilder
    private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red)
            Spacer()
            Text(subtitle).font(.caption).foregroundStyle(ok ? .green : .red)
        }
    }

    private func handlePairingImport(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                try? data.write(to: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                pairingFile = url.lastPathComponent
            }
        }
    }

    // Dùng NWPathMonitor để check VPN liên tục (chuẩn nhất)
    private func startMonitoringVPN() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                // Nếu có interface VPN (utun) đang active
                let hasVPN = path.availableInterfaces.contains { $0.type == .other || $0.name.hasPrefix("utun") || $0.name.hasPrefix("ipsec") }
                self.vpnActive = hasVPN
            }
        }
        monitor?.start(queue: DispatchQueue(label: "VPNMonitor"))
    }

    private func checkVPNNow() {
        // Check thủ công qua getifaddrs dự phòng
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else { return }
        defer { freeifaddrs(addrs) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)
            if (name.hasPrefix("utun") || name.hasPrefix("ipsec")) && (flags & IFF_UP) == IFF_UP {
                self.vpnActive = true
                return
            }
            pointer = interface.ifa_next
        }
        self.vpnActive = false
    }

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private func settingsDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}