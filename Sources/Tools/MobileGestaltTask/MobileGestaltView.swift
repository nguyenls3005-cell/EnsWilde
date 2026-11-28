import SwiftUI
import UniformTypeIdentifiers
import CoreFoundation

struct MGRegionPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let suffix: String
}

struct MobileGestaltView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    let origMGURL, modMGURL, featFlagsURL, resolutionURL: URL
    @Environment(\.scenePhase) var scenePhase
    @ObservedObject var toolStore: ToolStore
    @StateObject private var store = GestaltStore.shared

    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("ogMachineName") private var ogMachineName = ""

    @State var mbdb: Backup?
    @State var eligibilityData = Data()
    @State var featureFlagsData = Data()
    @State var mobileGestalt: NSMutableDictionary
    @State var productType = machineName()
    @State var respring = true
    @State var showPairingFileImporter = false
    @State var showErrorAlert = false
    @State var taskRunning = false
    @State var initError: String?
    @State var lastError: String?

    @State var dynamicIslandType: Int = 0
    @State var enableCustomSubtype: Bool = false
    @State var customSubtypeValue: String = ""
    @State var enableModelName: Bool = false
    @State var modelName: String = ""

    @State private var showDIWarning = false

    let regionPresets: [MGRegionPreset] = [
        MGRegionPreset(id: "VN", name: "Viet Nam", suffix: "VN/A"),
        MGRegionPreset(id: "LL", name: "United States", suffix: "LL/A"),
        MGRegionPreset(id: "CH", name: "China", suffix: "CH/A"),
        MGRegionPreset(id: "J", name: "Japan", suffix: "J/A"),
        MGRegionPreset(id: "ZA", name: "Singapore", suffix: "ZA/A"),
        MGRegionPreset(id: "VC", name: "Canada", suffix: "VC/A"),
        MGRegionPreset(id: "ZP", name: "Hong Kong", suffix: "ZP/A"),
    ]

    @State private var selectedRegionCode: String = "CH"
    @State private var regionCustomSuffix: String? = nil

    var body: some View {
        Form {
            Section(header: Text(L("tool_mobile_gestalt"))) {
                Toggle(L("enable_tweak"), isOn: $toolStore.replaceMobileGestaltEnabled)
                    .onChange(of: toolStore.replaceMobileGestaltEnabled) { isEnabled in
                        if !isEnabled { showApplyTab = false }
                    }
            }

            Section(header: Text(L("section_device_subtype"))) {
                Picker(selection: $dynamicIslandType) {
                    Text(L("mg_subtype_none")).tag(0)
                    Text(L("mg_subtype_2436")).tag(1)
                    Text(L("mg_subtype_2556")).tag(2)
                    Text(L("mg_subtype_2796")).tag(3)
                    Text(L("mg_subtype_2976")).tag(4)
                    Text(L("mg_subtype_2622")).tag(5)
                    Text(L("mg_subtype_2868")).tag(6)
                    Text(L("mg_subtype_2736")).tag(7)
                    Text(L("mg_subtype_2662")).tag(8)
                    Text(L("mg_subtype_custom")).tag(-1)
                } label: {
                    Text(L("mg_device_subtype_preset"))
                }
                .pickerStyle(.menu)
                .onChange(of: dynamicIslandType) { newValue in
                    if newValue == 8 {
                        showDIWarning = true
                        enableCustomSubtype = false
                    } else if newValue == -1 {
                        enableCustomSubtype = true
                    } else {
                        enableCustomSubtype = false
                    }
                }
                .alert(L("mg_di_warning_title"), isPresented: $showDIWarning) {
                    Button(L("alert_cancel"), role: .cancel) {
                        hydrateFromDict()
                    }
                    Button(L("alert_accept")) {
                        enableCustomSubtype = false
                    }
                }

                if enableCustomSubtype || dynamicIslandType == -1 {
                    Toggle(L("mg_enable_custom_subtype"), isOn: $enableCustomSubtype)
                    if enableCustomSubtype {
                        TextField(L("mg_custom_subtype_placeholder"), text: $customSubtypeValue)
                            .keyboardType(.numberPad)
                    }
                }

                Toggle(isOn: $enableModelName) {
                    Text(L("mg_change_model_name"))
                }
                if enableModelName {
                    TextField(L("mg_model_name_placeholder"), text: $modelName)
                }
            }

            Section(header: Text(L("section_hardware_features"))) {
                Toggle(L("mg_boot_chime"), isOn: store.mgByteBinding(key: MGKey.bootChime))
                Toggle(L("mg_charge_limit"), isOn: store.mgByteBinding(key: MGKey.chargeLim))
                    .disabled(Utils.requiresVersion(17))
                if UIDevice._hasHomeButton() {
                    Toggle(L("mg_tap_to_wake"), isOn: store.mgByteBinding(key: MGKey.tapToWake))
                }
                Toggle(L("mg_camera_button"), isOn: store.mgByteBinding(key: MGKey.camButton))
                    .disabled(Utils.requiresVersion(18))
            }

            Section(header: Text(L("section_display_and_ui"))) {
                Toggle(L("mg_stage_manager"), isOn: store.mgByteBinding(key: MGKey.stageMgr))
                Toggle(L("mg_aod"), isOn: bindingForMGKeys([MGKey.AOD, MGKey.AOTime]))
                    .disabled(Utils.requiresVersion(18))
                Toggle(L("mg_aod_vibrancy"), isOn: store.mgByteBinding(key: MGKey.AODVibrancy))
                    .disabled(Utils.requiresVersion(18))

                Toggle(L("mg_become_ipados"), isOn: Binding(
                    get: { return store.mgTrollPadBinding().wrappedValue },
                    set: { newValue in
                        _ = store.mgSetiPadOS(enable: newValue)
                        store.objectWillChange.send()
                    }
                ))
            }

            Section(header: Text(L("section_system_features"))) {
                Toggle(isOn: bindingForMGKeys(["9MZ5AdH43csAUajl/dU+IQ"], type: [Int].self, defaultValue: [1], enableValue: [1, 2])) {
                    Text(L("mg_install_ipad_apps"))
                }

                Picker(selection: $selectedRegionCode) {
                    ForEach(regionPresets) { preset in
                        Text("\(preset.suffix) - \(preset.name)").tag(preset.id)
                    }
                    if selectedRegionCode == "CUSTOM" {
                        Text("\(regionCustomSuffix ?? "Custom")").tag("CUSTOM")
                    }
                } label: {
                    Text(L("mg_region"))
                }
                .pickerStyle(.menu)
                .onChange(of: selectedRegionCode) { newVal in
                    if newVal != "CUSTOM" { regionCustomSuffix = nil }
                }

                Toggle(L("mg_apple_pencil"), isOn: store.mgByteBinding(key: MGKey.appPencil))
                Toggle(L("mg_action_button"), isOn: store.mgByteBinding(key: MGKey.actButton))
                    .disabled(Utils.requiresVersion(17))
                Toggle(L("mg_crash_detection"), isOn: store.mgByteBinding(key: MGKey.crashDet))
            }

            Section(header: Text(L("section_internal_features"))) {
                Toggle(L("mg_internal_storage"), isOn: store.mgByteBinding(key: MGKey.intBuild))
                Toggle(L("mg_internal_stuff"), isOn: store.mgByteBinding(key: MGKey.intInstall))
                Toggle(L("mg_security_research"), isOn: store.mgByteBinding(key: MGKey.srd))

                Toggle(isOn: bindingForAppleIntelligence()) {
                    Text(L("mg_apple_intelligence"))
                }
                .disabled(Utils.requiresVersion(18))

                if store.isEnabled(MGKey.appIntellAllKeys) {
                    Group {
                        Toggle(L("mg_ondevice_siri"), isOn: store.mgKeyBinding(["O/7gbXWA5X2IRPVtDRU+bw"]))
                        Toggle(L("mg_audio_intel"), isOn: store.mgKeyBinding(["rb2tKZxlj0Gm2tBmUQSLqQ"]))
                        Toggle(L("mg_personal_translator"), isOn: store.mgKeyBinding(["M1n2sAqf33NAOgZRGxQYBA"]))
                        Toggle(L("mg_clean_up"), isOn: store.mgKeyBinding(["XNCjqOupLM/S8fNyxRNQTA"]))
                        Toggle(L("mg_handwriting"), isOn: store.mgKeyBinding(["YgYIIViDt1kgzyIsIV61vA"]))
                        Toggle(L("mg_hey_siri"), isOn: store.mgKeyBinding(["U+73bmG4kBGj6kpreQXUTQ"]))
                    }
                    .padding(.leading, 16)
                    .transition(.opacity)
                }

                Picker(selection: $productType) {
                    Text(L("mg_device_model_unchanged")).tag(MobileGestaltView.machineName())
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Text("iPad Pro 11 inch 5th Gen").tag("iPad16,3")
                    } else {
                        Text("iPhone 15 Pro").tag("iPhone16,1")
                        Text("iPhone 15 Pro Max").tag("iPhone16,2")
                        Text("iPhone 16").tag("iPhone17,3")
                        Text("iPhone 16 Plus").tag("iPhone17,4")
                        Text("iPhone 16e").tag("iPhone17,5")
                        Text("iPhone 16 Pro").tag("iPhone17,1")
                        Text("iPhone 16 Pro Max").tag("iPhone17,2")
                        Text("iPhone 17").tag("iPhone18,3")
                        Text("iPhone 17 Pro").tag("iPhone18,1")
                        Text("iPhone 17 Pro Max").tag("iPhone18,2")
                        Text("iPhone Air").tag("iPhone18,4")
                        Text("iPhone 17e").tag("iPhone18,5")
                        Text("iPhone 18 Pro").tag("iPhone19,2")
                        Text("iPhone 18 Pro Max (US)").tag("iPhone19,3")
                        Text("iPhone 18 Pro Max (Global)").tag("iPhone19,7")
                        Text("iPhone Duo").tag("iPhone19,4")
                    }
                } label: {
                    Text(L("mg_device_model"))
                }
                .pickerStyle(.menu)
            }

            Section(header: Text(L("section_save_reset"))) {
                Button(action: saveChanges) {
                    Label(L("mg_save_settings"), systemImage: "square.and.arrow.down")
                }
                .disabled(taskRunning)
                Button(role: .destructive, action: resetOriginal) {
                    Label(L("mg_revert_tweaks"), systemImage: "arrow.counterclockwise")
                }
                .disabled(taskRunning)
            }
        }
        .navigationTitle(L("tool_mobile_gestalt"))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Chạy không thành công", isPresented: $showErrorAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(lastError ?? L("msg_error_unknown"))
        }
        .onAppear { loadData() }
        .onReceive(store.$mgCurrentDict) { newDict in
            if newDict.count > 0 {
                self.mobileGestalt = newDict
                self.hydrateFromDict()
            }
        }
    }

    private func loadData() {
        let liveURL = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
        _ = wq.grantAccess(path: liveURL.deletingLastPathComponent().path)

        if let liveData = try? Data(contentsOf: liveURL),
           let liveDict = try? PropertyListSerialization.propertyList(
               from: liveData,
               options: [.mutableContainersAndLeaves],
               format: nil
           ) as? NSMutableDictionary {
            store.mgCurrentDict = liveDict
            self.mobileGestalt = liveDict
            try? liveData.write(to: modMGURL)
        } else {
            store.loadFromPlist(url: modMGURL)
            mobileGestalt = store.mgCurrentDict
        }
        hydrateFromDict()
    }

    private func parseSubtypeInt(_ raw: Any?) -> Int? {
        if let n = raw as? NSNumber { return n.intValue }
        if let i = raw as? Int { return i }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func hydrateFromDict() {
        dynamicIslandType = 0
        enableCustomSubtype = false
        customSubtypeValue = ""
        enableModelName = false
        modelName = ""
        productType = MobileGestaltView.machineName()

        let activeDict: NSDictionary = store.mgCurrentDict.count > 0 ? store.mgCurrentDict : mobileGestalt
        guard let cacheExtra = activeDict["CacheExtra"] as? NSDictionary else { return }

        productType = cacheExtra[MGKey.productType] as? String ?? productType

        let sysconfig = cacheExtra[MGKey.regionSysconfig] as? String ?? ""
        let regionInfo = cacheExtra[MGKey.regionInfo] as? String ?? ""
        let regionCode = cacheExtra[MGKey.regionCode] as? String ?? ""
        let effectiveSuffix = !sysconfig.isEmpty ? sysconfig : regionInfo

        if let preset = regionPresets.first(where: {
            (!effectiveSuffix.isEmpty && $0.suffix.caseInsensitiveCompare(effectiveSuffix) == .orderedSame) ||
            (!regionCode.isEmpty && $0.id.caseInsensitiveCompare(regionCode) == .orderedSame && effectiveSuffix.isEmpty)
        }) {
            self.selectedRegionCode = preset.id
            self.regionCustomSuffix = nil
        } else if !regionCode.isEmpty || !effectiveSuffix.isEmpty {
            self.selectedRegionCode = "CUSTOM"
            self.regionCustomSuffix = effectiveSuffix.isEmpty ? "\(regionCode) - Custom" : effectiveSuffix
        }

        var foundSubtype: Int? = nil
        if let artwork = cacheExtra[MGKey.artwork] as? NSDictionary {
            foundSubtype = parseSubtypeInt(artwork["ArtworkDeviceSubType"])
            if let name = artwork["ArtworkDeviceProductDescription"] as? String, !name.isEmpty {
                enableModelName = true
                modelName = name
            }
        }
        if foundSubtype == nil {
            foundSubtype = parseSubtypeInt(cacheExtra["ArtworkDeviceSubType"])
        }

        if let subtype = foundSubtype {
            switch subtype {
            case 2436: dynamicIslandType = 1
            case 2556: dynamicIslandType = 2
            case 2796: dynamicIslandType = 3
            case 2976: dynamicIslandType = 4
            case 2622: dynamicIslandType = 5
            case 2868: dynamicIslandType = 6
            case 2736: dynamicIslandType = 7
            case 2662: dynamicIslandType = 8
            default:
                dynamicIslandType = -1
                enableCustomSubtype = true
                customSubtypeValue = "\(subtype)"
            }
        }
    }

    private func saveChanges() {
        guard !taskRunning else { return }
        taskRunning = true
        GLOBAL_LOG.beginNewSession(header: "=== Lưu MobileGestalt ===")
        GLOBAL_LOG.step("Đang lưu MobileGestalt...")

        Task {
            do {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                let ce = store.cacheExtra
                let targetProductType = productType
                let chosenRegionCode = selectedRegionCode

                let spoofMap: [String: (hw: String, cpu: String, reg: String)] = [
                    "iPhone16,1": ("D83AP", "t8130", "A2848"),
                    "iPhone16,2": ("D84AP", "t8130", "A2849"),
                    "iPhone17,3": ("D47AP", "t8140", "A3081"),
                    "iPhone17,4": ("D48AP", "t8140", "A3082"),
                    "iPhone17,1": ("D93AP", "t8140", "A3083"),
                    "iPhone17,2": ("D94AP", "t8140", "A3084"),
                    "iPhone17,5": ("V59AP", "t8140", "A3212"),
                    "iPhone18,3": ("V57AP", "t8150", "A3258"),
                    "iPhone18,1": ("V53AP", "t8150", "A3256"),
                    "iPhone18,2": ("V54AP", "t8150", "A3257"),
                    "iPhone18,4": ("D23AP", "t8150", "A3260"),
                    "iPhone18,5": ("V59AP", "t8150", "A3575"),
                    "iPhone19,2": ("V63AP", "t8160", "A3472"),
                    "iPhone19,3": ("V64AP", "t8160", "A3473"),
                    "iPhone19,7": ("V64sAP", "t8160", "A3717"),
                    "iPhone19,4": ("V68AP", "t8160", "A3447")
                ]

                if targetProductType != ogMachineName, let info = spoofMap[targetProductType] {
                    ce[MGKey.productType] = targetProductType
                    ce["oYicEKzVTz4/CxxE05pEgQ"] = info.hw
                    ce["5pYKlGnYYBzGvAlIU8RjEQ"] = info.cpu
                    ce["97JDvERpVwO+GHtthIh7hA"] = info.reg

                    ce["A62OafQ85EJAiiqKn4agtg"] = 1
                    ce["a3n5T9sFtlyQ74NEp9ESxg"] = 2
                    ce["XNCjqOupLM/S8fNyxRNQTA"] = 1
                    ce["YgYIIViDt1kgzyIsIV61vA"] = 1

                    ce.removeObject(forKey: "EqrsVvjcYDdxHBiQmGhAWw")
                    ce.removeObject(forKey: "LBJfwOEzExRxzlAnSuI7eg")
                    ce.removeObject(forKey: "waGD2UTpntjbDXD1r3oALQ")
                } else if targetProductType == ogMachineName {
                    if let ogCE = NSDictionary(contentsOf: MGURL.savedGestaltURL)?["CacheExtra"] as? NSDictionary {
                        for key in ["h9jDsbgj7xIVeIQ8S3/X3Q", "oYicEKzVTz4/CxxE05pEgQ", "5pYKlGnYYBzGvAlIU8RjEQ", "97JDvERpVwO+GHtthIh7hA"] {
                            if let val = ogCE[key] { ce[key] = val } else { ce.removeObject(forKey: key) }
                        }
                    }
                }

                let art = (ce[MGKey.artwork] as? NSMutableDictionary) ?? NSMutableDictionary()
                if dynamicIslandType == 0 {
                    art.removeObject(forKey: "ArtworkDeviceSubType")
                } else if dynamicIslandType > 0 {
                    let subtypes = [0, 2436, 2556, 2796, 2976, 2622, 2868, 2736, 2662]
                    art["ArtworkDeviceSubType"] = subtypes[dynamicIslandType]
                    ce["YlEtTtHlNesRBMal1CqRaA"] = 1
                } else if enableCustomSubtype, let val = Int(customSubtypeValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    art["ArtworkDeviceSubType"] = val
                    ce["YlEtTtHlNesRBMal1CqRaA"] = 1
                }
                if enableModelName {
                    art["ArtworkDeviceProductDescription"] = modelName
                } else {
                    art.removeObject(forKey: "ArtworkDeviceProductDescription")
                }
                ce[MGKey.artwork] = art

                if chosenRegionCode != "CUSTOM", let preset = regionPresets.first(where: { $0.id == chosenRegionCode }) {
                    ce[MGKey.regionCode] = preset.id
                    ce[MGKey.regionSysconfig] = preset.suffix
                    ce[MGKey.regionInfo] = preset.suffix
                    ce["yK+xavymRGZ3xWc1tb8XDg"] = preset.suffix
                }

                try await MobileGestaltApplyTask.applyGestalt(store: store) { log in
                    print(log)
                }

                let liveURL = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
                let expectedData = try Data(contentsOf: liveURL)
                try expectedData.write(to: modMGURL)

                store.loadFromPlist(url: modMGURL)

                await MainActor.run {
                    self.mobileGestalt = store.mgCurrentDict
                    hydrateFromDict()
                    showApplyTab = true
                    taskRunning = false
                    GLOBAL_LOG.success("Lưu MobileGestalt thành công.")
                    lastError = L("mg_save_success_message")
                    showErrorAlert = true
                }
            } catch {
                await MainActor.run {
                    taskRunning = false
                    GLOBAL_LOG.error("Chạy không thành công")
                    GLOBAL_LOG.error("Chi tiết lỗi: \(error.localizedDescription)")
                    lastError = "Chạy không thành công do: \(error.localizedDescription). Hãy qua Cài đặt -> Chạy thử nghiệm / Bad Query và sao chép log rồi gửi lên nhóm Telegram."
                    showErrorAlert = true
                }
            }
        }
    }

    private func resetOriginal() {
        guard !taskRunning else { return }
        taskRunning = true
        GLOBAL_LOG.beginNewSession(header: "=== Khôi phục MobileGestalt ===")
        GLOBAL_LOG.step("Đang khôi phục MobileGestalt gốc...")

        Task {
            do {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                try await MobileGestaltApplyTask.restoreGestalt { log in
                    print(log)
                }

                try? FileManager.default.removeItem(at: modMGURL)

                await MainActor.run {
                    store.mgCurrentDict = NSMutableDictionary()
                    self.mobileGestalt = store.mgCurrentDict
                    hydrateFromDict()
                    showApplyTab = true
                    taskRunning = false
                    GLOBAL_LOG.success("Đã khôi phục MobileGestalt thành công.")
                    lastError = L("mg_revert_success_message")
                    showErrorAlert = true
                }
            } catch {
                await MainActor.run {
                    taskRunning = false
                    GLOBAL_LOG.error("Chạy không thành công")
                    GLOBAL_LOG.error("Chi tiết lỗi: \(error.localizedDescription)")
                    lastError = "Chạy không thành công do: \(error.localizedDescription). Hãy qua Cài đặt -> Chạy thử nghiệm / Bad Query và sao chép log rồi gửi lên nhóm Telegram."
                    showErrorAlert = true
                }
            }
        }
    }

    init(toolStore: ToolStore) {
        self.toolStore = toolStore
        let docs = URL.documentsDirectory
        featFlagsURL   = docs.appendingPathComponent("FeatureFlags.plist", conformingTo: .data)
        origMGURL      = docs.appendingPathComponent("OriginalMobileGestalt.plist", conformingTo: .data)
        modMGURL       = docs.appendingPathComponent("ModifiedMobileGestalt.plist", conformingTo: .data)
        resolutionURL  = docs.appendingPathComponent("Resolution.plist", conformingTo: .data)

        let liveURL = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
        _ = wq.grantAccess(path: liveURL.deletingLastPathComponent().path)

        var initialDict = NSMutableDictionary()
        var initErr: String? = nil

        do {
            if FileManager.default.fileExists(atPath: liveURL.path) {
                try? FileManager.default.removeItem(at: modMGURL)
                try? FileManager.default.copyItem(at: liveURL, to: modMGURL)
            } else if !FileManager.default.fileExists(atPath: modMGURL.path) {
                try FileManager.default.copyItem(at: origMGURL, to: modMGURL)
            }
            chmod(modMGURL.path, 0o644)

            if !FileManager.default.fileExists(atPath: origMGURL.path) {
                FileManager.default.createFile(atPath: origMGURL.path, contents: nil, attributes: nil)
            }
            chmod(origMGURL.path, 0o644)

            if let mutable = GestaltStore.loadMutableDict(from: modMGURL) {
                initialDict = mutable
            } else {
                initErr = "Failed to load MobileGestalt"
            }
        } catch {
            initErr = "Failed to copy MobileGestalt: \(error)"
        }

        _mobileGestalt = State(initialValue: initialDict)
        _initError = State(initialValue: initErr)
    }

    private func bindingForAppleIntelligence() -> Binding<Bool> {
        return store.mgKeyBinding(MGKey.appIntellAllKeys)
    }

    private func bindingForMGKeys<T: Equatable>(_ keys: [String], type: T.Type = Int.self, defaultValue: T? = 0, enableValue: T? = 1) -> Binding<Bool> {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary, let firstKey = keys.first else {
            return .constant(false)
        }
        return Binding(
            get: {
                guard let value = cacheExtra[firstKey] as? T, let ev = enableValue else { return false }
                return value == ev
            },
            set: { enabled in
                for key in keys {
                    if enabled { cacheExtra[key] = enableValue } else { cacheExtra.removeObject(forKey: key) }
                }
            }
        )
    }

    static func machineName() -> String {
        var sys = utsname()
        uname(&sys)
        return Mirror(reflecting: sys.machine).children.reduce("") { id, el in
            guard let v = el.value as? Int8, v != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(v)))
        }
    }
}
