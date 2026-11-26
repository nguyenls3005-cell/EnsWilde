import SwiftUI
import Foundation
import UIKit
import UniformTypeIdentifiers
import Combine
import Darwin

// MARK: - Picker Models & Scanner

struct PickerAppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let containerUUID: String
    let containerPath: String
    let icon: UIImage?
}

private enum PickerAppScanner {
    private static let fm = FileManager.default
    private static let launchServicesPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"

    private static func loadLaunchServicesMap() -> [String: (bundleID: String, name: String)] {
        guard let data = fm.contents(atPath: launchServicesPath),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let userApps = plist["User"] as? [String: Any] else {
            return [:]
        }

        var map: [String: (bundleID: String, name: String)] = [:]
        map.reserveCapacity(userApps.count)

        for (bundleID, rawValue) in userApps {
            guard let info = rawValue as? [String: Any],
                  let uuid = info["Container"] as? String,
                  !uuid.isEmpty else {
                continue
            }

            let displayName = (info["CFBundleDisplayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleName = (info["CFBundleName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = bundleID.split(separator: ".").last.map(String.init) ?? bundleID

            let resolvedName: String
            if let displayName, !displayName.isEmpty {
                resolvedName = displayName
            } else if let bundleName, !bundleName.isEmpty {
                resolvedName = bundleName
            } else {
                resolvedName = fallback
            }

            map[uuid.lowercased()] = (bundleID: bundleID, name: resolvedName)
        }

        return map
    }

    private static func resolveIcon(bundleID: String, containerPath: String) -> UIImage? {
        if let jitIcon = try? JITEnableContext.shared.getAppIcon(withBundleId: bundleID) {
            return jitIcon
        }

        let normContainer = CSStoreEngine.normalizeVarPath(containerPath)
        guard !normContainer.isEmpty else { return nil }

        let parentDir = (normContainer as NSString).deletingLastPathComponent
        if let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: parentDir),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let name = fileURL.lastPathComponent.lowercased()
                if name.contains("appicon") && name.hasSuffix(".png"),
                   let image = UIImage(contentsOfFile: fileURL.path) {
                    return image
                }
            }
        }

        return nil
    }

    static func scan(forceRefresh: Bool = false) -> [PickerAppItem] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let lsMap = loadLaunchServicesMap()
        let rawContainers = fsHandlers.getDirPaths(
            FSURL.appContainers.path,
            forceRefresh: forceRefresh
        )

        var items: [PickerAppItem] = []
        items.reserveCapacity(rawContainers.count)

        for rawPath in rawContainers {
            let normPath = CSStoreEngine.normalizeVarPath(rawPath)
            let uuid = URL(fileURLWithPath: normPath).lastPathComponent
            let lowerUUID = uuid.lowercased()

            var resolvedBID = lsMap[lowerUUID]?.bundleID
            let resolvedName = lsMap[lowerUUID]?.name

            if resolvedBID == nil || resolvedBID?.isEmpty == true {
                if let xattrBID = getBIDFromXattr(URL(fileURLWithPath: normPath))?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !xattrBID.isEmpty {
                    resolvedBID = xattrBID
                }
            }

            let finalBID = (resolvedBID?.isEmpty == false) ? resolvedBID! : uuid
            let finalName: String
            if let resolvedName, !resolvedName.isEmpty {
                finalName = resolvedName
            } else if finalBID != uuid {
                finalName = finalBID.split(separator: ".").last.map(String.init) ?? finalBID
            } else {
                finalName = uuid
            }

            let icon = resolveIcon(bundleID: finalBID, containerPath: normPath)

            items.append(
                PickerAppItem(
                    id: "\(finalBID)#\(uuid)",
                    name: finalName,
                    bundleID: finalBID,
                    containerUUID: uuid,
                    containerPath: normPath,
                    icon: icon
                )
            )
        }

        return items.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

