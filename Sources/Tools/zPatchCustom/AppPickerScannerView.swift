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
    private static let bundleRoot = "/private/var/containers/Bundle/Application"

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

    private static func listSubdirectories(at rootPath: String, forceRefresh: Bool) -> [String] {
        let norm = normalizePath(rootPath)
        guard !norm.isEmpty else { return [] }
        _ = grantRead(at: norm)
        defer { releaseRead(at: norm) }

        var dirs = fsHandlers.getDirPaths(norm, forceRefresh: forceRefresh)
        if dirs.isEmpty, let names = try? fm.contentsOfDirectory(atPath: norm) {
            dirs = names.compactMap { name in
                let full = (norm as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    return full
                }
                return nil
            }
        }
        return dirs
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

    private static func iconForBundleID(_ bundleID: String, appPathHint: String?) -> UIImage? {
        if isUUIDString(bundleID) { return nil }
        if let c = cachedIcon(bundleID) { return c }
        if let zp = zPatchStore.shared.cachedAppIcon(for: bundleID) {
            storeIcon(bundleID, zp); return zp
        }

        guard let appPath = appPathHint, !appPath.isEmpty else { return nil }
        let norm = normalizePath(appPath)
        _ = grantRead(at: norm)

        var candidates: [String] = []
        let infoPath = (norm as NSString).appendingPathComponent("Info.plist")
        _ = grantRead(at: infoPath)

        if let data = try? Data(contentsOf: URL(fileURLWithPath: infoPath)),
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
                let p = (norm as NSString).appendingPathComponent(name)
                _ = grantRead(at: p)
                if let img = UIImage(contentsOfFile: p) {
                    storeIcon(bundleID, img); return img
                }
            }
        }

        for name in ["AppIcon60x60@3x.png","AppIcon60x60@2x.png","AppIcon60x60.png",
                     "AppIcon76x76@2x~ipad.png","AppIcon76x76.png",
                     "Icon-60@3x.png","Icon-60@2x.png","Icon-76@2x.png",
                     "Icon@2x.png","Icon.png","AppIcon.png"] {
            let p = (norm as NSString).appendingPathComponent(name)
            _ = grantRead(at: p)
            if let img = UIImage(contentsOfFile: p) {
                storeIcon(bundleID, img); return img
            }
        }

        if let names = try? fm.contentsOfDirectory(atPath: norm) {
            for name in names {
                let lower = name.lowercased()
                guard lower.hasSuffix(".png"), lower.contains("icon") else { continue }
                let p = (norm as NSString).appendingPathComponent(name)
                _ = grantRead(at: p)
                if let img = UIImage(contentsOfFile: p) {
                    storeIcon(bundleID, img); return img
                }
            }
        }
        return nil
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
            clearXattrBIDCache()
            iconCacheLock.lock(); iconCache.removeAll(); iconCacheLock.unlock()
        }

        var entries: [ScannedAppEntry] = []
        var processedUUIDs = Set<String>()
        var processedBundleIDs = Set<String>()

        let records = CSStoreEngine.shared.allAppRecords()
        for rec in records {
            let bid = zPatchItem.normalizedBundleID(rec.bundleID)
            guard !bid.isEmpty else { continue }

            let uuid = rec.dataContainerPath.isEmpty ? "" : (rec.dataContainerPath as NSString).lastPathComponent
            if !uuid.isEmpty { processedUUIDs.insert(uuid.lowercased()) }
            processedBundleIDs.insert(bid.lowercased())

            let name = resolveDisplayName(bundleID: bid, uuid: uuid, detectedName: rec.name)
            let icon = iconForBundleID(bid, appPathHint: rec.appBundlePath)

            entries.append(ScannedAppEntry(
                id: "\(uuid)_\(bid.lowercased())",
                name: name,
                bundleID: bid,
                containerUUID: uuid,
                containerPath: rec.dataContainerPath,
                icon: icon
            ))
        }

        let actualContainers = listSubdirectories(at: dataRoot, forceRefresh: forceRefresh)
        for path in actualContainers {
            let uuid = (path as NSString).lastPathComponent
            let uuidLower = uuid.lowercased()
            guard !uuidLower.isEmpty, !processedUUIDs.contains(uuidLower) else { continue }

            var bid = getBIDFromXattr(URL(fileURLWithPath: path))
            let name: String? = nil

            if bid == nil {
                _ = grantRead(at: path)
                let metaPath = (path as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                _ = grantRead(at: metaPath)
                if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                   let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    bid = dict["MCMMetadataIdentifier"] as? String
                }
                releaseRead(at: path)
            }

            if let validBid = cleanBundleID(bid, uuid: uuid) {
                processedUUIDs.insert(uuidLower)
                processedBundleIDs.insert(validBid.lowercased())
                let finalName = resolveDisplayName(bundleID: validBid, uuid: uuid, detectedName: name)
                entries.append(ScannedAppEntry(
                    id: "\(uuidLower)_\(validBid.lowercased())",
                    name: finalName,
                    bundleID: validBid,
                    containerUUID: uuid,
                    containerPath: path,
                    icon: iconForBundleID(validBid, appPathHint: nil)
                ))
            }
        }

        let bundleContainers = listSubdirectories(at: bundleRoot, forceRefresh: forceRefresh)
        for bContainer in bundleContainers {
            let uuid = (bContainer as NSString).lastPathComponent
            _ = grantRead(at: bContainer)
            guard let subItems = try? fm.contentsOfDirectory(atPath: bContainer) else {
                releaseRead(at: bContainer)
                continue
            }
            for item in subItems where item.hasSuffix(".app") {
                let appPath = (bContainer as NSString).appendingPathComponent(item)
                let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
                _ = grantRead(at: infoPath)
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: infoPath)),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                      let rawBid = plist["CFBundleIdentifier"] as? String,
                      let validBid = cleanBundleID(rawBid, uuid: uuid),
                      !processedBundleIDs.contains(validBid.lowercased()) else { continue }

                processedBundleIDs.insert(validBid.lowercased())
                let detName = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)
                let finalName = resolveDisplayName(bundleID: validBid, uuid: uuid, detectedName: detName)
                entries.append(ScannedAppEntry(
                    id: "\(uuid)_\(validBid.lowercased())",
                    name: finalName,
                    bundleID: validBid,
                    containerUUID: uuid,
                    containerPath: "",
                    icon: iconForBundleID(validBid, appPathHint: appPath)
                ))
            }
            releaseRead(at: bContainer)
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
                self.statusMessage = result.isEmpty
                    ? "Không tìm thấy app (0 app) -- có thể nhập tay Bundle ID bên dưới"
                    : "Đã quét xong: \(result.count) app"
            }
        }
    }
}

