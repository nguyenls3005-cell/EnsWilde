import SwiftUI
import Foundation
import UIKit
import Combine

struct ScannedAppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let containerUUID: String
    let containerPath: String
    let icon: UIImage?

    static func == (lhs: ScannedAppEntry, rhs: ScannedAppEntry) -> Bool {
        lhs.id == rhs.id && lhs.bundleID == rhs.bundleID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(bundleID)
    }
}

private enum AppScannerEngine {
    private static let fm = FileManager.default
    private static let targetRoot = CSStoreEngine.normalizeVarPath(FSURL.appContainers.path)

    private static func normalizePath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let std = (trimmed as NSString).standardizingPath
        var norm = CSStoreEngine.normalizeVarPath(std)
        while norm.count > 1 && norm.hasSuffix("/") {
            norm.removeLast()
        }
        return norm
    }

    private static func isUUIDString(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: trimmed) != nil
    }

    private static func cleanBundleID(_ raw: String?, uuid: String) -> String? {
        guard let raw else { return nil }
        let norm = zPatchItem.normalizedBundleID(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !norm.isEmpty else { return nil }
        if norm.caseInsensitiveCompare(uuid) == .orderedSame { return nil }
        if isUUIDString(norm) { return nil }
        return norm
    }

    private static func prettifyAppName(
        from bundleID: String,
        uuid: String,
        detectedName: String?
    ) -> String {
        if let cached = zPatchStore.shared.cachedAppName(for: bundleID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty,
           !isUUIDString(cached),
           cached.caseInsensitiveCompare(uuid) != .orderedSame {
            return cached
        }

        if let det = detectedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !det.isEmpty,
           !isUUIDString(det),
           det.caseInsensitiveCompare(uuid) != .orderedSame {
            return det
        }

        if isUUIDString(bundleID) || bundleID.caseInsensitiveCompare(uuid) == .orderedSame {
            return "App (\(String(uuid.prefix(8))))"
        }

        let parts = bundleID.split(separator: ".").map(String.init)
        let stopWords: Set<String> = [
            "com", "net", "org", "io", "app", "ios", "mobile",
            "client", "iphone", "ipad", "free", "vip", "pro", "official",
            "apple", "cn", "vn", "jp", "kr"
        ]

        for part in parts.reversed() {
            let low = part.lowercased()
            if !stopWords.contains(low), low.count >= 2 {
                return part.capitalized
            }
        }

        return parts.last?.capitalized ?? bundleID
    }

    private static func grantReadAccess(at path: String, allowFsgetpathFallback: Bool = true) -> Bool {
        let norm = normalizePath(path)
        guard !norm.isEmpty else { return false }

        let granted = wq.grantAccess(path: norm, requireWrite: false, allowFsgetpathFallback: allowFsgetpathFallback)
        if granted.0 {
            return true
        }

        if allowFsgetpathFallback {
            let (fsHandle, _) = NativeWorseQuery.shared.grantViaFsgetpath(
                targetFile: norm,
                requireWrite: false,
                allowRecursiveWq: false
            )
            if fsHandle >= 0 {
                return true
            }
        }

        return false
    }

    private static func releaseReadAccess(at path: String) {
        let norm = normalizePath(path)
        guard !norm.isEmpty else { return }
        if wq.hasActiveAccess(path: norm) {
            wq.releaseAccess(path: norm)
        }
    }

    private static func readFileDataWithWq(at fullPath: String) -> Data? {
        let norm = normalizePath(fullPath)
        guard !norm.isEmpty else { return nil }

        let didGrant = grantReadAccess(at: norm, allowFsgetpathFallback: true)
        defer { if didGrant { releaseReadAccess(at: norm) } }

        if let data = fm.contents(atPath: norm), !data.isEmpty {
            return data
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: norm), options: .uncached), !data.isEmpty {
            return data
        }
        return nil
    }

    private static func extractMetaFromPlistData(_ data: Data) -> (bundleID: String?, appName: String?) {
        guard let obj = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return (nil, nil)
        }

        let bidKeys = [
            "MCMMetadataIdentifier",
            "CFBundleIdentifier",
            "applicationIdentifier",
            "BundleIdentifier",
            "Identifier",
            "com.apple.containermanagerd.metadata.bundle-identifier"
        ]
        var foundBID: String? = nil
        for k in bidKeys {
            if let s = obj[k] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty && !isUUIDString(t) {
                    foundBID = t
                    break
                }
            }
        }

        let nameKeys = [
            "CFBundleDisplayName",
            "CFBundleName",
            "itemName",
            "DisplayName",
            "Name"
        ]
        var foundName: String? = nil
        for k in nameKeys {
            if let s = obj[k] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty && !isUUIDString(t) {
                    foundName = t
                    break
                }
            }
        }

        return (foundBID, foundName)
    }

    private static func inspectContainerFiles(at containerPath: String, uuid: String) -> (bundleID: String?, appName: String?) {
        let normContainer = normalizePath(containerPath)
        let didGrant = grantReadAccess(at: normContainer, allowFsgetpathFallback: true)
        defer { if didGrant { releaseReadAccess(at: normContainer) } }

        let directCandidates = [
            ".com.apple.mobile_container_manager.metadata.plist",
            "com.apple.mobile_container_manager.metadata.plist",
            "Library/Preferences/.GlobalPreferences.plist"
        ]

        var bestBID: String? = nil
        var bestName: String? = nil

        for rel in directCandidates {
            let full = (normContainer as NSString).appendingPathComponent(rel)
            if let data = readFileDataWithWq(at: full) {
                let extracted = extractMetaFromPlistData(data)
                if bestBID == nil, let b = cleanBundleID(extracted.bundleID, uuid: uuid) {
                    bestBID = b
                }
                if bestName == nil, let n = extracted.appName, !n.isEmpty {
                    bestName = n
                }
                if bestBID != nil && bestName != nil {
                    return (bestBID, bestName)
                }
            }
        }

        func walkPlist(dir: String, depth: Int) {
            guard depth <= 2 else { return }
            let normDir = normalizePath(dir)
            let gDir = grantReadAccess(at: normDir, allowFsgetpathFallback: true)
            defer { if gDir { releaseReadAccess(at: normDir) } }

            guard let names = try? fm.contentsOfDirectory(atPath: normDir) else { return }

            for name in names {
                if name == "." || name == ".." { continue }
                let full = normalizePath((normDir as NSString).appendingPathComponent(name))
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    if bestBID == nil || bestName == nil {
                        walkPlist(dir: full, depth: depth + 1)
                    }
                } else if name.lowercased().hasSuffix(".plist") {
                    if let attrs = try? fm.attributesOfItem(atPath: full),
                       let size = (attrs[.size] as? NSNumber)?.intValue,
                       size > 0, size < 256_000,
                       let data = readFileDataWithWq(at: full) {
                        let extracted = extractMetaFromPlistData(data)
                        if bestBID == nil, let b = cleanBundleID(extracted.bundleID, uuid: uuid) {
                            bestBID = b
                        }
                        if bestName == nil, let n = extracted.appName, !n.isEmpty {
                            bestName = n
                        }
                    }
                }

                if bestBID != nil && bestName != nil {
                    return
                }
            }
        }

        if bestBID == nil || bestName == nil {
            walkPlist(dir: normContainer, depth: 1)
        }

        return (bestBID, bestName)
    }

    private static func buildKnownMaps() -> (uuidToBID: [String: String], bidToName: [String: String]) {
        var uuidToBID: [String: String] = [:]
        var bidToName: [String: String] = [:]

        func indexPath(_ rawPath: String, bid: String) {
            let cleanBID = zPatchItem.normalizedBundleID(bid)
            guard !cleanBID.isEmpty, !isUUIDString(cleanBID) else { return }
            let norm = normalizePath(rawPath)
            guard !norm.isEmpty else { return }
            let last = ((norm as NSString).lastPathComponent).lowercased()
            if isUUIDString(last) {
                uuidToBID[last] = cleanBID
            }
        }

        for rec in CSStoreEngine.shared.allAppRecords() {
            let bid = zPatchItem.normalizedBundleID(rec.bundleID)
            guard !bid.isEmpty else { continue }
            let cleanName = rec.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanName.isEmpty && cleanName.caseInsensitiveCompare(bid) != .orderedSame {
                bidToName[bid.lowercased()] = cleanName
            }
            if !rec.dataContainerPath.isEmpty {
                indexPath(rec.dataContainerPath, bid: bid)
            } else if let (_, fastContainer) = CSStoreEngine.shared.lookupAppContainer(forBundleID: bid),
                      let fastContainer, !fastContainer.isEmpty {
                indexPath(fastContainer, bid: bid)
            }
        }

        for patch in zPatchStore.shared.patches {
            let bid = zPatchItem.normalizedBundleID(patch.bundleID)
            guard !bid.isEmpty else { continue }
            if let cached = zPatchStore.shared.cachedContainer(for: bid) {
                indexPath(cached, bid: bid)
            }
            if let fast = patch.cachedDestinationPath, !fast.isEmpty {
                let normFast = normalizePath(fast)
                if normFast.contains("/Containers/Data/Application/") {
                    var cur = normFast
                    while cur != "/" && cur.count > 1 {
                        let base = (cur as NSString).lastPathComponent
                        if isUUIDString(base) {
                            uuidToBID[base.lowercased()] = bid
                            break
                        }
                        cur = (cur as NSString).deletingLastPathComponent
                    }
                }
            }
        }

        if let savedMap = UserDefaults.standard.dictionary(forKey: zPatchStore.containerMapKey) as? [String: String] {
            for (k, v) in savedMap {
                indexPath(v, bid: k)
            }
        }

        return (uuidToBID, bidToName)
    }

    private static func listAllContainerPaths(forceRefresh: Bool) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        let roots = [
            targetRoot,
            "/var/mobile/Containers/Data/Application",
            "/private/var/mobile/Containers/Data/Application"
        ]

        for root in roots {
            let normRoot = normalizePath(root)
            guard !normRoot.isEmpty else { continue }

            let didGrant = grantReadAccess(at: normRoot, allowFsgetpathFallback: true)
            defer { if didGrant { releaseReadAccess(at: normRoot) } }

            if let names = try? fm.contentsOfDirectory(atPath: normRoot), !names.isEmpty {
                for name in names {
                    let full = normalizePath((normRoot as NSString).appendingPathComponent(name))
                    let key = full.lowercased()
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue, seen.insert(key).inserted {
                        result.append(full)
                    }
                }
            }
        }

        if let storePaths = CSStoreEngine.shared.containerPaths(forRoot: targetRoot) {
            for p in storePaths {
                let norm = normalizePath(p)
                let key = norm.lowercased()
                if !norm.isEmpty && seen.insert(key).inserted {
                    result.append(norm)
                }
            }
        }

        if result.count < 5 {
            let leaked = fsHandlers.getDirPaths(targetRoot, forceRefresh: forceRefresh)
            for p in leaked {
                let norm = normalizePath(p)
                let key = norm.lowercased()
                if !norm.isEmpty && seen.insert(key).inserted {
                    result.append(norm)
                }
            }
        }

        return result
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let maps = buildKnownMaps()
        let containerPaths = listAllContainerPaths(forceRefresh: forceRefresh)

        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(containerPaths.count)

        for rawPath in containerPaths {
            autoreleasepool {
                let path = normalizePath(rawPath)
                let uuid = (path as NSString).lastPathComponent
                let uuidLower = uuid.lowercased()
                let url = URL(fileURLWithPath: path)

                let fromStore = cleanBundleID(
                    zPatchStore.shared.bundleIDForContainerUUID(uuid),
                    uuid: uuid
                )
                let fromMap = cleanBundleID(
                    maps.uuidToBID[uuidLower],
                    uuid: uuid
                )

                let didGrantXattr = grantReadAccess(at: path, allowFsgetpathFallback: true)
                let fromXattr = cleanBundleID(
                    getBIDFromXattr(url),
                    uuid: uuid
                )
                if didGrantXattr {
                    releaseReadAccess(at: path)
                }

                var resolvedBID = fromStore ?? fromMap ?? fromXattr
                var detectedName = resolvedBID.flatMap { maps.bidToName[$0.lowercased()] }

                if resolvedBID == nil || detectedName == nil {
                    let fileMeta = inspectContainerFiles(at: path, uuid: uuid)
                    if resolvedBID == nil {
                        resolvedBID = cleanBundleID(fileMeta.bundleID, uuid: uuid)
                    }
                    if detectedName == nil {
                        detectedName = fileMeta.appName
                    }
                }

                let finalBID = resolvedBID ?? uuid
                let finalName = prettifyAppName(
                    from: finalBID,
                    uuid: uuid,
                    detectedName: detectedName
                )

                if resolvedBID != nil {
                    zPatchStore.shared.registerContainer(bundleID: finalBID, containerPath: path)
                }
                zPatchStore.shared.registerAppMeta(bundleID: finalBID, appName: finalName, icon: nil)

                entries.append(
                    ScannedAppEntry(
                        id: "\(uuidLower)_\(finalBID.lowercased())",
                        name: finalName,
                        bundleID: finalBID,
                        containerUUID: uuid,
                        containerPath: path,
                        icon: zPatchStore.shared.cachedAppIcon(for: finalBID)
                    )
                )
            }
        }

        return entries.sorted {
            let cmp = $0.name.localizedCaseInsensitiveCompare($1.name)
            if cmp == .orderedSame {
                return $0.bundleID.localizedCaseInsensitiveCompare($1.bundleID) == .orderedAscending
            }
            return cmp == .orderedAscending
        }
    }
}

