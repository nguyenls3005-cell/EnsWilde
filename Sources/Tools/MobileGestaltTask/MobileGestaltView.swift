//
//  MobileGestaltView.swift
//  EnsWilde
//
//  Tách biệt hoàn toàn Spoof (AI Model) và Dynamic Island (Device Subtype) theo logic Gester
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
    
    // --- BIẾN CHO DYNAMIC ISLAND (CHỈ DÙNG KHI CHỌN SUBTYPE) ---
    @State var dynamicIslandType: Int = 0
    @State var enableCustomSubtype: Bool = false
    @State var customSubtypeValue: String = ""
    
    // --- BIẾN CHO SPOOF AI MODEL (CHỈ SPOOF) ---
    @State var aiModelSelection: Int = 0
    
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

    // --- CÁC KEY CHUẨN ---
    let kArtKey = "oPeik/9e8lQWMszEjbPzng"
    let kIslandKey = "YlEtTtHlNesRBMal1CqRaA"
    let kAIKey = "A62OafQ85EJAiiqKn4agtg"
    let kProductTypeKey = "h9jDsbgj7xIVeIQ8S3/X3Q"
    let kHardwareKey = "oYicEKzVTz4/CxxE05pEgQ"
    let kCPUKey = "5pYKlGnYYBzGvAlIU8RjEQ"
    let kSiriRegionKey = "h63QSdBCiT/z0WU6rdQv6Q"
    let kSiriRegionCodeKey = "yK+xavymRGZ3xWc1tb8XDg"
    let kRegulatoryKey = "97JDvERpVwO+GHtthIh7hA"
    
    // --- DANH SÁCH MODEL AI SPOOF (FULL TỪ 15 PRO -> 18 SERIES & DUO) ---
    let aiModelOptions: [[String: String]] = [
        ["title": "Original", "product": "", "hw": "", "cpu": "", "reg": ""],
        ["title": "iPhone 15 Pro", "product": "iPhone16,1", "hw": "D83AP", "cpu": "t8130", "reg": "A2848"],
        ["title": "iPhone 15 Pro Max", "product": "iPhone16,2", "hw": "D84AP", "cpu": "t8130", "reg": "A2849"],
        
        ["title": "iPhone 16", "product": "iPhone17,3", "hw": "D47AP", "cpu": "t8140", "reg": "A3081"],
        ["title": "iPhone 16 Plus", "product": "iPhone17,4", "hw": "D48AP", "cpu": "t8140", "reg": "A3082"],
        ["title": "iPhone 16 Pro", "product": "iPhone17,1", "hw": "D93AP", "cpu": "t8140", "reg": "A3083"],
        ["title": "iPhone 16 Pro Max", "product": "iPhone17,2", "hw": "D94AP", "cpu": "t8140", "reg": "A3084"],
        ["title": "iPhone 16e", "product": "iPhone17,5", "hw": "V59AP", "cpu": "t8140", "reg": "A3212"],
        
        ["title": "iPhone 17", "product": "iPhone18,3", "hw": "V57AP", "cpu": "t8150", "reg": "A3258"],
        ["title": "iPhone 17 Pro", "product": "iPhone18,1", "hw": "V53AP", "cpu": "t8150", "reg": "A3256"],
        ["title": "iPhone 17 Pro Max", "product": "iPhone18,2", "hw": "V54AP", "cpu": "t8150", "reg": "A3257"],
        ["title": "iPhone Air", "product": "iPhone18,4", "hw": "D23AP", "cpu": "t8150", "reg": "A3260"],
        ["title": "iPhone 17e", "product": "iPhone18,5", "hw": "V59AP", "cpu": "t8150", "reg": "A3575"],
        
        ["title": "iPhone 18 Pro", "product": "iPhone19,2", "hw": "V63AP", "cpu": "t8160", "reg": "A3472"],
        ["title": "iPhone 18 Pro Max (US)", "product": "iPhone19,3", "hw": "V64AP", "cpu": "t8160", "reg": "A3473"],
        ["title": "iPhone 18 Pro Max (Global)", "product": "iPhone19,7", "hw": "V64sAP", "cpu": "t8160", "reg": "A3717"],
        ["title": "iPhone Duo", "product": "iPhone19,4", "hw": "V68AP", "cpu": "t8160", "reg": "A3447"]
    ]
    
    // --- DANH SÁCH SUBTYPE DYNAMIC ISLAND ---
    let islandOptions: [[String: Any]] = [
        ["title": "Original", "value": 0],
        ["title": "2436 (iPhone X / SE)", "value": 2436],
        ["title": "2556 (iPhone 14 Pro / 15 Pro / 16 / 17)", "value": 2556],
        ["title": "2796 (iPhone 14 Pro Max / 16 Plus)", "value": 2796],
        ["title": "2976 (iPhone 15 Pro Max / 16 Plus)", "value": 2976],
        ["title": "2622 (iPhone 16 Pro / 17 Pro)", "value": 2622],
        ["title": "2868 (iPhone 16 Pro Max / 17 Pro Max)", "value": 2868],
        ["title": "2736 (iPhone Air)", "value": 2736],
        ["title": "2662 (iPhone 18 Pro / 18 Pro Max)", "value": 2662],
        ["title": "Custom Subtype", "value": -1]
    ]

    var body: some View {
        Form {
            Section(header: Text(L("tool_mobile_gestalt"))) {
                Toggle(L("enable_tweak"), isOn: $toolStore.replaceMobileGestaltEnabled)
                    .onChange(of: toolStore.replaceMobileGestaltEnabled) { isEnabled in
                        if !isEnabled { showApplyTab = false }
                    }
            }
            
            // Phần Dynamic Island (CHỈ KHI CHỌN SUBTYPE MỚI GHI ĐÈ)
            Section(header: Text("Dynamic Island")) {
                Picker(selection: $dynamicIslandType) {
                    ForEach(0..<islandOptions.count, id: \.self) { index in
                        Text(islandOptions[index]["title"] as! String).tag(islandOptions[index]["value"] as! Int)
                    }
                } label: {
                    Text("Device Subtype")
                }
                .pickerStyle(.menu)
                .onChange(of: dynamicIslandType) { newValue in
                    if newValue == -1 { enableCustomSubtype = true }
                    else { enableCustomSubtype = false }
                }

                if enableCustomSubtype {
                    TextField("Enter ArtworkDeviceSubType (e.g. 2xxx)", text: $customSubtypeValue)
                        .keyboardType(.numberPad)
                }
                
                if dynamicIslandType != 0 || enableCustomSubtype {
                    Text("Only this selection writes ArtworkDeviceSubType and enables Dynamic Island.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Section(header: Text("Advanced")) {
                // Phần Spoof AI (CHỈ SPOOF, KHÔNG ĐỤNG SUBTYPE)
                Picker(selection: $aiModelSelection) {
                    ForEach(0..<aiModelOptions.count, id: \.self) { index in
                        Text(aiModelOptions[index]["title"]!).tag(index)
                    }
                } label: {
                    Text("AI device spoof")
                }
                .pickerStyle(.menu)
                
                if aiModelSelection != 0 {
                    Text("Spoofs ProductType, HardwareModel, CPUModel, RegulatoryModel. Does NOT change ArtworkDeviceSubType.")
                        .font(.caption).foregroundColor(.red)
                }

                // Region (giữ nguyên)
                Picker(selection: $selectedRegionCode) {
                    ForEach(regionPresets) { preset in
                        Text("\(preset.suffix) - \(preset.name)").tag(preset.id)
                    }
                    if selectedRegionCode == "CUSTOM" {
                        Text("\(regionCustomSuffix ?? "Custom")").tag("CUSTOM")
                    }
                } label: {
                    Text("Region")
                }
                .pickerStyle(.menu)
                .onChange(of: selectedRegionCode) { newVal in
                    if newVal != "CUSTOM" { regionCustomSuffix = nil }
                }
            }

            Section(header: Text(L("section_save_reset"))) {
                Button(action: saveChanges) {
                    Label(L("mg_save_settings"), systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive, action: resetOriginal) {
                    Label("Revert Tweaks", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle(L("tool_mobile_gestalt"))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Message", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(lastError ?? "???")
        }
        .onAppear {
            loadData()
        }
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
        if let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary {
            // AI Model selection
            let currentProd = cacheExtra[kProductTypeKey] as? String ?? ""
            if let idx = aiModelOptions.firstIndex(where: { $0["product"] == currentProd }) {
                aiModelSelection = idx
            } else {
                aiModelSelection = 0
            }
            
            // Dynamic Island subtype
            if let artwork = cacheExtra[kArtKey] as? NSDictionary, let subtype = artwork["ArtworkDeviceSubType"] as? Int {
                if let idx = islandOptions.firstIndex(where: { ($0["value"] as? Int) == subtype && subtype != 0 }) {
                    dynamicIslandType = islandOptions[idx]["value"] as! Int
                } else {
                    dynamicIslandType = -1
                    enableCustomSubtype = true
                    customSubtypeValue = "\(subtype)"
                }
            } else {
                dynamicIslandType = 0
            }
            
            // Region
            let sysconfig = cacheExtra[kSiriRegionCodeKey] as? String ?? ""
            let regionCode = cacheExtra[kSiriRegionKey] as? String ?? ""
            
            if let preset = regionPresets.first(where: { $0.suffix == sysconfig && $0.id == regionCode }) {
                self.selectedRegionCode = preset.id
                self.regionCustomSuffix = nil
            } else {
                self.selectedRegionCode = "CUSTOM"
                self.regionCustomSuffix = sysconfig.isEmpty ? "\(regionCode) - Custom" : sysconfig
            }
        }
    }

    private func saveChanges() {
        Task {
            do {
                if let ce = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary {
                    
                    // ===== 1. XỬ LÝ DYNAMIC ISLAND (CHỈ KHI CHỌN SUBTYPE) =====
                    let art = (ce[kArtKey] as? NSMutableDictionary) ?? NSMutableDictionary()
                    var finalSubtype = dynamicIslandType
                    if enableCustomSubtype, let val = Int(customSubtypeValue) {
                        finalSubtype = val
                    }
                    
                    if finalSubtype <= 0 {
                        // Nếu chọn Original -> xóa subtype và tắt cờ island
                        art.removeObject(forKey: "ArtworkDeviceSubType")
                        ce.removeObject(forKey: kIslandKey)
                    } else {
                        // Nếu chọn subtype cụ thể -> ghi đè và bật cờ island
                        art["ArtworkDeviceSubType"] = finalSubtype
                        ce[kIslandKey] = 1
                    }
                    
                    if art.count > 0 { ce[kArtKey] = art }
                    else { ce.removeObject(forKey: kArtKey) }
                    
                    // ===== 2. XỬ LÝ SPOOF AI (CHỈ SPOOF, KHÔNG ĐỤNG SUBTYPE) =====
                    let modelInfo = aiModelOptions[aiModelSelection]
                    let prod = modelInfo["product"]!
                    
                    if prod.isEmpty {
                        // Trả về gốc cho các key spoof
                        if let og = NSDictionary(contentsOf: MGURL.savedGestaltURL)?["CacheExtra"] as? NSDictionary {
                            for key in [kProductTypeKey, kHardwareKey, kCPUKey, kRegulatoryKey] {
                                if let val = og[key] { ce[key] = val } else { ce.removeObject(forKey: key) }
                            }
                        }
                        // Không động vào ArtworkDeviceSubType
                    } else {
                        // Spoof các key model
                        ce[kProductTypeKey] = modelInfo["product"]
                        ce[kHardwareKey] = modelInfo["hw"]
                        ce[kCPUKey] = modelInfo["cpu"]
                        if !(modelInfo["reg"]!).isEmpty {
                            ce[kRegulatoryKey] = modelInfo["reg"]
                        }
                        ce[kAIKey] = 1
                        // Không động vào ArtworkDeviceSubType
                    }
                    
                    // ===== 3. XỬ LÝ REGION =====
                    if selectedRegionCode != "CUSTOM", let preset = regionPresets.first(where: { $0.id == selectedRegionCode }) {
                        ce[kSiriRegionKey] = preset.id
                        ce[kSiriRegionCodeKey] = preset.suffix
                        ce["zHeENZu+wbg7PUprwNwBWg"] = preset.suffix
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
                    lastError = "Saved and applied successfully. Hãy Hard Reboot để iOS nhận cấu hình mới."
                    showErrorAlert = true
                }
            } catch {
                await MainActor.run {
                    lastError = "Save failed: \(error.localizedDescription)"
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
                    lastError = "All tweaks reverted successfully.\n\nPlease go to the SETTINGS tab and tap 'Respring Device' to apply the changes."
                    showErrorAlert = true
                }
            } catch {
                await MainActor.run {
                    lastError = "Revert failed: \(error.localizedDescription)"
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

    static func machineName() -> String {
        var sys = utsname()
        uname(&sys)
        return Mirror(reflecting: sys.machine).children.reduce("") { id, el in
            guard let v = el.value as? Int8, v != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(v)))
        }
    }
}