@MainActor
private final class PickerScannerModel: ObservableObject {
    @Published var apps: [PickerAppItem] = []
    @Published var searchText: String = ""
    @Published var isScanning: Bool = false
    @Published var statusText: String = "Chưa quét"

    var filteredApps: [PickerAppItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.lowercased().contains(query) ||
            $0.bundleID.lowercased().contains(query) ||
            $0.containerUUID.lowercased().contains(query)
        }
    }

    func scan(forceRefresh: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        statusText = "Đang quét danh sách app..."

        Task.detached(priority: .userInitiated) {
            let result = PickerAppScanner.scan(forceRefresh: forceRefresh)
            await MainActor.run {
                self.apps = result
                self.isScanning = false
                self.statusText = "Đã tìm thấy \(result.count) app"
            }
        }
    }
}

struct AppPickerScannerView: View {
    @Binding var selectedBundleID: String
    var onSelectApp: ((PickerAppItem) -> Void)? = nil

    @StateObject private var model = PickerScannerModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App đã cài đặt (\(model.filteredApps.count))")
                            .font(.headline)
                        Text(model.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        model.scan(forceRefresh: true)
                    } label: {
                        HStack(spacing: 6) {
                            if model.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(model.isScanning ? "Đang quét" : "Quét lại")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isScanning)
                }
                .padding()
                .background(Color(.secondarySystemBackground))

                List(model.filteredApps) { app in
                    Button {
                        selectedBundleID = app.bundleID
                        if !app.containerPath.isEmpty {
                            zPatchStore.shared.registerContainer(
                                bundleID: app.bundleID,
                                containerPath: app.containerPath
                            )
                        }
                        onSelectApp?(app)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            PickerAppIcon(icon: app.icon)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(app.bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                Text(app.containerUUID)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $model.searchText, prompt: "Tìm tên app, Bundle ID hoặc UUID...")
            }
            .navigationTitle("Chọn từ danh sách")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                if model.apps.isEmpty {
                    model.scan(forceRefresh: false)
                }
            }
        }
    }
}

private struct PickerAppIcon: View {
    let icon: UIImage?

    var body: some View {
        Group {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 46, height: 46)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - zPatchItem & zPatchStore

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
            return (bid as NSString).standardizingPath
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

        if let data = ud.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([zPatchItem].self, from: data) {
            patches = decoded
        } else {
            patches = []
        }
        hasLoaded = true
    }

