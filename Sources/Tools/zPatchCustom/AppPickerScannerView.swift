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
    private static let dataRoot = CSStoreEngine.normalizeVarPath(FSURL.appContainers.path)
    private static let bundleRoot = CSStoreEngine.normalizeVarPath(FSURL.appBundles.path)

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
        UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private static func cleanBundleID(_ raw: String?, uuid: String) -> String? {
        guard let raw else { return nil }
        let norm = zPatchItem.normalizedBundleID(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !norm.isEmpty else { return nil }
        if norm.caseInsensitiveCompare(uuid) == .orderedSame { return nil }
        if isUUIDString(norm) { return nil }
        return norm
    }

    private static func resolveDisplayName(
        bundleID: String,
        uuid: String,
        detectedName: String?
    ) -> String {
        if let det = detectedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !det.isEmpty,
           !isUUIDString(det),
           det.caseInsensitiveCompare(uuid) != .orderedSame {
            return det
        }

        if let cached = zPatchStore.shared.cachedAppName(for: bundleID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty,
           !isUUIDString(cached),
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
            targetFile: norm,
            requireWrite: false,
            allowRecursiveWq: false
        )
        return fsHandle >= 0
    }

    private static func releaseRead(at path: String) {
        let norm = normalizePath(path)
        guard !norm.isEmpty else { return }
        if wq.hasActiveAccess(path: norm) {
            wq.releaseAccess(path: norm)
        }
    }

    private static func readData(at fullPath: String) -> Data? {
        let norm = normalizePath(fullPath)
        guard !norm.isEmpty else { return nil }

        let granted = grantRead(at: norm)
        defer { if granted { releaseRead(at: norm) } }

        if let d = fm.contents(atPath: norm), !d.isEmpty {
            return d
        }
        if let d = try? Data(contentsOf: URL(fileURLWithPath: norm), options: .uncached), !d.isEmpty {
            return d
        }
        return nil
    }

    private static func listSubdirectories(in rootPath: String) -> [String] {
        let normRoot = normalizePath(rootPath)
        guard !normRoot.isEmpty else { return [] }

        let granted = grantRead(at: normRoot)
        defer { if granted { releaseRead(at: normRoot) } }

        var results: [String] = []
        var seen = Set<String>()

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
            for p in storePaths {
                addPath(p)
            }
        }

        if results.isEmpty {
            for leaked in fsHandlers.getDirPaths(normRoot, forceRefresh: false) {
                addPath(leaked)
            }
        }

        return results
    }

    private static func parsePlistDict(_ data: Data) -> [String: Any]? {
        try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    private static func extractAppInfoFromPlist(_ dict: [String: Any], uuid: String) -> (bundleID: String?, name: String?) {
        let bidKeys = [
            "CFBundleIdentifier",
            "MCMMetadataIdentifier",
            "applicationIdentifier",
            "BundleIdentifier",
            "Identifier",
            "com.apple.containermanagerd.metadata.bundle-identifier"
        ]
        var bid: String? = nil
        for k in bidKeys {
            if let raw = dict[k] as? String, let cleaned = cleanBundleID(raw, uuid: uuid) {
                bid = cleaned
                break
            }
        }

        let nameKeys = [
            "CFBundleDisplayName",
            "CFBundleName",
            "itemName",
            "DisplayName",
            "Name"
        ]
        var appName: String? = nil
        for k in nameKeys {
            if let raw = (dict[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty,
               !isUUIDString(raw) {
                appName = raw
                break
            }
        }

        return (bid, appName)
    }

    private static func scanBundleContainers() -> (bidToName: [String: String], bidToBundlePath: [String: String]) {
        var bidToName: [String: String] = [:]
        var bidToBundlePath: [String: String] = [:]

        let bundleDirs = listSubdirectories(in: bundleRoot)
        for dir in bundleDirs {
            autoreleasepool {
                let uuid = (dir as NSString).lastPathComponent
                let grantedDir = grantRead(at: dir)
                defer { if grantedDir { releaseRead(at: dir) } }

                guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
                for entry in entries where entry.lowercased().hasSuffix(".app") {
                    let appPath = normalizePath((dir as NSString).appendingPathComponent(entry))
                    let infoPlistPath = (appPath as NSString).appendingPathComponent("Info.plist")
                    guard let data = readData(at: infoPlistPath),
                          let dict = parsePlistDict(data) else { continue }

                    let info = extractAppInfoFromPlist(dict, uuid: uuid)
                    if let bid = info.bundleID {
                        let key = bid.lowercased()
                        if let name = info.name, !name.isEmpty {
                            bidToName[key] = name
                        }
                        bidToBundlePath[key] = appPath
                        break
                    }
                }
            }
        }

        return (bidToName, bidToBundlePath)
    }

    private static func inspectDataContainer(at containerPath: String, uuid: String) -> (bundleID: String?, name: String?) {
        let grantedContainer = grantRead(at: containerPath)
        defer { if grantedContainer { releaseRead(at: containerPath) } }

        let xattrBID = cleanBundleID(getBIDFromXattr(URL(fileURLWithPath: containerPath)), uuid: uuid)

        let metaCandidates = [
            ".com.apple.mobile_container_manager.metadata.plist",
            "com.apple.mobile_container_manager.metadata.plist"
        ]

        var plistBID: String? = nil
        var plistName: String? = nil

        for rel in metaCandidates {
            let full = (containerPath as NSString).appendingPathComponent(rel)
            if let data = readData(at: full), let dict = parsePlistDict(data) {
                let info = extractAppInfoFromPlist(dict, uuid: uuid)
                if plistBID == nil { plistBID = info.bundleID }
                if plistName == nil { plistName = info.name }
                if plistBID != nil && plistName != nil { break }
            }
        }

        return (xattrBID ?? plistBID, plistName)
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
            clearXattrBIDCache()
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
                if isUUIDString(last) {
                    uuidToBID[last] = bid
                }
            }
        }

        let bundleInfo = scanBundleContainers()
        for (k, v) in bundleInfo.bidToName {
            if bidToName[k] == nil {
                bidToName[k] = v
            }
        }

        let dataContainers = listSubdirectories(in: dataRoot)
        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(dataContainers.count)

        for path in dataContainers {
            autoreleasepool {
                let uuid = (path as NSString).lastPathComponent
                let uuidLower = uuid.lowercased()

                let inspected = inspectDataContainer(at: path, uuid: uuid)
                let resolvedBID = cleanBundleID(uuidToBID[uuidLower], uuid: uuid)
                    ?? cleanBundleID(zPatchStore.shared.bundleIDForContainerUUID(uuid), uuid: uuid)
                    ?? inspected.bundleID

                let finalBID = resolvedBID ?? uuid
                let detectedName = bidToName[finalBID.lowercased()] ?? inspected.name
                let finalName = resolveDisplayName(
                    bundleID: finalBID,
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
