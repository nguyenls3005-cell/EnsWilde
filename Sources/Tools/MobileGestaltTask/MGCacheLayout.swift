//
//  MGCacheLayout.swift
//  Erosion
//
//  Strict runtime MobileGestalt CacheData descriptor resolver and byte-level validator.
//  Resolves offsets exclusively from the running device's loaded /usr/lib/libMobileGestalt.dylib.
//  Any ambiguity, mismatch, or validation failure strictly blocks modification.
//

import Foundation

struct MGSlotDescriptorInfo: Identifiable, Equatable, Sendable {
    var id: String { "\(slotIndex):\(obfuscatedKey)" }
    let obfuscatedKey: String
    let slotIndex: Int       // -1 for non-cached queries, 0..<slotCount for CacheData slots
    let queryType: UInt32    // 11 = Boolean
    var valueOffset: Int? { slotIndex >= 0 ? slotIndex * 8 : nil }

    func validityOffset(slotCount: Int) -> Int? {
        guard slotIndex >= 0 else { return nil }
        return slotCount * 8 + slotIndex
    }
}

struct MGCacheDataLayout: Codable, Equatable, Sendable {
    static let greenTeaKey = "iyfxmLogGVIaH7aEgqwcIA"      // green-tea
    static let notGreenTeaKey = "4snMZS8LJkSctKypt2m+xA"   // not-green-tea
    static let wapiKey = "hiHut/WR+B9Lx/vd0WyeNg"          // wapi (WLAN vs Wi-Fi)

    // Media, Camera & Health Boolean Slot Keys (IODeviceTree-backed, slot >= 0, qtype = 11)
    static let audioMixKey = "aVL5GE3tx0LSCI/ErfrJGA"            // CameracinematicAudioTrackRendering (Audio Mix)
    static let spatialAudioRecKey = "X6NGcYcvHmbqlR8hLXASJA"     // spatial-audio-recording
    static let spatialFaceTimeAudioKey = "/EVOCjM/Nmb2roP5ebtEFA"// spatial-facetime-audio
    static let responsiveShutterKey = "gQDt76Te0SPw7N8oTLrBFw"   // ResponsiveShutter
    static let hypertensionNotifKey = "4fh9efw4o1yaFqkXNCXoeA"   // HypertensionNotifications

    // Apple Intelligence & iOS 27 Advanced AI Boolean Slot Keys (slot >= 0, qtype = 11)
    static let appIntellKey = "A62OafQ85EJAiiqKn4agtg"           // DeviceSupportsGenerativeModelSystems
    static let photosCleanUpKey = "XNCjqOupLM/S8fNyxRNQTA"       // Photos Clean Up
    static let handwritingSynthKey = "YgYIIViDt1kgzyIsIV61vA"    // Handwriting Synthesis
    static let audioIntellKey = "rb2tKZxlj0Gm2tBmUQSLqQ"         // supports-audio-intelligence
    static let personalTranslatorKey = "M1n2sAqf33NAOgZRGxQYBA"  // supports-personal-translator

    // Promoted Existing Hardware & UI Boolean Slot Keys (verified slot >= 0, qtype = 11)
    static let islandKey = "YlEtTtHlNesRBMal1CqRaA"              // DeviceSupportsDynamicIsland
    static let aodKey = "2OOJf1VhaM7NxfRok3HbWQ"                 // DeviceSupportsAlwaysOnDisplay
    static let aoTimeKey = "j8/Omm6s1lsmTDFsXjsBfA"              // DeviceSupportsAlwaysOnTime
    static let aodVibrancyKey = "ykpu7qyhqFweVMKtxNylWA"         // DeviceSupportsAODVibrancy
    static let liquidGlassLowPowerKey = "SAGvsp6O6kAQ4fEfDJpC4Q" // DeviceSupportsLiquidGlassLowPower
    static let chargeLimKey = "37NVydb//GP/GrhuTN+exg"           // DeviceSupports80ChargeLimit
    static let bootChimeKey = "QHxt+hGLaBPbQJbXiUJX3w"           // DeviceSupportsBootChime
    static let crashDetKey = "HCzWusHQwZDea6nNhaKndw"            // DeviceSupportsCollisionSOS
    static let pwmKey = "6IejgN+1Fmu5/QrZFOIeNw"                 // DeviceSupportsPulseWidthMaximization
    static let appPencilKey = "yhHcB0iH0d1XzPO/CFd3ow"           // DeviceSupportsApplePencil
    static let camButtonKey = "CwvKxM2cEogD3p+HYgaW0Q"           // CameraButtonCapability
    static let actButtonKey = "cT44WE1EohiwRzhsZ8xEsw"           // RingerButtonCapability
    static let tapToWakeKey = "yZf3GTRMGTuwSV/lD7Cagw"           // DeviceSupportsTapToWake
    static let stageMgrKey = "qeaj75wk3HF4DwQ8qbIi7g"            // DeviceSupportsEnhancedMultitasking

