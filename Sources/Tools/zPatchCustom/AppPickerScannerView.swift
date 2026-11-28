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

private enum CSStoreMetaExtractor {
    private static let fm = FileManager.default

    private static func normPath(_ p: String) -> String {
        var s = CSStoreEngine.normalizeVarPath(p.trimmingCharacters(in: .whitespacesAndNewlines))
        if s.hasPrefix("/private/") {
            s = String(s.dropFirst("/private".count))
        }
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s.lowercased()
    }

    private static func uuidFromContainerPath(_ p: String) -> String {
        let clean = normPath(p)
        guard clean.contains("/containers/data/application/") else { return "" }
        return ((clean as NSString).lastPathComponent).lowercased()
    }

    static func buildMaps() -> (uuidToBundleID: [String: String], bundleIDToName: [String: String]) {
        var uuidToBID: [String: String] = [:]
        var bidToName: [String: String] = [:]

        func walk(_ obj: Any, currentBID: String?) {
            if let dict = obj as? [String: Any] {
                var bidHint = currentBID
                if let rawB = (dict["CFBundleIdentifier"] as? String) ?? (dict["applicationIdentifier"] as? String) {
                    let normB = zPatchItem.normalizedBundleID(rawB)
                    if !normB.isEmpty {
                        bidHint = normB
                    }
                }

                if let b = bidHint, !b.isEmpty {
                    let bKey = b.lowercased()
                    for nameKey in ["CFBundleDisplayName", "CFBundleName", "itemName", "name"] {
                        if let rawName = dict[nameKey] as? String {
                            let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cleanName.isEmpty, bidToName[bKey] == nil {
                                bidToName[bKey] = cleanName
                            }
                        }
                    }

                    for pathKey in ["Container", "DataContainer", "Path", "BundleContainer", "URL"] {
                        if let rawPath = dict[pathKey] as? String {
                            let u = uuidFromContainerPath(rawPath)
                            if !u.isEmpty {
                                uuidToBID[u] = b
                            }
                        }
                    }
                }

                for (k, v) in dict {
                    let candidate = zPatchItem.normalizedBundleID(k)
                    let nextBID = (!candidate.isEmpty && k.contains(".")) ? candidate : bidHint
                    if let strPath = v as? String {
                        let u = uuidFromContainerPath(strPath)
                        if !u.isEmpty, !candidate.isEmpty {
                            uuidToBID[u] = candidate
                        }
                    }
                    walk(v, currentBID: nextBID)
                }
            } else if let arr = obj as? [Any] {
                for item in arr {
                    walk(item, currentBID: currentBID)
                }
            }
        }

        let mirror = Mirror(reflecting: CSStoreEngine.shared)
        for child in mirror.children {
            walk(child.value, currentBID: nil)
        }

        let plistCandidates = [
            "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist",
            "/private/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist",
            "/var/mobile/Library/Caches/com.apple.mobile.installation.plist",
            "/private/var/mobile/Library/Caches/com.apple.mobile.installation.plist"
        ]

        for p in plistCandidates {
            let g = wq.grantAccess(path: p, requireWrite: false, allowFsgetpathFallback: true)
            defer { if g.0 { wq.releaseAccess(path: p) } }

            if let data = fm.contents(atPath: p),
               let plist = try? PropertyListSerialization.propertyList(
                   from: data,
                   options: [],
                   format: nil
               ) {
                walk(plist, currentBID: nil)
            }
        }

        return (uuidToBID, bidToName)
    }
}

private enum AppScannerEngine {
    private static let fm = FileManager.default
    private static let targetRoot = "/private/var/mobile/Containers/Data/Application"

    private static func prettifyName(from bundleID: String, uuid: String, mapNames: [String: String]) -> String {
        if let cached = zPatchStore.shared.cachedAppName(for: bundleID)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty,
           cached.caseInsensitiveCompare(uuid) != .orderedSame {
            return cached
        }

        if let mapped = mapNames[bundleID.lowercased()]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mapped.isEmpty {
            return mapped
        }

        if bundleID.caseInsensitiveCompare(uuid) == .orderedSame {
            return "App (\(String(uuid.prefix(8))))"
        }

        let parts = bundleID.split(separator: ".").map(String.init)
        let ignored: Set<String> = ["app", "ios", "mobile", "client", "iphone", "free", "vip", "pro"]
        for part in parts.reversed() {
            let low = part.lowercased()
            if !ignored.contains(low), low != "com", low != "net", low != "org" {
                return part.capitalized
            }
        }

        return parts.last?.capitalized ?? bundleID
    }

    private static func listContainerDirectories(forceRefresh: Bool) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()

        let granted = wq.grantAccess(path: targetRoot, requireWrite: false, allowFsgetpathFallback: true)
        defer { if granted.0 { wq.releaseAccess(path: targetRoot) } }

        if let names = try? fm.contentsOfDirectory(atPath: targetRoot), !names.isEmpty {
            for name in names {
                let full = (targetRoot as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    if seen.insert(full).inserted {
                        paths.append(full)
                    }
                }
            }
        }

        if paths.isEmpty {
            let fsList = fsHandlers.getDirPaths(targetRoot, forceRefresh: forceRefresh)
            for p in fsList {
                let clean = p.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && seen.insert(clean).inserted {
                    paths.append(clean)
                }
            }
        }

        return paths
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let maps = CSStoreMetaExtractor.buildMaps()
        let dirs = listContainerDirectories(forceRefresh: forceRefresh)
        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(dirs.count)

        for path in dirs {
            autoreleasepool {
                let uuid = (path as NSString).lastPathComponent
                let uuidLower = uuid.lowercased()
                let url = URL(fileURLWithPath: path)

                let fromStore = zPatchStore.shared.bundleIDForContainerUUID(uuid)
                let fromMap = maps.uuidToBundleID[uuidLower]
                let fromXattr = getBIDFromXattr(url)?.trimmingCharacters(in: .whitespacesAndNewlines)

                let rawBID = [fromStore, fromMap, fromXattr]
                    .compactMap { $0 }
                    .first(where: { !$0.isEmpty }) ?? uuid

                let normBID = zPatchItem.normalizedBundleID(rawBID)
                let bundleID = normBID.isEmpty ? rawBID : normBID
                let title = prettifyName(from: bundleID, uuid: uuid, mapNames: maps.bundleIDToName)

                if bundleID.caseInsensitiveCompare(uuid) != .orderedSame {
                    zPatchStore.shared.registerContainer(bundleID: bundleID, containerPath: path)
                }
                zPatchStore.shared.registerAppMeta(bundleID: bundleID, appName: title, icon: nil)

                entries.append(
                    ScannedAppEntry(
                        id: "\(uuid)_\(bundleID.lowercased())",
                        name: title,
                        bundleID: bundleID,
                        containerUUID: uuid,
                        containerPath: path,
                        icon: zPatchStore.shared.cachedAppIcon(for: bundleID)
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
