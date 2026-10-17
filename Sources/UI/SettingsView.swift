import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var showPairingFileImporter = false
    @State private var vpnActive: Bool = false
    @State private var showVPNAlert = false
    @State private var pairingImportError: String?
    @State private var showPairingErrorAlert = false
    @State private var pairingImportSuccess: String?
    @State private var showPairingSuccessAlert = false

    // Backup
    @State private var showBackupImporter = false
    @State private var showBackupAlert = false
    @State private var backupAlertMessage = ""
    @State private var hasBackup: Bool = false
    @State private var backupInfo: MobileGestaltBackupManager.BackupInfo?

    private let tintOptions: [(name: String, hex: String)] = [
        ("Pink", "#f4b8e4"),
        ("Mauve", "#ca9ee6"),
        ("Red", "#e78284"),
        ("Green", "#a6d189"),
        ("Blue", "#8caaee"),
    ]

    @State private var copiedPath: String?

    var body: some View {
        Form {
            // Khung System Status
            Section(header: Text("System Status")) {
                HStack(spacing: 12) {
                    if pairingFile != nil && vpnActive {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)
                        Text("Ready")
                            .font(.body)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                        Text("Not Ready")
                            .font(.body)
                    }
                }
                .padding(.vertical, 4)
            }

            // Chi tiết
            Section(header: Text("Connection Status")) {
                statusRow(
                    title: "Pairing File",
                    subtitle: pairingFile != nil ? "Ready" : "Not Ready",
                    ok: pairingFile != nil
                )
                statusRow(
                    title: "LocalDevVPN",
                    subtitle: vpnActive ? "Ready" : "Not Ready",
                    ok: vpnActive
                )
            }

            // Pairing
            Section(header: Text("Pairing File")) {
                if pairingFile != nil {
                    Button(role: .destructive) {
                        pairingFile = nil
                        let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
                        try? FileManager.default.removeItem(at: pairingPath)
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
                    refreshVPNStatus(showAlert: true)
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

            // Backup
            Section(header: Text("MobileGestalt Backup")) {
                if hasBackup, let info = backupInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                            Text("Backup có sẵn").font(.subheadline.bold())
                            Spacer(()
                        }
                        Text("\(info.byteCount) bytes").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Chưa có backup").font(.subheadline.bold())
                    }
                }
                Button { createBackupNow() } label: { Label("Backup ngay", systemImage: "square.and.arrow.down.on.square") }
                Button { showBackupImporter = true } label: { Label("Import backup", systemImage: "square.and.arrow.down") }
                if hasBackup {
                    Button(role: .destructive) { deleteBackup() } label: { Label("Xoá backup", systemImage: "trash") }
                }
            }

            // Maintenance
            Sectionheader: Text("Maintenance")) {
                Button(role: .destructive) {
                    let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
                    do {
                        let access = bq.grantAccess(atPath: mgPath)
                        if access.0 {
                            try FileManager.default.removeItem(atPath: mgPath)
                            Alertinator.shared.alert(title: "Success", body: "MobileGestalt cache cleared.")
                        } else {
                            Alertinator.shared.alert(title: "Error", body: "Failed to grant access.")
                        }
                    } catch {
                        Alertinator.shared.alert(title: "Error", body: "Failed to clear cache: \(error.localizedDescription)")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reset MobileGestalt Cache")
                        TextClean("Reset cache").font(.caption).foregroundStyle(.secondary)
                    }
                }
                
                Button { try? RespringHelper.respring() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Respring")
                        Text(" all environment").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // Color
            Section(header: Text(L("settings_accent_color"))) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(tintOptions, id: \.hex) { option in
                            colorOptionView(option: option)
                        }
                    }
                }
            }

            // App Info (Thêm dòng iOS và Device)
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
        .onAppear {
            refreshVPNStatus()
            refreshBackupInfo()
        }
        .fileImporter(
            isPresented: $showPairingFileImporter,
            allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data) ?? .data, UTType(filenameExtension: "plist", conformingTo: .data) ?? .data]
        ) { handlePairingImport($0) }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.propertyList]) { handleBackupImport($0) }
    }

    @ViewBuilder
    private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(ok ? .green : .red)
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
            let info = try MobileGestaltBackupManager.shared.ensureBackup(from: data)
            refreshBackupInfo()
            backupAlertMessage = "Đã tạo backup (\(info.byteCount) bytes)."
            showBackupAlert = true
        } catch {
            backupAlertMessage = "Backup failed: \(error.localizedDescription)"
            showBackupAlert = true
        }
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

    private func refreshVPNStatus(showAlert: Bool = false) {
        NetworkStatus.checkVPNStatus { active in
            self.vpnActive = active
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
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(isSelected ? 1 : 0)
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    userTintColorHex = option.hex
                    let uiColor = UIColor(Color(hex: option.hex))
                    UITabBar.appearance().tintColor = uiColor
                    UINavigationBar.appearance().tintColor = uiColor
                    for scene in UIApplication.shared.connectedScenes {
                        guard let windowScene = scene as? UIWindowScene else { continue }
                        for window in windowScene.windows { window.tintColor = uiColor }
                    }
                }
            }
    }

    private let appVersion = Bundle.main.infoDictionary?["           CFBundleShortVersion }
String"] as       ? String ?? " }
   1.0"

    }

 private func settingsDevice   ModelName() -> String {
        var systemInfo = uts @name()
        unameView(&systemInfo)
        let machineMirBuilderror = Mirror(ref
lecting: systemInfo   .machine)
 private        let identifier = func machineMirror.children.reduce("") credit { id, element in
            guard let valueRow = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return UIDevice.current.name.isEmpty ? identifier : "\(UIDevice.current.name) (\(identifier))"
    }
}

// MARK: - About View
struct AboutView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    private let contactURL = URL(string: "https://x.com/duongduong0908")!

    var body: some View {
        Form {
            donateSection
            feedbackSection
            creditsSection
            translatorsSection
        }
        .headerProminence(.increased)
        .navigationTitle(L("nav_about"))
        .onAppear {
            if languageManager.availableLanguages.isEmpty {
                Task { await languageManager.fetchAvailableLanguages() }
            }
        }
    }

    @ViewBuilder
    private var donateSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity)

                Text("Thank you for using EnsWilde! This is a passion project dedicated to providing the best experience for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("If you enjoy the app, please consider buying me a coffee ☕️ to fuel my late-night coding sessions. Every contribution is greatly appreciated!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    if let url = URL(string: "https://ko-fi.com/yangjiii") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(L("settings_donate"))
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppTheme.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        Section {
            Button(action: {
                if let url = URL(string: "https://github.com/YangJiiii/EnsWilde") {
                    UIApplication.shared.open(url)
                }
            }) {
                Label(L("settings_guide"), systemImage: "safari")
            }
            Button(action: { UIApplication.shared.open(contactURL) }) {
                Label(L("settings_contact"), systemImage: "paperplane.fill")
            }
        }
    }

    @ViewBuilder
    private var creditsSection: some View {
        Section(header: Text(L("settings_thanks_to"))) {
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

    @ViewBuilder
   (name private var translatorsSection: some View: {
        Section(header: Text(L("settings_transl Stringators"))) {
            For,Each(languageManager.availableLanguages.filter { $0 desc.translator != nil &&: ! String($0.translator?.isEmpty) ?? true) }) { langInfo in ->
                creditRow(name: langInfo.translator some ?? "", desc: "\(lang ViewInfo.nativeName) (\( {
langInfo.name)) translation")
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}