    // [测试特性] Newly Mined Experimental Boolean Slot Keys (100% verified slot >= 0, qtype = 11)
    static let shutterRelaxationKey = "P4ZJVy/zYuLy4ejRKP+0DA"          // DeviceSupportsRegionalCameraShutterRelaxation
    static let shutterKeyboardMutePreserveKey = "bGUN8lS6sYzy3xhePubp8A"// KeyboardMutePreservesRegionalShutterClickBehavior
    static let shutterLegacyMutePreserveKey = "Bim3FC83Te8QX1kfSpqYKQ"  // KeyboardMutePreservesRegionalShutterClickBehaviorForLegacyDevices
    static let concurrentHPLPMicsKey = "dI30ovtFUIeLioNQKDMbGQ"         // DeviceSupportsConcurrentHPLPMics
    static let photosLocalLightKey = "m9ORTKMgu9A+zF+A61Zz5A"           // DeviceSupportsPhotosLocalLight
    static let toneMappingKey = "Lcu6Zck+C/+AMO8qULacDw"                // DeviceSupportsToneMapping
    static let hdrDeferredProcessingKey = "JkZlE8z9YwHjE1hnbMhcgA"      // DeviceSupportsHDRDeferredProcessing
    static let spatialOverCaptureKey = "SjQQ07G8UacM7E69G7dPbg"         // DeviceSupportsSpatialOverCapture
    static let stereoAudioRecKey = "YlK+0xmxNWhNn/+r8SM8kA"             // DeviceSupportsStereoAudioRecording
    static let p3VideoRecKey = "1eBwtCIwbIDdC80wiyzfow"                 // DeviceSupportsP3ColorspaceVideoRecording
    static let touchSensitiveCamControlKey = "lyJZrSDc8J8eQ5Zb7A1Rvw"   // DeviceSupportsTouchSensitiveCameraControl
    static let hardwareDetentsKey = "V9pLLbPQhyb75bbdTioZVw"            // DeviceSupportsHardwareDetents
    static let cameraHapticsKey = "XriAxQ+JY1z5nt5f3ftXVw"              // DeviceSupportsCameraHaptics
    static let legacyBatteryInfoKey = "Rq0MF/w+gXM66Ii4fkWOzg"          // DeviceShowsBatteryModelInformationLegacyHW
    static let legacyDynamicEndOfChargeKey = "nfR1IphTGCaoFNu3NrCtWQ"   // DeviceSupportsDynamicEndOfChargeLegacyHW
    static let highLuminanceAODKey = "7brdL5xrEUWnlF9C0kdg5A"           // DeviceSupportsHighLuminanceAlwaysOnDisplay
    static let aodFlipbookKey = "aoJSd/MXk7M40NgXTM6x+g"                // DeviceSupportsAlwaysOnDisplayFlipbook
    static let carPlay2Key = "PR+xeEtTAiUN0R25+EYGfw"                   // DeviceSupportsCarPlay2
    static let touchDelivery120HzKey = "2OK50OGmkXM1ospsh766WQ"         // TouchDelivery120Hz
    static let hearingAidEQKey = "SMgTCc2v9AU2ziIHRX8qww"               // hearingaid-audio-equalization
    static let hearingAidLEKey = "RyXm3yMC4ejlFvwlEI509w"               // hearingaid-low-energy-audio
    static let hearingAidPowerRedKey = "u3c0R+31Df4SUTHrICQkTg"         // hearingaid-power-reduction
    static let breathingDisturbancesKey = "e0HV2blYUDBk/MsMEQACNA"      // DeviceSupportsBreathingDisturbancesMeasurements
    static let usBloodOxygenKey = "E4vGMChwcVRKD8hMVxnRvg"              // DeviceSupportsUSLegallyCompliantBloodOxygen
    static let workoutUltraKey = "fu+4kyf8VcMBtgbMyJlLtg"               // WorkoutUltraMode
    static let timeInDaylightKey = "8gVfz9/8R1OtWBBtI0o/+Q"             // DeviceSupportsTimeInDaylight
    static let siriHubKey = "waGD2UTpntjbDXD1r3oALQ"                    // DeviceSupportsSiriHub
    static let onDeviceSiriKey = "O/7gbXWA5X2IRPVtDRU+bw"               // OnDeviceSiriCapability
    static let modelPruningKey = "m4xs4mhvxnAopYrApoLDMw"               // DeviceSupportsInstructionFollowingPruningModels

    static let optionalFeatureSlotKeys: Set<String> = [
        audioMixKey,
        spatialAudioRecKey,
        spatialFaceTimeAudioKey,
        responsiveShutterKey,
        hypertensionNotifKey,
        appIntellKey,
        photosCleanUpKey,
        handwritingSynthKey,
        audioIntellKey,
        personalTranslatorKey,
        // Promoted existing toggles
        islandKey,
        aodKey,
        aoTimeKey,
        aodVibrancyKey,
        liquidGlassLowPowerKey,
        chargeLimKey,
        bootChimeKey,
        crashDetKey,
        pwmKey,
        appPencilKey,
        camButtonKey,
        actButtonKey,
        tapToWakeKey,
        stageMgrKey,
        // Newly mined experimental toggles
        shutterRelaxationKey,
        shutterKeyboardMutePreserveKey,
        shutterLegacyMutePreserveKey,
        concurrentHPLPMicsKey,
        photosLocalLightKey,
        toneMappingKey,
        hdrDeferredProcessingKey,
        spatialOverCaptureKey,
        stereoAudioRecKey,
        p3VideoRecKey,
        touchSensitiveCamControlKey,
        hardwareDetentsKey,
        cameraHapticsKey,
        legacyBatteryInfoKey,
        legacyDynamicEndOfChargeKey,
        highLuminanceAODKey,
        aodFlipbookKey,
        carPlay2Key,
        touchDelivery120HzKey,
        hearingAidEQKey,
        hearingAidLEKey,
        hearingAidPowerRedKey,
        breathingDisturbancesKey,
        usBloodOxygenKey,
        workoutUltraKey,
        timeInDaylightKey,
        siriHubKey,
        onDeviceSiriKey,
        modelPruningKey
    ]

    static let mediaHealthSlotKeys: Set<String> = [
        audioMixKey,
        spatialAudioRecKey,
        spatialFaceTimeAudioKey,
        responsiveShutterKey,
        hypertensionNotifKey
    ]

    let uuid: String
    let slotCount: Int
    let greenTeaIndex: Int
    let notGreenTeaIndex: Int
    let wapiIndex: Int?
    var featureSlotIndices: [String: Int] = [:]

    var byteCount: Int { slotCount * 9 }
    var greenTeaOffset: Int { greenTeaIndex * 8 }
    var notGreenTeaOffset: Int { notGreenTeaIndex * 8 }
    var wapiOffset: Int? { wapiIndex.map { $0 * 8 } }

    func slotIndex(forKey key: String) -> Int? {
        if key == Self.greenTeaKey { return greenTeaIndex }
        if key == Self.notGreenTeaKey { return notGreenTeaIndex }
        if key == Self.wapiKey { return wapiIndex }
        return featureSlotIndices[key]
    }

    func valueOffset(forKey key: String) -> Int? {
        return slotIndex(forKey: key).map { $0 * 8 }
    }

    func validityOffset(for slotIndex: Int) -> Int {
        return slotCount * 8 + slotIndex
    }

    var permittedMutableOffsets: Set<Int> {
        var set: Set<Int> = [greenTeaOffset, notGreenTeaOffset]
        if let wOff = wapiOffset {
            set.insert(wOff)
        }
        for (_, slotIdx) in featureSlotIndices where (0..<slotCount).contains(slotIdx) {
            set.insert(slotIdx * 8)
        }
        return set
    }

    // MARK: - Pure Runtime Descriptor Scanner (Zero Hardcoded Fallbacks)

