import Foundation

struct CSAppRecord: Identifiable, Hashable {
    var id: String { bundleID.lowercased() }
    let bundleID: String
    let name: String
    let dataContainerPath: String
    let bundleContainerPath: String
    let appBundlePath: String
}

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
        let recordsByLowerBID: [String: CSAppRecord]
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

    private static func cleanName(from dict: [String: Any], bundleID: String) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName", "itemName"] {
            if let val = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !val.isEmpty {
                return val
            }
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private static func extractDataPath(from dict: [String: Any]) -> String {
        guard let rawContainer = dict["Container"] as? String,
              let cleaned = cleanPath(rawContainer) else {
            return ""
        }
        if cleaned.hasPrefix("/") {
            return cleaned
        }
        return "\(appDataContainerRoot)/\(cleaned)"
    }

    private static func extractBundlePaths(from dict: [String: Any]) -> (containerPath: String, appPath: String) {
        let raw = (dict["Path"] as? String)
            ?? (dict["BundleURL"] as? String)
            ?? (dict["BundlePath"] as? String)
        guard let cleaned = cleanPath(raw) else {
            return ("", "")
        }

        if cleaned.hasSuffix(".app") {
            let parent = (cleaned as NSString).deletingLastPathComponent
            let cPath = parent.hasPrefix(appBundleContainerRoot) ? parent : ""
            return (cPath, cleaned)
        }

        if cleaned.hasPrefix(appBundleContainerRoot) {
            return (cleaned, "")
        }

        return ("", cleaned)
    }

    private static func readPlistDict(at path: String) -> [String: Any]? {
        let granted = wq.grantAccess(path: path, requireWrite: false, allowFsgetpathFallback: false)
        defer {
            if granted.0 {
                wq.releaseAccess(path: path)
            }
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              !data.isEmpty,
              let parsed = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            return nil
        }
        return parsed
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
            "/private/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist",
            "/var/mobile/Library/Caches/com.apple.mobile.installation.plist"
        ]

        var plistDict: [String: Any]?
        for path in candidates {
            if let parsed = Self.readPlistDict(at: path), !parsed.isEmpty {
                plistDict = parsed
                break
            }
        }

        guard let plist = plistDict else { return nil }

        var records: [String: CSAppRecord] = [:]
        var dataMap: [String: String] = [:]
        var bundleMap: [String: String] = [:]

        for sectionKey in ["User", "System", "Internal"] {
            guard let section = plist[sectionKey] as? [String: Any] else { continue }
            for (rawBID, value) in section {
                let bid = rawBID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bid.isEmpty, let dict = value as? [String: Any] else { continue }

                let lower = bid.lowercased()
                let title = Self.cleanName(from: dict, bundleID: bid)
                let dataPath = Self.extractDataPath(from: dict)
                let bundleInfo = Self.extractBundlePaths(from: dict)

                let prev = records[lower]
                let mergedName = title.isEmpty ? (prev?.name ?? bid) : title
                let mergedData = dataPath.isEmpty ? (prev?.dataContainerPath ?? "") : dataPath
                let mergedBundleContainer = bundleInfo.containerPath.isEmpty
                    ? (prev?.bundleContainerPath ?? "")
                    : bundleInfo.containerPath
                let mergedAppPath = bundleInfo.appPath.isEmpty
                    ? (prev?.appBundlePath ?? "")
                    : bundleInfo.appPath

                let record = CSAppRecord(
                    bundleID: prev?.bundleID ?? bid,
                    name: mergedName,
                    dataContainerPath: mergedData,
                    bundleContainerPath: mergedBundleContainer,
                    appBundlePath: mergedAppPath
                )
                records[lower] = record

                if !mergedData.isEmpty {
                    dataMap[record.bundleID] = mergedData
                }
                if !mergedBundleContainer.isEmpty {
                    bundleMap[record.bundleID] = mergedBundleContainer
                }
            }
        }

        let snap = StoreSnapshot(
            recordsByLowerBID: records,
            dataByBundleID: dataMap,
            bundleByBundleID: bundleMap
        )
        cachedSnapshot = snap
        cacheTimestamp = Date()
        return snap
    }

    func allAppRecords() -> [CSAppRecord] {
        guard let snap = loadSnapshot() else { return [] }
        return snap.recordsByLowerBID.values.sorted {
            let cmp = $0.name.localizedCaseInsensitiveCompare($1.name)
            if cmp == .orderedSame {
                return $0.bundleID.localizedCaseInsensitiveCompare($1.bundleID) == .orderedAscending
            }
            return cmp == .orderedAscending
        }
    }

    func record(forBundleID bundleID: String) -> CSAppRecord? {
        guard let snap = loadSnapshot() else { return nil }
        return snap.recordsByLowerBID[bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
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
