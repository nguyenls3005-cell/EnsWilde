//
//  GestaltStore.swift
//  EnsWilde (Fixed Subtypes & Removed Blocks)
//

import SwiftUI
import Combine
import CoreFoundation

// ... (GIỮ NGUYÊN PHẦN enum MGURL, MGRegionUnlockMode, MGMsg, MGKey... như file của bạn) ...

final class GestaltStore: ObservableObject {
    static let shared = GestaltStore()
    
    @Published var mgCurrentDict = NSMutableDictionary()
    var cacheExtra: NSMutableDictionary {
        return mgCurrentDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
    }
    
    init() {}
    
    // MARK: helpers
    func originalCacheExtraValue(forKey key: String) -> Any? {
        guard let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL),
              let ogCacheExtra = ogDict["CacheExtra"] as? NSDictionary else {
            return nil
        }
        return ogCacheExtra[key]
    }
    
    func restoreOrRemoveKey(_ key: String) {
        if let ogVal = originalCacheExtraValue(forKey: key) {
            self.cacheExtra[key] = ogVal
        } else {
            self.cacheExtra.removeObject(forKey: key)
        }
    }

    func disableBooleanExtraKey(_ key: String, enableValue: Int = 1) {
        if let ogVal = originalCacheExtraValue(forKey: key) {
            if let ogNum = ogVal as? NSNumber, ogNum.intValue == enableValue {
                self.cacheExtra.removeObject(forKey: key)
            } else {
                self.cacheExtra[key] = ogVal
            }
        } else {
            self.cacheExtra.removeObject(forKey: key)
        }
    }
    
    // MARK: actions
    func mgPullKeys(_ keys: [String], enableValue: Int = 1) {
        for key in keys {
            disableBooleanExtraKey(key, enableValue: enableValue)
        }
    }
    
    func isKeyEnabled(_ key: String, enableValue: Int = 1) -> Bool {
        if let num = self.cacheExtra[key] as? NSNumber, num.intValue == enableValue {
            return true
        }
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict),
           let slotIdx = layout.slotIndex(forKey: key),
           layout.validateSingleBooleanSlot(slotIdx, in: data),
           data[slotIdx * 8] == 1 {
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
            if !origVal {
                return true
            }
        }
        return false
    }

    func isEnabled(_ keys: [String], enableValue: Int = 1) -> Bool {
        guard !keys.isEmpty else { return false }
        return keys.allSatisfy { self.isKeyEnabled($0, enableValue: enableValue) }
    }
    
    func strVal(forKey key: String) -> String {
        let value = self.cacheExtra[key] as? String ?? ""
        return value
    }
    
    func mgKeyBinding(_ keys: [String], defaultValue: Int = 0, enableValue: Int = 1) -> Binding<Bool> {
        return Binding(get: {
            guard !keys.isEmpty else { return false }
            return keys.allSatisfy { self.isKeyEnabled($0, enableValue: enableValue) }
        }, set: { enabled in
            self.objectWillChange.send()
            for key in keys {
                if enabled {
                    self.cacheExtra[key] = enableValue
                } else {
                    self.disableBooleanExtraKey(key, enableValue: enableValue)
                }
            }
            if case .success((let layout, var data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                var touchedSlot = false
                for key in keys {
                    if let slotIdx = layout.featureSlotIndices[key],
                       layout.validateSingleBooleanSlot(slotIdx, in: data) {
                        if enabled {
                            data[slotIdx * 8] = (enableValue != 0) ? 1 : 0
                        } else {
                            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
                            data[slotIdx * 8] = origVal ? 1 : 0
                        }
                        touchedSlot = true
                    }
                }
                if touchedSlot {
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    testDict["CacheData"] = data
                    if case .success = layout.validatePlist(testDict) {
                        self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        })
    }
    
    // ĐÃ XÓA BỎ POPUP CHẶN iPADOS
    func mgTrollPadBinding() -> Binding<Bool> {
        return Binding(get: {
            guard let firstKey = MGKey.ipadosCacheEx.first else { return false }
            return (self.cacheExtra[firstKey] as? NSNumber)?.intValue == 1
        }, set: { enabled in
            self.objectWillChange.send()
            for key in MGKey.ipadosCacheEx {
                if enabled {
                    self.cacheExtra[key] = 1
                } else {
                    self.disableBooleanExtraKey(key, enableValue: 1)
                }
            }
        })
    }

    // ... (Các hàm Region, Apple Intelligence giữ nguyên) ...

    // SỬA LẠI HÀM NÀY ĐỂ FIX LỖI NHẢY VỀ 14 PRO
    func applyDynamicIsland(type: Int, customValue: Int? = nil) -> Bool {
        // Đã thêm đúng mã của các dòng máy mới
        let subtypes = [
            0,      // 0: Tắt
            2436,   // 1: iPhone X
            2556,   // 2: iPhone 14 Pro / 15 Pro
            2796,   // 3: iPhone 14 Pro Max / 15 Pro Max
            2622,   // 4: iPhone 16 Pro / 17 Pro
            2868,   // 5: iPhone 16 Pro Max / 17 Pro Max
            2736,   // 6: iPhone Air
            2670    // 7: iPhone 18 Pro Max (MỚI THÊM)
        ]
        
        guard let ce = mgCurrentDict["CacheExtra"] as? NSMutableDictionary else { return false }
        
        if type == 0 {
            (ce[MGKey.artwork] as? NSMutableDictionary)?.removeObject(forKey: "ArtworkDeviceSubType")
        } else if type > 0 && type < subtypes.count {
            let art = (ce[MGKey.artwork] as? NSMutableDictionary) ?? NSMutableDictionary()
            art["ArtworkDeviceSubType"] = subtypes[type]
            ce[MGKey.artwork] = art
        }
        objectWillChange.send()
        return true
    }
}