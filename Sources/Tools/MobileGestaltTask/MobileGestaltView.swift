import SwiftUI
import UniformTypeIdentifiers

struct MobileGestaltView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    let origMGURL, modMGURL, featFlagsURL, resolutionURL: URL
    @Environment(\.scenePhase) var scenePhase
    @ObservedObject var toolStore: ToolStore
    @StateObject private var store = GestaltStore.shared
    
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false

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
    @State var enableModelName: Bool = false
    @State var modelName: String = ""

    var body: some View {
        Form {
            enableSection
            deviceSubtypeSection
            hardwareFeaturesSection
            displayAndUISection
            systemFeaturesSection
            advancedSection
            saveResetSection
        }
        .headerProminence(.increased)
        .alert("Message", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(lastError ?? "???")
        }
        .navigationTitle(L("tool_mobile_gestalt"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.loadFromPlist(url: modMGURL)
            
            if initError != nil {
                lastError = initError
                initError = nil
                showErrorAlert.toggle()
                return
            }

            if let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary {
                productType = cacheExtra[MGKey.prodType] as? String ?? productType

                if let diValue = cacheExtra[MGKey.artwork] as? NSDictionary,
                   let subtype = diValue["ArtworkDeviceSubType"] as? Int {
                    switch subtype {
                    case 2436: dynamicIslandType = 1
                    case 2556: dynamicIslandType = 2
                    case 2796: dynamicIslandType = 3
                    case 2976: dynamicIslandType = 4
                    case 2622: dynamicIslandType = 5
                    case 2868: dynamicIslandType = 6
                    case 2736: dynamicIslandType = 7
                    default: dynamicIslandType = 0
                    }
                }

                if let diValue = cacheExtra[MGKey.artwork] as? NSDictionary,
                   let modelNameValue = diValue["ArtworkDeviceProductDescription"] as? String,
                   !modelNameValue.isEmpty {
                    enableModelName = true
                    modelName = modelNameValue
                }
            }
        }
        .onChange(of: enableModelName) { enabled in
            if enabled { applyModelName() } else { removeModelName() }
        }
        .onChange(of: modelName) { _ in
            if enableModelName && !modelName.isEmpty { applyModelName() }
        }
        .onChange(of: scenePhase) { _ in
            if scenePhase == .inactive {
                Utils.bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                    UIApplication.shared.endBackgroundTask(Utils.bgTask)
                    Utils.bgTask = .invalid
                })
            } else if scenePhase == .active {
                if Utils.bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(Utils.bgTask)
                    Utils.bgTask = .invalid
                }
            }
        }
    }

    // MARK: - Body Sections

    @ViewBuilder
    private var enableSection: some View {
        Section(header: Text(L("tool_mobile_gestalt"))) {
            Toggle(L("enable_tweak"), isOn: $toolStore.replaceMobileGestaltEnabled)
                .onChange(of: toolStore.replaceMobileGestaltEnabled) { isEnabled in
                    if !isEnabled { showApplyTab = false }
                }
        }
    }

    @ViewBuilder
    private var deviceSubtypeSection: some View {
        Section(header: Text(L("section_device_subtype"))) {
            Picker(L("mg_device_subtype_preset"), selection: $dynamicIslandType) {
                Text(L("mg_subtype_none")).tag(0)
                Text(L("mg_subtype_2436")).tag(1)
                Text(L("mg_subtype_2796")).tag(3)
                Text(L("mg_subtype_2976")).tag(4)
                Text(L("mg_subtype_2622")).tag(5)
                Text(L("mg_subtype_2868")).tag(6)
                Text(L("mg_subtype_2736")).tag(7)
            }
            .pickerStyle(.menu)
            .onChange(of: dynamicIslandType) { newValue in
                _ = store.applyDynamicIsland(type: newValue)
            }

            Toggle(L("mg_change_model_name"), isOn: $enableModelName)

            if enableModelName {
                TextField(L("mg_model_name_placeholder"), text: $modelName)
            }
        }
    }

    @ViewBuilder
    private var hardwareFeaturesSection: some View {
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
    }

    @ViewBuilder
    private var displayAndUISection: some View {
        Section(header: Text(L("section_display_and_ui"))) {
            // ❌ Đã bỏ Disable Parallax
            Toggle(L("mg_stage_manager"), isOn: store.mgByteBinding(key: MGKey.stageMgr))
            Toggle(L("mg_aod"), isOn: store.mgByteBinding(key: MGKey.AOD))
                .disabled(Utils.requiresVersion(18))
            Toggle(L("mg_aod_vibrancy"), isOn: store.mgByteBinding(key: MGKey.AODVibrancy))
                .disabled(Utils.requiresVersion(18))
            
            Toggle(isOn: store.mgTrollPadBinding()) {
                Text("Become iPadOS")
            }
        }
    }

    @ViewBuilder
    private var systemFeaturesSection: some View {
        Section(header: Text(L("section_system_features"))) {
            Toggle(L("mg_install_ipad_apps"), isOn: bindingForMGKeys(["9MZ5AdH43csAUajl/dU+IQ"], type: [Int].self, defaultValue: [1], enableValue: [1, 2]))
            Toggle(L("mg_disable_region"), isOn: store.mgRegionRestrictionsBinding())
            Toggle(L("mg_apple_pencil"), isOn: store.mgByteBinding(key: MGKey.appPencil))
            Toggle(L("mg_action_button"), isOn: store.mgByteBinding(key: MGKey.actButton))
                .disabled(Utils.requiresVersion(17))
            Toggle(L("mg_crash_detection"), isOn: store.mgByteBinding(key: MGKey.crashDet))
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        Section(header: Text(L("section_internal_features"))) {
            Toggle(L("mg_internal_storage"), isOn: store.mgByteBinding(key: MGKey.intBuild))
            
            // ✅ Internal Stuff giờ hoạt động độc lập, không cần Metal HUD
            Toggle(L("mg_internal_stuff"), isOn: bindingForInternalStuff())
            
            Toggle(L("mg_security_research"), isOn: store.mgByteBinding(key: MGKey.srd))
            
            // ❌ Đã bỏ Metal HUD (mg_metal_hud)
            
            Toggle(L("mg_apple_intelligence"), isOn: bindingForAppleIntelligence())
                .disabled(Utils.requiresVersion(18))
            Picker(L("mg_device_model"), selection: $productType) {
                Text(L("mg_device_model_unchanged")).tag(MobileGestaltView.machineName())
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Text("iPad Pro 11 inch 5th Gen").tag("iPad16,3")
                } else {
                    Text("iPhone 15 Pro Max").tag("iPhone16,2")
                    Text("iPhone 16 Pro Max").tag("iPhone17,2")
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var saveResetSection: some View {
        Section(header: Text(L("section_save_reset"))) {
            Button(action: {
                do {
                    let onDevicePath = MobileGestaltApplyTask.onDeviceMGPath
                    let onDeviceURL = URL(fileURLWithPath: onDevicePath)
                    if let originalData = try? Data(contentsOf: onDeviceURL) {
                        try? MobileGestaltBackupManager.shared.ensureBackup(from: originalData)
                    }

                    saveProductType()
                    
                    if let storeCacheExtra = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary,
                       let localCacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary {
                        for (key, value) in storeCacheExtra {
                            localCacheExtra[key as! String] = value
                        }
                    }
                    if let storeCacheData = store.mgCurrentDict["CacheData"] {
                        mobileGestalt["CacheData"] = storeCacheData
                    }

                    try mobileGestalt.write(to: modMGURL)
                    store.loadFromPlist(url: modMGURL)

                    showApplyTab = true 

                    lastError = MobileGestaltBackupManager.shared.hasBackup 
                        ? "Đã lưu + tạo backup pristine. Tab Apply đã được mở ở dưới."
                        : "Đã lưu. Tab Apply đã được mở ở dưới."
                    showErrorAlert = true
                } catch {
                    lastError = "Save failed: \(error)"
                    showErrorAlert = true
                }
            }) {
                Label(L("mg_save_settings"), systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive, action: {
                do {
                    let pristineData = try MobileGestaltBackupManager.shared.restoreData()
                    try pristineData.write(to: modMGURL)

                    mobileGestalt = try NSMutableDictionary(contentsOf: modMGURL, error: ())
                    store.loadFromPlist(url: modMGURL)
                    toolStore.replaceMobileGestaltEnabled = true
                    showApplyTab = true

                    lastError = "Đã reset về pristine backup. Tab Apply đã được mở — bấm Apply để ghi lại vào hệ thống."
                    showErrorAlert = true
                } catch {
                    lastError = "Reset failed: \(error)"
                    showErrorAlert = true
                }
            }) {
                Label("Reset Original", systemImage: "arrow.counterclockwise")
            }
        }
    }

    init(toolStore: ToolStore) {
        self.toolStore = toolStore

        let documentsDirectory = URL.documentsDirectory
        featFlagsURL = documentsDirectory.appendingPathComponent("FeatureFlags.plist", conformingTo: .data)
        origMGURL = documentsDirectory.appendingPathComponent("OriginalMobileGestalt.plist", conformingTo: .data)
        modMGURL = documentsDirectory.appendingPathComponent("ModifiedMobileGestalt.plist", conformingTo: .data)
        resolutionURL = documentsDirectory.appendingPathComponent("Resolution.plist", conformingTo: .data)

        do {
            if !FileManager.default.fileExists(atPath: origMGURL.path) {
                let url = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
                try FileManager.default.copyItem(at: url, to: origMGURL)
            }
            chmod(origMGURL.path, 0o644)

            if !FileManager.default.fileExists(atPath: modMGURL.path) {
                try FileManager.default.copyItem(at: origMGURL, to: modMGURL)
            }
            chmod(modMGURL.path, 0o644)

            _mobileGestalt = State(initialValue: try NSMutableDictionary(contentsOf: modMGURL, error: ()))
        } catch {
            _mobileGestalt = State(initialValue: [:])
            _initError = State(initialValue: "Failed to copy MobileGestalt: \(error)")
            taskRunning = true
        }
    }

    // MARK: - Bindings

    func bindingForAppleIntelligence() -> Binding<Bool> {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else {
            return State(initialValue: false).projectedValue
        }
        let key = MGKey.appIntell
        return Binding(
            get: {
                if let value = cacheExtra[key] as? Int { return value == 1 }
                return false
            },
            set: { enabled in
                if enabled {
                    eligibilityData = try! Data(contentsOf: Bundle.main.url(forResource: "eligibility", withExtension: "plist")!)
                    featureFlagsData = try! Data(contentsOf: Bundle.main.url(forResource: "FeatureFlags_Global", withExtension: "plist")!)
                    cacheExtra[key] = 1
                } else {
                    featureFlagsData = try! PropertyListSerialization.data(fromPropertyList: [:], format: .xml, options: 0)
                    eligibilityData = featureFlagsData
                    cacheExtra.removeObject(forKey: key)
                }
            }
        )
    }

    // ✅ Internal Stuff giờ độc lập: chỉ sửa byte trong CacheData, không liên quan Metal HUD
    func bindingForInternalStuff() -> Binding<Bool> {
        guard let cacheData = mobileGestalt["CacheData"] as? NSMutableData else {
            return State(initialValue: false).projectedValue
        }
        
        guard let off_appleInternalInstall = store.FindCacheDataOffset(MGKey.intInstall),
              let off_InternalBuild = store.FindCacheDataOffset(MGKey.intBuild) else {
            return State(initialValue: false).projectedValue
        }

        return Binding(
            get: { cacheData.bytes.load(fromByteOffset: off_appleInternalInstall, as: Int.self) == 1 },
            set: { enabled in
                cacheData.mutableBytes.storeBytes(of: enabled ? 1 : 0, toByteOffset: off_appleInternalInstall, as: Int.self)
                cacheData.mutableBytes.storeBytes(of: enabled ? 1 : 0, toByteOffset: off_InternalBuild, as: Int.self)
            }
        )
    }

    func bindingForMGKeys<T: Equatable>(_ keys: [String], type: T.Type = Int.self, defaultValue: T? = 0, enableValue: T? = 1) -> Binding<Bool> {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else {
            return State(initialValue: false).projectedValue
        }
        return Binding(
            get: {
                if let value = cacheExtra[keys.first!] as? T, let ev = enableValue {
                    return value == ev
                }
                return false
            },
            set: { enabled in
                for key in keys {
                    if enabled { cacheExtra[key] = enableValue }
                    else { cacheExtra.removeObject(forKey: key) }
                }
            }
        )
    }

    // MARK: - Helpers

    static func machineName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    func saveProductType() {
        let cacheExtra = mobileGestalt["CacheExtra"] as! NSMutableDictionary
        cacheExtra[MGKey.prodType] = productType
    }

    func applyModelName() {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return }
        var gestaltDict: NSMutableDictionary
        if let existing = cacheExtra[MGKey.artwork] as? NSMutableDictionary {
            gestaltDict = existing
        } else {
            gestaltDict = NSMutableDictionary()
            cacheExtra[MGKey.artwork] = gestaltDict
        }
        gestaltDict["ArtworkDeviceProductDescription"] = modelName
    }

    func removeModelName() {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return }
        if let gestaltDict = cacheExtra[MGKey.artwork] as? NSMutableDictionary {
            gestaltDict.removeObject(forKey: "ArtworkDeviceProductDescription")
        }
    }
}