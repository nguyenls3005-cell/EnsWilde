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
        lhs.id == rhs.id && lhs.containerUUID == rhs.containerUUID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(containerUUID)
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

    private static func loadLookupMap() -> (
        byUUID: [String: (bid: String, name: String)],
        byBID: [String: String]
    ) {
        var byUUID: [String: (bid: String, name: String)] = [:]
        var byBID: [String: String] = [:]

        // 1. Nguồn chính từ JITEnableContext.shared.getAllAppsInfo()
        if let allApps = try? JITEnableContext.shared.getAllAppsInfo() as? [String: Any] {
            var cacheDict: [String: [String: Any]] = [:]
            for (bid, raw) in allApps {
                guard let info = raw as? [String: Any] else { continue }
                cacheDict[bid] = info

                let disp = (info["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let bname = (info["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = bid.split(separator: ".").last.map(String.init) ?? bid
                let title = (disp?.isEmpty == false) ? disp! : ((bname?.isEmpty == false) ? bname! : fallback)

                byBID[bid.lowercased()] = title
                if let rawC = info["Container"] as? String, !rawC.isEmpty {
                    let cleanC = rawC.replacingOccurrences(of: "file://", with: "")
                    let uuid = (cleanC as NSString).lastPathComponent.lowercased()
                    if !uuid.isEmpty {
                        byUUID[uuid] = (bid: bid, name: title)
                    }
                }
            }
            if !cacheDict.isEmpty {
                zPatchStore.shared.updateContainerCache(from: cacheDict)
            }
        }

        // 2. Fallback LastLaunchServicesMap.plist qua wq
        let lsPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"
        if let plist = readPlistDict(at: lsPath) {
            for sectionKey in ["User", "System", "Internal"] {
                guard let section = plist[sectionKey] as? [String: Any] else { continue }
                for (bid, raw) in section {
                    guard let info = raw as? [String: Any] else { continue }
                    let disp = (info["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let bname = (info["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallback = bid.split(separator: ".").last.map(String.init) ?? bid
                    let title = (disp?.isEmpty == false) ? disp! : ((bname?.isEmpty == false) ? bname! : fallback)

                    if byBID[bid.lowercased()] == nil {
                        byBID[bid.lowercased()] = title
                    }
                    if let rawC = info["Container"] as? String, !rawC.isEmpty {
                        let uuid = (rawC as NSString).lastPathComponent.lowercased()
                        if !uuid.isEmpty, byUUID[uuid] == nil {
                            byUUID[uuid] = (bid: bid, name: title)
                        }
                    }
                }
            }
        }

        return (byUUID, byBID)
    }

    private static func resolveEntry(
        containerPath: String,
        uuid: String,
        lookup: (byUUID: [String: (bid: String, name: String)], byBID: [String: String])
    ) -> (name: String, bundleID: String) {
        let lowerUUID = uuid.lowercased()
        if let hit = lookup.byUUID[lowerUUID] {
            return (name: hit.name, bundleID: hit.bid)
        }

        if let storedBID = zPatchStore.shared.bundleIDForContainerUUID(uuid), !storedBID.isEmpty {
            let storedName = zPatchStore.shared.cachedAppName(for: storedBID)
                ?? lookup.byBID[storedBID.lowercased()]
                ?? (storedBID.split(separator: ".").last.map(String.init) ?? storedBID)
            return (name: storedName, bundleID: storedBID)
        }

        var foundBID: String? = nil
        var foundName: String? = nil

        let gDir = wq.grantAccess(path: containerPath, requireWrite: false, allowFsgetpathFallback: true)
        defer { if gDir.0 { wq.releaseAccess(path: containerPath) } }

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

        let finalBID = (foundBID?.isEmpty == false) ? foundBID! : uuid
        let finalName: String
        if let foundName, !foundName.isEmpty {
            finalName = foundName
        } else if let mappedName = lookup.byBID[finalBID.lowercased()], !mappedName.isEmpty {
            finalName = mappedName
        } else if finalBID != uuid {
            finalName = finalBID.split(separator: ".").last.map(String.init) ?? finalBID
        } else {
            finalName = "App \(uuid.prefix(8))"
        }

        return (name: finalName, bundleID: finalBID)
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let rootPath = CSStoreEngine.normalizeVarPath(FSURL.appContainers.path)
        let gRoot = wq.grantAccess(path: rootPath, requireWrite: false, allowFsgetpathFallback: true)
        defer { if gRoot.0 { wq.releaseAccess(path: rootPath) } }

        let rawContainers = fsHandlers.getDirPaths(
            FSURL.appContainers.path,
            forceRefresh: forceRefresh
        )
        let lookup = loadLookupMap()

        var list: [ScannedAppEntry] = []
        list.reserveCapacity(rawContainers.count)

        for rawPath in rawContainers {
            autoreleasepool {
                let normPath = CSStoreEngine.normalizeVarPath(rawPath)
                guard !normPath.isEmpty else { return }

                let uuid = (normPath as NSString).lastPathComponent
                guard !uuid.isEmpty else { return }

                let info = resolveEntry(containerPath: normPath, uuid: uuid, lookup: lookup)
                if info.bundleID != uuid {
                    zPatchStore.shared.registerContainer(bundleID: info.bundleID, containerPath: normPath)
                    zPatchStore.shared.registerAppMeta(bundleID: info.bundleID, appName: info.name, icon: nil)
                }

                list.append(
                    ScannedAppEntry(
                        id: "\(info.bundleID)#\(uuid)",
                        name: info.name,
                        bundleID: info.bundleID,
                        containerUUID: uuid,
                        containerPath: normPath,
                        icon: nil
                    )
                )
            }
        }

        return list.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
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
                .searchable(text: $vm.searchText, prompt: "Tìm tên app, Bundle ID hoặc UUID...")
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

                    Text(app.containerUUID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, 3)
        }
        .onAppear {
            guard lazyIcon == nil,
                  app.bundleID != app.containerUUID,
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
