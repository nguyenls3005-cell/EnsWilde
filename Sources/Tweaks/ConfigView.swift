import SwiftUI

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
    @State private var saveAlertMessage = ""
    @State private var navigateAfterAlert = false
    @State private var justRestored = false

    private let fm = FileManager.default
    private let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"

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
        .alert(L("saved"), isPresented: $showSaveAlert) {
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

    private func ensureConfigAccess() {
        _ = bq.grantAccess(atPath: configDir)
        if !fm.fileExists(atPath: sharedDevConfigURL.path) {
            let dict: [String: Any] = ["LockScreenFootnote": ""]
            if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
                try? data.write(to: sharedDevConfigURL, options: .atomic)
            }
        }
    }

    private func doSetup() {
        ensureConfigAccess()
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

    private func writeConfigFiles(footnote: String, isSupervised: Bool, organization: String) {
        ensureConfigAccess()
        let ftDict: [String: Any] = ["LockScreenFootnote": footnote]
        if let ftData = try? PropertyListSerialization.data(fromPropertyList: ftDict, format: .binary, options: 0) {
            try? ftData.write(to: sharedDevConfigURL, options: .atomic)
        }

        let ccDict = NSMutableDictionary(contentsOf: cloudConfigURL) ?? NSMutableDictionary()
        ccDict["IsSupervised"] = isSupervised
        if isSupervised && !organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ccDict["OrganizationName"] = organization
        } else {
            ccDict.removeObject(forKey: "OrganizationName")
        }
        if let ccData = try? PropertyListSerialization.data(fromPropertyList: ccDict, format: .binary, options: 0) {
            try? ccData.write(to: cloudConfigURL, options: .atomic)
        }
    }

    private func apply() {
        justRestored = false
        navigateAfterAlert = false
        toolStore.configFootnoteText = footnoteText
        storedFootnoteText = footnoteText
        storedSupervised = supervised
        storedOrgName = orgName
        toolStore.configTweaksEnabled = true
        writeConfigFiles(footnote: footnoteText, isSupervised: supervised, organization: orgName)
        showApplyTab = true
        GLOBAL_LOG.success("Đã lưu Config Tweaks.")
        saveAlertMessage = L("config_saved_message")
        showSaveAlert = true
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
        writeConfigFiles(footnote: "", isSupervised: false, organization: "")
        showApplyTab = true
        navigateAfterAlert = true
        GLOBAL_LOG.step("Đã đặt lại Config Tweaks & xoá footnote.")
        saveAlertMessage = L("reset_tweaks_info")
        showSaveAlert = true
    }
}
