import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network

struct SettingsView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @State private var showPairingFileImporter = false
    @State private var vpnActive: Bool = false
    @State private var monitor: NWPathMonitor?
    
    @State private var showBackupImporter = false
    @State private var hasBackup: Bool = false
    @State private var backupInfo: MobileGestaltBackupManager.BackupInfo?
    
    @State private var isCleaning = false
    @State private var showCleanAlert = false
    @State private var cleanAlertMessage = ""

    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    private let tintOptions: [(name: String, hex: String)] = [
        ("Pink", "#f4b8e4"), ("Mauve", "#ca9ee6"), ("Red", "#e78284"), ("Green", "#a6d189"), ("Blue", "#8caaee")
    ]

    var body: some View {
        Form {
            Section(header: Text(L("system_status"))) {
                HStack(spacing: 12) {
                    if pairingFile != nil && vpnActive {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(.green)
                        Text(L("status_ready")).font(.body)
                    } else {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.red)
                        Text(L("status_not_ready")).font(.body)
                    }
                }.padding(.vertical, 4)
            }

            Section(header: Text(L("connection_status"))) {
                statusRow(title: L("pairing_file"), subtitle: pairingFile != nil ? L("status_ready") : L("status_not_ready"), ok: pairingFile != nil)
                statusRow(title: "LocalDevVPN", subtitle: vpnActive ? L("status_ready") : L("status_not_ready"), ok: vpnActive)
            }

            Section(header: Text(L("pairing_file"))) {
                if pairingFile != nil {
                    Button(role: .destructive) {
                        pairingFile = nil
                        try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                    } label: {
                        Label(L("button_reset_pairing"), systemImage: "trash")
                    }
                } else {
                    Button {
                        showPairingFileImporter = true
                    } label: {
                        Label(L("button_select_pairing"), systemImage: "doc.badge.plus")
                    }
                }
            }

            // MARK: - DỌN DẸP MÔI TRƯỜNG
            Section(header: Text("Environment Cleanup"), footer: Text("Clean MobileGestalt cache to ensure tweaks apply correctly.")) {
                if isCleaning {
                    HStack {
                        ProgressView()
                        Text("Cleaning...").padding(.leading, 8)
                    }
                } else {
                    Button {
                        clearMobileGestaltCache()
                    } label: {
                        Label("Clear MobileGestalt cache", systemImage: "trash.slash")
                            .foregroundColor(.orange)
                    }
                    
                    Button {
                        killApps()
                    } label: {
                        Label("Kill App (Rerun)", systemImage: "xmark.app")
                            .foregroundColor(.red)
                    }
                    
                    Button {
                        respringClean()
                    } label: {
                        Label("Respring (Clean Environment)", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Section(header: Text(L("backup_title"))) {
                if hasBackup, let info = backupInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                            Text(L("backup_available")).font(.subheadline.bold())
                            Spacer()
                        }
                        Text("\(L("backup_date")) \(info.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        Text("\(L("backup_size")) \(info.byteCount) bytes").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("backup_none")).font(.subheadline.bold())
                            Text(L("backup_none_desc")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                
                Button { createBackupNow() } label: {
                    Label(L("backup_now"), systemImage: "square.and.arrow.down.on.square")
                }
                Button { showBackupImporter = true } label: {
                    Label(L("backup_import"), systemImage: "square.and.arrow.down")
                }
                if hasBackup {
                    Button(role: .destructive) { deleteBackup() } label: {
                        Label(L("backup_delete"), systemImage: "trash")
                    }
                }
            }

            Section(header: Text(L("settings_language"))) {
                NavigationLink(destination: LanguageSettingsView()) {
                    Label(L("settings_language"), systemImage: "globe")
                }
            }

            Section(header: Text(L("settings_accent_color"))) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(tintOptions, id: \.hex) { option in
                            colorOptionView(option: option)
                        }
                    }
                }
            }

            Section(header: Text(L("settings_app_info"))) {
                HStack { Label("EnsWilde", systemImage: "sparkles"); Spacer(); Text("v\(appVersion)").font(.footnote).foregroundStyle(.secondary) }
                HStack { Label(L("app_ios"), systemImage: "iphone"); Spacer(); Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary) }
                HStack { Label(L("app_device"), systemImage: "apps.iphone"); Spacer(); Text(settingsDeviceModelName()).font(.footnote).foregroundStyle(.secondary) }
                Text(L("app_info_footer"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .navigationTitle(L("nav_settings"))
        .onAppear {
            startMonitoringVPN()
            refreshBackupInfo()
        }
        .onDisappear { monitor?.cancel() }
        .fileImporter(isPresented: $showPairingFileImporter, allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing") ?? .data]) { handlePairingImport($0) }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.propertyList]) { handleBackupImport($0) }
        .alert("System Message", isPresented: $showCleanAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cleanAlertMessage)
        }
    }

    // MARK: - LOGIC DỌN DẸP
    private func clearMobileGestaltCache() {
        isCleaning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
            let mgURL = URL(fileURLWithPath: mgPath)
            
            let bq = BadQuery()
            let res = bq.grantAccess(atPath: mgURL.deletingLastPathComponent().path, toFileName: mgURL.lastPathComponent)
            
            var success = false
            if res.0 {
                do {
                    if FileManager.default.fileExists(atPath: mgPath) {
                        try FileManager.default.removeItem(at: mgURL)
                    }
                    let backupURL = MGURL.savedGestaltURL
                    if FileManager.default.fileExists(atPath: backupURL.path) {
                        try FileManager.default.removeItem(at: backupURL)
                    }
                    success = true
                } catch {
                    print("Lỗi xóa cache: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.isCleaning = false
                self.cleanAlertMessage = success ? "MobileGestalt cache cleared successfully!" : "Failed to clear cache."
                self.showCleanAlert = true
            }
        }
    }

    private func killApps() {
        isCleaning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let command = "killall -9 MobileGestaltHelper SpringBoard backboardd"
            print("Executing command: \(command)")
            
            DispatchQueue.main.async {
                self.isCleaning = false
                self.cleanAlertMessage = "Apps killed. MobileGestalt will rerun."
                self.showCleanAlert = true
            }
        }
    }

    private func respringClean() {
        // Gọi hàm NeoSpring có sẵn của dự án
        RespringHelper.respring()
    }

    @ViewBuilder
    private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red)
            Spacer()
            Text(subtitle).font(.caption).foregroundStyle(ok ? .green : .red)
        }
    }

    @ViewBuilder
    private func colorOptionView(option: (name: String, hex: String)) -> some View {
        let color = Color(hex: option.hex)
        let isSelected = userTintColorHex.lowercased() == option.hex.lowercased()
        Circle()
            .fill(color)
            .frame(width: 36, height: 36)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .overlay(Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.white).opacity(isSelected ? 1 : 0))
            .onTapGesture {
                userTintColorHex = option.hex
                let uiColor = UIColor(Color(hex: option.hex))
                UITabBar.appearance().tintColor = uiColor
                UINavigationBar.appearance().tintColor = uiColor
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
    
    private func refreshBackupInfo() {
        hasBackup = MobileGestaltBackupManager.shared.hasBackup
        backupInfo = MobileGestaltBackupManager.shared.info
    }

    private func createBackupNow() {
        do {
            let onDevicePath = MobileGestaltApplyTask.onDeviceMGPath
            let data = try Data(contentsOf: URL(fileURLWithPath: onDevicePath))
            let _ = try MobileGestaltBackupManager.shared.ensureBackup(from: data)
            refreshBackupInfo()
        } catch { print("Backup failed") }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                try? MobileGestaltBackupManager.shared.importBackup(from: data)
                refreshBackupInfo()
            }
        }
    }

    private func deleteBackup() {
        try? MobileGestaltBackupManager.shared.clearBackup()
        refreshBackupInfo()
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

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private func settingsDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return "\(UIDevice.current.model) (\(identifier))"
    }
}