    func updateContainerCache(from appsInfo: [String: [String: Any]]) {
        var updated: [String: String] = [:]
        for (bid, info) in appsInfo {
            if let raw = info["Container"] as? String, !raw.isEmpty {
                let clean = raw
                    .replacingOccurrences(of: "file://", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let std = (clean as NSString).standardizingPath
                if !std.isEmpty {
                    updated[bid.lowercased()] = std
                }
            }
        }
        guard !updated.isEmpty else { return }

        mapLock.lock()
        for (k, v) in updated {
            containerMap[k] = v
        }
        let snapshot = containerMap
        mapLock.unlock()

        UserDefaults.standard.set(snapshot, forKey: Self.containerMapKey)
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

    func cachedContainer(for bundleID: String) -> String? {
        let key = zPatchItem.normalizedBundleID(bundleID).lowercased()
        mapLock.lock()
        let val = containerMap[key]
        mapLock.unlock()
        return val
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

// MARK: - .ens Export / Import & Apply Immediately

struct EnsPatchArchive: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var bundleID: String
    var relativeDestPath: String
    var containerPath: String
    var payloadBase64: String?
    var payloadFiles: [String: String]
    var notes: String
    var isEnabled: Bool
    var iconPNGBase64: String?
    var createdAt: Date
    var updatedAt: Date

    var uiIcon: UIImage? {
        guard let b64 = iconPNGBase64,
              !b64.isEmpty,
              let data = Data(base64Encoded: b64) else {
            return nil
        }
        return UIImage(data: data)
    }
}

@MainActor
final class EnsPatchArchiveStore: ObservableObject {
    static let shared = EnsPatchArchiveStore()

    @Published var packages: [EnsPatchArchive] = []
    @Published var statusMessage: String = ""

    private let storeURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.storeURL = docs.appendingPathComponent("ens_patch_archives_v1.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([EnsPatchArchive].self, from: data) else {
            return
        }
        packages = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(packages) else { return }
        _ = writeFileTemp(data, to: storeURL)
    }

    @discardableResult
    func createPackage(
        name: String,
        bundleID: String,
        relativeDestPath: String,
        sourcePath: String,
        icon: UIImage? = nil,
        notes: String = ""
    ) -> EnsPatchArchive? {
        let cleanBID = zPatchItem.normalizedBundleID(bundleID)
        guard !cleanBID.isEmpty else {
            statusMessage = "Bundle ID không hợp lệ"
            return nil
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (cleanBID.split(separator: ".").last.map(String.init) ?? cleanBID)
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        let containerPath = zPatchItem.resolveContainerRoot(for: cleanBID)
            ?? (zPatchItem.baseContainerPrefix + cleanBID)

        let resolvedIcon = icon ?? (try? JITEnableContext.shared.getAppIcon(withBundleId: cleanBID))
        let iconB64 = resolvedIcon?.pngData()?.base64EncodedString()

        var payloadB64: String? = nil
        var filesMap: [String: String] = [:]
        let cleanRel = relativeDestPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if !sourcePath.isEmpty,
           FileManager.default.fileExists(atPath: sourcePath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: sourcePath)) {
            let b64 = data.base64EncodedString()
            payloadB64 = b64
            let effectiveRel = cleanRel.isEmpty
                ? URL(fileURLWithPath: sourcePath).lastPathComponent
                : cleanRel
            filesMap[effectiveRel] = b64
        }

        let pkg = EnsPatchArchive(
            id: UUID().uuidString,
            name: cleanName,
            bundleID: cleanBID,
            relativeDestPath: cleanRel,
            containerPath: containerPath,
            payloadBase64: payloadB64,
            payloadFiles: filesMap,
            notes: notes,
            isEnabled: true,
            iconPNGBase64: iconB64,
            createdAt: Date(),
            updatedAt: Date()
        )

        packages.removeAll { $0.bundleID.caseInsensitiveCompare(cleanBID) == .orderedSame }
        packages.insert(pkg, at: 0)
        persist()
        statusMessage = "Đã tạo gói .ens cho \(cleanBID)"
        return pkg
    }

    func exportPackage(_ pkg: EnsPatchArchive) -> URL? {
        guard let encoded = try? JSONEncoder().encode(pkg) else {
            statusMessage = "Không thể mã hoá file .ens"
            return nil
        }
        let safeBID = pkg.bundleID.replacingOccurrences(of: "/", with: "_")
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeBID).ens")
        let (ok, err) = writeFileTemp(encoded, to: outURL)
        if ok {
            statusMessage = "Đã xuất \(outURL.lastPathComponent)"
            return outURL
        } else {
            statusMessage = "Export lỗi: \(err)"
            return nil
        }
    }

    @discardableResult
    func importAndApply(from url: URL) -> EnsPatchArchive? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(EnsPatchArchive.self, from: data) else {
            statusMessage = "File .ens không hợp lệ"
            return nil
        }

        let cleanBID = zPatchItem.normalizedBundleID(decoded.bundleID)
        let resolvedContainer = zPatchItem.resolveContainerRoot(for: cleanBID)
            ?? (decoded.containerPath.isEmpty ? (zPatchItem.baseContainerPrefix + cleanBID) : decoded.containerPath)

        zPatchStore.shared.registerContainer(bundleID: cleanBID, containerPath: resolvedContainer)

        let active = EnsPatchArchive(
            id: UUID().uuidString,
            name: decoded.name.isEmpty
                ? (cleanBID.split(separator: ".").last.map(String.init) ?? cleanBID)
                : decoded.name,
            bundleID: cleanBID,
            relativeDestPath: decoded.relativeDestPath,
            containerPath: resolvedContainer,
            payloadBase64: decoded.payloadBase64,
            payloadFiles: decoded.payloadFiles,
            notes: decoded.notes,
            isEnabled: true,
            iconPNGBase64: decoded.iconPNGBase64,
            createdAt: decoded.createdAt,
            updatedAt: Date()
        )

        applyImmediately(active)

        packages.removeAll { $0.bundleID.caseInsensitiveCompare(cleanBID) == .orderedSame }
        packages.insert(active, at: 0)
        persist()
        statusMessage = "Đã import & áp dụng ngay: \(active.name) (\(active.bundleID))"
        return active
    }