struct AppPickerScannerView: View {
    @Binding var selectedBundleID: String
    var onSelectApp: ((ScannedAppEntry) -> Void)? = nil

    @StateObject private var vm = AppScannerVM()
    @Environment(\.dismiss) private var dismiss
    @State private var manualBundleID: String = ""
    @State private var manualAppName: String = ""

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

                if vm.filteredApps.isEmpty && !vm.isScanning {
                    Form {
                        Section(header: Text("Nhập tay Bundle ID khi không quét được")) {
                            TextField("Bundle ID (vd: com.lemon.lvoverseas)", text: $manualBundleID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Tên app (tuỳ chọn)", text: $manualAppName)
                            Button("Dùng Bundle ID này") {
                                let clean = zPatchItem.normalizedBundleID(manualBundleID)
                                guard !clean.isEmpty else { return }
                                let finalName = manualAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? (clean.split(separator: ".").last.map(String.init)?.capitalized ?? clean)
                                    : manualAppName.trimmingCharacters(in: .whitespacesAndNewlines)
                                selectedBundleID = clean
                                let icon = zPatchStore.shared.cachedAppIcon(for: clean)
                                zPatchStore.shared.registerAppMeta(bundleID: clean, appName: finalName, icon: icon)
                                onSelectApp?(ScannedAppEntry(
                                    id: clean.lowercased(),
                                    name: finalName,
                                    bundleID: clean,
                                    containerUUID: "",
                                    containerPath: "",
                                    icon: icon
                                ))
                                dismiss()
                            }
                            .disabled(zPatchItem.normalizedBundleID(manualBundleID).isEmpty)
                        }
                    }
                } else {
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
                }
            }
            .searchable(text: $vm.searchText, prompt: "Tìm tên app hoặc Bundle ID...")
            .navigationTitle("Chọn từ danh sách")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                if vm.apps.isEmpty {
                    vm.scan(forceRefresh: true)
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
