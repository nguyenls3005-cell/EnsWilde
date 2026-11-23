//
//  MGCacheLayout.swift
//  EnsWilde
//

import Foundation

fileprivate extension String {
    var loc: String { L(self) }
}

struct MGSlotDescriptorInfo: Identifiable, Equatable, Sendable {
    var id: String { "\(slotIndex):\(obfuscatedKey)" }
    let obfuscatedKey: String
    let slotIndex: Int
    let queryType: UInt32

    var valueOffset: Int? { slotIndex >= 0 ? slotIndex * 8 : nil }

    func validityOffset(slotCount: Int) -> Int? {
        guard slotIndex >= 0 else { return nil }
        return slotCount * 8 + slotIndex
    }
}

enum MGCacheResolutionError: LocalizedError {
    case libraryUnavailable(String)
    case malformedImage(String)
    case uuidNotFound(String)
    case ambiguousUUID(String)
    case invalidTargetDescriptor(String)
    case descriptorTableNotFound(String)
    case sparseDescriptorTable(String)
    case invalidCacheData(String)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let s):       return "Library unavailable: \(s)"
        case .malformedImage(let s):           return "Malformed image: \(s)"
        case .uuidNotFound(let s):             return "UUID not found: \(s)"
        case .ambiguousUUID(let s):            return "Ambiguous UUID: \(s)"
        case .invalidTargetDescriptor(let s):  return "Invalid descriptor: \(s)"
        case .descriptorTableNotFound(let s):  return "Descriptor table not found: \(s)"
        case .sparseDescriptorTable(let s):    return "Sparse table: \(s)"
        case .invalidCacheData(let s):         return "Invalid CacheData: \(s)"
        }
    }
}

struct MGCacheDataLayout: Codable, Equatable, Sendable {
    static let greenTeaKey = "iyfxmLogGVIaH7aEgqwcIA"
    static let notGreenTeaKey = "4snMZS8LJkSctKypt2m+xA"
    static let wapiKey = "hiHut/WR+B9Lx/vd0WyeNg"

    static let audioMixKey = "aVL5GE3tx0LSCI/ErfrJGA"
    static let spatialAudioRecKey = "X6NGcYcvHmbqlR8hLXASJA"
    static let spatialFaceTimeAudioKey = "/EVOCjM/Nmb2roP5ebtEFA"
    static let responsiveShutterKey = "gQDt76Te0SPw7N8oTLrBFw"
    static let hypertensionNotifKey = "4fh9efw4o1yaFqkXNCXoeA"

    static let appIntellKey = "A62OafQ85EJAiiqKn4agtg"
    static let photosCleanUpKey = "XNCjqOupLM/S8fNyxRNQTA"
    static let handwritingSynthKey = "YgYIIViDt1kgzyIsIV61vA"
    static let audioIntellKey = "rb2tKZxlj0Gm2tBmUQSLqQ"
    static let personalTranslatorKey = "M1n2sAqf33NAOgZRGxQYBA"

    static let islandKey = "YlEtTtHlNesRBMal1CqRaA"
    static let aodKey = "2OOJf1VhaM7NxfRok3HbWQ"
    static let aoTimeKey = "j8/Omm6s1lsmTDFsXjsBfA"
    static let aodVibrancyKey = "ykpu7qyhqFweVMKtxNylWA"
    static let liquidGlassLowPowerKey = "SAGvsp6O6kAQ4fEfDJpC4Q"
    static let chargeLimKey = "37NVydb//GP/GrhuTN+exg"
    static let bootChimeKey = "QHxt+hGLaBPbQJbXiUJX3w"
    static let crashDetKey = "HCzWusHQwZDea6nNhaKndw"
    static let pwmKey = "6IejgN+1Fmu5/QrZFOIeNw"
    static let appPencilKey = "yhHcB0iH0d1XzPO/CFd3ow"
    static let camButtonKey = "CwvKxM2cEogD3p+HYgaW0Q"
    static let actButtonKey = "cT44WE1EohiwRzhsZ8xEsw"
    static let tapToWakeKey = "yZf3GTRMGTuwSV/lD7Cagw"
    static let stageMgrKey = "qeaj75wk3HF4DwQ8qbIi7g"

    static let ipadModeKey = "uKc7FPnEO++lVhHWHFlGbQ"
    static let medusaFloatingKey = "mG0AnH/Vy1veoqoLRAIgTA"
    static let medusaOverlayKey = "UCG5MkVahJxG1YULbbd5Bg"
    static let medusaPinnedKey = "ZYqko/XM5zD3XBfN5RmaXA"
    static let medusaPipKey = "nVh/gwNpy7Jv1NOk00CMrw"
    static let deviceClassNumberKey = "mtrAoWJ3gsq+I90ZnQ0vQw"

