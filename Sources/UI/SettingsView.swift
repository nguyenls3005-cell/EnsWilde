//
//  SettingsView.swift
//  EnsWilde
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network
import AirliftFFI
import Darwin
import Security

// MARK: - Unified Document Picker
struct DocumentPickerView: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType] = [.data, .item]
    let onPick: (URL) -> Void
    var onCancel: (() -> Void)? = nil
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

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel?()
            parent.dismiss()
        }
    }
}

// MARK: - Main Settings View
struct SettingsView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var globalLog = GLOBAL_LOG
    @AppStorage("PairingFile") private var pairingFile: String?
    @State private var showPairingPicker = false
    @State private var showOnDevicePairing = false
    @State private var vpnActive: Bool = false
    @State private var monitor: NWPathMonitor?
    @AppStorage("isAirLiftMode") private var isAirLiftMode: Bool = false

    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @State private var isTestingWrite = false
    @State private var writeTestLog = ""
    @State private var writeTestSuccess: Bool? = nil
    @State private var copiedLog: Bool = false

    private var tintOptions: [(name: String, hex: String)] {
        [
            (L("color_orange"), "#ef9f76"),
            (L("color_pink"),   "#f4b8e4"),
            (L("color_mauve"),  "#ca9ee6"),
            (L("color_red"),    "#e78284"),
            (L("color_green"),  "#a6d189"),
            (L("color_blue"),   "#8caaee"),
        ]
    }

    private var combinedLogForCopy: String {
        var sections: [String] = []
        let mainLog = globalLog.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mainLog.isEmpty {
            sections.append(mainLog)
        }
        let testLog = writeTestLog.trimmingCharacters(in: .whitespacesAndNewlines)
        if !testLog.isEmpty {
            sections.append("--- Bad Query Test Log ---\n\(testLog)")
        }
        return sections.joined(separator: "\n\n")
    }

    var body: some View {
        Form {
            runTestSection
            respringSection
            connectionStatusSection
            pairingFileSection
            languageSection
            accentColorSection
            appInfoSection
        }
        .navigationTitle(L("nav_settings"))
        .onAppear { startMonitoringVPN() }
        .onDisappear { monitor?.cancel() }
        .sheet(isPresented: $showPairingPicker) {
            DocumentPickerView(
                allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing") ?? .data],
                onPick: { url in handlePairingImport(url) }
            )
        }
        .sheet(isPresented: $showOnDevicePairing) {
            NavigationStack {
                OnDevicePairingView().toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("alert_close")) { showOnDevicePairing = false }
                    }
                }
            }
        }
        .alert("Chạy không thành công", isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var runTestSection: some View {
        Section {
            Button(action: runMobileGestaltTest) {
                HStack {
                    Label(L("settings_run_test_btn"), systemImage: "doc.badge.plus")
                        .foregroundStyle(.primary)
                    Spacer()
                    if isTestingWrite { ProgressView() }
                }
            }
            .disabled(isTestingWrite)

            if !writeTestLog.isEmpty {
                ScrollView {
                    Text(writeTestLog)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(writeTestSuccess == true ? .green : (writeTestSuccess == false ? .red : .primary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 250)
            }
        } header: {
            HStack {
                Text(L("settings_run_test_header"))
                    .font(.headline)
                    .textCase(nil)

                Spacer()

                Button {
                    UIPasteboard.general.string = combinedLogForCopy
                    withAnimation {
                        copiedLog = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation {
                            copiedLog = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedLog ? "checkmark" : "doc.on.doc")
                        Text(copiedLog ? "Copied" : "Copy Log")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(copiedLog ? .green : .secondary)
                    .textCase(nil)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var respringSection: some View {
        Section(header: Text(L("settings_respring_header"))) {
            Button {
                do {
                    try RespringHelper.respring()
                } catch {
                    errorMessage = "Chạy không thành công do: \(error.localizedDescription). Hãy qua Cài đặt -> Chạy thử nghiệm / Bad Query và sao chép log rồi gửi lên nhóm Telegram."
                    showErrorAlert = true
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.blue)
                    Text(L("settings_respring_btn"))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var connectionStatusSection: some View {
        Section(header: Text(L("connection_status"))) {
            statusRow(title: L("pairing_file"), subtitle: pairingFile != nil ? L("status_ready") : L("status_not_ready"), ok: pairingFile != nil)
            statusRow(title: L("settings_tunnel_status"), subtitle: vpnActive ? L("status_ready") : L("status_not_ready"), ok: vpnActive)
            if isAirLiftMode { statusRow(title: L("airlift_mode"), subtitle: L("enabled"), ok: true) }
        }
    }

    private var pairingFileSection: some View {
        Section(header: Text(L("pairing_file"))) {
            if pairingFile != nil {
                Button(role: .destructive) {
                    pairingFile = nil
                    try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                } label: { Label(L("button_reset_pairing"), systemImage: "trash") }
            } else {
                Button { showPairingPicker = true } label: { Label(L("import_pairing"), systemImage: "doc.badge.plus") }

                if #available(iOS 27.0, *) {
                    Button { showOnDevicePairing = true } label: {
                        Label(L("pair_on_device"), systemImage: "iphone.radiowaves.left.and.right")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var languageSection: some View {
        Section(header: Text(L("settings_language"))) {
            NavigationLink(destination: LanguageSettingsView()) {
                Label(L("settings_language"), systemImage: "globe")
            }
        }
    }

    private var accentColorSection: some View {
        Section(header: Text(L("settings_accent_color"))) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(tintOptions, id: \.hex) { option in
                        colorOptionView(option: option)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var appInfoSection: some View {
        Section(header: Text(L("settings_app_info"))) {
            HStack { Label("EnsWilde", systemImage: "sparkles"); Spacer(); Text("v3.1.3 Beta 4").font(.footnote).foregroundStyle(.secondary) }
            HStack { Label(L("app_ios"), systemImage: "iphone"); Spacer(); Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary) }
            HStack { Label(L("app_device"), systemImage: "apps.iphone"); Spacer(); Text(settingsDeviceModelName()).font(.footnote).foregroundStyle(.secondary) }
            Text(L("app_info_footer")).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private func runMobileGestaltTest() {
        isTestingWrite = true
        writeTestSuccess = nil
        GLOBAL_LOG.beginNewSession(header: "=== Bad Query Test Log ===")
        writeTestLog = "[*] Starting permission test (Native MCM & fsgetpath)...\n"
        GLOBAL_LOG.step("[*] Starting permission test (Native MCM & fsgetpath)...")

        let work = DispatchWorkItem {
            let testFile = MobileGestaltApplyTask.onDeviceMGPath
            let bridge = NativeWorseQuery.shared
            let runtimeGroups = self.getAllRuntimeAppGroups()
            let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"

            DispatchQueue.main.async {
                let line = "📱 Runtime Groups: \(runtimeGroups.joined(separator: ", "))"
                self.writeTestLog += line + "\n"
                GLOBAL_LOG.step(line)
            }
            Thread.sleep(forTimeInterval: 1.0)

            var finalHandle: Int64 = -1
            var lastError = ""

            for group in runtimeGroups {
                if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) == nil { continue }

                DispatchQueue.main.async {
                    let line = "[*] Try requesting permission via App Group: \(group)..."
                    self.writeTestLog += line + "\n"
                    GLOBAL_LOG.step(line)
                }

                let (handle, error) = bridge.grantAccess(targetPath: targetDir, appGroupID: group)

                if handle > 0 {
                    finalHandle = handle
                    DispatchQueue.main.async {
                        let line = "✅ Success: \(error)"
                        self.writeTestLog += line + "\n"
                        GLOBAL_LOG.success(line)
                    }
                    break
                } else {
                    lastError = error
                    DispatchQueue.main.async {
                        let line = " ⚠️ Failure: \(error)"
                        self.writeTestLog += line + "\n"
                        GLOBAL_LOG.error(line)
                    }
                }
            }

            if finalHandle <= 0 {
                DispatchQueue.main.async {
                    let line = "[*] Fallback: Try fsgetpath inode traversal..."
                    self.writeTestLog += line + "\n"
                    GLOBAL_LOG.step(line)
                }
                let (handle, error) = bridge.grantViaFsgetpath(targetFile: testFile)
                if handle > 0 {
                    finalHandle = handle
                    DispatchQueue.main.async {
                        let line = "✅ Success: \(error)"
                        self.writeTestLog += line + "\n"
                        GLOBAL_LOG.success(line)
                    }
                } else {
                    lastError = error
                    DispatchQueue.main.async {
                        let line = " ⚠️ Failure: \(error)"
                        self.writeTestLog += line + "\n"
                        GLOBAL_LOG.error(line)
                    }
                }
            }

            guard finalHandle > 0 else {
                DispatchQueue.main.async {
                    let failMsg = "Chạy không thành công"
                    let detail = lastError.isEmpty ? "Không cấp được quyền truy cập file" : lastError
                    self.writeTestLog += "\n❌ \(failMsg): \(detail)\n"
                    GLOBAL_LOG.error(failMsg)
                    GLOBAL_LOG.error("Chi tiết lỗi: \(detail)")
                    self.writeTestSuccess = false
                    self.isTestingWrite = false
                    self.errorMessage = "Chạy không thành công do: \(detail). Hãy qua Cài đặt -> Chạy thử nghiệm / Bad Query và sao chép log rồi gửi lên nhóm Telegram."
                    self.showErrorAlert = true
                }
                return
            }

            DispatchQueue.main.async {
                let line = "✅ Token acquired! Testing file writing..."
                self.writeTestLog += line + "\n"
                GLOBAL_LOG.step(line)
            }
            Thread.sleep(forTimeInterval: 1.0)

            do {
                let originalData = try Data(contentsOf: URL(fileURLWithPath: testFile))
                var st = stat()
                if stat(testFile, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
                    _ = chflags(testFile, st.st_flags & ~UInt32(UF_IMMUTABLE))
                }

                let fd = open(testFile, O_RDWR | O_CLOEXEC)
                guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                defer { close(fd) }

                let bytesWritten = originalData.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
                guard bytesWritten == originalData.count else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "pwrite errno: \(errno)"])
                }

                _ = fcntl(fd, F_FULLFSYNC)
                bridge.releaseAll()
                DispatchQueue.main.async {
                    let line = "✅ FILE WRITE SUCCESSFULLY!"
                    self.writeTestLog += line + "\n"
                    GLOBAL_LOG.success(line)
                    self.writeTestSuccess = true
                    self.isTestingWrite = false
                }
            } catch {
                bridge.releaseAll()
                DispatchQueue.main.async {
                    let failMsg = "Chạy không thành công"
                    let detail = error.localizedDescription
                    self.writeTestLog += "❌ \(failMsg): \(detail)\n"
                    GLOBAL_LOG.error(failMsg)
                    GLOBAL_LOG.error("Chi tiết lỗi: \(detail)")
                    self.writeTestSuccess = false
                    self.isTestingWrite = false
                    self.errorMessage = "Chạy không thành công do: \(detail). Hãy qua Cài đặt -> Chạy thử nghiệm / Bad Query và sao chép log rồi gửi lên nhóm Telegram."
                    self.showErrorAlert = true
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func getAllRuntimeAppGroups() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [] }
        guard let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) else { return [] }
        return (entitlements as? [String]) ?? []
    }

    @ViewBuilder private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack { Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red); Spacer(); Text(subtitle).font(.caption).foregroundStyle(ok ? .green : .red) }
    }

    @ViewBuilder private func colorOptionView(option: (name: String, hex: String)) -> some View {
        let color = Color(hex: option.hex)
        let isSelected = userTintColorHex.lowercased() == option.hex.lowercased()
        VStack(spacing: 6) {
            Circle().fill(color).frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay(Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.white).opacity(isSelected ? 1 : 0))
            Text(option.name).font(.caption).foregroundColor(isSelected ? .primary : .secondary)
        }
        .onTapGesture {
            userTintColorHex = option.hex
            let uiColor = UIColor(Color(hex: option.hex))
            UITabBar.appearance().tintColor = uiColor
            UINavigationBar.appearance().tintColor = uiColor
        }
    }

    private func handlePairingImport(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try RPPairingParser.parse(url: url)
            let data = try Data(contentsOf: url)
            let destURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
            try data.write(to: destURL)
            pairingFile = url.lastPathComponent
        } catch {
            errorMessage = "Chạy không thành công do: \(error.localizedDescription). Hãy qua Cài đặt -> Chạy thử nghiệm / Worse Query và sao chép log rồi gửi lên nhóm Telegram."
            showErrorAlert = true
        }
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

// MARK: - About View
struct AboutView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"

    var body: some View {
        Form {
            aboutHeroSection
            aboutSocialSection
            aboutThanksSection
            aboutTranslatorsSection
        }
        .navigationTitle(L("nav_about"))
        .onAppear {
            if localizationManager.availableLanguages.isEmpty {
                Task { await localizationManager.fetchAvailableLanguages() }
            }
        }
    }

    private var aboutHeroSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(.pink)
                Text(L("about_desc")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: "https://dangdi.dev/donate") { UIApplication.shared.open(url) }
                } label: {
                    Text(L("button_donate"))
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(hex: userTintColorHex))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutSocialSection: some View {
        Section {
            Button(action: { if let url = URL(string: "https://t.me/yangjiiidibo") { UIApplication.shared.open(url) } }) {
                Label(L("about_group_yang"), systemImage: "safari")
            }
            Button(action: { if let url = URL(string: "https://t.me/lsnguyengr") { UIApplication.shared.open(url) } }) {
                Label(L("about_group_ls"), systemImage: "safari")
            }
            Button(action: { if let url = URL(string: "https://t.me/lsnguyyniu") { UIApplication.shared.open(url) } }) {
                Label(L("about_contact"), systemImage: "paperplane.fill")
            }
        }
    }

    private var aboutThanksSection: some View {
        Section(header: Text(L("settings_thanks_to"))) {
            creditRow(name: "@YangJiii", desc: L("credit_yang_support"))
            creditRow(name: "@YangJiii", desc: L("credit_yang_original"))
            creditRow(name: "@LSNguyen", desc: L("credit_ls_new"))
            creditRow(name: "@forcequitOS", desc: L("credit_forcequit_badquery"))
            creditRow(name: "@0xjohnnydev", desc: L("credit_johnny_airlift"))
            creditRow(name: "@mak5er", desc: L("credit_mak5er_aod"))
            creditRow(name: "@jailbreakdotparty", desc: L("credit_jailbreak_config"))
            creditRow(name: "@LikePass888", desc: L("credit_likepass_sound"))
            creditRow(name: "@Little_34306", desc: L("credit_little_34306_concept"))
            creditRow(name: "@YiHoooong", desc: L("credit_yihooong_silent"))
            creditRow(name: "@Kianuni", desc: L("credit_kianuni_erosion"))
            creditRow(name: "Cộng đồng LSNguyen & YangJiii và những người bạn chat ⚡️", desc: L("credit_community"))
        }
    }

    private var aboutTranslatorsSection: some View {
        Section(header: Text(L("settings_translators"))) {
            ForEach(translatorLanguages) { langInfo in
                creditRow(name: langInfo.translator ?? "", desc: String(format: L("translation_by"), langInfo.nativeName, langInfo.name))
            }
        }
    }

    private var translatorLanguages: [LanguageInfo] {
        localizationManager.availableLanguages.filter { (info: LanguageInfo) -> Bool in
            guard let tr = info.translator else { return false }
            return !tr.isEmpty
        }
    }

    @ViewBuilder
    private func creditRow(name: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).fontWeight(.semibold)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
