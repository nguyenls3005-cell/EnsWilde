import SwiftUI
import Darwin
import AirliftFFI

private struct QuickActionBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .background(Color.white.opacity(0.22))
            .clipShape(Circle())
    }
}

private struct HeaderLabel: View {
    let text: String
    let symbol: String

    init(_ text: String, symbol: String) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.bold())
    }
}

struct ConfigView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("ConfigFootnoteText") private var storedFootnoteText: String = ""
    @AppStorage("ConfigSupervised") private var storedSupervised: Bool = false
    @AppStorage("ConfigOrgName") private var storedOrgName: String = ""

    @State private var footnoteText = ""
    @State private var supervised = false
    @State private var orgName = ""
    @State private var showSupervisionWarning = false
    @State private var showSaveAlert = false
    @State private var saveAlertTitle = L("saved")
    @State private var saveAlertMessage = ""
    @State private var navigateAfterAlert = false
    @State private var justRestored = false

    private let fm = FileManager.default
    private let configDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"

    private var sharedDevConfigURL: URL {
        URL(fileURLWithPath: "\(configDir)/SharedDeviceConfiguration.plist")
    }

    private var cloudConfigURL: URL {
        URL(fileURLWithPath: "\(configDir)/CloudConfigurationDetails.plist")
    }

    init(toolStore: ToolStore = ToolStore()) {
        self.toolStore = toolStore
    }

    var body: some View {
        Form {
            Section(header: Text(L("config_tweaks_title"))) {
                Toggle(L("enable_tweak"), isOn: $toolStore.configTweaksEnabled)
                    .onChange(of: toolStore.configTweaksEnabled) { isEnabled in
                        if !isEnabled {
                            showApplyTab = false
                        }
                    }
            }

            Section {
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "flashlight.off.fill")
                            .resizable().scaledToFit().frame(width: 26, height: 26)
                            .padding()
                            .modifier(QuickActionBackground())
                        Spacer()
                        Image(systemName: "camera.fill")
                            .resizable().scaledToFit().frame(width: 26, height: 26)
                            .padding()
                            .modifier(QuickActionBackground())
                    }
                    .padding(.horizontal, 35)

                    VStack(spacing: 6) {
                        Text(footnoteText.isEmpty ? L("swipe_up_to_open") : footnoteText)
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                        Capsule().frame(width: 145, height: 4).foregroundStyle(.white)
                    }
                }
                .padding(.top, 25).padding(.bottom, 10)
                .listRowInsets(EdgeInsets())
                .listRowBackground(
                    ZStack {
                        Color.black
                        Image("solarium")
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }
                )

                TextField(L("custom_footnote"), text: $footnoteText)
                    .autocorrectionDisabled()
                    .onChange(of: footnoteText) { newValue in
                        toolStore.configFootnoteText = newValue
                        storedFootnoteText = newValue
                    }
            } header: {
                HeaderLabel(L("lock_screen_footnote"), symbol: "textformat")
            }

            Section {
                Toggle(L("enable_supervision"), isOn: $supervised)
                    .onChange(of: supervised) { newValue in
                        storedSupervised = newValue
                        if newValue { showSupervisionWarning = true }
                    }
                if supervised {
                    TextField(L("organization_name"), text: $orgName)
                        .autocorrectionDisabled()
                        .onChange(of: orgName) { newValue in
                            storedOrgName = newValue
                        }
                }
            } header: {
                HeaderLabel(L("supervision_title"), symbol: "eye")
            }

            Section {
                Button {
                    apply()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text(L("apply_save_changes")).font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                }

                Button(role: .destructive) {
                    reset()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(L("restore_save_changes")).font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("config_tweaks_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            doSetup()
            if !justRestored {
                if !toolStore.configFootnoteText.isEmpty {
                    footnoteText = toolStore.configFootnoteText
                } else if !storedFootnoteText.isEmpty {
                    footnoteText = storedFootnoteText
                    toolStore.configFootnoteText = storedFootnoteText
                }
                supervised = storedSupervised
                orgName = storedOrgName
            }
        }
        .alert(L("supervision_warning_title"), isPresented: $showSupervisionWarning) {
            Button(L("cancel"), role: .cancel) {
                supervised = false
                storedSupervised = false
            }
            Button(L("i_understand"), role: .destructive) {}
        } message: {
            Text(L("supervision_warning_message"))
        }
        .alert(saveAlertTitle, isPresented: $showSaveAlert) {
            Button("OK") {
                if navigateAfterAlert {
                    navigateAfterAlert = false
                    showApplyTab = true
                    NotificationCenter.default.post(name: .ensWildeNavigateToApply, object: nil)
                }
            }
        } message: {
            Text(saveAlertMessage)
        }
    }

    private func grantDirectFileWrite(at filePath: String) {
        _ = wq.grantAccess(path: configDir, requireWrite: true, allowFsgetpathFallback: true)
        _ = wq.grantAccess(path: filePath, requireWrite: true, allowFsgetpathFallback: true)
        _ = NativeWorseQuery.shared.grantViaFsgetpath(targetFile: filePath, requireWrite: true, allowRecursiveWq: true)

        var st = stat()
        if stat(filePath, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
            _ = chflags(filePath, st.st_flags & ~UInt32(UF_IMMUTABLE))
        }
    }

    private func directOverwritePlist(data: Data, to url: URL) throws {
        let path = url.path
        grantDirectFileWrite(at: path)

        let fd = open(path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard fd >= 0 else {
            let err = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: "Mở file thất bại: \(url.lastPathComponent) (errno: \(err))"]
            )
        }
        defer { close(fd) }

        let oldSize = lseek(fd, 0, SEEK_END)
        let written = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return pwrite(fd, base, data.count, 0)
        }
        guard written == data.count else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Ghi file thất bại: \(url.lastPathComponent) (errno: \(errno))"]
            )
        }
        if oldSize > off_t(data.count) {
            ftruncate(fd, off_t(data.count))
        }
        if fcntl(fd, F_FULLFSYNC) == -1 {
            fsync(fd)
        }
    }

    private func doSetup() {
        _ = wq.grantAccess(path: configDir, requireWrite: true, allowFsgetpathFallback: true)
        if justRestored { return }
        if let ftDict = NSDictionary(contentsOf: sharedDevConfigURL) as? [String: Any],
           let diskFootnote = ftDict["LockScreenFootnote"] as? String, !diskFootnote.isEmpty {
            footnoteText = diskFootnote
            toolStore.configFootnoteText = diskFootnote
            storedFootnoteText = diskFootnote
        }
        if let ccDict = NSDictionary(contentsOf: cloudConfigURL) as? [String: Any] {
            if let diskSup = ccDict["IsSupervised"] as? Bool {
                supervised = diskSup
                storedSupervised = diskSup
            }
            if let diskOrg = ccDict["OrganizationName"] as? String {
                orgName = diskOrg
                storedOrgName = diskOrg
            }
        }
    }

    private func writeConfigFiles(footnote: String, isSupervised: Bool, organization: String) throws {
        let ftDict: [String: Any] = ["LockScreenFootnote": footnote]
        let ftData = try PropertyListSerialization.data(fromPropertyList: ftDict, format: .binary, options: 0)
        try directOverwritePlist(data: ftData, to: sharedDevConfigURL)

        let ccDict = NSMutableDictionary(contentsOf: cloudConfigURL) ?? NSMutableDictionary()
        ccDict["IsSupervised"] = isSupervised
        if isSupervised && !organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ccDict["OrganizationName"] = organization
        } else {
            ccDict.removeObject(forKey: "OrganizationName")
        }
        let ccData = try PropertyListSerialization.data(fromPropertyList: ccDict, format: .binary, options: 0)
        try directOverwritePlist(data: ccData, to: cloudConfigURL)
    }

    private func apply() {
        justRestored = false
        navigateAfterAlert = false
        toolStore.configFootnoteText = footnoteText
        storedFootnoteText = footnoteText
        storedSupervised = supervised
        storedOrgName = orgName
        toolStore.configTweaksEnabled = true

        GLOBAL_LOG.beginNewSession(header: "=== Config Tweaks ===")
        GLOBAL_LOG.step("[Config] Đang xin quyền ghi vào ConfigurationProfiles...")

        do {
            try writeConfigFiles(footnote: footnoteText, isSupervised: supervised, organization: orgName)
            showApplyTab = true
            GLOBAL_LOG.success("Đã lưu Config Tweaks.")
            saveAlertTitle = L("saved")
            saveAlertMessage = L("config_saved_message")
            showSaveAlert = true
        } catch {
            let detail = error.localizedDescription
            GLOBAL_LOG.error("Chạy không thành công")
            GLOBAL_LOG.error("Chi tiết lỗi: \(detail)")
            saveAlertTitle = "Chạy không thành công"
            saveAlertMessage = "Chạy không thành công do: \(detail). Hãy qua Cài đặt -> Chạy thử nghiệm / Bad Query và sao chép log rồi gửi lên nhóm Telegram."
            showSaveAlert = true
        }
    }

    private func reset() {
        justRestored = true
        footnoteText = ""
        orgName = ""
        supervised = false
        toolStore.configFootnoteText = ""
        storedFootnoteText = ""
        storedSupervised = false
        storedOrgName = ""
        toolStore.configTweaksEnabled = true

        GLOBAL_LOG.beginNewSession(header: "=== Reset Config Tweaks ===")
        GLOBAL_LOG.step("Đang đặt lại Config Tweaks & xoá footnote...")

        do {
            try writeConfigFiles(footnote: "", isSupervised: false, organization: "")
            showApplyTab = true
            navigateAfterAlert = true
            GLOBAL_LOG.success("Đã đặt lại Config Tweaks & xoá footnote.")
            saveAlertTitle = L("saved")
            saveAlertMessage = L("reset_tweaks_info")
            showSaveAlert = true
        } catch {
            let detail = error.localizedDescription
            GLOBAL_LOG.error("Chạy không thành công")
            GLOBAL_LOG.error("Chi tiết lỗi: \(detail)")
            saveAlertTitle = "Chạy không thành công"
            saveAlertMessage = "Chạy không thành công do: \(detail). Hãy qua Cài đặt -> Chạy thử nghiệm / Bad Query và sao chép log rồi gửi lên nhóm Telegram."
            showSaveAlert = true
        }
    }
}
