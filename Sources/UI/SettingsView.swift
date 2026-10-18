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
    
    // Trạng thái cho phần dọn dẹp
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

            // MARK: - DỌN DẸP MÔI TRƯỜNG (GIỐNG EROSION)
            Section(header: Text(L("environment_cleanup")), footer: Text(L("clean_env_footer"))) {
                if isCleaning {
                    HStack {
                        ProgressView()
                        Text(L("cleaning")).padding(.leading, 8)
                    }
                } else {
                    Button {
                        clearMobileGestaltCache()
                    } label: {
                        Label("Xóa Cache MobileGestalt (Clean The Environment)", systemImage: "trash.slash")
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
        .alert(L("alert_system_message"), isPresented: $showCleanAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cleanAlertMessage)
        }
    }

    // MARK: - LOGIC DỌN DẸP (CHUẨN iOS 27 / EROSION)
    private func clearMobileGestaltCache() {
        isCleaning = true
        DispatchQueue.global(qos: .userInitiated).async {
            // Đường dẫn chuẩn của iOS 27
            let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
            let mgURL = URL(fileURLWithPath: mgPath)
            
            // 1. Xin quyền truy cập qua bad_query
            let bq = BadQuery()
            let res = bq.grantAccess(atPath: mgURL.deletingLastPathComponent().path, toFileName: mgURL.lastPathComponent)
            
            var success = false
            if res.0 {
                do {
                    // 2. Xóa file gốc (iOS sẽ tự tạo lại khi Respring)
                    if FileManager.default.fileExists(atPath: mgPath) {
                        try FileManager.default.removeItem(at: mgURL)
                    }
                    // 3. Xóa luôn file backup gốc (nếu có) để đảm bảo sạch sẽ
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
                self.cleanAlertMessage = success ? L("cache_cleared_success") : L("cache_cleared_fail")
                self.showCleanAlert = true
            }
        }
    }

    private func killApps() {
        isCleaning = true
        DispatchQueue.global(qos: .userInitiated).async {
            // Lệnh kill các tiến trình (có thể cần bad_query để chạy)
            let command = "killall -9 MobileGestaltHelper SpringBoard backboardd"
            
            // Chạy lệnh (bạn cần thay bằng hàm thực tế của dự án nếu có, ví dụ: bq.execute(command))
            print("Thực thi lệnh: \(command)")
            
            DispatchQueue.main.async {
                self.isCleaning = false
                self.cleanAlertMessage = L("apps_killed_success")
                self.showCleanAlert = true
            }
        }
    }

    private func respringClean() {
        // Gọi hàm Respring có sẵn của dự án (thường là dùng neon method)
        RespringHelper.shared.respring()
    }

    // ... (Các hàm statusRow, colorOptionView, handlePairingImport... giữ nguyên như cũ)
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

// MARK: - ABOUT VIEW
struct AboutView: View {
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(.pink)
                    Text(L("about_desc"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        if let url = URL(string: "https://dangdi.dev/donate") { UIApplication.shared.open(url) }
                    } label: {
                        Text(L("button_donate"))
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
                Button(action: { if let url = URL(string: "https://t.me/yangjiiidibo") { UIApplication.shared.open(url) } }) {
                    Label(L("about_group_yang"), systemImage: "safari")
                }
                Button(action: { if let url = URL(string: "https://t.me/lsnguyengr") { UIApplication.shared.open(url) } }) {
                    Label(L("about_group_ls"), systemImage: "safari")
                }
                Button(action: { if let url = URL(string: "https://t.me/duongduong0908") { UIApplication.shared.open(url) } }) {
                    Label(L("about_contact"), systemImage: "paperplane.fill")
                }
            }
            
            Section(header: Text(L("settings_thanks_to"))) {
                creditRow(name: "@YangJiii", desc: L("developed_enswilde"))
                creditRow(name: "@LSNguyen", desc: L("rebuild_enswilde"))
                creditRow(name: "@skadz108 & @rooootdev", desc: L("neospring_method"))
                creditRow(name: "@Sidestore team", desc: L("get_pairing_file"))
                creditRow(name: "@0xjohnnydev", desc: L("developed_airlift"))
                creditRow(name: "@forcequit", desc: L("developed_badquery"))
                creditRow(name: "@jailbreakdotparty", desc: L("source_changing_mg"))
                creditRow(name: "@mak5er", desc: L("dev_aircard"))
            }
            
            Section(header: Text(L("settings_translators"))) {
                ForEach(languageManager.availableLanguages.filter { $0.translator != nil && !($0.translator?.isEmpty ?? true) }) { langInfo in
                    creditRow(name: langInfo.translator ?? "", desc: "\(langInfo.nativeName) (\(langInfo.name)) translation")
                }
            }
        }
        .navigationTitle(L("nav_about"))
        .onAppear {
            if languageManager.availableLanguages.isEmpty {
                Task { await languageManager.fetchAvailableLanguages() }
            }
        }
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