    static let shutterRelaxationKey = "P4ZJVy/zYuLy4ejRKP+0DA"
    static let shutterKeyboardMutePreserveKey = "bGUN8lS6sYzy3xhePubp8A"
    static let shutterLegacyMutePreserveKey = "Bim3FC83Te8QX1kfSpqYKQ"
    static let concurrentHPLPMicsKey = "dI30ovtFUIeLioNQKDMbGQ"
    static let photosLocalLightKey = "m9ORTKMgu9A+zF+A61Zz5A"
    static let toneMappingKey = "Lcu6Zck+C/+AMO8qULacDw"
    static let hdrDeferredProcessingKey = "JkZlE8z9YwHjE1hnbMhcgA"
    static let spatialOverCaptureKey = "SjQQ07G8UacM7E69G7dPbg"
    static let stereoAudioRecKey = "YlK+0xmxNWhNn/+r8SM8kA"
    static let p3VideoRecKey = "1eBwtCIwbIDdC80wiyzfow"
    static let touchSensitiveCamControlKey = "lyJZrSDc8J8eQ5Zb7A1Rvw"
    static let hardwareDetentsKey = "V9pLLbPQhyb75bbdTioZVw"
    static let cameraHapticsKey = "XriAxQ+JY1z5nt5f3ftXVw"
    static let legacyBatteryInfoKey = "Rq0MF/w+gXM66Ii4fkWOzg"
    static let legacyDynamicEndOfChargeKey = "nfR1IphTGCaoFNu3NrCtWQ"
    static let highLuminanceAODKey = "7brdL5xrEUWnlF9C0kdg5A"
    static let aodFlipbookKey = "aoJSd/MXk7M40NgXTM6x+g"
    static let carPlay2Key = "PR+xeEtTAiUN0R25+EYGfw"
    static let touchDelivery120HzKey = "2OK50OGmkXM1ospsh766WQ"
    static let hearingAidEQKey = "SMgTCc2v9AU2ziIHRX8qww"
    static let hearingAidLEKey = "RyXm3yMC4ejlFvwlEI509w"
    static let hearingAidPowerRedKey = "u3c0R+31Df4SUTHrICQkTg"
    static let breathingDisturbancesKey = "e0HV2blYUDBk/MsMEQACNA"
    static let usBloodOxygenKey = "E4vGMChwcVRKD8hMVxnRvg"
    static let workoutUltraKey = "fu+4kyf8VcMBtgbMyJlLtg"
    static let timeInDaylightKey = "8gVfz9/8R1OtWBBtI0o/+Q"
    static let siriHubKey = "waGD2UTpntjbDXD1r3oALQ"
    static let onDeviceSiriKey = "O/7gbXWA5X2IRPVtDRU+bw"
    static let modelPruningKey = "m4xs4mhvxnAopYrApoLDMw"

    static let optionalFeatureSlotKeys: Set<String> = [
        audioMixKey, spatialAudioRecKey, spatialFaceTimeAudioKey, responsiveShutterKey, hypertensionNotifKey,
        appIntellKey, photosCleanUpKey, handwritingSynthKey, audioIntellKey, personalTranslatorKey,
        islandKey, aodKey, aoTimeKey, aodVibrancyKey, liquidGlassLowPowerKey, chargeLimKey, bootChimeKey,
        crashDetKey, pwmKey, appPencilKey, camButtonKey, actButtonKey, tapToWakeKey, stageMgrKey,
        ipadModeKey, medusaFloatingKey, medusaOverlayKey, medusaPinnedKey, medusaPipKey,
        shutterRelaxationKey, shutterKeyboardMutePreserveKey, shutterLegacyMutePreserveKey, concurrentHPLPMicsKey,
        photosLocalLightKey, toneMappingKey, hdrDeferredProcessingKey, spatialOverCaptureKey, stereoAudioRecKey,
        p3VideoRecKey, touchSensitiveCamControlKey, hardwareDetentsKey, cameraHapticsKey, legacyBatteryInfoKey,
        legacyDynamicEndOfChargeKey, highLuminanceAODKey, aodFlipbookKey, carPlay2Key, touchDelivery120HzKey,
        hearingAidEQKey, hearingAidLEKey, hearingAidPowerRedKey, breathingDisturbancesKey, usBloodOxygenKey,
        workoutUltraKey, timeInDaylightKey, siriHubKey, onDeviceSiriKey, modelPruningKey
    ]

