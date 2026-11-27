import Foundation
import Combine
import Darwin
import UIKit

struct zPatchItem: Identifiable, Codable {
    var id: UUID
    var bundleID: String
    var relativeDestPath: String
    var sourcePath: String
    var cachedDestinationPath: String?
    var backupPath: String?
    var hasInitialBackup: Bool
    var isEnabled: Bool
    var pendingRevert: Bool
    var createdDate: Date

    static let baseContainerPrefix = "/var/mobile/Containers/Data/Application/"

    private static let cacheLock = NSLock()
    private static var containerCache: [String: String] = [:]

    static func normalizedBundleID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("con.lemon.lvoverseas") == .orderedSame {
            return "com.lemon.lvoverseas"
        }
        return trimmed
    }

    var fastPreviewPath: String {
        if let cached = cachedDestinationPath, !cached.isEmpty {
            return cached
        }
        let cleanBundle = Self.normalizedBundleID(bundleID)
        let cleanRel = relativeDestPath.hasPrefix("/")
            ? String(relativeDestPath.dropFirst())
            : relativeDestPath

        if let mapped = zPatchStore.shared.cachedContainer(for: cleanBundle), !mapped.isEmpty {
            return cleanRel.isEmpty ? mapped : (mapped as NSString).appendingPathComponent(cleanRel)
        }

        if cleanBundle.hasPrefix("/") {
            return cleanRel.isEmpty ? cleanBundle : (cleanBundle as NSString).appendingPathComponent(cleanRel)
        }

        let baseRoot = Self.baseContainerPrefix + cleanBundle
        return cleanRel.isEmpty ? baseRoot : (baseRoot as NSString).appendingPathComponent(cleanRel)
    }

    static func resolveContainerRoot(for rawBundleID: String) -> String? {
        let bid = normalizedBundleID(rawBundleID)
        guard !bid.isEmpty else { return nil }

        if let saved = zPatchStore.shared.cachedContainer(for: bid), !saved.isEmpty {
            return saved
        }

        let key = bid.lowercased()
        cacheLock.lock()
        if let hit = containerCache[key], !hit.isEmpty {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        if bid.hasPrefix("/") {
            let std = (bid as NSString).standardizingPath
            return std
        }

        if bid.hasPrefix("group."),
           let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: bid) {
            return groupURL.path
        }

        var found: String? = nil

        autoreleasepool {
            if let allApps = try? JITEnableContext.shared.getAllAppsInfo() as? [String: Any] {
                var dictMap: [String: [String: Any]] = [:]
                for (k, v) in allApps {
                    if let d = v as? [String: Any] {
                        dictMap[k] = d
                        if k.caseInsensitiveCompare(bid) == .orderedSame,
                           let rawC = d["Container"] as? String, !rawC.isEmpty {
                            found = (rawC.replacingOccurrences(of: "file://", with: "") as NSString).standardizingPath
                        }
                    }
                }
                if !dictMap.isEmpty {
                    zPatchStore.shared.updateContainerCache(from: dictMap)
                }
            }

            if found == nil {
                let (_, hit) = CSStoreEngine.shared.lookupAppContainer(forBundleID: bid)
                if let hit, !hit.isEmpty {
                    found = (hit as NSString).standardizingPath
                }
            }

            if found == nil {
                let viaFS = fsHandlers.getContainerPath(at: FSURL.appContainers, forMatch: bid)
                if !viaFS.isEmpty {
                    found = (viaFS as NSString).standardizingPath
                }
            }
        }

        if let found, !found.isEmpty {
            cacheLock.lock()
            containerCache[key] = found
            cacheLock.unlock()
            zPatchStore.shared.registerContainer(bundleID: bid, containerPath: found)
        }

        return found
    }

    func resolveDestinationPath() -> String {
        let cleanBundle = Self.normalizedBundleID(bundleID)
        let cleanRel = relativeDestPath.hasPrefix("/")
            ? String(relativeDestPath.dropFirst())
            : relativeDestPath

        let root = Self.resolveContainerRoot(for: cleanBundle) ?? (Self.baseContainerPrefix + cleanBundle)
        if cleanRel.isEmpty { return root }
        return (root as NSString).appendingPathComponent(cleanRel)
    }

    init(
        id: UUID = UUID(),
        bundleID: String,
        relativeDestPath: String,
        sourcePath: String,
        cachedDestinationPath: String? = nil,
        backupPath: String? = nil,
        hasInitialBackup: Bool = false,
        isEnabled: Bool = true,
        pendingRevert: Bool = false
    ) {
        self.id = id
        self.bundleID = bundleID
        self.relativeDestPath = relativeDestPath
        self.sourcePath = sourcePath
        self.cachedDestinationPath = cachedDestinationPath
        self.backupPath = backupPath
        self.hasInitialBackup = hasInitialBackup
        self.isEnabled = isEnabled
        self.pendingRevert = pendingRevert
        self.createdDate = Date()
    }
}