    static func resolveFromLoadedLibrary() -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let image = MGCopyLoadedMobileGestaltImage() else {
            return .failure(.libraryUnavailable(L("无法从内存只读加载 /usr/lib/libMobileGestalt.dylib 段数据。")))
        }
        return scan(image: image)
        #else
        return .failure(.libraryUnavailable(L("当前运行环境不是 iOS 实机，已禁用二进制 CacheData 修改。")))
        #endif
    }

    static func scan(image: [String: Any]) -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        guard let strings = image["strings"] as? Data,
              let addressNum = image["stringAddress"] as? NSNumber,
              let constants = image["constants"] as? [Data] else {
            return .failure(.malformedImage(L("系统库镜像缺少必要的 __cstring 或 __const 段数据。")))
        }
        let extraUUIDs = (image["cfUUIDs"] as? [String]) ?? []
        return scan(
            strings: strings,
            stringAddress: addressNum.uint64Value,
            constants: constants,
            extraUUIDs: extraUUIDs
        )
    }

    /// Scans modern 64-byte MobileGestalt query descriptors:
    /// +0x00: pointer to 22-char obfuscated key string (canonical 48-bit user VA)
    /// +0x3A: signed Int16 cache slot index
    /// +0x3C: UInt32 query type (11 = Boolean)
    static func scan(
        strings: Data,
        stringAddress: UInt64,
        constants: [Data],
        extraUUIDs: [String] = []
    ) -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        guard !strings.isEmpty,
              strings.count <= 32 * 1024 * 1024,
              stringAddress > 0,
              stringAddress <= UInt64.max - UInt64(strings.count),
              !constants.isEmpty,
              constants.count <= 8,
              constants.allSatisfy({ $0.count <= 32 * 1024 * 1024 }) else {
            return .failure(.malformedImage(L("系统库段大小或地址范围异常，已拒绝解析。")))
        }

        var hashByAddress: [UInt64: String] = [:]
        var discoveredUUIDs = Set<String>()

        for u in extraUUIDs {
            if u.count == 36, let parsed = UUID(uuidString: u) {
                discoveredUUIDs.insert(parsed.uuidString.uppercased())
            }
        }

        strings.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuf.count
            var tokenStart = 0
            for idx in 0..<count where base[idx] == 0 {
                let len = idx - tokenStart
                if len == 22 {
                    var valid = true
                    for k in tokenStart..<idx {
                        let b = base[k]
                        if !((65...90).contains(b) || (97...122).contains(b) || (48...57).contains(b) || b == 43 || b == 47) {
                            valid = false
                            break
                        }
                    }
                    if valid {
                        let slice = UnsafeBufferPointer(start: base.advanced(by: tokenStart), count: 22)
                        hashByAddress[stringAddress + UInt64(tokenStart)] = String(decoding: slice, as: UTF8.self)
                    }
                } else if len == 36 {
                    let slice = UnsafeBufferPointer(start: base.advanced(by: tokenStart), count: 36)
                    if let text = String(bytes: slice, encoding: .utf8),
                       let parsedUUID = UUID(uuidString: text) {
                        discoveredUUIDs.insert(parsedUUID.uuidString.uppercased())
                    }
                }
                tokenStart = idx + 1
            }
        }

        guard !discoveredUUIDs.isEmpty else {
            return .failure(.uuidNotFound(L("未能在系统库中找到唯一的 CacheUUID 标识，已拒绝修改。")))
        }
        guard discoveredUUIDs.count == 1, let resolvedUUID = discoveredUUIDs.first else {
            return .failure(.ambiguousUUID(L("系统库中发现多个 UUID 候选（\(discoveredUUIDs.count) 个），拒绝猜测偏移！")))
        }

        var positiveIndices = Set<Int>()
        var targetIndices: [String: Set<Int>] = [:]
        var targetAlignments: [String: Set<String>] = [:]
        let requiredKeys: Set<String> = [greenTeaKey, notGreenTeaKey, wapiKey]

        for (secID, secData) in constants.enumerated() where secData.count >= 64 {
            let scanErr: MGCacheResolutionError? = secData.withUnsafeBytes { raw -> MGCacheResolutionError? in
                for off in stride(from: 0, through: secData.count - 64, by: 8) {
                    let rawPtr = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt64.self))
                    // Darwin arm64e userland VA space is 47-bit (0x0000_7FFF_FFFF_FFFF); strip bits 63:47 PAC tags
                    let canonicalPtr = rawPtr & 0x0000_7FFF_FFFF_FFFF
                    guard let key = hashByAddress[canonicalPtr] else { continue }

                    let slotIdx = Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3A, as: Int16.self)))
                    let queryType = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3C, as: UInt32.self))
                    guard (-1..<16384).contains(slotIdx), (1...11).contains(queryType) else { continue }

                    if slotIdx >= 0 {
                        positiveIndices.insert(slotIdx)
                    }

                    if requiredKeys.contains(key) {
                        guard queryType == 11, slotIdx >= 0 else {
                            return .invalidTargetDescriptor(L("目标键 \(key) 的描述符类型 (\(queryType)) 或槽位 (\(slotIdx)) 非有效布尔缓存项。"))
                        }
                        targetIndices[key, default: []].insert(slotIdx)
                        targetAlignments[key, default: []].insert("\(secID):\(off % 64)")
                    } else if optionalFeatureSlotKeys.contains(key), queryType == 11, slotIdx >= 0 {
                        targetIndices[key, default: []].insert(slotIdx)
                        targetAlignments[key, default: []].insert("\(secID):\(off % 64)")
                    }
                }
                return nil
            }
            if let scanErr {
                return .failure(scanErr)
            }
        }

        guard let maxSlotIndex = positiveIndices.max(), maxSlotIndex >= 1 else {
            return .failure(.descriptorTableNotFound(L("未能在系统库中定位有效的 MobileGestalt 查询描述符表。")))
        }
        let slotCount = maxSlotIndex + 1
        guard positiveIndices.count > slotCount / 2 else {
            return .failure(.sparseDescriptorTable(L("描述符表槽位覆盖率异常（\(positiveIndices.count)/\(slotCount)），已拒绝解析。")))
        }

        guard let gtSet = targetIndices[greenTeaKey], gtSet.count == 1, let gtIdx = gtSet.first,
              let ngtSet = targetIndices[notGreenTeaKey], ngtSet.count == 1, let ngtIdx = ngtSet.first,
              gtIdx != ngtIdx,
              (0..<slotCount).contains(gtIdx),
              (0..<slotCount).contains(ngtIdx),
              let gtAlign = targetAlignments[greenTeaKey], gtAlign.count == 1,
              gtAlign == targetAlignments[notGreenTeaKey] else {
            return .failure(.invalidTargetDescriptor(L("无法唯一确定 green-tea / not-green-tea 的缓存槽位或表对齐不一致，已拒绝修改。")))
        }

        var resolvedWapiIdx: Int? = nil
        if let wapiSet = targetIndices[wapiKey] {
            guard wapiSet.count == 1,
                  let wIdx = wapiSet.first,
                  (0..<slotCount).contains(wIdx),
                  wIdx != gtIdx,
                  wIdx != ngtIdx,
                  targetAlignments[wapiKey] == gtAlign else {
                return .failure(.invalidTargetDescriptor(L("wapi 描述符存在歧义或对齐不一致，已拒绝解析。")))
            }
            resolvedWapiIdx = wIdx
        }

        var resolvedFeatureSlots: [String: Int] = [:]
        var usedCoreSlots: Set<Int> = [gtIdx, ngtIdx]
        if let wIdx = resolvedWapiIdx {
            usedCoreSlots.insert(wIdx)
        }
        for fKey in optionalFeatureSlotKeys.sorted() {
            if let fSet = targetIndices[fKey],
               fSet.count == 1,
               let fIdx = fSet.first,
               (0..<slotCount).contains(fIdx),
               !usedCoreSlots.contains(fIdx),
               targetAlignments[fKey] == gtAlign {
                resolvedFeatureSlots[fKey] = fIdx
            }
        }

        return .success(
            MGCacheDataLayout(
                uuid: resolvedUUID,
                slotCount: slotCount,
                greenTeaIndex: gtIdx,
                notGreenTeaIndex: ngtIdx,
                wapiIndex: resolvedWapiIdx,
                featureSlotIndices: resolvedFeatureSlots
            )
        )
    }

    static func scanDescriptorsFromLoadedLibrary() -> [MGSlotDescriptorInfo] {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let image = MGCopyLoadedMobileGestaltImage(),
              let strings = image["strings"] as? Data,
              let addressNum = image["stringAddress"] as? NSNumber,
              let constants = image["constants"] as? [Data] else {
            return []
        }
        let stringAddress = addressNum.uint64Value
        var hashByAddress: [UInt64: String] = [:]
        strings.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuf.count
            var tokenStart = 0
            for idx in 0..<count where base[idx] == 0 {
                let len = idx - tokenStart
                if len == 22 {
                    var valid = true
                    for k in tokenStart..<idx {
                        let b = base[k]
                        if !((65...90).contains(b) || (97...122).contains(b) || (48...57).contains(b) || b == 43 || b == 47) {
                            valid = false
                            break
                        }
                    }
                    if valid {
                        let slice = UnsafeBufferPointer(start: base.advanced(by: tokenStart), count: 22)
                        hashByAddress[stringAddress + UInt64(tokenStart)] = String(decoding: slice, as: UTF8.self)
                    }
                }
                tokenStart = idx + 1
            }
        }

        // Determine the primary descriptor table alignment from green-tea
        var expectedSecID: Int? = nil
        var expectedMod: Int? = nil
        for (secID, secData) in constants.enumerated() where secData.count >= 64 {
            secData.withUnsafeBytes { raw in
                for off in stride(from: 0, through: secData.count - 64, by: 8) {
                    let rawPtr = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt64.self))
                    let canonicalPtr = rawPtr & 0x0000_7FFF_FFFF_FFFF
                    if hashByAddress[canonicalPtr] == greenTeaKey {
                        let slotIdx = Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3A, as: Int16.self)))
                        let queryType = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3C, as: UInt32.self))
                        if slotIdx >= 0 && queryType == 11 {
                            expectedSecID = secID
                            expectedMod = off % 64
                            break
                        }
                    }
                }
            }
            if expectedSecID != nil { break }
        }

        var results: [MGSlotDescriptorInfo] = []
        var seenKeys = Set<String>()
        for (secID, secData) in constants.enumerated() where secData.count >= 64 {
            if let expSec = expectedSecID, expSec != secID { continue }
            secData.withUnsafeBytes { raw in
                for off in stride(from: 0, through: secData.count - 64, by: 8) {
                    if let expMod = expectedMod, (off % 64) != expMod { continue }
                    let rawPtr = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt64.self))
                    let canonicalPtr = rawPtr & 0x0000_7FFF_FFFF_FFFF
                    guard let key = hashByAddress[canonicalPtr], !seenKeys.contains(key) else { continue }
                    let slotIdx = Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3A, as: Int16.self)))
                    let queryType = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3C, as: UInt32.self))
                    guard (-1..<16384).contains(slotIdx), (1...11).contains(queryType) else { continue }
                    seenKeys.insert(key)
                    results.append(MGSlotDescriptorInfo(obfuscatedKey: key, slotIndex: slotIdx, queryType: queryType))
                }
            }
        }
        return results
        #else
        return []
        #endif
    }

    // MARK: - Strict Plist & Byte-Level Verification

    func validatePlist(_ dict: NSDictionary, checkWapiSlot: Bool = false) -> Result<Data, MGCacheResolutionError> {
        guard (1...16384).contains(slotCount),
              (0..<slotCount).contains(greenTeaIndex),
              (0..<slotCount).contains(notGreenTeaIndex),
              greenTeaIndex != notGreenTeaIndex else {
            return .failure(.invalidTargetDescriptor(L("缓存槽位索引超出合法范围。")))
        }

        guard let plistUUID = dict["CacheUUID"] as? String, !plistUUID.isEmpty else {
            return .failure(.plistMismatch(L("MobileGestalt 文件缺少 CacheUUID 字段，拒绝修改。")))
        }
        guard plistUUID.caseInsensitiveCompare(uuid) == .orderedSame else {
            return .failure(.plistMismatch(L("缓存文件 CacheUUID (\(plistUUID)) 与本机系统库 (\(uuid)) 不一致，拒绝修改！")))
        }

        guard let cacheData = dict["CacheData"] as? Data else {
            return .failure(.plistMismatch(L("MobileGestalt 文件缺少二进制 CacheData 字段，拒绝修改。")))
        }
        guard cacheData.count == byteCount else {
            return .failure(.plistMismatch(L("CacheData 长度 (\(cacheData.count) 字节) 与系统库计算的精确长度 (\(byteCount) 字节，\(slotCount) 槽位) 不一致，拒绝修改！")))
        }

        var slotsToVerify = [greenTeaIndex, notGreenTeaIndex]
        if let wIdx = wapiIndex {
            if checkWapiSlot || validateSingleBooleanSlot(wIdx, in: cacheData) {
                slotsToVerify.append(wIdx)
            }
        } else if checkWapiSlot {
            return .failure(.invalidTargetDescriptor(L("当前系统库未解析出有效的 wapi 槽位，拒绝修改该项。")))
        }

        for slotIdx in slotsToVerify {
            let valOff = slotIdx * 8
            let validOff = validityOffset(for: slotIdx)
            guard validOff < cacheData.count, valOff + 8 <= cacheData.count else {
                return .failure(.plistMismatch(L("槽位 \(slotIdx) 偏移越界，拒绝修改。")))
            }
            guard cacheData[validOff] == 1 else {
                let validOffHex = String(format: "%X", validOff)
                return .failure(.slotInvalid(L("槽位 \(slotIdx)（有效位偏移 0x\(validOffHex)）未被系统标记为有效 (validity != 1)，拒绝修改！")))
            }
            guard cacheData[valOff] <= 1 else {
                let valOffHex = String(format: "%X", valOff)
                return .failure(.slotInvalid(L("槽位 \(slotIdx)（偏移 0x\(valOffHex)）当前字节值 (\(cacheData[valOff])) 不是合法布尔值 (0/1)，拒绝修改！")))
            }
            for pad in (valOff + 1)..<(valOff + 8) {
                guard cacheData[pad] == 0 else {
                    let padHex = String(format: "%X", pad)
                    return .failure(.slotInvalid(L("槽位 \(slotIdx) 填充字节非零（偏移 0x\(padHex) = \(cacheData[pad])），拒绝修改！")))
                }
            }
        }

        if let extra = dict["CacheExtra"] as? NSDictionary {
            var forbiddenKeys = [Self.greenTeaKey, Self.notGreenTeaKey, "green-tea", "not-green-tea"]
            if checkWapiSlot {
                forbiddenKeys.append(contentsOf: [Self.wapiKey, "wapi"])
            }
            for k in forbiddenKeys where extra[k] != nil {
                return .failure(.conflictingCacheExtra(L("检测到 CacheExtra 中已存在覆盖键 \(k)，为确保安全已拒绝修改 CacheData。")))
            }
        }

        return .success(cacheData)
    }

    func validateSingleBooleanSlot(_ slotIdx: Int, in cacheData: Data) -> Bool {
        let valOff = slotIdx * 8
        let validOff = validityOffset(for: slotIdx)
        guard cacheData.count == byteCount,
              (0..<slotCount).contains(slotIdx),
              validOff < cacheData.count,
              valOff + 8 <= cacheData.count,
              cacheData[validOff] == 1,
              cacheData[valOff] <= 1 else {
            return false
        }
        return cacheData[(valOff + 1)..<(valOff + 8)].allSatisfy { $0 == 0 }
    }
}

