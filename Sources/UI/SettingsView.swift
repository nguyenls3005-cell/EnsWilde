import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network

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

    private func checkVPNNow() {
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

// MARK: - ABOUT VIEW (Khôi phục Credits)
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(.pink)
                    Text("Thank you for using EnsWilde!").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button {
                        if let url = URL(string: "https://ko-fi.com/yangjiii") { UIApplication.shared.open(url) }
                    } label: {
                        Text("Donate")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AppTheme.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            Section(header: Text("Thanks To")) {
                creditRow(name: "@YangJiii", desc: "Developed EnsWilde")
                creditRow(name: "@LSNguyen", desc: "Rebuild EnsWilde")
                creditRow(name: "@skadz108 & @rooootdev", desc: "NeoSpring method")
                creditRow(name: "@Sidestore team", desc: "Get Pairing File on iOS: StikPair")
                creditRow(name: "@0xjohnnydev", desc: "Developed the AirLift sandbox escape")
                creditRow(name: "@forcequit", desc: "Developed the bad_query sandbox escape")
                creditRow(name: "@jailbreakdotparty", desc: "Source for changing MobileGestalt logic, config file")
                creditRow(name: "@mak5er", desc: "Dev App AirCard. Method for AirLift Gappa")
            }
        }
        .navigationTitle("About")
    }

    @ViewBuilder
    private func creditRow(name: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill").font(.system(size: 32)).foregroundStyle(.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).fontWeight(.semibold)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}