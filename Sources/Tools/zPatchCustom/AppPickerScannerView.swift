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

        if let data = fm.contents(atPath: path),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return dict
        }
        return nil
    }

    private static func loadAppLookup() -> (byUUID: [String: (bid: String, name: String)], byBID: [String: (uuid: String, name: String)]) {
        var byUUID: [String: (bid: String, name: String)] = [:]
        var byBID: [String: (uuid: String, name: String)] = [:]

        // 1. Thử đọc JITEnableContext nếu có sẵn dictionary app info
        if let allApps = try? JITEnableContext.shared.getAllAppsInfo() as? [String: Any] {
            for (bid, raw) in allApps {
                guard let info = raw as? [String: Any] else { continue }
                let disp = (info["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let bname = (info["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = (disp?.isEmpty == false) ? disp! : ((bname?.isEmpty == false) ? bname! : (bid.split(separator: ".").last.map(String.init) ?? bid))
                let rawC = (info["Container"] as? String) ?? ""
                let uuid = rawC.isEmpty ? "" : (rawC as NSString).lastPathComponent
                if !uuid.isEmpty {
                    byUUID[uuid.lowercased()] = (bid: bid, name: title)
                }
                byBID[bid.lowercased()] = (uuid: uuid, name: title)
            }
        }

        // 2. Thử đọc LastLaunchServicesMap.plist nếu có
        let lsPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"
        if let plist = readPlistDict(at: lsPath) {
            for sectionKey in ["User", "System", "Internal"] {
                guard let section = plist[sectionKey] as? [String: Any] else { continue }
                for (bid, raw) in section {
                    guard let info = raw as? [String: Any] else { continue }
                    let disp = (info["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let bname = (info["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = (disp?.isEmpty == false) ? disp! : ((bname?.isEmpty == false) ? bname! : (bid.split(separator: ".").last.map(String.init) ?? bid))
                    let rawC = (info["Container"] as? String) ?? ""
                    let uuid = rawC.isEmpty ? "" : (rawC as NSString).lastPathComponent
                    if !uuid.isEmpty, byUUID[uuid.lowercased()] == nil {
                        byUUID[uuid.lowercased()] = (bid: bid, name: title)
                    }
                    if byBID[bid.lowercased()] == nil {
                        byBID[bid.lowercased()] = (uuid: uuid, name: title)
                    }
                }
            }
        }

        return (byUUID, byBID)
    }

    private static func resolveMetaAndIcon(
        containerPath: String,
        uuid: String,
        lookup: (byUUID: [String: (bid: String, name: String)], byBID: [String: (uuid: String, name: String)])
    ) -> (name: String, bundleID: String, icon: UIImage?) {
        let lowerUUID = uuid.lowercased()
        var bid: String? = lookup.byUUID[lowerUUID]?.bid
        var appName: String? = lookup.byUUID[lowerUUID]?.name

        let gDir = wq.grantAccess(path: containerPath, requireWrite: false, allowFsgetpathFallback: true)
        defer { if gDir.0 { wq.releaseAccess(path: containerPath) } }

        if bid == nil || bid?.isEmpty == true {
            if let xattrBID = getBIDFromXattr(URL(fileURLWithPath: containerPath))?.trimmingCharacters(in: .whitespacesAndNewlines),
               !xattrBID.isEmpty {
                bid = xattrBID
            }
        }

        if bid == nil || bid?.isEmpty == true {
            for metaName in [".com.apple.mobile_container_manager.metadata.plist", "iTunesMetadata.plist"] {
                let metaPath = (containerPath as NSString).appendingPathComponent(metaName)
                if let p = readPlistDict(at: metaPath) {
                    if let foundBID = (p["MCMMetadataIdentifier"] as? String) ?? (p["softwareVersionBundleId"] as? String),
                       !foundBID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        bid = foundBID.trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
        }

        let finalBID = (bid?.isEmpty == false) ? bid! : uuid
        if appName == nil || appName?.isEmpty == true {
            appName = lookup.byBID[finalBID.lowercased()]?.name
        }
        if appName == nil || appName?.isEmpty == true {
            if finalBID != uuid {
                appName = finalBID.split(separator: ".").last.map(String.init) ?? finalBID
            } else {
                appName = "App \(uuid.prefix(8))"
            }
        }

        var icon: UIImage? = nil
        if finalBID != uuid, !finalBID.contains("/") {
            icon = try? JITEnableContext.shared.getAppIcon(withBundleId: finalBID)
        }

        return (name: appName!, bundleID: finalBID, icon: icon)
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let rootPath = CSStoreEngine.normalizeVarPath(FSURL.appContainers.path)
        let gRoot = wq.grantAccess(path: rootPath, requireWrite: false, allowFsgetpathFallback: true)
        defer { if gRoot.0 { wq.releaseAccess(path: rootPath) } }

        let rawContainers = fsHandlers.getDirPaths(FSURL.appContainers.path, forceRefresh: forceRefresh)
        let lookup = loadAppLookup()

        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(rawContainers.count)

        for raw in rawContainers {
            autoreleasepool {
                let norm = CSStoreEngine.normalizeVarPath(raw)
                guard !norm.isEmpty else { return }
                let uuid = (norm as NSString).lastPathComponent
                guard !uuid.isEmpty else { return }

                let meta = resolveMetaAndIcon(containerPath: norm, uuid: uuid, lookup: lookup)
                entries.append(
                    ScannedAppEntry(
                        id: "\(meta.bundleID)#\(uuid)",
                        name: meta.name,
                        bundleID: meta.bundleID,
                        containerUUID: uuid,
                        containerPath: norm,
                        icon: meta.icon
                    )
                )
            }
        }

        return entries.sorted {
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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let list = AppScannerEngine.scan(forceRefresh: forceRefresh)
            self.apps = list
            self.isScanning = false
            self.statusMessage = "Đã quét xong: \(list.count) app"
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
                            AppPickerIconBadge(icon: app.icon)

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

private struct AppPickerIconBadge: View {
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
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 40, height: 40)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
