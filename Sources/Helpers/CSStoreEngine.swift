import Foundation

class CSStoreEngine {
    static let shared = CSStoreEngine()
    private init() {}

    static func normalizeVarPath(_ path: String) -> String {
        if path == "/private/var" { return "/var" }
        if path.hasPrefix("/private/var/") {
            return "/var/" + path.dropFirst("/private/var/".count)
        }
        return path
    }

    private static let launchServicesMapPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"
    private static let appDataContainerRoot = "/var/mobile/Containers/Data/Application"
    private static let appBundleContainerRoot = "/var/containers/Bundle/Application"

    private struct StoreSnapshot {
        let dataByBundleID: [String: String]
        let bundleByBundleID: [String: String]
    }

    private var cachedSnapshot: StoreSnapshot?
    private var cacheTimestamp: Date?
    private let cacheLock = NSLock()
    private let cacheTTL: TimeInterval = 30

    private static func cleanPath(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let stripped = raw
            .replacingOccurrences(of: "file://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        return normalizeVarPath((stripped as NSString).standardizingPath)
    }

    private static func extractBundlePath(from dict: [String: Any]) -> String? {
        if let raw = (dict["Path"] as? String)
            ?? (dict["BundleURL"] as? String)
            ?? (dict["BundlePath"] as? String) {
            if let cleaned = cleanPath(raw) {
                if cleaned.hasPrefix(appBundleContainerRoot) {
                    return cleaned
                }
                if cleaned.hasSuffix(".app") {
                    return (cleaned as NSString).deletingLastPathComponent
                }
                return cleaned
            }
        }
        return nil
    }

    private static func extractDataPath(from dict: [String: Any]) -> String? {
        guard let rawContainer = dict["Container"] as? String,
              let cleaned = cleanPath(rawContainer) else {
            return nil
        }
        if cleaned.hasPrefix("/") {
            return cleaned
        }
        return "\(appDataContainerRoot)/\(cleaned)"
    }

    private func loadSnapshot() -> StoreSnapshot? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedSnapshot,
           let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < cacheTTL {
            return cached
        }

        let candidates = [
            Self.launchServicesMapPath,
            "/private/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"
        ]

        var plistDict: [String: Any]?
        for path in candidates {
            if let data = FileManager.default.contents(atPath: path),
               let parsed = try? PropertyListSerialization.propertyList(
                   from: data,
                   options: [],
                   format: nil
               ) as? [String: Any] {
                plistDict = parsed
                break
            }
        }

        guard let plist = plistDict else { return nil }

        var dataMap: [String: String] = [:]
        var bundleMap: [String: String] = [:]

        for sectionKey in ["User", "System", "Internal"] {
            guard let section = plist[sectionKey] as? [String: Any] else { continue }
            for (bundleID, value) in section {
                let bid = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bid.isEmpty, let dict = value as? [String: Any] else { continue }

                if let dataPath = Self.extractDataPath(from: dict) {
                    dataMap[bid] = dataPath
                }
                if let bundlePath = Self.extractBundlePath(from: dict) {
                    bundleMap[bid] = bundlePath
                }
            }
        }

        let snap = StoreSnapshot(dataByBundleID: dataMap, bundleByBundleID: bundleMap)
        cachedSnapshot = snap
        cacheTimestamp = Date()
        return snap
    }

    func lookupAppContainer(forBundleID bundleID: String) -> (Bool, String?) {
        guard let snap = loadSnapshot() else { return (false, nil) }
        if let hit = snap.dataByBundleID[bundleID] {
            return (true, hit)
        }
        let match = snap.dataByBundleID.first { $0.key.caseInsensitiveCompare(bundleID) == .orderedSame }?.value
        return (true, match)
    }

    func lookupAppBundle(forBundleID bundleID: String) -> (Bool, String?) {
        guard let snap = loadSnapshot() else { return (false, nil) }
        if let hit = snap.bundleByBundleID[bundleID] {
            return (true, hit)
        }
        let match = snap.bundleByBundleID.first { $0.key.caseInsensitiveCompare(bundleID) == .orderedSame }?.value
        return (true, match)
    }

    func containerPaths(forRoot root: String) -> [String]? {
        let normalizedRoot = CSStoreEngine.normalizeVarPath(root)
        guard let snap = loadSnapshot() else { return nil }

        if normalizedRoot == Self.appDataContainerRoot {
            let paths = Array(Set(snap.dataByBundleID.values))
            return paths.isEmpty ? nil : paths
        }

        if normalizedRoot == Self.appBundleContainerRoot {
            let paths = Array(Set(snap.bundleByBundleID.values))
            return paths.isEmpty ? nil : paths
        }

        return nil
    }
}
