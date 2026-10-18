import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network
import AirliftFFI

struct DocumentPickerView: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        init(_ parent: DocumentPickerView) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
            parent.onPick(url)
            parent.dismiss()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.dismiss() }
    }
}

struct SettingsView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @State private var showPairingPicker = false
    @State private var vpnActive: Bool = false
    @State private var monitor: NWPathMonitor?
    @AppStorage("isAirLiftMode") private var isAirLiftMode: Bool = false
    @State private var hasBackup: Bool = false
    @State private var backupInfo: MobileGestaltBackupManager.BackupInfo?
    @State private var isCheckingAirLift = false
    @State private var airLiftLogs: [String] = []
    @State private var showAirLiftLogs = false
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    private let tintOptions: [(name: String, hex: String)] = [
        ("Pink", "#f4b8e4"), ("Mauve", "#ca9ee6"), ("Red", "#e78284"), ("Green", "#a6d189"), ("Blue", "#8caaee")
    ]

    var body: some View {
        Form {
            Section(header: Text(L("connection_status"))) {
                statusRow(title: L("pairing_file"), subtitle: pairingFile != nil ? L("status_ready") : L("status_not_ready"), ok: pairingFile != nil)
                statusRow(title: "LocalDevVPN", subtitle: vpnActive ? L("status_ready") : L("status_not_ready"), ok: vpnActive)
                if isAirLiftMode { statusRow(title: "AirLift Mode", subtitle: "Enabled", ok: true) }
            }

            Section(header: Text("Check AirLift Status")) {
                Button { checkAirLift() } label: {
                    HStack {
                        if isCheckingAirLift { ProgressView().tint(.blue) }
                        else { Image(systemName: "bolt.shield.fill").foregroundStyle(.blue) }
                        Text(isCheckingAirLift ? "Checking..." : "Check AirLift Status").fontWeight(.semibold)
                    }
                }.disabled(isCheckingAirLift)

                if showAirLiftLogs {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(airLiftLogs, id: \.self) { log in
                            Text(log).font(.caption2).foregroundStyle(log.contains("❌") ? .red : (log.contains("✅") ? .green : .secondary))
                        }
                    }.padding(.vertical, 4)
                }
            }

            Section(header: Text(L("pairing_file"))) {
                if pairingFile != nil {
                    Button(role: .destructive) {
                        pairingFile = nil
                        try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                    } label: { Label(L("button_reset_pairing"), systemImage: "trash") }
                } else {
                    Button { showPairingPicker = true } label: { Label(L("button_select_pairing"), systemImage: "doc.badge.plus") }
                }
            }

            if !isAirLiftMode {
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
                    Button { createBackupNow() } label: { Label(L("backup_now"), systemImage: "square.and.arrow.down.on.square") }
                    if hasBackup { Button(role: .destructive) { deleteBackup() } label: { Label(L("backup_delete"), systemImage: "trash") } }
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
                Text(L("app_info_footer")).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .navigationTitle(L("nav_settings"))
        .onAppear {
            startMonitoringVPN()
            refreshBackupInfo()
        }
        .onDisappear { monitor?.cancel() }
        .sheet(isPresented: $showPairingPicker) {
            DocumentPickerView(allowedContentTypes: [.item]) { url in
                handlePairingImport(url)
            }
        }
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

    private func checkAirLift() {
        isCheckingAirLift = true
        airLiftLogs.removeAll()
        showAirLiftLogs = true
        airLiftLogs.append("Starting AirLift check...")

        let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
        guard FileManager.default.fileExists(atPath: pairingPath) else {
            airLiftLogs.append("❌ Missing Pairing File! Vui lòng nhập pairing trước.")
            isCheckingAirLift = false
            return
        }
        airLiftLogs.append("✅ Pairing File found.")

        DispatchQueue.global(qos: .userInitiated).async {
            _ = al_set_target_host("127.0.0.1")
            var outJson: UnsafeMutablePointer<CChar>? = nil
            var outError: UnsafeMutablePointer<CChar>? = nil
            
            let result = al_exploit_run(
                pairingPath,
                "/var/mobile/Library",
                { _, msg in
                    guard let msg = msg else { return }
                    let line = String(cString: msg)
                    DispatchQueue.main.async { airLiftLogs.append("   \(line)") }
                },
                nil,
                &outJson,
                &outError
            )

            DispatchQueue.main.async {
                if result == 0 {
                    airLiftLogs.append("✅ AirLift is ACTIVE and working!")
                    isAirLiftMode = true
                    if let jsonStr = outJson {
                        airLiftLogs.append("Response: \(String(cString: jsonStr).prefix(100))...")
                        al_string_free(jsonStr)
                    }
                } else {
                    var errMsg = "Unknown error"
                    if let err = outError {
                        errMsg = String(cString: err)
                        al_string_free(err)
                    }
                    airLiftLogs.append("❌ AirLift failed: \(errMsg)")
                }
                isCheckingAirLift = false
            }
        }
    }

    private func handlePairingImport(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty && ext != "plist" && ext != "mobiledevicepairing" { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
            pairingFile = url.lastPathComponent
        }
    }

    private func refreshBackupInfo() {
        hasBackup = MobileGestaltBackupManager.shared.hasBackup
        backupInfo = MobileGestaltBackupManager.shared.info
    }

    private func createBackupNow() {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: MobileGestaltApplyTask.onDeviceMGPath))
            _ = try MobileGestaltBackupManager.shared.ensureBackup(from: data)
            refreshBackupInfo()
        } catch { print("Backup failed") }
    }

    private func deleteBackup() {
        try? MobileGestaltBackupManager.shared.clearBackup()
        refreshBackupInfo()
    }

    private func startMonitoringVPN() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.vpnActive = path.availableInterfaces.contains { $0.type == .other || $0.name.hasPrefix("utun") || $0.name.hasPrefix("ipsec") }
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

struct AboutView: View {
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        Form {
            Section {
                VStack "(spacing: 12) {
                    Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(.pink)
                    Text(L("about_desc")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                    Label(L("about_contact"), systemImage:paperplane.fill")
                }
            }

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