enum MGCacheResolutionError: LocalizedError, Equatable {
    case libraryUnavailable(String)
    case malformedImage(String)
    case uuidNotFound(String)
    case ambiguousUUID(String)
    case descriptorTableNotFound(String)
    case sparseDescriptorTable(String)
    case invalidTargetDescriptor(String)
    case plistMismatch(String)
    case slotInvalid(String)
    case conflictingCacheExtra(String)
    case unauthorizedByteMutation(String)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let m),
             .malformedImage(let m),
             .uuidNotFound(let m),
             .ambiguousUUID(let m),
             .descriptorTableNotFound(let m),
             .sparseDescriptorTable(let m),
             .invalidTargetDescriptor(let m),
             .plistMismatch(let m),
             .slotInvalid(let m),
             .conflictingCacheExtra(let m),
             .unauthorizedByteMutation(let m):
            return m
        }
    }
}

// MARK: - Original Per-UUID Flag Snapshot & Runtime Coordinator

struct MGCacheRecordedFlags: Codable, Equatable {
    let layoutUUID: String
    let cacheVersion: String
    let greenTea: Bool
    let notGreenTea: Bool
    let wapi: Bool?
    var extraSlots: [String: Bool]? = nil
}

struct MGCacheDataDiffDetail {
    let id: String
    let label: String
    let keyPath: String
    let beforeText: String
    let afterText: String
}

