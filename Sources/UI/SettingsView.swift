import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @State private var showPairingFileImporter = false
    @State private var vpnActive: Bool = false

    var body: some View {
        Form {
            // Khung System Status
            Section(header: Text("System Status")) {
                HStack(spacing: 12) {
                    if pairingFile != nil && vpnActive {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)
                        Text("Ready").font(.body)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                        Text("Not Ready").font(.body)
                    }
                }
                .padding(.vertical, 4)
            }

            // Chi tiết
            Section(header: Text("Connection Status")) {
                statusRow(title: "Pairing File", subtitle: pairingFile != nil ? "Ready" : "Not Ready", ok: pairingFile != nil)
                statusRow(title: "LocalDevVPN", subtitle: vpnActive ? "Ready" : "Not Ready", ok: vpnActive)
            }

            // Pairing
            Section(header: Text("Pairing File")) {
                if pairingFile != nil {
                    Button(role: .destructive) {
                        pairingFile = nil
                        try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                    } label: {
                        Label("Reset Pairing", systemImage: "trash")
                    }
                } else {
                    Button {
                        showPairingFileImporter = true
                    } label: {
                        Label("Import Pairing", systemImage: "doc.badge.plus")
                    }
                }

                Button {
                    refreshVPNStatus()
                } label: {
                    HStack {
                        Label("Check LocalDevVPN", systemImage: "wifi")
                        Spacer()
                        if vpnActive {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            }

            // Maintenance
            Section(header: Text("Maintenance")) {
                Button(role: .destructive) {
                    let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
                    do {
                        let access = bq.grantAccess(atPath: mgPath)
                        if access.0 {
                            try FileManager.default.removeItem(atPath: mgPath)
                            Alertinator.shared.alert(title: "Success", body: "MobileGestalt cache cleared.")
                        }
                    } catch {
                        Alertinator.shared.alert(title: "Error", body: "Failed to clear cache.")
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

            // App Info (Hiển thị rõ Version, iOS và Device)
            Section(header: Text(L("settings_app_info"))) {
                HStack {
                    Label("EnsWilde", systemImage: "sparkles")
                    Spacer()
                    Text("v\(appVersion)").font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    Label("iOS", systemImage: "iphone")
                    Spacer()
                    Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    Label("Device", systemImage: "apps.iphone")
                    Spacer()
                    Text(settingsDeviceModelName()).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L("nav_settings"))
        .onAppear { refreshVPNStatus() }
        .fileImporter(
            isPresented: $showPairingFileImporter,
            allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data) ?? .data]
        ) { handlePairingImport($0) }
    }

    @ViewBuilder
    private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
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

    private func refreshVPNStatus() {
        NetworkStatus.checkVPNStatus { active in
            self.vpnActive = active
        }
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

// MARK: - About View (Khôi phục lại bảng Credits)
struct AboutView: View {
    private let contactURL = URL(string: "https://x.com/duongduong0908")!

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
            Section {
                Button(action: { if let url = URL(string: "https://github.com/YangJiiii/EnsWilde") { UIApplication.shared.open(url) } }) {
                    Label("Guide", systemImage: "safari")
                }
                Button(action: { UIApplication.shared.open(contactURL) }) {
                    Label("Contact", systemImage: "paperplane.fill")
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
        .navigationTitle(L("nav_about"))
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