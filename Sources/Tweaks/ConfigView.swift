import SwiftUI

enum CNURL {
    static var sharedDevConfig = FSURL.configProfiles.appendingPathComponent("SharedDeviceConfiguration.plist")
    static var cloudConfig = FSURL.configProfiles.appendingPathComponent("CloudConfigurationDetails.plist")
}

enum CNMsg {
    // Đã sửa thành Key để dịch bảng cảnh báo
    static var supWarning = "supervision_warning_message"
    static var resetInfo = "reset_tweaks_info"
}

struct ConfigView: View {
    @ObservedObject var toolStore: ToolStore
    @State private var ftCurrentDict = NSMutableDictionary()
    @State private var ccCurrentDict = NSMutableDictionary()
    @State private var footnoteText = ""
    @State private var supervised = false
    @State private var orgName = ""
    @State private var showSupervisionWarning = false
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = ""

    init(toolStore: ToolStore = ToolStore()) {
        self.toolStore = toolStore
    }

    var body: some View {
        Form {
            Section(header: Text(L("config_tweaks_title"))) {
                Toggle(L("enable_tweak"), isOn: $toolStore.configTweaksEnabled)
                    .onChange(of: toolStore.configTweaksEnabled) { isEnabled in
                        if !isEnabled {
                            UserDefaults.standard.set(false, forKey: "ShowApplyTab")
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
                    .onChange(of: footnoteText) { newValue in
                        toolStore.configFootnoteText = newValue
                    }
            } header: {
                HeaderLabel(L("lock_screen_footnote"), symbol: "textformat")
            }

            Section {
                Toggle(L("enable_supervision"), isOn: $supervised)
                    .onChange(of: supervised) { newValue in
                        if newValue { showSupervisionWarning = true }
                    }
                if supervised {
                    TextField(L("organization_name"), text: $orgName)
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
                    Alertinator.shared.alert(
                        title: L("reset_tweaks_title"),
                        body: L("reset_tweaks_info"),
                        actionLabel: L("confirm"),
                        action: { reset() }
                    )
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
            footnoteText = toolStore.configFootnoteText
        }
        .alert(L("supervision_warning_title"), isPresented: $showSupervisionWarning) {
            Button(L("cancel"), role: .cancel) { supervised = false }
            Button(L("i_understand"), role: .destructive) {}
        } message: {
            Text(L(CNMsg.supWarning))
        }
        .alert(L("saved"), isPresented: $showSaveAlert) {
            Button("OK") {}
        } message: {
            Text(saveAlertMessage)
        }
    }

    private func doSetup() {
        if !fm.isWritableFile(atPath: CNURL.sharedDevConfig.path) {
            let res = bq.grantAccess(atPath: FSURL.configProfiles.path)
            if !res.0 {
                Alertinator.shared.alert(title: L("failed_write_access"), body: L("op_failed"))
                return
            }
        }
        if !fm.fileExists(atPath: CNURL.sharedDevConfig.path) {
            do {
                let dict = ["LockScreenFootnote" : ""]
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
                try data.write(to: CNURL.sharedDevConfig)
            } catch {
                print("(cn) failed to create footnote file: \(error.localizedDescription)")
            }
        }
        loadData()
    }

    private func loadData() {
        if let ftDict = NSMutableDictionary(contentsOf: CNURL.sharedDevConfig) {
            ftCurrentDict = ftDict
            footnoteText = ftDict["LockScreenFootnote"] as? String ?? ""
        }
        if let ccDict = NSMutableDictionary(contentsOf: CNURL.cloudConfig) {
            ccCurrentDict = ccDict
            supervised = ccDict["IsSupervised"] as? Bool ?? false
            orgName = ccDict["OrganizationName"] as? String ?? ""
        }
    }

    private func apply() {
        toolStore.configFootnoteText = footnoteText
        toolStore.configTweaksEnabled = true
        UserDefaults.standard.set(supervised, forKey: "ConfigSupervised")
        UserDefaults.standard.set(orgName, forKey: "ConfigOrgName")
        
        UserDefaults.standard.set(true, forKey: "ShowApplyTab")

        saveAlertMessage = L("saved_apply_hint")
        showSaveAlert = true
    }

    private func reset() {
        ccCurrentDict["IsSupervised"] = false
        ccCurrentDict.removeObject(forKey: "OrganizationName")
        do {
            try? fm.removeItem(at: CNURL.sharedDevConfig)
            let ccData = try PropertyListSerialization.data(fromPropertyList: ccCurrentDict, format: .binary, options: 0)
            try ccData.write(to: CNURL.cloudConfig)
            print("(cn) successfully reset config tweaks!")
            Haptic.shared.play(.soft)
            loadData()
            footnoteText = ""
            toolStore.configFootnoteText = ""
            toolStore.configTweaksEnabled = false
            UserDefaults.standard.set(false, forKey: "ConfigSupervised")
            UserDefaults.standard.removeObject(forKey: "ConfigOrgName")
            
            UserDefaults.standard.set(true, forKey: "ShowApplyTab")

            saveAlertMessage = L("reset_apply_hint")
            showSaveAlert = true
        } catch {
            print("(cn) failed to reset config files: \(error.localizedDescription)")
            Alertinator.shared.alert(title: L("failed_reset"), body: L("op_failed"))
        }
    }
}

struct QuickActionBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.ultraThinMaterial, in: .circle)
    }
}