final class MGCacheDataCoordinator {
    static let shared = MGCacheDataCoordinator()

    private let defaultsKey = "mgRecordedOriginalCacheFlagsByUUID_v1"
    private let lock = NSLock()
    private var cachedVerifiedLayout: MGCacheDataLayout?
    private var cachedAllDescriptors: [MGSlotDescriptorInfo]?

    private init() {}

    func allDescriptors() -> [MGSlotDescriptorInfo] {
        lock.lock()
        if let existing = cachedAllDescriptors {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let scanned = MGCacheDataLayout.scanDescriptorsFromLoadedLibrary()
        if !scanned.isEmpty {
            lock.lock()
            cachedAllDescriptors = scanned
            lock.unlock()
        }
        return scanned
    }

    func libraryLayout() -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        lock.lock()
        if let existing = cachedVerifiedLayout {
            lock.unlock()
            return .success(existing)
        }
        lock.unlock()

        let resolved = MGCacheDataLayout.resolveFromLoadedLibrary()
        if case .success(let layout) = resolved {
            lock.lock()
            cachedVerifiedLayout = layout
            lock.unlock()
        }
        return resolved
    }

    /// Resolves layout from live libMobileGestalt.dylib AND validates against the given plist dictionary.
    func resolveValidated(for dict: NSDictionary, checkWapiSlot: Bool = false) -> Result<(MGCacheDataLayout, Data), MGCacheResolutionError> {
        switch libraryLayout() {
        case .failure(let err):
            return .failure(err)
        case .success(let layout):
            switch layout.validatePlist(dict, checkWapiSlot: checkWapiSlot) {
            case .failure(let err):
                return .failure(err)
            case .success(let data):
                return .success((layout, data))
            }
        }
    }

    /// Records the earliest observed valid flags for a CacheUUID (preferring OriginalGestalt.plist if its UUID matches).
    func recordBaselineIfNeeded(liveDict: NSDictionary, savedOriginalDict: NSDictionary?) {
        // Prefer OriginalGestalt.plist if it matches this exact CacheUUID & layout
        if let saved = savedOriginalDict,
           case .success((let layout, let savedData)) = resolveValidated(for: saved) {
            saveInitialFlagsIfAbsent(from: saved, data: savedData, layout: layout)
            return
        }
        if case .success((let layout, let liveData)) = resolveValidated(for: liveDict) {
            saveInitialFlagsIfAbsent(from: liveDict, data: liveData, layout: layout)
        }
    }

    private func saveInitialFlagsIfAbsent(from dict: NSDictionary, data: Data, layout: MGCacheDataLayout) {
        lock.lock()
        defer { lock.unlock() }
        var map = loadRecordedMap()
        let key = layout.uuid.uppercased()

        var extraMap: [String: Bool] = [:]
        let hwModel = currentOriginalMachineName()
        for (fKey, fSlot) in layout.featureSlotIndices where layout.validateSingleBooleanSlot(fSlot, in: data) {
            if fKey == MGCacheDataLayout.audioIntellKey && (hwModel.hasPrefix("iPhone") || hwModel.hasPrefix("iPad")) {
                extraMap[fKey] = false
            } else if fKey == MGCacheDataLayout.personalTranslatorKey && hwModel.hasPrefix("iPhone") {
                extraMap[fKey] = isAppleIntellHD()
            } else {
                extraMap[fKey] = (data[fSlot * 8] == 1)
            }
        }

        if var existing = map[key] {
            var currentExtra = existing.extraSlots ?? [:]
            var updated = false
            for (k, v) in extraMap where currentExtra[k] == nil {
                currentExtra[k] = v
                updated = true
            }
            if updated {
                existing.extraSlots = currentExtra
                map[key] = existing
                saveRecordedMap(map)
            }
            return
        }

        let gt = data[layout.greenTeaOffset] == 1
        let ngt = data[layout.notGreenTeaOffset] == 1
        var wapiVal: Bool? = nil
        if let wIdx = layout.wapiIndex, layout.validateSingleBooleanSlot(wIdx, in: data) {
            wapiVal = (data[wIdx * 8] == 1)
        }
        let build = dict["CacheVersion"] as? String ?? ""
        map[key] = MGCacheRecordedFlags(
            layoutUUID: key,
            cacheVersion: build,
            greenTea: gt,
            notGreenTea: ngt,
            wapi: wapiVal,
            extraSlots: extraMap
        )
        saveRecordedMap(map)
    }