    static let mediaHealthSlotKeys: Set<String> = [
        audioMixKey, spatialAudioRecKey, spatialFaceTimeAudioKey, responsiveShutterKey, hypertensionNotifKey
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
        if let wOff = wapiOffset { set.insert(wOff) }
        for (_, slotIdx) in featureSlotIndices where (0..<slotCount).contains(slotIdx) {
            set.insert(slotIdx * 8)
        }
        return set
    }

    /// Fallback cứng từ GestaltX — chỉ dùng khi runtime scan fail.
    static let originalProfile = MGCacheDataLayout(
        uuid: "7F1DF278-18B7-4E5A-8425-09E8830DE9AF",
        slotCount: 720, greenTeaIndex: 383, notGreenTeaIndex: 506, wapiIndex: 694,
        featureSlotIndices: [:]
    )

    private static let runtimeProfile: MGCacheDataLayout? = {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let image = MGCopyLoadedMobileGestaltImage() else { return nil }
        if case .success(let layout) = scan(image: image) { return layout }
        return nil
        #else
        return nil
        #endif
    }()

    func matches(_ dict: NSDictionary) -> Bool {
        guard (1...16384).contains(slotCount),
              (0..<slotCount).contains(greenTeaIndex),
              (0..<slotCount).contains(notGreenTeaIndex),
              greenTeaIndex != notGreenTeaIndex,
              let docUUID = dict["CacheUUID"] as? String,
              let data = dict["CacheData"] as? Data else { return false }
        if let wapiIndex, (!(0..<slotCount).contains(wapiIndex) || wapiIndex == greenTeaIndex || wapiIndex == notGreenTeaIndex) {
            return false
        }
        return uuid.caseInsensitiveCompare(docUUID) == .orderedSame && data.count == byteCount
    }

