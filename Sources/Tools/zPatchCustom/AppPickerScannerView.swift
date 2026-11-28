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
        hasher.combine(id); hasher.combine(bundleID)
    }
}

private enum AppScannerEngine {
    private static let fm = FileManager.default
    private static let dataRoot = CSStoreEngine.normalizeVarPath(FSURL.appContainers.path)

    private static func normalizePath(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let std = (t as NSString).standardizingPath
        var norm = CSStoreEngine.normalizeVarPath(std)
        while norm.count > 1 && norm.hasSuffix("/") { norm.removeLast() }
        return norm
    }

    private static func isUUIDString(_ v: String) -> Bool {
        UUID(uuidString: v.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private static func cleanBundleID(_ raw: String?, uuid: String) -> String? {
        guard let raw else { return nil }
        let norm = zPatchItem.normalizedBundleID(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !norm.isEmpty else { return nil }
        if norm.caseInsensitiveCompare(uuid) == .orderedSame { return nil }
        if isUUIDString(norm) { return nil }
        return norm
    }

    private static func resolveDisplayName(bundleID: String, uuid: String, detectedName: String?) -> String {
        if let det = detectedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !det.isEmpty, !isUUIDString(det),
           det.caseInsensitiveCompare(uuid) != .orderedSame {
            return det
        }
        if let cached = zPatchStore.shared.cachedAppName(for: bundleID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty, !isUUIDString(cached),
           cached.caseInsensitiveCompare(uuid) != .orderedSame {
            return cached
        }
        if isUUIDString(bundleID) || bundleID.caseInsensitiveCompare(uuid) == .orderedSame {
            return "App (\(String(uuid.prefix(8)).uppercased()))"
        }
        let parts = bundleID.split(separator: ".").map(String.init)
        return parts.last?.capitalized ?? bundleID
    }

    @discardableResult
    private static func grantRead(at path: String) -> Bool {
        let norm = normalizePath(path)
        guard !norm.isEmpty else { return false }
        let r = wq.grantAccess(path: norm, requireWrite: false, allowFsgetpathFallback: true)
        if r.0 { return true }
        let (fsHandle, _) = NativeWorseQuery.shared.grantViaFsgetpath(
            targetFile: norm, requireWrite: false, allowRecursiveWq: false)
        return fsHandle >= 0
    }

    private static func releaseRead(at path: String) {
        let norm = normalizePath(path)
        guard !norm.isEmpty else { return }
        if wq.hasActiveAccess(path: norm) { wq.releaseAccess(path: norm) }
    }

    private static func containerPathsFromLaunchServices() -> [String] {
        guard let raw = wq_ls_container_paths(nil) else { return [] }
        return raw
            .filter { $0.contains("/Containers/Data/Application/") }
            .map { normalizePath($0) }
            .filter { fm.fileExists(atPath: $0) }
    }

    private static func listSubdirectories(in rootPath: String) -> [String] {
        let normRoot = normalizePath(rootPath)
        guard !normRoot.isEmpty else { return [] }
        let granted = grantRead(at: normRoot)
        defer { if granted { releaseRead(at: normRoot) } }
        var results: [String] = []; var seen = Set<String>()
        func addPath(_ p: String) {
            let clean = normalizePath(p)
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { return }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: clean, isDirectory: &isDir), isDir.boolValue {
                results.append(clean)
            }
        }
        if let names = try? fm.contentsOfDirectory(atPath: normRoot), !names.isEmpty {
            for name in names where name != "." && name != ".." {
                addPath((normRoot as NSString).appendingPathComponent(name))
            }
        }
        if results.isEmpty, let storePaths = CSStoreEngine.shared.containerPaths(forRoot: normRoot) {
            for p in storePaths { addPath(p) }
        }
        if results.isEmpty {
            for leaked in fsHandlers.getDirPaths(normRoot, forceRefresh: false) { addPath(leaked) }
        }
        return results
    }

    private static func parsePlistDict(_ data: Data) -> [String: Any]? {
        try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    private static func inspectDataContainer(at path: String, uuid: String) -> (bundleID: String?, name: String?) {
        let g = grantRead(at: path)
        defer { if g { releaseRead(at: path) } }
        let xattrBID = cleanBundleID(getBIDFromXattr(URL(fileURLWithPath: path)), uuid: uuid)
        var plistBID: String? = nil, plistName: String? = nil
        for rel in [".com.apple.mobile_container_manager.metadata.plist",
                    "com.apple.mobile_container_manager.metadata.plist"] {
            let full = (path as NSString).appendingPathComponent(rel)
            if let d = fm.contents(atPath: full), let dict = parsePlistDict(d) {
                for k in ["CFBundleIdentifier","MCMMetadataIdentifier","applicationIdentifier",
                          "com.apple.containermanagerd.metadata.bundle-identifier"] {
                    if plistBID == nil, let raw = dict[k] as? String,
                       let c = cleanBundleID(raw, uuid: uuid) { plistBID = c }
                }
                for k in ["CFBundleDisplayName","CFBundleName","itemName","DisplayName","Name"] {
                    if plistName == nil, let raw = (dict[k] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !raw.isEmpty, !isUUIDString(raw) { plistName = raw }
                }
                if plistBID != nil && plistName != nil { break }
            }
        }
        return (xattrBID ?? plistBID, plistName)
    }

    private static var iconCache: [String: UIImage] = [:]
    private static let iconCacheLock = NSLock()

    private static func cachedIcon(_ b: String) -> UIImage? {
        iconCacheLock.lock(); defer { iconCacheLock.unlock() }
        return iconCache[b]
    }
    private static func storeIcon(_ b: String, _ i: UIImage) {
        iconCacheLock.lock(); iconCache[b] = i; iconCacheLock.unlock()
    }

    private static func iconForBundleID(_ bundleID: String) -> UIImage? {
        if isUUIDString(bundleID) { return nil }
        if let c = cachedIcon(bundleID) { return c }
        if let zp = zPatchStore.shared.cachedAppIcon(for: bundleID) {
            storeIcon(bundleID, zp); return zp
        }
        guard let appPath = wq_bundle_path_for_id(bundleID) else { return nil }
        let appNorm = normalizePath(appPath)
        guard !appNorm.isEmpty else { return nil }
        guard let img = readIconFromAppBundle(appNorm) else { return nil }
        storeIcon(bundleID, img)
        return img
    }

    private static func readIconFromAppBundle(_ appPath: String) -> UIImage? {
        _ = grantRead(at: appPath)
        var candidates: [String] = []
        let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
        _ = grantRead(at: infoPath)
        if let data = fm.contents(atPath: infoPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
                if let icons = plist[key] as? [String: Any],
                   let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
                   let files = primary["CFBundleIconFiles"] as? [String] {
                    candidates.append(contentsOf: files)
                }
            }
            if let files = plist["CFBundleIconFiles"] as? [String] {
                candidates.append(contentsOf: files)
            }
            if let single = plist["CFBundleIconFile"] as? String {
                candidates.append(single)
            }
        }
        for base in candidates.reversed() {
            for suffix in ["@3x.png", "@2x.png", "@2x~ipad.png", ".png"] {
                let name = base.hasSuffix(".png") ? base : "\(base)\(suffix)"
                let p = (appPath as NSString).appendingPathComponent(name)
                _ = grantRead(at: p)
                if let img = UIImage(contentsOfFile: p) { return img }
            }
        }
        for name in ["AppIcon60x60@3x.png","AppIcon60x60@2x.png","AppIcon60x60.png",
                     "AppIcon76x76@2x~ipad.png","AppIcon76x76.png",
                     "Icon-60@3x.png","Icon-60@2x.png","Icon-76@2x.png",
                     "Icon@2x.png","Icon.png","AppIcon.png"] {
            let p = (appPath as NSString).appendingPathComponent(name)
            _ = grantRead(at: p)
            if let img = UIImage(contentsOfFile: p) { return img }
        }
        if let names = try? fm.contentsOfDirectory(atPath: appPath) {
            for name in names {
                let lower = name.lowercased()
                guard lower.hasSuffix(".png"), lower.contains("icon") else { continue }
                let p = (appPath as NSString).appendingPathComponent(name)
                _ = grantRead(at: p)
                if let img = UIImage(contentsOfFile: p) { return img }
            }
        }
        return nil
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        installWQGrantCallbackIfNeeded()

        if forceRefresh {
            fsHandlers.invalidateCache()
            clearXattrBIDCache()
            wq_display_names_reset_miss()
            iconCacheLock.lock(); iconCache.removeAll(); iconCacheLock.unlock()
        }

        wq_load_display_names()

        var containerPaths = containerPathsFromLaunchServices()
        if containerPaths.isEmpty {
            containerPaths = listSubdirectories(in: dataRoot)
        }

        var uuidToBID: [String: String] = [:]
        var bidToName: [String: String] = [:]
        for rec in CSStoreEngine.shared.allAppRecords() {
            let bid = zPatchItem.normalizedBundleID(rec.bundleID)
            guard !bid.isEmpty else { continue }
            let cleanName = rec.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanName.isEmpty && cleanName.caseInsensitiveCompare(bid) != .orderedSame {
                bidToName[bid.lowercased()] = cleanName
            }
            if !rec.dataContainerPath.isEmpty {
                let last = ((normalizePath(rec.dataContainerPath) as NSString).lastPathComponent).lowercased()
                if isUUIDString(last) { uuidToBID[last] = bid }
            }
        }

        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(containerPaths.count)

        for path in containerPaths {
            autoreleasepool {
                let uuid = (path as NSString).lastPathComponent
                let uuidLower = uuid.lowercased()

                var resolvedBID: String? = wq_bundle_id_for_container(path)
                if resolvedBID == nil {
                    resolvedBID = cleanBundleID(uuidToBID[uuidLower], uuid: uuid)
                }
                if resolvedBID == nil {
                    resolvedBID = cleanBundleID(zPatchStore.shared.bundleIDForContainerUUID(uuid), uuid: uuid)
                }
                var inspectedName: String? = nil
                if resolvedBID == nil {
                    let ins = inspectDataContainer(at: path, uuid: uuid)
                    resolvedBID = ins.bundleID
                    inspectedName = ins.name
                }

                let finalBID = resolvedBID ?? uuid

                var detectedName: String? = wq_display_name(finalBID)
                if detectedName?.isEmpty ?? true {
                    detectedName = bidToName[finalBID.lowercased()] ?? inspectedName
                }
                let finalName = resolveDisplayName(
                    bundleID: finalBID, uuid: uuid, detectedName: detectedName)

                let icon = iconForBundleID(finalBID)

                if resolvedBID != nil {
                    zPatchStore.shared.registerContainer(bundleID: finalBID, containerPath: path)
                }
                zPatchStore.shared.registerAppMeta(bundleID: finalBID, appName: finalName, icon: icon)

                entries.append(ScannedAppEntry(
                    id: "\(uuidLower)_\(finalBID.lowercased())",
                    name: finalName,
                    bundleID: finalBID,
                    containerUUID: uuid,
                    containerPath: path,
                    icon: icon
                ))
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
                            id: app.id, name: app.name, bundleID: app.bundleID,
                            containerUUID: app.containerUUID, containerPath: app.containerPath,
                            icon: resolvedIcon
                        )
                        zPatchStore.shared.registerAppMeta(
                            bundleID: app.bundleID, appName: app.name, icon: resolvedIcon
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