    func originalFlags(for layout: MGCacheDataLayout, savedOriginalDict: NSDictionary?) -> MGCacheRecordedFlags? {
        if let saved = savedOriginalDict,
           case .success(let savedData) = layout.validatePlist(saved) {
            let gt = savedData[layout.greenTeaOffset] == 1
            let ngt = savedData[layout.notGreenTeaOffset] == 1
            var wVal: Bool? = nil
            if let wIdx = layout.wapiIndex, layout.validateSingleBooleanSlot(wIdx, in: savedData) {
                wVal = (savedData[wIdx * 8] == 1)
            }
            var extraMap: [String: Bool] = [:]
            for (fKey, fSlot) in layout.featureSlotIndices where layout.validateSingleBooleanSlot(fSlot, in: savedData) {
                extraMap[fKey] = (savedData[fSlot * 8] == 1)
            }
            let build = saved["CacheVersion"] as? String ?? ""
            return MGCacheRecordedFlags(
                layoutUUID: layout.uuid.uppercased(),
                cacheVersion: build,
                greenTea: gt,
                notGreenTea: ngt,
                wapi: wVal,
                extraSlots: extraMap
            )
        }
        return loadRecordedMap()[layout.uuid.uppercased()]
    }

    func originalSlotValue(forKey key: String, layout: MGCacheDataLayout, savedOriginalDict: NSDictionary?) -> Bool? {
        let hwModel = currentOriginalMachineName()
        if key == MGCacheDataLayout.audioIntellKey && (hwModel.hasPrefix("iPhone") || hwModel.hasPrefix("iPad")) {
            return false
        }
        if key == MGCacheDataLayout.personalTranslatorKey && hwModel.hasPrefix("iPhone") {
            return isAppleIntellHD()
        }
        if let saved = savedOriginalDict,
           case .success(let savedData) = layout.validatePlist(saved),
           let slotIdx = layout.slotIndex(forKey: key),
           layout.validateSingleBooleanSlot(slotIdx, in: savedData) {
            return savedData[slotIdx * 8] == 1
        }
        if key == MGCacheDataLayout.personalTranslatorKey {
            return isAppleIntellHD()
        }
        return loadRecordedMap()[layout.uuid.uppercased()]?.extraSlots?[key]
    }

