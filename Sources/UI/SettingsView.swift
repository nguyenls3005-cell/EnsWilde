import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Settings View
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
            systemStatusSection
            pairingSection
            backupSection
            languageSection
            colorSection
            appInfoSection
        }
        .headerProminence(.increased)
        .navigationTitle(L("nav_settings"))
        .onAppear {
            if languageManager.availableLanguages.isEmpty {
                Task {
                    await languageManager.fetchAvailableLanguages()
                }
            }
            refreshVPNStatus()
            refreshBackupInfo()
        }
        .fileImporter(
            isPresented: $showPairingFileImporter,
            allowedContentTypes: [
                .propertyList,
                UTType(filenameExtension: "plist", conformingTo: .data) ?? .data
            ]
        ) { result in
            print("[Pairing] File picker result: \(result)")
            handlePairingImport(result)
        }
        .fileImporter(
            isPresented: $showBackupImporter,
            allowedContentTypes: [
                .propertyList,
                UTType(filenameExtension: "plist", conformingTo: .data) ?? .data
            ]
        ) { result in
            handleBackupImport(result)
        }
        .alert("LocalDevVPN", isPresented: $showVPNAlert) {
            Button("OK") {}
        } message: {
            Text("LocalDevVPN chưa bật. Airlift (Wallet / Passcode) sẽ không hoạt động.")
        }
        .alert("Pairing Error", isPresented: $showPairingErrorAlert) {
            Button("OK") {}
        } message: {
            Text(pairingImportError ?? "Unknown error")
        }
        .alert("Pairing Success", isPresented: $showPairingSuccessAlert) {
            Button("OK") {}
        } message: {
            Text(pairingImportSuccess ?? "")
        }
        .alert("Backup", isPresented: $showBackupAlert) {
            Button("OK") {}
        } message: {
            Text(backupAlertMessage)
        }
    }

    // MARK: - System Status
    @ViewBuilder
    private var systemStatusSection: some View {
        Section(header: Text(L("system_status") + " (For Passcode, Wallet)")) {
            statusRow(
                title: L("status_pairing_file"),
                subtitle: pairingFile != nil ? L("status_pairing_loaded") : L("status_pairing_missing"),
                ok: pairingFile != nil
            )
            statusRow(
                title: "LocalDevVPN",
                subtitle: vpnActive ? "Connected" : "Not connected",
                ok: vpnActive
            )
        }
    }

    @ViewBuilder
    private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pairing Section
    @ViewBuilder
    private var pairingSection: some View {
        Section(header: Text(L("status_pairing_file"))) {
            if pairingFile != nil {
                Button(role: .destructive) {
                    pairingFile = nil
                    let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
                    try? FileManager.default.removeItem(at: pairingPath)
                } label: {
                    Label(L("button_reset_pairing"), systemImage: "trash")
                }
            } else {
                Button {
                    print("[Pairing] Import button tapped")
                    showPairingFileImporter = true
                } label: {
                    Label(L("button_select_pairing"), systemImage: "doc.badge.plus")
                }
            }

            Button {
                refreshVPNStatus(showAlert: true)
            } label: {
                HStack {
                    Label("Check LocalDevVPN", systemImage: "wifi")
                    Spacer()
                    if vpnActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    // MARK: - Backup Section
    @ViewBuilder
    private var backupSection: some View {
        Section(header: Text("MobileGestalt Backup")) {
            if hasBackup, let info = backupInfo {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Text("Backup có sẵn")
                            .font(.subheadline.bold())
                        Spacer()
                    }
                    HStack {
                        Text("Ngày tạo:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(info.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Kích thước:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(info.byteCount) bytes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chưa có backup")
                            .font(.subheadline.bold())
                        Text("Sẽ tự tạo khi bấm Save lần đầu, hoặc bấm Backup ngay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                createBackupNow()
            } label: {
                Label("Backup ngay", systemImage: "square.and.arrow.down.on.square")
            }

            Button {
                showBackupImporter = true
            } label: {
                Label("Import backup", systemImage: "square.and.arrow.down")
            }

            if hasBackup {
                Button(role: .destructive) {
                    deleteBackup()
                } label: {
                    Label("Xoá backup", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Backup Handlers
    private func refreshBackupInfo() {
        hasBackup = MobileGestaltBackupManager.shared.hasBackup
        backupInfo = MobileGestaltBackupManager.shared.info
    }

    private func createBackupNow() {
        do {
            let onDevicePath = MobileGestaltApplyTask.onDeviceMGPath
            let onDeviceURL = URL(fileURLWithPath: onDevicePath)
            let data = try Data(contentsOf: onDeviceURL)

            let info = try MobileGestaltBackupManager.shared.ensureBackup(from: data)

            refreshBackupInfo()

            backupAlertMessage = "Đã tạo backup (\(info.byteCount) bytes). SHA256: \(info.sha256.prefix(16))..."
            showBackupAlert = true
        } catch {
            backupAlertMessage = "Backup failed: \(error.localizedDescription)"
            showBackupAlert = true
        }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)

                guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil else {
                    backupAlertMessage = "File không phải plist hợp lệ."
                    showBackupAlert = true
                    return
                }

                try MobileGestaltBackupManager.shared.importBackup(from: data)

                refreshBackupInfo()

                backupAlertMessage = "Đã import backup (\(data.count) bytes)."
                showBackupAlert = true
            } catch {
                backupAlertMessage = "Import failed: \(error.localizedDescription)"
                showBackupAlert = true
            }

        case .failure(let error):
            backupAlertMessage = "Chọn file thất bại: \(error.localizedDescription)"
            showBackupAlert = true
        }
    }

    private func deleteBackup() {
        do {
            try MobileGestaltBackupManager.shared.clearBackup()
            refreshBackupInfo()
            backupAlertMessage = "Đã xoá backup."
            showBackupAlert = true
        } catch {
            backupAlertMessage = "Xoá thất bại: \(error.localizedDescription)"
            showBackupAlert = true
        }
    }

    // MARK: - Pairing Import Handler
    private func handlePairingImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            print("[Pairing] Selected file: \(url.lastPathComponent)")

            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                print("[Pairing] Data size: \(data.count) bytes")

                do {
                    let parsed = try RPPairingParser.parse(data)
                    print("[Pairing] Parsed OK. identifier=\(parsed.identifier)")
                } catch let parseError as RPPairingError {
                    print("[Pairing] Parse error: \(parseError.localizedDescription)")
                    pairingImportError = parseError.localizedDescription
                    showPairingErrorAlert = true
                    return
                } catch {
                    print("[Pairing] Unknown parse error: \(error)")
                    pairingImportError = "Parse failed: \(error.localizedDescription)"
                    showPairingErrorAlert = true
                    return
                }

                let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
                try data.write(to: pairingPath)
                print("[Pairing] Saved to: \(pairingPath.path)")

                pairingFile = url.lastPathComponent
                print("[Pairing] pairingFile set to: \(url.lastPathComponent)")

                pairingImportSuccess = "Đã import pairing: \(url.lastPathComponent)\nKích thước: \(data.count) bytes"
                showPairingSuccessAlert = true

            } catch {
                print("[Pairing] Read/write error: \(error)")
                pairingImportError = "Đọc file thất bại: \(error.localizedDescription)"
                showPairingErrorAlert = true
            }

        case .failure(let error):
            print("[Pairing] File picker failed: \(error)")
            pairingImportError = "Chọn file thất bại: \(error.localizedDescription)"
            showPairingErrorAlert = true
        }
    }

    // MARK: - VPN Check
    private func refreshVPNStatus(showAlert: Bool = false) {
        NetworkStatus.checkVPNStatus { active in
            self.vpnActive = active

            if showAlert && !active {
                self.showVPNAlert = true
            }
        }
    }

    // MARK: - Language
    @ViewBuilder
    private var languageSection: some View {
        Section(header: Text(L("settings_language"))) {
            NavigationLink(destination: LanguageSettingsView()) {
                Label(L("settings_language"), systemImage: "globe")
            }
        }
    }

    // MARK: - Color
    @ViewBuilder
    private var colorSection: some View {
        Section(header: Text(L("settings_accent_color"))) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tintOptions, id: \.hex) { option in
                        colorOptionView(option: option)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    @ViewBuilder
    private func colorOptionView(option: (name: String, hex: String)) -> some View {
        let color = Color(hex: option.hex)
        let isSelected = userTintColorHex.lowercased() == option.hex.lowercased()
        VStack(spacing: 6) {
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
            Text(option.name)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(width: 60)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? color.opacity(0.15) : Color.clear)
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

    // MARK: - App Info
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    @ViewBuilder
    private var appInfoSection: some View {
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
            Text("iOS 27+: bad_query có thể chỉnh chữ trên màn hình khoá (swipe up text) và PosterBoard wallpaper. iOS 26: chỉ Airlift (Wallet/Passcode).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func settingsDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
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

                Text("Thank you for using EnsWilde! This is a passion project dedicated to providing the best experience for you. Your support is my biggest motivation to keep improving it every day.")
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
            creditRow(name: "Carrot1211", desc: "For cheering me on and supporting me during development.")
            creditRow(name: "@khanhduytran0", desc: "is based on SparseBox.")
            creditRow(name: "@SideStore team", desc: "idevice and C bindings from StikDebug.")
            creditRow(name: "@JJTech0130", desc: "SparseRestore and backup exploit.")
            creditRow(name: "@hanakim3945", desc: "bl_sbx exploit files and writeup.")
            creditRow(name: "@Lakr233", desc: "BBackupp.")
            creditRow(name: "@libimobiledevice", desc: L("settings_thanks_libimobile"))
            creditRow(name: "@PoomSmart", desc: "MobileGestalt dump.")
            creditRow(name: "@paragonarsi", desc: "Apple Wallet Get.")
            creditRow(name: "@iTechExpert21", desc: "Hide Dynamic Island.")
            creditRow(name: "@skadz108 & @rooootdev", desc: "NeoSpring respring.")
            creditRow(name: "@mak5er", desc: "AirCard-iOS reference.")
            creditRow(name: "@Nouvborne", desc: "Ketamine reference.")
            creditRow(name: "@jailbreakdotparty", desc: "Erosion reference.")
        }
    }

    @ViewBuilder
    private var translatorsSection: some View {
        Section(header: Text(L("settings_translators"))) {
            ForEach(languageManager.availableLanguages.filter { $0.translator != nil && !($0.translator?.isEmpty ?? true) }) { langInfo in
                creditRow(name: langInfo.translator ?? "", desc: "\(langInfo.nativeName) (\(langInfo.name)) translation")
            }
        }
    }

    @ViewBuilder
    private func creditRow(name: String, desc: String) -> some View {
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

// MARK: - Components Helper
struct ThanksRow: View {
    let name: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}