    static func resolve(in dict: NSDictionary) -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        for layout in [runtimeProfile, originalProfile].compactMap({ $0 }) {
            if layout.matches(dict) { return .success(layout) }
        }
        return .failure(.invalidCacheData("Unable to resolve cache layout for this plist."))
    }

    static func resolveFromLoadedLibrary() -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let image = MGCopyLoadedMobileGestaltImage() else {
            return .success(originalProfile)
        }
        switch scan(image: image) {
        case .success(let layout): return .success(layout)
        case .failure:             return .success(originalProfile)
        }
        #else
        return .success(originalProfile)
        #endif
    }

    static func scan(image: [String: Any]) -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        guard let strings = image["strings"] as? Data,
              let addressNum = image["stringAddress"] as? NSNumber,
              let constants = image["constants"] as? [Data] else {
            return .failure(.malformedImage("Missing required sections."))
        }
        return scan(strings: strings, stringAddress: addressNum.uint64Value, constants: constants)
    }

    static func scan(strings: Data, stringAddress: UInt64, constants: [Data],
                     extraUUIDs: [String] = []) -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        guard !strings.isEmpty, strings.count <= 32 * 1024 * 1024,
              stringAddress > 0, stringAddress <= UInt64.max - UInt64(strings.count),
              !constants.isEmpty, constants.count <= 8,
              constants.allSatisfy({ $0.count <= 32 * 1024 * 1024 }) else {
            return .failure(.malformedImage("Abnormal section size."))
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
                            valid = false; break
                        }
                    }
                    if valid {
                        let slice = UnsafeBufferPointer(start: base.advanced(by: tokenStart), count: 22)
                        hashByAddress[stringAddress + UInt64(tokenStart)] = String(decoding: slice, as: UTF8.self)
                    }
                } else if len == 36 {
                    let slice = UnsafeBufferPointer(start: base.advanced(by: tokenStart), count: 36)
                    if let text = String(bytes: slice, encoding: .utf8),
                       let parsed = UUID(uuidString: text) {
                        discoveredUUIDs.insert(parsed.uuidString.uppercased())
                    }
                }
                tokenStart = idx + 1
            }
        }
        guard !discoveredUUIDs.isEmpty else { return .failure(.uuidNotFound("No UUID found.")) }
        guard discoveredUUIDs.count == 1, let resolvedUUID = discoveredUUIDs.first else {
            return .failure(.ambiguousUUID("Multiple UUIDs (\(discoveredUUIDs.count))."))
        }

        var positiveIndices = Set<Int>()
        var targetIndices: [String: Set<Int>] = [:]
        var targetAlignments: [String: Set<String>] = [:]
        let requiredKeys: Set<String> = [greenTeaKey, notGreenTeaKey, wapiKey]

        for (secID, secData) in constants.enumerated() where secData.count >= 64 {
            let scanErr: MGCacheResolutionError? = secData.withUnsafeBytes { raw -> MGCacheResolutionError? in
                for off in stride(from: 0, through: secData.count - 64, by: 8) {
                    let rawPtr = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt64.self))
                    let canonicalPtr = rawPtr & 0x0000_7FFF_FFFF_FFFF
                    guard let key = hashByAddress[canonicalPtr] else { continue }
                    let slotIdx = Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3A, as: Int16.self)))
                    let queryType = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3C, as: UInt32.self))
                    guard (-1..<16384).contains(slotIdx), (1...11).contains(queryType) else { continue }
                    if slotIdx >= 0 { positiveIndices.insert(slotIdx) }
                    if requiredKeys.contains(key) {
                        guard queryType == 11, slotIdx >= 0 else {
                            return .invalidTargetDescriptor("Target key \(key) invalid.")
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
            if let scanErr { return .failure(scanErr) }
        }
        guard let maxSlotIndex = positiveIndices.max(), maxSlotIndex >= 1 else {
            return .failure(.descriptorTableNotFound("No descriptor table."))
        }
        let slotCount = maxSlotIndex + 1
        guard positiveIndices.count > slotCount / 2 else {
            return .failure(.sparseDescriptorTable("Sparse (\(positiveIndices.count)/\(slotCount))."))
        }
        guard let gtSet = targetIndices[greenTeaKey], gtSet.count == 1, let gtIdx = gtSet.first,
              let ngtSet = targetIndices[notGreenTeaKey], ngtSet.count == 1, let ngtIdx = ngtSet.first,
              gtIdx != ngtIdx,
              (0..<slotCount).contains(gtIdx),
              (0..<slotCount).contains(ngtIdx),
              let gtAlign = targetAlignments[greenTeaKey], gtAlign.count == 1,
              gtAlign == targetAlignments[notGreenTeaKey] else {
            return .failure(.invalidTargetDescriptor("Cannot uniquely determine green-tea slots."))
        }
        var resolvedWapiIdx: Int? = nil
        if let wapiSet = targetIndices[wapiKey] {
            guard wapiSet.count == 1, let wIdx = wapiSet.first,
                  (0..<slotCount).contains(wIdx), wIdx != gtIdx, wIdx != ngtIdx,
                  targetAlignments[wapiKey] == gtAlign else {
                return .failure(.invalidTargetDescriptor("wapi ambiguous."))
            }
            resolvedWapiIdx = wIdx
        }
        var resolvedFeatureSlots: [String: Int] = [:]
        var usedCoreSlots: Set<Int> = [gtIdx, ngtIdx]
        if let wIdx = resolvedWapiIdx { usedCoreSlots.insert(wIdx) }
        for fKey in optionalFeatureSlotKeys.sorted() {
            if let fSet = targetIndices[fKey], fSet.count == 1, let fIdx = fSet.first,
               (0..<slotCount).contains(fIdx), !usedCoreSlots.contains(fIdx),
               targetAlignments[fKey] == gtAlign {
                resolvedFeatureSlots[fKey] = fIdx
            }
        }
        return .success(MGCacheDataLayout(
            uuid: resolvedUUID,
            slotCount: slotCount,
            greenTeaIndex: gtIdx,
            notGreenTeaIndex: ngtIdx,
            wapiIndex: resolvedWapiIdx,
            featureSlotIndices: resolvedFeatureSlots
        ))
    }

    static func scanDescriptorsFromLoadedLibrary() -> [MGSlotDescriptorInfo] {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let image = MGCopyLoadedMobileGestaltImage(),
              let strings = image["strings"] as? Data,
              let addressNum = image["stringAddress"] as? NSNumber,
              let constants = image["constants"] as? [Data] else { return [] }

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
                            valid = false; break
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
                            expectedSecID = secID; expectedMod = off % 64; break
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

    func validatePlist(_ dict: NSDictionary, checkWapiSlot: Bool = false) -> Result<Data, MGCacheResolutionError> {
        guard let docUUID = dict["CacheUUID"] as? String,
              docUUID.caseInsensitiveCompare(uuid) == .orderedSame else {
            return .failure(.invalidCacheData("CacheUUID mismatch."))
        }
        guard let data = dict["CacheData"] as? Data, data.count == byteCount else {
            return .failure(.invalidCacheData("CacheData length mismatch."))
        }
        if checkWapiSlot, let wOff = wapiOffset {
            let v = data[wOff]
            guard v == 0 || v == 1 else {
                return .failure(.invalidCacheData("WAPI slot not boolean."))
            }
        }
        return .success(data)
    }

    func validateSingleBooleanSlot(_ slot: Int, in data: Data) -> Bool {
        guard slot >= 0, slot < slotCount, data.count == byteCount else { return false }
        guard data[slotCount * 8 + slot] == 1 else { return false }
        let v = data[slot * 8]
        return v == 0 || v == 1
    }
}