    func clearRecordedBaselines() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func loadRecordedMap() -> [String: MGCacheRecordedFlags] {
        guard let raw = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: MGCacheRecordedFlags].self, from: raw) else {
            return [:]
        }
        return decoded
    }

    private func saveRecordedMap(_ map: [String: MGCacheRecordedFlags]) {
        if let encoded = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }

    // MARK: - Strict Transition Audit & Diff Generation

    /// Ensures that ANY CacheData byte mutation ONLY touches dynamically resolved & validated Boolean offsets.
    /// Zero privilege bypasses: any unresolved layout or unrelated byte change is strictly blocked.
    func validateTransition(from beforeDict: NSDictionary, to afterDict: NSDictionary, using customLayout: MGCacheDataLayout? = nil) -> Result<Void, MGCacheResolutionError> {
        let beforeData = beforeDict["CacheData"] as? Data
        let afterData = afterDict["CacheData"] as? Data
        guard beforeData != afterData else {
            return .success(())
        }

        let layout: MGCacheDataLayout
        if let customLayout {
            layout = customLayout
        } else {
            switch libraryLayout() {
            case .failure(let err):
                return .failure(err)
            case .success(let resolved):
                layout = resolved
            }
        }

        guard case .success(let validBefore) = layout.validatePlist(beforeDict),
              case .success(let validAfter) = layout.validatePlist(afterDict),
              validBefore.count == validAfter.count else {
            switch layout.validatePlist(afterDict) {
            case .failure(let err):
                return .failure(err)
            case .success:
                if case .failure(let err2) = layout.validatePlist(beforeDict) {
                    return .failure(err2)
                }
                return .failure(.plistMismatch(L("修改前后 CacheData 校验未通过，已拒绝写入。")))
            }
        }

        let allowedOffsets = layout.permittedMutableOffsets
        if let wOff = layout.wapiOffset, validBefore[wOff] != validAfter[wOff] {
            if case .failure(let wErr) = layout.validatePlist(afterDict, checkWapiSlot: true) {
                return .failure(wErr)
            }
        }

        for (fKey, fSlot) in layout.featureSlotIndices {
            let fOff = fSlot * 8
            if validBefore[fOff] != validAfter[fOff] {
                guard layout.validateSingleBooleanSlot(fSlot, in: validBefore),
                      layout.validateSingleBooleanSlot(fSlot, in: validAfter) else {
                    return .failure(.slotInvalid(L("功能槽位 \(fSlot) (\(fKey)) 未通过 8 字节布尔有效性校验，已拒绝修改！")))
                }
            }
        }

        for idx in validBefore.indices where validBefore[idx] != validAfter[idx] {
            guard allowedOffsets.contains(idx) else {
                return .failure(.unauthorizedByteMutation(String(format: "检测到未授权的无关缓存字节变动（偏移 0x%X：0x%02X -> 0x%02X），已强制中止写入！".loc, idx, validBefore[idx], validAfter[idx])))
            }
        }

        return .success(())
    }

    static func featureSlotMeta(forKey key: String) -> (id: String, label: String, trueHint: String, falseHint: String) {
        switch key {
        case MGCacheDataLayout.audioMixKey:
            return ("audio-mix", L("相册与相机混音 (Audio Mix)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.spatialAudioRecKey:
            return ("spatial-audio-rec", L("空间音频录制 (spatial-audio-recording)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.spatialFaceTimeAudioKey:
            return ("spatial-facetime-audio", L("FaceTime 空间音频 (spatial-facetime-audio)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.responsiveShutterKey:
            return ("responsive-shutter", L("按下快门瞬间抓拍 (ResponsiveShutter)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.hypertensionNotifKey:
            return ("hypertension-notif", L("健康高血压趋势评估 (HypertensionNotifications)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.appIntellKey:
            return ("ai-core-slot", L("Apple 智能底层槽位 (GenerativeModelSystems)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.photosCleanUpKey:
            return ("photos-cleanup-slot", L("相册消除底层槽位 (Photos Clean Up)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.handwritingSynthKey:
            return ("handwriting-slot", L("手写体合成底层槽位 (Handwriting Synthesis)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.audioIntellKey:
            return ("audio-intell-slot", L("iOS 27 音频智能底层槽位 (Audio Intelligence)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.personalTranslatorKey:
            return ("personal-translator-slot", L("个人实时翻译底层槽位 (Personal Translator)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.islandKey:
            return ("dynamic-island-slot", L("灵动岛底层槽位 (DynamicIsland)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.aodKey:
            return ("aod-slot", L("全天候显示底层槽位 (AOD)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.aoTimeKey:
            return ("aotime-slot", L("全天候显示时间槽位 (AlwaysOnTime)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.aodVibrancyKey:
            return ("aod-vibrancy-slot", L("全天候显示鲜艳度槽位 (AODVibrancy)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.liquidGlassLowPowerKey:
            return ("liquid-glass-lp-slot", L("液态玻璃低功耗槽位 (LiquidGlassLowPower)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.chargeLimKey:
            return ("charge-limit-slot", L("80% 充电上限底层槽位 (80ChargeLimit)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.bootChimeKey:
            return ("boot-chime-slot", L("开关机提示音底层槽位 (BootChime)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.crashDetKey:
            return ("crash-det-slot", L("车祸检测底层槽位 (CollisionSOS)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.pwmKey:
            return ("pwm-slot", L("PWM 调光底层槽位 (PulseWidthMaximization)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.appPencilKey:
            return ("apple-pencil-slot", L("Apple Pencil 底层槽位"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.camButtonKey:
            return ("cam-button-slot", L("相机控制按键底层槽位 (CameraButton)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.actButtonKey:
            return ("action-button-slot", L("操作按钮底层槽位 (RingerButton)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.tapToWakeKey:
            return ("tap-to-wake-slot", L("轻点唤醒底层槽位 (TapToWake)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.stageMgrKey:
            return ("stage-mgr-slot", L("台前调度底层槽位 (EnhancedMultitasking)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.shutterRelaxationKey:
            return ("shutter-relax-slot", L("[测试] 地区快门音豁免槽位 (RegionalCameraShutterRelaxation)"), L("true (0x01 · 允许静音)"), L("false (0x00 · 强制快门音)"))
        case MGCacheDataLayout.shutterKeyboardMutePreserveKey:
            return ("shutter-kb-mute-slot", L("[测试] 保留地区强制快门音 (KeyboardMutePreservesShutter)"), L("true (0x01 · 保留强制音)"), L("false (0x00 · 已解除强制音)"))
        case MGCacheDataLayout.shutterLegacyMutePreserveKey:
            return ("shutter-legacy-mute-slot", L("[测试] 旧机型保留强制快门音 (LegacyShutterPreserve)"), L("true (0x01 · 保留强制音)"), L("false (0x00 · 已解除强制音)"))
        case MGCacheDataLayout.concurrentHPLPMicsKey:
            return ("concurrent-mics-slot", L("[测试] 高低功耗双麦并发槽位 (ConcurrentHPLPMics)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.photosLocalLightKey:
            return ("photos-local-light-slot", L("[测试] 相册局部光效重绘槽位 (PhotosLocalLight)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.toneMappingKey:
            return ("tone-mapping-slot", L("[测试] 动态色调映射槽位 (ToneMapping)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.hdrDeferredProcessingKey:
            return ("hdr-deferred-slot", L("[测试] HDR 深度延迟渲染槽位 (HDRDeferredProcessing)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.spatialOverCaptureKey:
            return ("spatial-overcapture-slot", L("[测试] 超取景框空间捕获槽位 (SpatialOverCapture)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.stereoAudioRecKey:
            return ("stereo-audio-rec-slot", L("[测试] 立体声视频拾音槽位 (StereoAudioRecording)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.p3VideoRecKey:
            return ("p3-video-rec-slot", L("[测试] P3 广色域视频录制槽位 (P3ColorspaceVideo)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.touchSensitiveCamControlKey:
            return ("touch-cam-control-slot", L("[测试] 电容触敏相机控制槽位 (TouchSensitiveCameraControl)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.hardwareDetentsKey:
            return ("hw-detents-slot", L("[测试] 物理触感档位阻尼槽位 (HardwareDetents)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.cameraHapticsKey:
            return ("camera-haptics-slot", L("[测试] 相机微幅触觉反馈槽位 (CameraHaptics)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.legacyBatteryInfoKey:
            return ("legacy-battery-info-slot", L("[测试] 旧机型电池健康详情槽位 (BatteryModelInfoLegacyHW)"), L("true (0x01 · 显示循环/日期)"), L("false (0x00 · 默认隐藏)"))
        case MGCacheDataLayout.legacyDynamicEndOfChargeKey:
            return ("legacy-dyn-eoc-slot", L("[测试] 旧机型智能充电截止槽位 (DynamicEndOfChargeLegacyHW)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.highLuminanceAODKey:
            return ("high-lum-aod-slot", L("[测试] 户外高亮息屏显示槽位 (HighLuminanceAOD)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.aodFlipbookKey:
            return ("aod-flipbook-slot", L("[测试] AOD 低功耗翻页帧缓冲槽位 (AODFlipbook)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.carPlay2Key:
            return ("carplay2-slot", L("[测试] CarPlay Ultra 多屏车载槽位 (CarPlay2)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.touchDelivery120HzKey:
            return ("touch-120hz-slot", L("[测试] 120Hz 触控投递槽位 (TouchDelivery120Hz)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.hearingAidEQKey:
            return ("hearingaid-eq-slot", L("[测试] 临床助听均衡器槽位 (hearingaid-audio-equalization)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.hearingAidLEKey:
            return ("hearingaid-le-slot", L("[测试] 助听低功耗音频槽位 (hearingaid-low-energy-audio)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.hearingAidPowerRedKey:
            return ("hearingaid-pwr-slot", L("[测试] 助听降功耗模式槽位 (hearingaid-power-reduction)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.breathingDisturbancesKey:
            return ("sleep-apnea-slot", L("[测试] 睡眠呼吸紊乱检测槽位 (BreathingDisturbances)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.usBloodOxygenKey:
            return ("us-blood-oxygen-slot", L("[测试] 美版血氧软件限制槽位 (USLegallyCompliantBloodOxygen)"), L("true (0x01 · 受专利限制)"), L("false (0x00 · 已解除血氧限制)"))
        case MGCacheDataLayout.workoutUltraKey:
            return ("workout-ultra-slot", L("[测试] 户外极限运动模式槽位 (WorkoutUltraMode)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.timeInDaylightKey:
            return ("daylight-time-slot", L("[测试] 日光照射时长监测槽位 (TimeInDaylight)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.siriHubKey:
            return ("siri-hub-slot", L("[测试] 端侧 Siri Hub 路由槽位 (DeviceSupportsSiriHub)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.onDeviceSiriKey:
            return ("ondevice-siri-slot", L("[测试] 离线端侧 Siri 能力槽位 (OnDeviceSiriCapability)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        case MGCacheDataLayout.modelPruningKey:
            return ("model-pruning-slot", L("[测试] 端侧指令模型剪枝槽位 (InstructionFollowingPruningModels)"), L("true (0x01 · 已启用)"), L("false (0x00 · 默认关闭)"))
        default:
            return (key, L("硬件特性槽位 (\(key))"), "true (0x01)", "false (0x00)")
        }
    }

    func diffDetails(from beforeDict: NSDictionary, to afterDict: NSDictionary, using customLayout: MGCacheDataLayout? = nil) -> [MGCacheDataDiffDetail] {
        guard let beforeData = beforeDict["CacheData"] as? Data,
              let afterData = afterDict["CacheData"] as? Data,
              beforeData != afterData,
              beforeData.count == afterData.count else {
            return []
        }

        let resolvedLayout: MGCacheDataLayout? = customLayout ?? {
            if case .success(let l) = libraryLayout() { return l }
            return nil
        }()

        guard let layout = resolvedLayout,
              case .success = layout.validatePlist(beforeDict),
              case .success = layout.validatePlist(afterDict) else {
            return []
        }

        var details: [MGCacheDataDiffDetail] = []
        var describedOffsets = Set<Int>()

        let slots: [(id: String, label: String, key: String, slot: Int, trueHint: String, falseHint: String)] = {
            var arr: [(String, String, String, Int, String, String)] = [
                ("green-tea", L("国行限制标记 (green-tea)"), MGCacheDataLayout.greenTeaKey, layout.greenTeaIndex, L("true (0x01 · 受限)"), L("false (0x00 · 已解除)")),
                ("not-green-tea", L("非国行设备标记 (not-green-tea)"), MGCacheDataLayout.notGreenTeaKey, layout.notGreenTeaIndex, L("true (0x01 · 非国行)"), L("false (0x00 · 国行默认)"))
            ]
            if let wIdx = layout.wapiIndex, layout.validateSingleBooleanSlot(wIdx, in: beforeData) && layout.validateSingleBooleanSlot(wIdx, in: afterData) {
                arr.append(("wapi", L("无线局域网显示标记 (wapi)"), MGCacheDataLayout.wapiKey, wIdx, L("true (0x01 · 无线局域网)"), "false (0x00 · Wi-Fi)"))
            }
            for fKey in layout.featureSlotIndices.keys.sorted() {
                if let fSlot = layout.featureSlotIndices[fKey],
                   layout.validateSingleBooleanSlot(fSlot, in: beforeData),
                   layout.validateSingleBooleanSlot(fSlot, in: afterData) {
                    let meta = Self.featureSlotMeta(forKey: fKey)
                    arr.append((meta.id, meta.label, fKey, fSlot, meta.trueHint, meta.falseHint))
                }
            }
            return arr
        }()

        for entry in slots {
            let off = entry.slot * 8
            if beforeData[off] != afterData[off] {
                describedOffsets.insert(off)
                details.append(
                    MGCacheDataDiffDetail(
                        id: "CacheData.\(entry.id)",
                        label: entry.label,
                        keyPath: String(format: "CacheData[0x%X] · 槽位 %d (%@)".loc, off, entry.slot, entry.key),
                        beforeText: beforeData[off] != 0 ? entry.trueHint : entry.falseHint,
                        afterText: afterData[off] != 0 ? entry.trueHint : entry.falseHint
                    )
                )
            }
        }

        let otherChangedCount = beforeData.indices.filter { !describedOffsets.contains($0) && beforeData[$0] != afterData[$0] }.count
        if otherChangedCount > 0 {
            details.append(
                MGCacheDataDiffDetail(
                    id: "CacheData.other",
                    label: L("底层二进制缓存其他偏移 (CacheData)"),
                    keyPath: "CacheData",
                    beforeText: L("<Data: \(beforeData.count) 字节>"),
                    afterText: L("<已变更 \(otherChangedCount) 个字节>")
                )
            )
        }

        return details
    }

    func diagnosticReport(for dict: NSDictionary) -> String {
        switch resolveValidated(for: dict) {
        case .failure(let err):
            return L("状态：❌ 动态解析未通过（已拒绝并锁定修改）\n原因：\(err.localizedDescription)")
        case .success((let layout, let data)):
            let gtVal = data[layout.greenTeaOffset] == 1
            let ngtVal = data[layout.notGreenTeaOffset] == 1
            var lines: [String] = [
                L("状态：✅ 已精确匹配本机系统库与缓存文件"),
                L("CacheUUID：\(layout.uuid)"),
                L("总槽位数：\(layout.slotCount) 个（共 \(layout.byteCount) 字节）"),
                String(format: "green-tea：槽位 %d，偏移 0x%X（有效位 0x%X），当前值 = %@".loc,
                       layout.greenTeaIndex, layout.greenTeaOffset, layout.validityOffset(for: layout.greenTeaIndex), gtVal ? "true" : "false"),
                String(format: "not-green-tea：槽位 %d，偏移 0x%X（有效位 0x%X），当前值 = %@".loc,
                       layout.notGreenTeaIndex, layout.notGreenTeaOffset, layout.validityOffset(for: layout.notGreenTeaIndex), ngtVal ? "true" : "false")
            ]
            if let wIdx = layout.wapiIndex, layout.validateSingleBooleanSlot(wIdx, in: data) {
                let wOff = wIdx * 8
                let wVal = data[wOff] == 1
                lines.append(String(format: "wapi (WLAN/Wi-Fi)：槽位 %d，偏移 0x%X（有效位 0x%X），当前值 = %@".loc,
                                    wIdx, wOff, layout.validityOffset(for: wIdx), wVal ? L("true (无线局域网)") : "false (Wi-Fi)"))
            } else {
                lines.append(L("wapi (WLAN/Wi-Fi)：当前系统未解析出有效槽位（已单独禁用）"))
            }
            for fKey in MGCacheDataLayout.mediaHealthSlotKeys.sorted() {
                if let fSlot = layout.featureSlotIndices[fKey], layout.validateSingleBooleanSlot(fSlot, in: data) {
                    let meta = Self.featureSlotMeta(forKey: fKey)
                    let fVal = data[fSlot * 8] == 1
                    lines.append(String(format: "%@：槽位 %d，偏移 0x%X，当前值 = %@".loc,
                                        meta.label, fSlot, fSlot * 8, fVal ? "true" : "false"))
                }
            }
            return lines.joined(separator: "\n")
        }
    }
}
