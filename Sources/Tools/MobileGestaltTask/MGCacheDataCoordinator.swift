import Foundation

struct MGDiffItem: Identifiable {
    let id: String
    let label: String
    let keyPath: String
    let beforeText: String
    let afterText: String
}

final class MGCacheDataCoordinator {
    static let shared = MGCacheDataCoordinator()
    private init() {}

    private var cachedLayout: MGCacheDataLayout?
    private let lock = NSLock()

    func libraryLayout() -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        lock.lock(); defer { lock.unlock() }
        if let l = cachedLayout { return .success(l) }
        let res = MGCacheDataLayout.resolveFromLoadedLibrary()
        if case .success(let l) = res { cachedLayout = l }
        return res
    }

    func resolveValidated(for dict: NSDictionary, checkWapiSlot: Bool = false)
        -> Result<(MGCacheDataLayout, Data), MGCacheResolutionError> {
        switch MGCacheDataLayout.resolve(in: dict) {
        case .failure(let e): return .failure(e)
        case .success(let layout):
            return layout.validatePlist(dict, checkWapiSlot: checkWapiSlot).map { (layout, $0) }
        }
    }

    /// Chỉ cho phép đổi byte tại các offset trong `permittedMutableOffsets`.
    /// Vi phạm → REJECT (chống bootloop).
    func validateTransition(from original: NSDictionary, to edited: NSDictionary) -> Result<Void, Error> {
        guard let originalData = original["CacheData"] as? Data,
              let editedData = edited["CacheData"] as? Data else {
            return .success(())
        }
        guard originalData != editedData else { return .success(()) }
        guard case .success(let layout) = MGCacheDataLayout.resolve(in: original),
              layout.matches(original), layout.matches(edited) else {
            return .failure(NSError(domain: "MGCacheDataCoordinator", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cache layout mismatch on edit."]))
        }
        let changed = Set(originalData.indices.filter { originalData[$0] != editedData[$0] })
        let permitted = layout.permittedMutableOffsets
        guard changed.isSubset(of: permitted) else {
            return .failure(NSError(domain: "MGCacheDataCoordinator", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Edit changes protected cache bytes."]))
        }
        return .success(())
    }

    func originalSlotValue(forKey key: String, layout: MGCacheDataLayout,
                           savedOriginalDict: NSDictionary?) -> Bool? {
        guard let slotIdx = layout.slotIndex(forKey: key) else { return nil }
        if let dict = savedOriginalDict,
           let data = dict["CacheData"] as? Data,
           data.count == layout.byteCount,
           layout.validateSingleBooleanSlot(slotIdx, in: data) {
            return data[slotIdx * 8] == 1
        }
        return nil
    }

    func diffDetails(from beforeDict: NSDictionary, to afterDict: NSDictionary) -> [MGDiffItem] {
        guard case .success(let layout) = MGCacheDataLayout.resolve(in: beforeDict),
              let fromData = try? layout.validatePlist(beforeDict).get(),
              let toData = try? layout.validatePlist(afterDict).get(),
              fromData.count == toData.count else { return [] }
        var items: [MGDiffItem] = []
        var seen: Set<Int> = []
        func check(_ key: String, _ idx: Int) {
            guard !seen.contains(idx) else { return }
            seen.insert(idx)
            let off = idx * 8
            if fromData[off] != toData[off] {
                items.append(MGDiffItem(
                    id: "slot.\(key)",
                    label: mgKeyDisplayName(key),
                    keyPath: "CacheData[\(idx)]",
                    beforeText: "\(fromData[off])",
                    afterText: "\(toData[off])"
                ))
            }
        }
        check(MGCacheDataLayout.greenTeaKey, layout.greenTeaIndex)
        check(MGCacheDataLayout.notGreenTeaKey, layout.notGreenTeaIndex)
        if let wIdx = layout.wapiIndex { check(MGCacheDataLayout.wapiKey, wIdx) }
        for (key, idx) in layout.featureSlotIndices { check(key, idx) }
        return items
    }

    func clearRecordedBaselines() {}
}
