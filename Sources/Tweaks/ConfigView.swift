import SwiftUI

enum CNURL {
    static var sharedDevConfig = FSURL.configProfiles.appendingPathComponent("SharedDeviceConfiguration.plist")
    static var cloudConfig = FSURL.configProfiles.appendingPathComponent("CloudConfigurationDetails.plist")
}

enum CNMsg {
    static var supWarning = "⚠️ CẢNH BÁO SUPERVISION. Nếu thiết bị đã được MDM quản lý → ĐỪNG bật toggle này! Sau khi respring có thể thấy màn hình setup ban đầu. Dùng với rủi ro của bạn."
    static var resetInfo = "Bấm Confirm → footnote bị xoá và thiết bị sẽ không còn supervised."
}

struct ConfigView: View {
    @ObservedObject var toolStore: ToolStore
    @State private var ftCurrentDict = NSMutableDictionary()
    @State private var ccCurrentDict = NSMutableDictionary()
    @State private var footnoteText = ""
    @State private var supervised = false
    @State private var orgName = ""
    @State private var showRespringAlert = false
    @State private var respringMessage = ""
    @State private var showSupervisionWarning = false

    init(toolStore: ToolStore = ToolStore()) {
        self.toolStore = toolStore
    }

    var body: some View {
        Form {
            Section(header: Text("Config Tweaks")) {
                Toggle("Enable Tweak", isOn: $toolStore.configTweaksEnabled)
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
                        Text(footnoteText.isEmpty ? "Swipe up to open" : footnoteText)
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                        Capsule().frame(width: 145, height: 4).foregroundStyle(.white)
                    }
                }
                .padding(.top, 25).padding(.bottom, 10)
                .listRowInsets(EdgeInsets())
                .listRowBackground(
                    LinearGradient(
                        colors: [Color.black, Color.gray.opacity(0.4), Color.black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                TextField("Custom Footnote", text: $footnoteText)
                    .onChange(of: footnoteText) { newValue in
                        toolStore.configFootnoteText = newValue
                    }
            } header: {
                HeaderLabel("Lock Screen Footnote", symbol: "textformat")
            }

            Section {
                Toggle("Enable Supervision", isOn: $supervised)
                    .onChange(of: supervised) { newValue in
                        if newValue { showSupervisionWarning = true }
                    }
                if supervised {
                    TextField("Organization Name", text: $orgName)
                }
            } header: {
                HeaderLabel("Supervision", symbol: "eye")
            }

            Section {
                Button {
                    apply()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Apply Save Changes").font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                }

                Button(role: .destructive) {
                    Alertinator.shared.alert(
                        title: "Reset your tweaks?",
                        body: CNMsg.resetInfo,
                        actionLabel: "Confirm",
                        action: { reset() }
                    )
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Restore Save Changes").font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle("Config Tweaks")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            doSetup()
            footnoteText = toolStore.configFootnoteText
        }
        .alert("Supervision Warning!", isPresented: $showSupervisionWarning) {
            Button("Cancel", role: .cancel) { supervised = false }
            Button("I Understand", role: .destructive) {}
        } message: {
            Text(CNMsg.supWarning)
        }
        .alert("Config Tweaks", isPresented: $showRespringAlert) {
            Button("Respring") { try? RespringHelper.respring() }
            Button("Later", role: .cancel) {}
        } message: {
            Text(respringMessage)
        }
    }

    private func doSetup() {
        if !fm.isWritableFile(atPath: CNURL.sharedDevConfig.path) {
            let res = bq.grantAccess(atPath: FSURL.configProfiles.path)
            if !res.0 {
                Alertinator.shared.alert(title: "Failed to get write access!", body: AppMsg.opFailed)
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
        let ftDict = ["LockScreenFootnote" : footnoteText]
        ccCurrentDict["IsSupervised"] = supervised
        ccCurrentDict["OrganizationName"] = orgName
        toolStore.configFootnoteText = footnoteText
        toolStore.configTweaksEnabled = true

        do {
            let ftData = try PropertyListSerialization.data(fromPropertyList: ftDict, format: .binary, options: 0)
            try ftData.write(to: CNURL.sharedDevConfig)
            let ccData = try PropertyListSerialization.data(fromPropertyList: ccCurrentDict, format: .binary, options: 0)
            try ccData.write(to: CNURL.cloudConfig)
            print("(cn) successfully applied config tweaks!")
            Haptic.shared.play(.soft)
            UserDefaults.standard.set(true, forKey: "ShowApplyTab")
            respringMessage = "Đã apply. Tab Apply đã được mở ở dưới."
            showRespringAlert = true
        } catch {
            print("(cn) failed: \(error.localizedDescription)")
            Alertinator.shared.alert(title: "Failed to apply tweaks!", body: AppMsg.opFailed)
        }
    }

    private func reset() {
        ccCurrentDict["IsSupervised"] = false
        ccCurrentDict.removeObject(forKey: "OrganizationName")
        do {
            try? fm.removeItem(at: CNURL.sharedDevConfig)
            let ccData = try PropertyListSerialization.data(fromPropertyList: ccCurrentDict, format: .binary, options: 0)
            try ccData.write(to: CNURL.cloudConfig)
            print("(cn) successfully reset!")
            Haptic.shared.play(.soft)
            loadData()
            footnoteText = ""
            respringMessage = "Đã reset. Respring để thay đổi có hiệu lực."
            showRespringAlert = true
        } catch {
            print("(cn) failed to reset: \(error.localizedDescription)")
            Alertinator.shared.alert(title: "Failed to reset tweaks!", body: AppMsg.opFailed)
        }
    }
}

struct QuickActionBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.ultraThinMaterial, in: .circle)
    }
}