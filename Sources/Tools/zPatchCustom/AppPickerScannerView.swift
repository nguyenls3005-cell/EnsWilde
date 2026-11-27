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

    private static func readPlistDict(at path: String) -> [String: Any]? {
        let granted = wq.grantAccess(path: path, requireWrite: false, allowFsgetpathFallback: true)
        defer { if granted.0 { wq.releaseAccess(path: path) } }

        guard let data = fm.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            return nil
        }
        return plist
    }

    private static func cleanDisplayName(from info: [String: Any], bundleID: String) -> String {
        let disp = (info["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let disp, !disp.isEmpty { return disp }

        let bname = (info["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bname, !bname.isEmpty { return bname }

        let item = (info["itemName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item, !item.isEmpty { return item }

        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private static func loadKnownApps() -> (
        byBID: [String: (bid: String, name: String, containerPath: String)],
        byUUID: [String: (bid: String, name: String, containerPath: String)]
    ) {
        var byBID: [String: (bid: String, name: String, containerPath: String)] = [:]
        var byUUID: [String: (bid: String, name: String, containerPath: String)] = [:]

        // 1. Nguồn chính từ JITEnableContext
        if let allApps = try? JITEnableContext.shared.getAllAppsInfo() as? [String: Any] {
            var cacheDict: [String: [String: Any]] = [:]
            for (rawBID, raw) in allApps {
                let bid = rawBID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bid.isEmpty, let info = raw as? [String: Any] else { continue }
                cacheDict[bid] = info

                let title = cleanDisplayName(from: info, bundleID: bid)
                let rawC = (info["Container"] as? String ?? "")
                    .replacingOccurrences(of: "file://", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let normC = rawC.isEmpty ? "" : CSStoreEngine.normalizeVarPath(rawC)
                let uuid = normC.isEmpty ? "" : (normC as NSString).lastPathComponent.lowercased()

                byBID[bid.lowercased()] = (bid: bid, name: title, containerPath: normC)
                if !uuid.isEmpty {
                    byUUID[uuid] = (bid: bid, name: title, containerPath: normC)
                }
            }
            if !cacheDict.isEmpty {
                zPatchStore.shared.updateContainerCache(from: cacheDict)
            }
        }

        // 2. Bổ sung từ LastLaunchServicesMap.plist qua wq
        let lsPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"
        if let plist = readPlistDict(at: lsPath) {
            for sectionKey in ["User", "System", "Internal"] {
                guard let section = plist[sectionKey] as? [String: Any] else { continue }
                for (rawBID, raw) in section {
                    let bid = rawBID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !bid.isEmpty, let info = raw as? [String: Any] else { continue }

                    let title = cleanDisplayName(from: info, bundleID: bid)
                    let rawC = (info["Container"] as? String ?? "")
                        .replacingOccurrences(of: "file://", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let normC = rawC.isEmpty ? "" : CSStoreEngine.normalizeVarPath(rawC)
                    let uuid = normC.isEmpty ? "" : (normC as NSString).lastPathComponent.lowercased()

                    let key = bid.lowercased()
                    if let existing = byBID[key] {
                        let mergedPath = existing.containerPath.isEmpty ? normC : existing.containerPath
                        let mergedName = existing.name.isEmpty ? title : existing.name
                        byBID[key] = (bid: bid, name: mergedName, containerPath: mergedPath)
                    } else {
                        byBID[key] = (bid: bid, name: title, containerPath: normC)
                    }

                    if !uuid.isEmpty, byUUID[uuid] == nil {
                        byUUID[uuid] = (bid: bid, name: title, containerPath: normC)
                    }
                }
            }
        }

        return (byBID, byUUID)
    }

    private static func resolveContainerMetadata(
        containerPath: String,
        uuid: String,
        known: (
            byBID: [String: (bid: String, name: String, containerPath: String)],
            byUUID: [String: (bid: String, name: String, containerPath: String)]
        )
    ) -> (bid: String, name: String)? {
        let lowerUUID = uuid.lowercased()
        if let hit = known.byUUID[lowerUUID] {
            return (bid: hit.bid, name: hit.name)
        }

        if let storedBID = zPatchStore.shared.bundleIDForContainerUUID(uuid), !storedBID.isEmpty {
            let storedName = zPatchStore.shared.cachedAppName(for: storedBID)
                ?? known.byBID[storedBID.lowercased()]?.name
                ?? (storedBID.split(separator: ".").last.map(String.init) ?? storedBID)
            return (bid: storedBID, name: storedName)
        }

        let gDir = wq.grantAccess(path: containerPath, requireWrite: false, allowFsgetpathFallback: true)
        defer { if gDir.0 { wq.releaseAccess(path: containerPath) } }

        var foundBID: String? = nil
        var foundName: String? = nil

        if let xattrBID = getBIDFromXattr(URL(fileURLWithPath: containerPath))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !xattrBID.isEmpty {
            foundBID = xattrBID
        }

        if foundBID == nil {
            for metaName in [".com.apple.mobile_container_manager.metadata.plist", "iTunesMetadata.plist"] {
                let metaPath = (containerPath as NSString).appendingPathComponent(metaName)
                if let p = readPlistDict(at: metaPath) {
                    if let b = (p["MCMMetadataIdentifier"] as? String) ?? (p["softwareVersionBundleId"] as? String),
                       !b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        foundBID = b.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if let item = p["itemName"] as? String,
                       !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        foundName = item.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if foundBID != nil { break }
                }
            }
        }

        guard let bid = foundBID, !bid.isEmpty else {
            return nil
        }

        let name = foundName
            ?? known.byBID[bid.lowercased()]?.name
            ?? (bid.split(separator: ".").last.map(String.init) ?? bid)

        return (bid: bid, name: name)
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let known = loadKnownApps()
        var mergedByBID: [String: ScannedAppEntry] = [:]

        // Bước 1: Đưa toàn bộ app đã biết Bundle ID + Tên vào trước
        for (lowerBID, item) in known.byBID {
            let uuid = item.containerPath.isEmpty ? "" : (item.containerPath as NSString).lastPathComponent
            if !item.containerPath.isEmpty {
                zPatchStore.shared.registerContainer(bundleID: item.bid, containerPath: item.containerPath)
            }
            zPatchStore.shared.registerAppMeta(bundleID: item.bid, appName: item.name, icon: nil)

            mergedByBID[lowerBID] = ScannedAppEntry(
                id: item.bid,
                name: item.name,
                bundleID: item.bid,
                containerUUID: uuid,
                containerPath: item.containerPath,
                icon: nil
            )
        }

        // Bước 2: Quét thêm thư mục container để bổ sung containerPath hoặc app chưa có trong danh sách trên
        let rootPath = CSStoreEngine.normalizeVarPath(FSURL.appContainers.path)
        let gRoot = wq.grantAccess(path: rootPath, requireWrite: false, allowFsgetpathFallback: true)
        defer { if gRoot.0 { wq.releaseAccess(path: rootPath) } }

        let rawContainers = fsHandlers.getDirPaths(
            FSURL.appContainers.path,
            forceRefresh: forceRefresh
        )

        for rawPath in rawContainers {
            autoreleasepool {
                let normPath = CSStoreEngine.normalizeVarPath(rawPath)
                guard !normPath.isEmpty else { return }

                let uuid = (normPath as NSString).lastPathComponent
                guard !uuid.isEmpty else { return }

                guard let resolved = resolveContainerMetadata(
                    containerPath: normPath,
                    uuid: uuid,
                    known: known
                ) else {
                    return
                }

                let lowerBID = resolved.bid.lowercased()
                zPatchStore.shared.registerContainer(bundleID: resolved.bid, containerPath: normPath)
                zPatchStore.shared.registerAppMeta(bundleID: resolved.bid, appName: resolved.name, icon: nil)

                if let existing = mergedByBID[lowerBID] {
                    if existing.containerPath.isEmpty {
                        mergedByBID[lowerBID] = ScannedAppEntry(
                            id: existing.bundleID,
                            name: existing.name,
                            bundleID: existing.bundleID,
                            containerUUID: uuid,
                            containerPath: normPath,
                            icon: nil
                        )
                    }
                } else {
                    mergedByBID[lowerBID] = ScannedAppEntry(
                        id: resolved.bid,
                        name: resolved.name,
                        bundleID: resolved.bid,
                        containerUUID: uuid,
                        containerPath: normPath,
                        icon: nil
                    )
                }
            }
        }

        return mergedByBID.values.sorted {
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
            $0.bundleID.lowercased().contains(q)
        }
    }

    func scan(forceRefresh: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "Đang quét danh sách app..."

        Task.detached(priority: .userInitiated) {
            let result = AppScannerEngine.scan(forceRefresh: forceRefresh)
            await MainActor.run {
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
                    vm.scan(forceRefresh: false)
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
            guard lazyIcon == nil,
                  !app.bundleID.isEmpty,
                  !app.bundleID.contains("/") else { return }

            if let cached = zPatchStore.shared.cachedAppIcon(for: app.bundleID) {
                lazyIcon = cached
                return
            }

            if let icon = try? JITEnableContext.shared.getAppIcon(withBundleId: app.bundleID) {
                lazyIcon = icon
                zPatchStore.shared.registerAppMeta(bundleID: app.bundleID, appName: app.name, icon: icon)
            }
        }
    }
}
