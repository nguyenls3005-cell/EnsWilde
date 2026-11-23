import Foundation

final class GestaltStore {
    static let shared = GestaltStore()
    private init() {}

    var mgCurrentDict: NSMutableDictionary = NSMutableDictionary()

    func isSlotRulesNativeSatisfied(_ key: String) -> Bool {
        guard case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout(),
              let slotIdx = layout.slotIndex(forKey: key) else { return false }
        guard let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL),
              let ogData = ogDict["CacheData"] as? Data,
              ogData.count == layout.byteCount,
              layout.validateSingleBooleanSlot(slotIdx, in: ogData) else { return false }
        return ogData[slotIdx * 8] == 1
    }
}