//
//  MobileGestaltView.swift
//  EnsWilde
//

import SwiftUI
import UniformTypeIdentifiers

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
                    if newValue == 8 { showDIWarning = true }
                    else if newValue != -1 { enableCustomSubtype = false }
                    else { enableCustomSubtype = true }
                }
                .alert(L("mg_di_warning_title"), isPresented: $showDIWarning) {
                    Button(L("alert_cancel"), role: .cancel) { dynamicIslandType = 0 }
                    Button(L("alert_accept")) { enableCustomSubtype = false }
                }

                if enableCustomSubtype {
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
                Toggle(L("mg_aod"), isOn: store.mgByteBinding(key: MGKey.AOD))
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
                
                // Bật AI
                Toggle(isOn: bindingForAppleIntelligence()) {
                    Text(L("mg_apple_intelligence"))
                }
                .disabled(Utils.requiresVersion(18))
                
                // AI Sub-menu (Chỉ hiện khi AI được bật)
                if store.isEnabled(MGKey.appIntellAllKeys) {
                    Group {
                        Toggle("On-device Siri", isOn: bindingForMGKey(key: "O/7gbXWA5X2IRPVtDRU+bw"))
                        Toggle("Audio Intelligence", isOn: bindingForMGKey(key: "rb2tKZxlj0Gm2tBmUQSLqQ"))
                        Toggle("Personal Translator", isOn: bindingForMGKey(key: "M1n2sAqf33NAOgZRGxQYBA"))
                        Toggle("Clean Up in Photos", isOn: bindingForMGKey(key: "XNCjqOupLM/S8fNyxRNQTA"))
                        Toggle("Handwriting Synthesis", isOn: bindingForMGKey(key: "YgYIIViDt1kgzyIsIV61vA"))
                        Toggle("Always-Listening \"Hey Siri\"", isOn: bindingForMGKey(key: "U+73bmG4kBGj6kpreQXUTQ"))
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
                Button(role: .destructive, action: resetOriginal) {
                    Label(L("mg_revert_tweaks"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle(L("tool_mobile_gestalt"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("alert_message_title"), isPresented: $showErrorAlert) {
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
        .onChange(of: enableModelName) { enabled in if enabled { applyModelName() } else { removeModelName() } }
        .onChange(of: modelName) { _ in if enableModelName && !modelName.isEmpty { applyModelName() } }
        .onChange(of: enableCustomSubtype) { enabled in
            if enabled { dynamicIslandType = -1; applyCustomSubtype() }
        }
        .onChange(of: customSubtypeValue) { _ in if enableCustomSubtype { applyCustomSubtype() } }
    }

    // MARK: - Helper Functions
    private func bindingForMGKey(key: String) -> Binding<Bool> {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return .constant(false) }
        return Binding(
            get: { (cacheExtra[key] as? NSNumber)?.boolValue ?? false },
            set: { enabled in
                if enabled { cacheExtra[key] = 1 } else { cacheExtra.removeObject(forKey: key) }
                store.objectWillChange.send()
            }
        )
    }

    private func loadData() {
        let liveURL = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
        _ = wq.grantAccess(path: liveURL.deletingLastPathComponent().path)
        
        if let liveData = try? Data(contentsOf: liveURL),
           let liveDict = try? PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary {
            store.mgCurrentDict = liveDict
            self.mobileGestalt = liveDict
            try? liveData.write(to: modMGURL)
        } else {
            store.loadFromPlist(url: modMGURL)
            mobileGestalt = store.mgCurrentDict
        }
        hydrateFromDict()
    }

    private func hydrateFromDict() {
        dynamicIslandType = 0
        enableCustomSubtype = false
        customSubtypeValue = ""
        enableModelName = false
        modelName = ""
        productType = MobileGestaltView.machineName()

        if let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary {
            productType = cacheExtra[MGKey.prodType] as? String ?? productType
            
            let sysconfig = cacheExtra[MGKey.regionSysconfig] as? String ?? ""
            let regionCode = cacheExtra[MGKey.regionCode] as? String ?? ""
            
            if let preset = regionPresets.first(where: { $0.suffix == sysconfig && $0.id == regionCode }) {
                self.selectedRegionCode = preset.id
                self.regionCustomSuffix = nil
            } else {
                self.selectedRegionCode = "CUSTOM"
                self.regionCustomSuffix = sysconfig.isEmpty ? "\(regionCode) - Custom" : sysconfig
            }
            
            if let artwork = cacheExtra[MGKey.artwork] as? NSDictionary, let subtype = artwork["ArtworkDeviceSubType"] as? Int {
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
            if let artwork = cacheExtra[MGKey.artwork] as? NSDictionary, let name = artwork["ArtworkDeviceProductDescription"] as? String, !name.isEmpty {
                enableModelName = true
                modelName = name
            }
        }
    }

    private func applyCustomSubtype() {
        if let val = Int(customSubtypeValue) {
            if let ce = mobileGestalt["CacheExtra"] as? NSMutableDictionary {
                let dict = (ce[MGKey.artwork] as? NSMutableDictionary) ?? NSMutableDictionary()
                dict["ArtworkDeviceSubType"] = val
                ce[MGKey.artwork] = dict
            }
            if let ce = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary {
                let dict = (ce[MGKey.artwork] as? NSMutableDictionary) ?? NSMutableDictionary()
                dict["ArtworkDeviceSubType"] = val
                ce[MGKey.artwork] = dict
            }
            store.objectWillChange.send()
        }
    }

    private func saveChanges() {
        Task {
            do {
                if let ce = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary {
                    
                    // BLOCK 1: SPOOF AI
                    let targetProductType = productType
                    let isOriginal = (targetProductType == ogMachineName)
                    
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
                    
                    if !isOriginal, let info = spoofMap[targetProductType] {
                        ce[MGKey.prodType] = targetProductType
                        ce["oYicEKzVTz4/CxxE05pEgQ"] = info.hw
                        ce["5pYKlGnYYBzGvAlIU8RjEQ"] = info.cpu
                        ce["97JDvERpVwO+GHtthIh7hA"] = info.reg
                        
                        ce["A62OafQ85EJAiiqKn4agtg"] = 1
                        ce["a3n5T9sFtlyQ74NEp9ESxg"] = 2
                        ce["XNCjqOupLM/S8fNyxRNQTA"] = 1
                        ce["YgYIIViDt1kgzyIsIV61vA"] = 1
                        ce["h63QSdBCiT/z0WU6rdQv6Q"] = "LL"
                        ce["yK+xavymRGZ3xWc1tb8XDg"] = "LL/A"
                        
                        ce.removeObject(forKey: "EqrsVvjcYDdxHBiQmGhAWw")
                        ce.removeObject(forKey: "LBJfwOEzExRxzlAnSuI7eg")
                        ce.removeObject(forKey: "waGD2UTpntjbDXD1r3oALQ")
                        
                        self.selectedRegionCode = "LL"
                    } else if isOriginal {
                        if let ogCE = NSDictionary(contentsOf: MGURL.savedGestaltURL)?["CacheExtra"] as? NSDictionary {
                            for key in ["h9jDsbgj7xIVeIQ8S3/X3Q", "oYicEKzVTz4/CxxE05pEgQ", "5pYKlGnYYBzGvAlIU8RjEQ", "97JDvERpVwO+GHtthIh7hA"] {
                                if let val = ogCE[key] { ce[key] = val } else { ce.removeObject(forKey: key) }
                            }
                        }
                    }
                    
                    if !isOriginal {
                        if case .success((let layout, var data)) = MGCacheDataCoordinator.shared.resolveValidated(for: store.mgCurrentDict) {
                            for key in MGKey.appIntellAllKeys {
                                if let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                                    data[slotIdx * 8] = 1
                                }
                            }
                            data[layout.greenTeaOffset] = 0
                            data[layout.notGreenTeaOffset] = 1
                            
                            let testDict = NSMutableDictionary(dictionary: store.mgCurrentDict)
                            testDict["CacheData"] = data
                            if case .success = layout.validatePlist(testDict) {
                                store.mgCurrentDict["CacheData"] = data
                            }
                        }
                    }
                    
                    // BLOCK 2: DYNAMIC ISLAND
                    let art = (ce[MGKey.artwork] as? NSMutableDictionary) ?? NSMutableDictionary()
                    
                    if dynamicIslandType == 0 && !enableCustomSubtype {
                        art.removeObject(forKey: "ArtworkDeviceSubType")
                        ce.removeObject(forKey: "YlEtTtHlNesRBMal1CqRaA")
                    } else if dynamicIslandType > 0 {
                        let subtypes = [0, 2436, 2556, 2796, 2976, 2622, 2868, 2736, 2662]
                        art["ArtworkDeviceSubType"] = subtypes[dynamicIslandType]
                        ce["YlEtTtHlNesRBMal1CqRaA"] = 1
                    } else if enableCustomSubtype, let val = Int(customSubtypeValue) {
                        art["ArtworkDeviceSubType"] = val
                        ce["YlEtTtHlNesRBMal1CqRaA"] = 1
                    }
                    
                    if enableModelName {
                        art["ArtworkDeviceProductDescription"] = modelName
                    } else {
                        art.removeObject(forKey: "ArtworkDeviceProductDescription")
                    }
                    ce[MGKey.artwork] = art
                    
                    if selectedRegionCode != "CUSTOM", let preset = regionPresets.first(where: { $0.id == selectedRegionCode }) {
                        ce[MGKey.regionCode] = preset.id
                        ce[MGKey.regionSysconfig] = preset.suffix
                        ce[MGKey.regionInfo] = preset.suffix
                    }
                }
                
                try await MobileGestaltApplyTask.applyGestalt(store: store) { log in
                    print(log)
                }
                
                let liveURL = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
                let expectedData = try Data(contentsOf: liveURL)
                try expectedData.write(to: modMGURL)
                
                await MainActor.run {
                    store.loadFromPlist(url: modMGURL)
                    self.mobileGestalt = store.mgCurrentDict
                    hydrateFromDict()
                    showApplyTab = true
                    lastError = L("mg_save_success_message")
                    showErrorAlert = true
                }
            } catch {
                await MainActor.run {
                    lastError = L("mg_save_failed") + " \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }

    private func resetOriginal() {
        Task {
            do {
                try await MobileGestaltApplyTask.restoreGestalt { log in
                    print(log)
                }
                
                try? FileManager.default.removeItem(at: modMGURL)
                
                await MainActor.run {
                    store.mgCurrentDict = NSMutableDictionary()
                    self.mobileGestalt = store.mgCurrentDict
                    hydrateFromDict()
                    showApplyTab = true
                    lastError = L("mg_revert_success_message")
                    showErrorAlert = true
                }
            } catch {
                await MainActor.run {
                    lastError = L("mg_revert_failed") + " \(error.localizedDescription)"
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
        
        do {
            if FileManager.default.fileExists(atPath: liveURL.path) {
                try? FileManager.default.removeItem(at: modMGURL)
                try FileManager.default.copyItem(at: liveURL, to: modMGURL)
            } else if !FileManager.default.fileExists(atPath: modMGURL.path) {
                try FileManager.default.copyItem(at: origMGURL, to: modMGURL)
            }
            chmod(modMGURL.path, 0o644)
            
            if !FileManager.default.fileExists(atPath: origMGURL.path) {
                FileManager.default.createFile(atPath: origMGURL.path, contents: nil, attributes: nil)
            }
            chmod(origMGURL.path, 0o644)
            
            if let mutable = GestaltStore.loadMutableDict(from: modMGURL) {
                _mobileGestalt = State(initialValue: mutable)
            } else {
                _mobileGestalt = State(initialValue: [:])
                _initError = State(initialValue: "Failed to load MobileGestalt")
            }
        } catch {
            _mobileGestalt = State(initialValue: [:])
            _initError = State(initialValue: "Failed to copy MobileGestalt: \(error)")
            taskRunning = true
        }
    }

    func bindingForAppleIntelligence() -> Binding<Bool> {
        return store.mgKeyBinding(MGKey.appIntellAllKeys)
    }

    func bindingForMGKeys<T: Equatable>(_ keys: [String], type: T.Type = Int.self, defaultValue: T? = 0, enableValue: T? = 1) -> Binding<Bool> {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return .constant(false) }
        return Binding(
            get: {
                guard let value = cacheExtra[keys.first!] as? T, let ev = enableValue else { return false }
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

    func saveProductType() {
        if let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary {
            cacheExtra[MGKey.prodType] = productType
        }
    }

    func applyModelName() {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return }
        let dict = (cacheExtra[MGKey.artwork] as? NSMutableDictionary) ?? NSMutableDictionary()
        dict["ArtworkDeviceProductDescription"] = modelName
        cacheExtra[MGKey.artwork] = dict
        store.cacheExtra[MGKey.artwork] = dict
        store.objectWillChange.send()
    }

    func removeModelName() {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return }
        if let g = cacheExtra[MGKey.artwork] as? NSMutableDictionary {
            g.removeObject(forKey: "ArtworkDeviceProductDescription")
        }
        if let s = store.cacheExtra[MGKey.artwork] as? NSMutableDictionary {
            s.removeObject(forKey: "ArtworkDeviceProductDescription")
        }
    }
}