    func applyImmediately(_ pkg: EnsPatchArchive) {
        let base = CSStoreEngine.normalizeVarPath(pkg.containerPath)
        guard !base.isEmpty else { return }

        zPatchStore.shared.registerContainer(bundleID: pkg.bundleID, containerPath: base)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let payloadDir = docs.appendingPathComponent("zPatchImportedPayloads/\(pkg.bundleID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        var entriesToWrite: [(rel: String, data: Data)] = []
        for (relPath, b64) in pkg.payloadFiles {
            if let d = Data(base64Encoded: b64) {
                entriesToWrite.append((relPath, d))
            }
        }
        if entriesToWrite.isEmpty,
           let b64 = pkg.payloadBase64,
           let d = Data(base64Encoded: b64),
           !pkg.relativeDestPath.isEmpty {
            entriesToWrite.append((pkg.relativeDestPath, d))
        }

        for entry in entriesToWrite {
            let cleanRel = entry.rel.hasPrefix("/") ? String(entry.rel.dropFirst()) : entry.rel
            let localFileURL = payloadDir.appendingPathComponent((cleanRel as NSString).lastPathComponent)
            _ = writeFileTemp(entry.data, to: localFileURL)

            let destPath = (base as NSString).appendingPathComponent(cleanRel)
            let parentDir = (destPath as NSString).deletingLastPathComponent
            _ = wq.grantAccess(path: parentDir, requireWrite: true, allowFsgetpathFallback: true)
            _ = wq.grantAccess(path: destPath, requireWrite: true, allowFsgetpathFallback: true)
            try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            _ = writeFileTemp(entry.data, to: URL(fileURLWithPath: destPath))

            zPatchStore.shared.saveNewPatch(
                bundleID: pkg.bundleID,
                relativeDestPath: cleanRel,
                sourcePath: localFileURL.path
            )
        }

        zPatchStore.shared.setTweakEnabledImmediate(true)
        zPatchStore.shared.saveChange(enableTweak: true)
    }

    func delete(_ pkg: EnsPatchArchive) {
        packages.removeAll { $0.id == pkg.id }
        persist()
    }
}

// MARK: - zPatchCustomView

struct zPatchCustomView: View {
    @ObservedObject private var patchStore = zPatchStore.shared
    @ObservedObject private var ensStore = EnsPatchArchiveStore.shared
    var onNavigateToApply: (() -> Void)? = nil

    @State private var draftEnabled: Bool = UserDefaults.standard.bool(forKey: zPatchStore.enabledKey)

    @State private var showAddSheet = false
    @State private var showAppPicker = false
    @State private var showEnsImporter = false
    @State private var shareURL: URL? = nil

    @State private var newAppName: String = ""
    @State private var newAppIcon: UIImage? = nil
    @State private var newBundleID: String = ""
    @State private var newRelativeDest: String = ""
    @State private var newSourcePath: String = ""
    @State private var showDocumentPicker = false

    @State private var showSavedPopup = false
    @State private var popupMessage = "Đã lưu thay đổi. Bạn có thể tự chuyển sang tab Apply để áp dụng."
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var editingPatch: zPatchItem? = nil