@MainActor
private final class AppScannerVM: ObservableObject {
    @Published var apps: [ScannedAppEntry] = []
    @Published var searchText: String = ""
    @Published var isScanning: Bool = false
    @Published var statusMessage: String = "Chưa quét"

    var filteredApps: [ScannedAppEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.name.lowercased().contains(q) ||
            $0.bundleID.lowercased().contains(q) ||
            $0.containerUUID.lowercased().contains(q)
        }
    }

    func scan(forceRefresh: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "Đang quét danh sách app..."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = AppScannerEngine.scan(forceRefresh: forceRefresh)
            DispatchQueue.main.async {
                self.apps = result
                self.isScanning = false
                self.statusMessage = "Đã quét xong: \(result.count) app"
            }
        }
    }
}

struct AppPickerScannerView: View {
    @Binding var selectedBundleID: String
    var onSelectApp: ((ScannedAppEntry) -> Void)? = nil

    @StateObject private var vm = AppScannerVM()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Danh sách app (\(vm.filteredApps.count))")
                            .font(.subheadline.weight(.semibold))
                        Text(vm.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        vm.scan(forceRefresh: true)
                    } label: {
                        HStack(spacing: 5) {
                            if vm.isScanning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(vm.isScanning ? "Đang quét" : "Quét lại")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isScanning)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))

                List(vm.filteredApps) { app in
                    AppScannerRowButton(app: app) { resolvedIcon in
                        selectedBundleID = app.bundleID
                        if !app.containerPath.isEmpty {
                            zPatchStore.shared.registerContainer(
                                bundleID: app.bundleID,
                                containerPath: app.containerPath
                            )
                        }
                        let picked = ScannedAppEntry(
                            id: app.id,
                            name: app.name,
                            bundleID: app.bundleID,
                            containerUUID: app.containerUUID,
                            containerPath: app.containerPath,
                            icon: resolvedIcon
                        )
                        zPatchStore.shared.registerAppMeta(
                            bundleID: app.bundleID,
                            appName: app.name,
                            icon: resolvedIcon
                        )
                        onSelectApp?(picked)
                        dismiss()
                    }
                }
                .listStyle(.plain)
                .searchable(text: $vm.searchText, prompt: "Tìm tên app hoặc Bundle ID...")
            }
            .navigationTitle("Chọn từ danh sách")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                if vm.apps.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        vm.scan(forceRefresh: false)
                    }
                }
            }
        }
    }
}

private struct AppScannerRowButton: View {
    let app: ScannedAppEntry
    let onTap: (UIImage?) -> Void

    @State private var lazyIcon: UIImage? = nil

    var body: some View {
        Button {
            onTap(lazyIcon ?? app.icon)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let img = lazyIcon ?? app.icon {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "app.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(.tint)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 3)
        }
        .onAppear {
            if lazyIcon == nil {
                lazyIcon = zPatchStore.shared.cachedAppIcon(for: app.bundleID)
            }
        }
    }
}
