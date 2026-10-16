import SwiftUI

enum CNURL {
    static var sharedDevConfig = FSURL.configProfiles.appendingPathComponent("SharedDeviceConfiguration.plist")
    static var cloudConfig = FSURL.configProfiles.appendingPathComponent("CloudConfigurationDetails.plist")
}

struct ConfigView: View {
    @ObservedObject var toolStore: ToolStore

    @State private var ftCurrentDict = NSMutableDictionary()
    @State private var footnoteText = ""
    @State private var showRespringAlert = false
    @State private var respringMessage = ""
    @State private var saveSuccess = false

    init(toolStore: ToolStore = ToolStore()) {
        self.toolStore = toolStore
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "flashlight.off.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .padding()
                            .modifier(QuickActionBackground())
                        Spacer()
                        Image(systemName: "camera.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .padding()
                            .modifier(QuickActionBackground())
                    }
                    .padding(.horizontal, 35)

                    VStack(spacing: 6) {
                        Text(footnoteText.isEmpty ? "Swipe up to open" : footnoteText)
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                        Capsule()
                            .frame(width: 145, height: 4)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 25)
                .padding(.bottom, 10)
                .listRowInsets(EdgeInsets())
                .listRowBackground(
                    Group {
                        Image("SolariumBackground")
                            .resizable()
                            .scaledToFill()
                    }
                )

                TextField("Custom Footnote", text: $footnoteText)
                    .onChange(of: footnoteText) { newValue in
                        toolStore.configFootnoteText = newValue
                    }
            } header: {
                HeaderLabel("Lock Screen Footnote", symbol: "textformat")
            }

            Section {
                Button {
                    apply()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Apply")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
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
        .alert("Config Tweaks", isPresented: $showRespringAlert) {
            Button("Respring") {
                try? RespringHelper.respring()
            }
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
    }

    private func apply() {
        let ftDict = ["LockScreenFootnote" : footnoteText]

        // Save to AppStorage trước để state luôn được giữ
        toolStore.configFootnoteText = footnoteText
        toolStore.configTweaksEnabled = true

        do {
            let ftData = try PropertyListSerialization.data(fromPropertyList: ftDict, format: .binary, options: 0)
            try ftData.write(to: CNURL.sharedDevConfig)
            print("(cn) successfully applied config tweaks!")
            Haptic.shared.play(.soft)

            // Bật tab Apply — user tự chuyển sang
            UserDefaults.standard.set(true, forKey: "ShowApplyTab")

            respringMessage = "Đã apply. Tab Apply đã được mở ở dưới — chuyển sang để respring."
            showRespringAlert = true
        } catch {
            print("(cn) failed to write config file: \(error.localizedDescription)")
            Alertinator.shared.alert(title: "Failed to apply tweaks!", body: AppMsg.opFailed)
        }
    }
}

// MARK: - UI
struct QuickActionBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: .circle)
    }
}