final class zPatchStore: ObservableObject {
    static let shared = zPatchStore()

    static let itemsKey = "zPatchCustomItems_v3"
    static let enabledKey = "zPatchCustomEnabled"
    static let pendingApplyKey = "zPatchPendingApply"
    static let containerMapKey = "zPatchContainerMap_v1"
    static let appNameMapKey = "zPatchAppNameMap_v1"

    @Published var patches: [zPatchItem] = []
    @Published var isTweakEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isTweakEnabled, forKey: Self.enabledKey)
        }
    }
    @Published var pendingApply: Bool = false {
        didSet {
            UserDefaults.standard.set(pendingApply, forKey: Self.pendingApplyKey)
        }
    }

    private let mapLock = NSLock()
    private var containerMap: [String: String] = [:]
    private var appNameMap: [String: String] = [:]
    private var iconMemoryCache: [String: UIImage] = [:]
    private var hasLoaded = false

    init() {
        reloadFromStorage()
    }

    func ensureLoaded() {
        guard !hasLoaded else { return }
        reloadFromStorage()
    }

    func reloadFromStorage() {
        let ud = UserDefaults.standard
        isTweakEnabled = ud.bool(forKey: Self.enabledKey)
        pendingApply = ud.bool(forKey: Self.pendingApplyKey)

        if let savedMap = ud.dictionary(forKey: Self.containerMapKey) as? [String: String] {
            mapLock.lock()
            containerMap = savedMap
            mapLock.unlock()
        }

        if let savedNames = ud.dictionary(forKey: Self.appNameMapKey) as? [String: String] {
            mapLock.lock()
            appNameMap = savedNames
            mapLock.unlock()
        }

        if let data = ud.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([zPatchItem].self, from: data) {
            patches = decoded
        } else {
            patches = []
        }
        hasLoaded = true
    }

    func updateContainerCache(from appsInfo: [String: [String: Any]]) {
        var updatedContainers: [String: String] = [:]
        var updatedNames: [String: String] = [:]

        for (bid, info) in appsInfo {
            let key = bid.lowercased()
            if let raw = info["Container"] as? String, !raw.isEmpty {
                let clean = raw
                    .replacingOccurrences(of: "file://", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let std = (clean as NSString).standardizingPath
                if !std.isEmpty {
                    updatedContainers[key] = std
                }
            }
            let disp = (info["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bname = (info["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let disp, !disp.isEmpty {
                updatedNames[key] = disp
            } else if let bname, !bname.isEmpty {
                updatedNames[key] = bname
            }
        }

        guard !updatedContainers.isEmpty || !updatedNames.isEmpty else { return }

        mapLock.lock()
        for (k, v) in updatedContainers { containerMap[k] = v }
        for (k, v) in updatedNames { appNameMap[k] = v }
        let containerSnapshot = containerMap
        let nameSnapshot = appNameMap
        mapLock.unlock()

        UserDefaults.standard.set(containerSnapshot, forKey: Self.containerMapKey)
        UserDefaults.standard.set(nameSnapshot, forKey: Self.appNameMapKey)
    }

    func registerContainer(bundleID: String, containerPath: String) {
        let key = zPatchItem.normalizedBundleID(bundleID).lowercased()
        let clean = containerPath
            .replacingOccurrences(of: "file://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !clean.isEmpty else { return }

        mapLock.lock()
        containerMap[key] = (clean as NSString).standardizingPath
        let snapshot = containerMap
        mapLock.unlock()

        UserDefaults.standard.set(snapshot, forKey: Self.containerMapKey)
    }

    func registerAppMeta(bundleID: String, appName: String?, icon: UIImage?) {
        let key = zPatchItem.normalizedBundleID(bundleID).lowercased()
        guard !key.isEmpty else { return }

        mapLock.lock()
        if let name = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            appNameMap[key] = name
        }
        if let icon {
            iconMemoryCache[key] = icon
        }
        let nameSnapshot = appNameMap
        mapLock.unlock()

        UserDefaults.standard.set(nameSnapshot, forKey: Self.appNameMapKey)
    }

    func cachedAppName(for bundleID: String) -> String? {
        let key = zPatchItem.normalizedBundleID(bundleID).lowercased()
        mapLock.lock()
        let val = appNameMap[key]
        mapLock.unlock()
        return val
    }

    func cachedAppIcon(for bundleID: String) -> UIImage? {
        let key = zPatchItem.normalizedBundleID(bundleID).lowercased()
        mapLock.lock()
        let val = iconMemoryCache[key]
        mapLock.unlock()
        return val
    }

    func cachedContainer(for bundleID: String) -> String? {
        let key = zPatchItem.normalizedBundleID(bundleID).lowercased()
        mapLock.lock()
        let val = containerMap[key]
        mapLock.unlock()
        return val
    }

    func bundleIDForContainerUUID(_ uuid: String) -> String? {
        let target = uuid.lowercased()
        guard !target.isEmpty else { return nil }
        mapLock.lock()
        defer { mapLock.unlock() }
        for (bid, path) in containerMap {
            if (path as NSString).lastPathComponent.lowercased() == target {
                return bid
            }
        }
        return nil
    }

    func setTweakEnabledImmediate(_ enabled: Bool) {
        isTweakEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }

    func savePatches() {
        if let encoded = try? JSONEncoder().encode(patches) {
            UserDefaults.standard.set(encoded, forKey: Self.itemsKey)
        }
    }

    private func backupFileURL(for item: zPatchItem, targetPath: String) -> URL {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupDir = docsURL
            .appendingPathComponent("zPatchBackups", isDirectory: true)
            .appendingPathComponent(item.id.uuidString, isDirectory: true)
        let name = URL(fileURLWithPath: targetPath).lastPathComponent
        return backupDir.appendingPathComponent(name.isEmpty ? "target.bin" : name)
    }

    private func acquireAccessForTarget(_ targetPath: String, onLog: @escaping (String) -> Void) -> [String] {
        var acquired: [String] = []
        let parentDir = (targetPath as NSString).deletingLastPathComponent

        if !parentDir.isEmpty && parentDir != "/" {
            let (okDir, _, errDir) = wq.grantAccess(path: parentDir, requireWrite: true)
            if okDir {
                acquired.append(parentDir)
            } else {
                onLog("[zPatch] wq thư mục cha (\(parentDir)): \(errDir)")
            }
        }

        let (okFile, _, errFile) = wq.grantAccess(path: targetPath, requireWrite: true)
        if okFile {
            acquired.append(targetPath)
        } else {
            onLog("[zPatch] wq file đích (\(targetPath)): \(errFile)")
        }

        return acquired
    }

    private func releaseAcquired(_ paths: [String]) {
        for p in paths.reversed() {
            wq.releaseAccess(path: p)
        }
    }

    func saveNewPatch(bundleID: String, relativeDestPath: String, sourcePath: String, onLog: ((String) -> Void)? = nil) {
        let work = {
            var item = zPatchItem(
                bundleID: bundleID,
                relativeDestPath: relativeDestPath,
                sourcePath: sourcePath,
                hasInitialBackup: false,
                isEnabled: true,
                pendingRevert: false
            )
            let resolved = item.resolveDestinationPath()
            item.cachedDestinationPath = resolved

            self.patches.append(item)
            self.savePatches()
            onLog?("[zPatch] Đã thêm: \(resolved)")
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func updatePatch(_ patch: zPatchItem) {
        let work = {
            if let idx = self.patches.firstIndex(where: { $0.id == patch.id }) {
                var updated = patch
                updated.cachedDestinationPath = nil
                updated.cachedDestinationPath = updated.resolveDestinationPath()
                self.patches[idx] = updated
                self.savePatches()
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func removePatch(_ patch: zPatchItem) {
        if let backupPath = patch.backupPath {
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        patches.removeAll { $0.id == patch.id }
        savePatches()
    }

    func togglePatch(_ patch: zPatchItem) {
        if let idx = patches.firstIndex(where: { $0.id == patch.id }) {
            patches[idx].isEnabled.toggle()
            if patches[idx].isEnabled {
                patches[idx].pendingRevert = false
            }
            savePatches()
        }
    }

    func requestRevert(_ patch: zPatchItem) {
        guard let idx = patches.firstIndex(where: { $0.id == patch.id }) else { return }
        patches[idx].isEnabled = false
        patches[idx].pendingRevert = true
        savePatches()
        pendingApply = true
    }

    func saveChange(enableTweak: Bool) {
        setTweakEnabledImmediate(enableTweak)
        savePatches()
        pendingApply = true
    }

    func applyAllUsingWorseQuery(onLog: @escaping (String) -> Void) throws {
        let ud = UserDefaults.standard
        let enabledSnapshot = ud.bool(forKey: Self.enabledKey)
        var snapshot: [zPatchItem] = []
        if let data = ud.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([zPatchItem].self, from: data) {
            snapshot = decoded
        }

        let hasPendingRevert = snapshot.contains { $0.pendingRevert }
        guard enabledSnapshot || hasPendingRevert else {
            onLog("[zPatch] Tweak đang tắt và không có mục chờ Revert, bỏ qua.")
            DispatchQueue.main.async {
                self.pendingApply = false
            }
            return
        }

        let fm = FileManager.default
        for idx in snapshot.indices {
            let targetPath = snapshot[idx].resolveDestinationPath()
            snapshot[idx].cachedDestinationPath = targetPath
            let targetURL = URL(fileURLWithPath: targetPath)

            if snapshot[idx].pendingRevert {
                guard let backupPath = snapshot[idx].backupPath, fm.fileExists(atPath: backupPath) else {
                    onLog("[zPatch] Thiếu file backup để revert: \(targetPath)")
                    snapshot[idx].pendingRevert = false
                    continue
                }

                let leased = acquireAccessForTarget(targetPath, onLog: onLog)
                defer { releaseAcquired(leased) }

                do {
                    let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
                    let (ok, msg) = writePayload(backupData, to: targetURL)
                    if ok {
                        snapshot[idx].pendingRevert = false
                        onLog("[zPatch] Đã revert: \(targetPath)")
                    } else {
                        onLog("[zPatch] Revert lỗi (\(targetPath)): \(msg)")
                    }
                } catch {
                    onLog("[zPatch] Revert đọc backup lỗi: \(error.localizedDescription)")
                }
                continue
            }

            if enabledSnapshot && snapshot[idx].isEnabled {
                guard fm.fileExists(atPath: snapshot[idx].sourcePath) else {
                    onLog("[zPatch] File nguồn không tồn tại: \(snapshot[idx].sourcePath)")
                    continue
                }

                let leased = acquireAccessForTarget(targetPath, onLog: onLog)
                defer { releaseAcquired(leased) }

                do {
                    let sourceData = try Data(contentsOf: URL(fileURLWithPath: snapshot[idx].sourcePath))
                    let bURL = backupFileURL(for: snapshot[idx], targetPath: targetPath)

                    if (!snapshot[idx].hasInitialBackup || snapshot[idx].backupPath == nil),
                       fm.fileExists(atPath: targetPath),
                       let ogData = try? Data(contentsOf: targetURL) {
                        try? fm.createDirectory(at: bURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? ogData.write(to: bURL)
                        snapshot[idx].backupPath = bURL.path
                        snapshot[idx].hasInitialBackup = true
                    }

                    let (ok, msg) = writePayload(sourceData, to: targetURL)
                    if ok {
                        onLog("[zPatch] Đã ghi đè thành công: \(targetPath)")
                    } else {
                        onLog("[zPatch] Ghi đè thất bại (\(targetPath)): \(msg)")
                    }
                } catch {
                    onLog("[zPatch] Đọc file nguồn lỗi: \(error.localizedDescription)")
                }
            }
        }

        let finalSnapshot = snapshot
        if let encoded = try? JSONEncoder().encode(finalSnapshot) {
            ud.set(encoded, forKey: Self.itemsKey)
        }

        DispatchQueue.main.async {
            self.patches = finalSnapshot
            self.pendingApply = false
        }
    }

    private func writePayload(_ data: Data, to url: URL) -> (Bool, String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let (ok, err) = writeFileAtomically(data, to: url, allowEmpty: false)
            if ok { return (true, "OK") }
            let (okTemp, errTemp) = writeFileTemp(data, to: url)
            return (okTemp, okTemp ? "OK" : "\(err) | temp: \(errTemp)")
        } else {
            let (okTemp, errTemp) = writeFileTemp(data, to: url)
            return (okTemp, okTemp ? "OK" : errTemp)
        }
    }

    func clearPendingApply() {
        pendingApply = false
    }
}

struct zPatchEnsBundle: Codable {
    var version: Int = 1
    var bundleID: String
    var appName: String
    var relativeDestPath: String
    var containerPath: String
    var sourceFileName: String
    var payloadBase64: String?
    var iconPNGBase64: String?
    var isEnabled: Bool
    var createdDate: Date
}

extension zPatchStore {
    func buildEnsData(
        for patch: zPatchItem,
        appName: String? = nil,
        icon: UIImage? = nil
    ) -> Data? {
        let cleanBID = zPatchItem.normalizedBundleID(patch.bundleID)
        let resolvedName: String = {
            if let n = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                return n
            }
            if let cached = cachedAppName(for: cleanBID), !cached.isEmpty {
                return cached
            }
            return cleanBID.split(separator: ".").last.map(String.init) ?? cleanBID
        }()

        let payloadData: Data? = {
            guard !patch.sourcePath.isEmpty,
                  FileManager.default.fileExists(atPath: patch.sourcePath) else {
                return nil
            }
            return try? Data(contentsOf: URL(fileURLWithPath: patch.sourcePath), options: .mappedIfSafe)
        }()

        let resolvedContainer: String = {
            if let cached = patch.cachedDestinationPath, !cached.isEmpty {
                return (cached as NSString).deletingLastPathComponent
            }
            if let mapped = cachedContainer(for: cleanBID), !mapped.isEmpty {
                return mapped
            }
            return zPatchItem.baseContainerPrefix + cleanBID
        }()

        let safeIconData = (icon ?? cachedAppIcon(for: cleanBID))?.pngData()

        let bundleObj = zPatchEnsBundle(
            bundleID: cleanBID,
            appName: resolvedName,
            relativeDestPath: patch.relativeDestPath,
            containerPath: resolvedContainer,
            sourceFileName: URL(fileURLWithPath: patch.sourcePath).lastPathComponent,
            payloadBase64: payloadData?.base64EncodedString(),
            iconPNGBase64: safeIconData?.base64EncodedString(),
            isEnabled: patch.isEnabled,
            createdDate: patch.createdDate
        )

        return try? JSONEncoder().encode(bundleObj)
    }

    func exportEnsFile(
        for patch: zPatchItem,
        appName: String? = nil,
        icon: UIImage? = nil
    ) -> Result<URL, Error> {
        guard let data = buildEnsData(for: patch, appName: appName, icon: icon) else {
            return .failure(NSError(
                domain: "zPatch.ens",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Không thể mã hoá gói .ens (kiểm tra file nguồn)."]
            ))
        }

        let fm = FileManager.default
        let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportDir = docsURL.appendingPathComponent("zPatchExports", isDirectory: true)

        do {
            try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
            let rawBID = zPatchItem.normalizedBundleID(patch.bundleID)
            let safeBID = (rawBID.isEmpty ? "patch" : rawBID)
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            let outURL = exportDir.appendingPathComponent("\(safeBID).ens")

            if fm.fileExists(atPath: outURL.path) {
                try fm.removeItem(at: outURL)
            }
            try data.write(to: outURL, options: .atomic)

            guard fm.fileExists(atPath: outURL.path) else {
                return .failure(NSError(
                    domain: "zPatch.ens",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Ghi file .ens thất bại."]
                ))
            }
            return .success(outURL)
        } catch {
            return .failure(error)
        }
    }

    @discardableResult
    func importEnsAndApplyNow(from fileURL: URL, onLog: ((String) -> Void)? = nil) -> Result<zPatchEnsBundle, Error> {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { fileURL.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .failure(error)
        }

        let decoded: zPatchEnsBundle
        do {
            decoded = try JSONDecoder().decode(zPatchEnsBundle.self, from: data)
        } catch {
            return .failure(error)
        }

        let cleanBID = zPatchItem.normalizedBundleID(decoded.bundleID)
        guard !cleanBID.isEmpty else {
            return .failure(NSError(
                domain: "zPatch.ens",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Bundle ID trong file .ens trống"]
            ))
        }

        let decodedIcon = decoded.iconPNGBase64
            .flatMap { Data(base64Encoded: $0) }
            .flatMap { UIImage(data: $0) }
        registerAppMeta(bundleID: cleanBID, appName: decoded.appName, icon: decodedIcon)

        if !decoded.containerPath.isEmpty {
            registerContainer(bundleID: cleanBID, containerPath: decoded.containerPath)
        }

        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let payloadDir = docsURL
            .appendingPathComponent("zPatchCustomFiles", isDirectory: true)
            .appendingPathComponent("ens_\(cleanBID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        let fileName = decoded.sourceFileName.isEmpty
            ? URL(fileURLWithPath: decoded.relativeDestPath).lastPathComponent
            : decoded.sourceFileName
        let safeFileName = fileName.isEmpty ? "payload.bin" : fileName
        let savedSourceURL = payloadDir.appendingPathComponent(safeFileName)

        if let b64 = decoded.payloadBase64,
           let payloadData = Data(base64Encoded: b64) {
            try? payloadData.write(to: savedSourceURL, options: .atomic)
        }

        let relDest = decoded.relativeDestPath.isEmpty ? safeFileName : decoded.relativeDestPath
        var item = zPatchItem(
            bundleID: cleanBID,
            relativeDestPath: relDest,
            sourcePath: savedSourceURL.path,
            hasInitialBackup: false,
            isEnabled: true,
            pendingRevert: false
        )
        let resolvedDest = item.resolveDestinationPath()
        item.cachedDestinationPath = resolvedDest

        patches.removeAll {
            zPatchItem.normalizedBundleID($0.bundleID).caseInsensitiveCompare(cleanBID) == .orderedSame
                && $0.relativeDestPath.caseInsensitiveCompare(relDest) == .orderedSame
        }
        patches.insert(item, at: 0)
        setTweakEnabledImmediate(true)
        savePatches()
        pendingApply = true

        do {
            try applyAllUsingWorseQuery { msg in
                onLog?(msg)
            }
        } catch {
            return .failure(error)
        }

        return .success(decoded)
    }
}