    var body: some View {
        Form {
            Section(header: Text("zPatch Custom")) {
                Toggle(L("enable_tweak"), isOn: Binding(
                    get: { draftEnabled },
                    set: { newValue in
                        draftEnabled = newValue
                        patchStore.setTweakEnabledImmediate(newValue)
                    }
                ))

                Button {
                    patchStore.saveChange(enableTweak: draftEnabled)
                    UserDefaults.standard.set(true, forKey: "ShowApplyTab")
                    popupMessage = draftEnabled
                        ? "Đã bật và lưu thay đổi. Bạn có thể tự chuyển sang tab Apply để áp dụng."
                        : "Đã tắt và lưu thay đổi. Bạn có thể tự chuyển sang tab Apply để áp dụng."
                    showSavedPopup = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Change")
                            .fontWeight(.semibold)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        showEnsImporter = true
                    } label: {
                        Label("Import .ens", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if !ensStore.statusMessage.isEmpty {
                        Text(ensStore.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section(header: Text(L("section_patch_list"))) {
                Button("Add New Patch") {
                    resetForm()
                    showAddSheet = true
                }

                if !patchStore.patches.isEmpty {
                    ForEach(patchStore.patches) { patch in
                        patchRow(patch)
                    }
                }
            }

            Section(header: Text(L("section_info"))) {
                Text("Bật/tắt Enable Tweak rồi bấm Save Change để lưu. Sau khi hiện thông báo, bạn tự chuyển qua tab Apply để áp dụng.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .headerProminence(.increased)
        .navigationTitle("zPatch Custom")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            patchStore.ensureLoaded()
            draftEnabled = patchStore.isTweakEnabled
        }
        .sheet(isPresented: $showAddSheet) {
            addPatchSheet
        }
        .fileImporter(
            isPresented: $showEnsImporter,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let fileURL = urls.first {
                _ = ensStore.importAndApply(from: fileURL)
                patchStore.reloadFromStorage()
                draftEnabled = patchStore.isTweakEnabled
                popupMessage = ensStore.statusMessage
                showSavedPopup = true
            }
        }
        .sheet(item: Binding(
            get: { shareURL.map { CustomShareItem(url: $0) } },
            set: { shareURL = $0?.url }
        )) { wrapper in
            CustomShareSheet(activityItems: [wrapper.url])
        }
        .alert("Thông báo", isPresented: $showSavedPopup) {
            Button("OK", role: .cancel) {
                showSavedPopup = false
            }
        } message: {
            Text(popupMessage)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func patchRow(_ patch: zPatchItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { patch.isEnabled },
                    set: { _ in patchStore.togglePatch(patch) }
                ))
                .labelsHidden()

                VStack(alignment: .leading, spacing: 3) {
                    Text(patch.bundleID.isEmpty ? "Unknown Bundle" : patch.bundleID)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    Text("File nguồn: \(patch.sourcePath.isEmpty ? "Chưa chọn" : (patch.sourcePath.split(separator: "/").last.map(String.init) ?? "Đã chọn"))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("→ \(patch.fastPreviewPath)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if patch.pendingRevert {
                        Text("Trạng thái: Đã chọn Revert — qua tab Apply để khôi phục")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                    } else if patch.hasInitialBackup && patch.backupPath != nil {
                        Text("Backup lần đầu: Đã lưu")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    editPatch(patch)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button {
                    if let pkg = ensStore.createPackage(
                        name: patch.bundleID,
                        bundleID: patch.bundleID,
                        relativeDestPath: patch.relativeDestPath,
                        sourcePath: patch.sourcePath
                    ), let url = ensStore.exportPackage(pkg) {
                        shareURL = url
                    }
                } label: {
                    Label("Export .ens", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Button {
                    patchStore.requestRevert(patch)
                    popupMessage = "Đã chọn Revert cho \(patch.bundleID). Bạn có thể tự chuyển qua tab Apply để khôi phục về patch cũ."
                    showSavedPopup = true
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Spacer()

                Button(role: .destructive) {
                    patchStore.removePatch(patch)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }

    private var addPatchSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Đích (Tự động ghép /var/mobile/Containers/Data/Application/)")) {
                    HStack(spacing: 8) {
                        TextField("Bundle ID (vd: com.lemon.lvoverseas)", text: $newBundleID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            showAppPicker = true
                        } label: {
                            Label("Chọn từ danh sách", systemImage: "list.bullet.rectangle")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }

                    TextField("File đích (vd: Library/Cookies/Cookies.binarycookies)", text: $newRelativeDest)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !newBundleID.isEmpty || !newRelativeDest.isEmpty {
                        let preview = zPatchItem(
                            bundleID: newBundleID,
                            relativeDestPath: newRelativeDest,
                            sourcePath: newSourcePath
                        ).fastPreviewPath
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section(header: Text("File cần thay đổi")) {
                    Button {
                        showDocumentPicker = true
                    } label: {
                        HStack {
                            Text(newSourcePath.isEmpty ? "Chọn file nguồn" : (newSourcePath.split(separator: "/").last.map(String.init) ?? "Đã chọn"))
                                .foregroundStyle(newSourcePath.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "doc.badge.plus")
                        }
                    }
                }

                Section(header: Text(L("section_actions"))) {
                    Button(editingPatch != nil ? "Update Patch" : "Save Patch") {
                        savePatch()
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty || newRelativeDest.trimmingCharacters(in: .whitespaces).isEmpty || newSourcePath.isEmpty)
                }
            }
            .navigationTitle(editingPatch != nil ? "Edit Patch" : "Add Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddSheet = false
                        resetForm()
                    }
                }
            }
            .sheet(isPresented: $showAppPicker) {
                AppPickerScannerView(selectedBundleID: $newBundleID) { picked in
                    newAppName = picked.name
                    newAppIcon = picked.icon
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                zPatchDocumentPicker(
                    onPick: { url in
                        importSourceURL(url)
                    },
                    onError: { msg in
                        errorMessage = msg
                        showErrorAlert = true
                    }
                )
            }
        }
    }

    private func importSourceURL(_ url: URL) {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let patchDir = docsURL.appendingPathComponent("zPatchCustomFiles", isDirectory: true)
        let destURL = patchDir.appendingPathComponent(url.lastPathComponent)

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.createDirectory(at: patchDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
            newSourcePath = destURL.path
        } catch {
            errorMessage = "Không thể import file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func savePatch() {
        let cleanBundle = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRel = newRelativeDest.trimmingCharacters(in: .whitespacesAndNewlines)

        if var editing = editingPatch {
            editing.bundleID = cleanBundle
            editing.relativeDestPath = cleanRel
            editing.sourcePath = newSourcePath
            patchStore.updatePatch(editing)
        } else {
            patchStore.saveNewPatch(
                bundleID: cleanBundle,
                relativeDestPath: cleanRel,
                sourcePath: newSourcePath
            )
        }

        _ = ensStore.createPackage(
            name: newAppName,
            bundleID: cleanBundle,
            relativeDestPath: cleanRel,
            sourcePath: newSourcePath,
            icon: newAppIcon
        )

        showAddSheet = false
        resetForm()
    }

    private func editPatch(_ patch: zPatchItem) {
        editingPatch = patch
        newBundleID = patch.bundleID
        newRelativeDest = patch.relativeDestPath
        newSourcePath = patch.sourcePath
        showAddSheet = true
    }

    private func resetForm() {
        newAppName = ""
        newAppIcon = nil
        newBundleID = ""
        newRelativeDest = ""
        newSourcePath = ""
        editingPatch = nil
    }
}

private struct CustomShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CustomShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct zPatchDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data, .content], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        var onError: (String) -> Void

        init(onPick: @escaping (URL) -> Void, onError: @escaping (String) -> Void) {
            self.onPick = onPick
            self.onError = onError
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onError("Không có file nào được chọn.")
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
