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
    private static let targetRoot = "/var/mobile/Containers/Data/Application"

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
            "client", "iphone", "ipad", "free", "vip", "pro", "official"
        ]

        for part in parts.reversed() {
            let low = part.lowercased()
            if !stopWords.contains(low), low.count >= 2 {
                return part.capitalized
            }
        }

        return parts.last?.capitalized ?? bundleID
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
            "Identifier"
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
        let granted = wq.grantAccess(path: containerPath, requireWrite: false, allowFsgetpathFallback: true)
        defer { if granted.0 { wq.releaseAccess(path: containerPath) } }

        let directCandidates = [
            ".com.apple.mobile_container_manager.metadata.plist",
            "com.apple.mobile_container_manager.metadata.plist",
            "Library/Preferences/.GlobalPreferences.plist"
        ]

        var bestBID: String? = nil
        var bestName: String? = nil

        for rel in directCandidates {
            let full = (containerPath as NSString).appendingPathComponent(rel)
            if let data = fm.contents(atPath: full) {
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

        // Quét nhẹ tối đa 3 lớp thư mục để tìm plist có chứa CFBundleIdentifier / CFBundleDisplayName nếu có
        func walkPlist(dir: String, depth: Int) {
            guard depth <= 3 else { return }
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }

            for name in names {
                if name == "." || name == ".." { continue }
                let full = (dir as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    if bestBID == nil || bestName == nil {
                        walkPlist(dir: full, depth: depth + 1)
                    }
                } else if name.lowercased().hasSuffix(".plist") {
                    if let attrs = try? fm.attributesOfItem(atPath: full),
                       let size = (attrs[.size] as? NSNumber)?.intValue,
                       size > 0, size < 512_000,
                       let data = fm.contents(atPath: full) {
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
            walkPlist(dir: containerPath, depth: 1)
        }

        return (bestBID, bestName)
    }

    private static func buildCSStoreLookup() -> (uuidToBID: [String: String], bidToName: [String: String]) {
        var uuidToBID: [String: String] = [:]
        var bidToName: [String: String] = [:]

        let records = CSStoreEngine.shared.allAppRecords()
        for rec in records {
            let bid = rec.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bid.isEmpty else { continue }
            let lowerBID = bid.lowercased()

            let cleanName = rec.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanName.isEmpty && cleanName.caseInsensitiveCompare(bid) != .orderedSame {
                bidToName[lowerBID] = cleanName
            }

            let dataNorm = CSStoreEngine.normalizeVarPath(rec.dataContainerPath)
            if !dataNorm.isEmpty {
                let last = ((dataNorm as NSString).lastPathComponent).lowercased()
                if isUUIDString(last) {
                    uuidToBID[last] = bid
                }
            }
        }

        return (uuidToBID, bidToName)
    }

    private static func listAllContainerPaths(forceRefresh: Bool) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        let roots = [
            "/var/mobile/Containers/Data/Application",
            "/private/var/mobile/Containers/Data/Application"
        ]

        for root in roots {
            let g = wq.grantAccess(path: root, requireWrite: false, allowFsgetpathFallback: true)
            defer { if g.0 { wq.releaseAccess(path: root) } }

            if let names = try? fm.contentsOfDirectory(atPath: root), !names.isEmpty {
                for name in names {
                    let full = CSStoreEngine.normalizeVarPath((root as NSString).appendingPathComponent(name))
                    let key = full.lowercased()
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue, seen.insert(key).inserted {
                        result.append(full)
                    }
                }
            }
        }

        if result.count < 5 {
            let leaked = fsHandlers.getDirPaths(targetRoot, forceRefresh: forceRefresh)
            for p in leaked {
                let norm = CSStoreEngine.normalizeVarPath(p.trimmingCharacters(in: .whitespacesAndNewlines))
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

        let csLookup = buildCSStoreLookup()
        let containerPaths = listAllContainerPaths(forceRefresh: forceRefresh)

        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(containerPaths.count)

        for path in containerPaths {
            autoreleasepool {
                let uuid = (path as NSString).lastPathComponent
                let uuidLower = uuid.lowercased()
                let url = URL(fileURLWithPath: path)

                let fromStore = cleanBundleID(
                    zPatchStore.shared.bundleIDForContainerUUID(uuid),
                    uuid: uuid
                )
                let fromCS = cleanBundleID(
                    csLookup.uuidToBID[uuidLower],
                    uuid: uuid
                )
                let fromXattr = cleanBundleID(
                    getBIDFromXattr(url),
                    uuid: uuid
                )

                var resolvedBID = fromStore ?? fromCS ?? fromXattr
                var detectedName = resolvedBID.flatMap { csLookup.bidToName[$0.lowercased()] }

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
