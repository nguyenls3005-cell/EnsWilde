import SwiftUI
import Foundation
import UIKit

struct ScannedAppEntry: Identifiable, Hashable {
    let id: String              // Unique key
    let name: String            // Tên app
    let bundleID: String        // Bundle ID hoặc UUID nếu chưa đọc được
    let containerUUID: String   // UUID container
    let containerPath: String   // Đường dẫn data container
    let bundlePath: String?     // Đường dẫn .app nếu có
    let sizeBytes: Int64        // Dung lượng (bytes)
    let icon: UIImage?          // Icon app

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    static func == (lhs: ScannedAppEntry, rhs: ScannedAppEntry) -> Bool {
        lhs.id == rhs.id && lhs.containerUUID == rhs.containerUUID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(containerUUID)
    }
}

@MainActor
final class AppScannerViewModel: ObservableObject {
    @Published var apps: [ScannedAppEntry] = []
    @Published var searchText: String = ""
    @Published var isScanning: Bool = false
    @Published var statusMessage: String = "Chưa quét"
    @Published var debugDetail: String = ""

    var filteredApps: [ScannedAppEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.name.lowercased().contains(q) ||
            $0.bundleID.lowercased().contains(q) ||
            $0.containerUUID.lowercased().contains(q)
        }
    }

    var totalSizeBytes: Int64 {
        filteredApps.reduce(0) { $0 + $1.sizeBytes }
    }

    func scanApps(forceRefresh: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "Đang quét..."
        debugDetail = ""

        Task.detached(priority: .userInitiated) {
            let result = Self.collectApps(forceRefresh: forceRefresh)
            await MainActor.run {
                self.apps = result.entries
                self.isScanning = false
                self.statusMessage = "Đã quét xong: \(result.entries.count) mục"
                self.debugDetail = result.debugInfo
            }
        }
    }

    @discardableResult
    nonisolated private static func grantRead(at path: String) -> (Bool, String) {
        guard !path.isEmpty else { return (false, "empty") }
        let fm = FileManager.default
        if fm.isReadableFile(atPath: path) {
            return (true, "readable")
        }
        let (ok, _, msg) = wq.grantAccess(path: path, requireWrite: false, allowFsgetpathFallback: true)
        return (ok || fm.isReadableFile(atPath: path), msg)
    }

    nonisolated private static func readPlistDict(atPath path: String) -> [String: Any]? {
        _ = grantRead(at: path)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return (try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )) as? [String: Any]
    }

    nonisolated private static func directorySize(atPath path: String) -> Int64 {
        guard !path.isEmpty else { return 0 }
        _ = grantRead(at: path)

        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    nonisolated private static func loadAppIcon(appBundlePath: String?, infoPlist: [String: Any]?) -> UIImage? {
        guard let bundlePath = appBundlePath, !bundlePath.isEmpty else { return nil }
        _ = grantRead(at: bundlePath)

        let fm = FileManager.default
        let bundleURL = URL(fileURLWithPath: bundlePath)
        var candidatePaths: [String] = []

        if let plist = infoPlist {
            if let icons = plist["CFBundleIcons"] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String] {
                for baseName in files.reversed() {
                    candidatePaths.append(contentsOf: [
                        "\(baseName)@3x.png",
                        "\(baseName)@2x.png",
                        "\(baseName).png",
                        baseName
                    ].map { bundleURL.appendingPathComponent($0).path })
                }
            }
            if let iconFiles = plist["CFBundleIconFiles"] as? [String] {
                for baseName in iconFiles.reversed() {
                    candidatePaths.append(bundleURL.appendingPathComponent(baseName).path)
                    candidatePaths.append(bundleURL.appendingPathComponent("\(baseName)@2x.png").path)
                    candidatePaths.append(bundleURL.appendingPathComponent("\(baseName)@3x.png").path)
                }
            }
        }

        for p in candidatePaths {
            _ = grantRead(at: p)
            if let img = UIImage(contentsOfFile: p) {
                return img
            }
        }

        if let enumerator = fm.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            var bestImage: UIImage?
            var bestArea: CGFloat = 0

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "png" else { continue }
                let lower = fileURL.lastPathComponent.lowercased()
                guard lower.contains("icon") || lower.contains("logo") else { continue }

                _ = grantRead(at: fileURL.path)
                if let img = UIImage(contentsOfFile: fileURL.path) {
                    let area = img.size.width * img.size.height * img.scale * img.scale
                    if area > bestArea {
                        bestArea = area
                        bestImage = img
                    }
                }
            }
            if let bestImage { return bestImage }
        }

        return nil
    }

    nonisolated private static func findAppBundleFolder(inside path: String) -> String? {
        guard !path.isEmpty else { return nil }
        _ = grantRead(at: path)
        if path.hasSuffix(".app") { return path }

        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(atPath: path) {
            if let appDir = items.first(where: { $0.hasSuffix(".app") }) {
                return (path as NSString).appendingPathComponent(appDir)
            }
            for sub in items {
                let subPath = (path as NSString).appendingPathComponent(sub)
                if let subItems = try? fm.contentsOfDirectory(atPath: subPath),
                   let appDir = subItems.first(where: { $0.hasSuffix(".app") }) {
                    return (subPath as NSString).appendingPathComponent(appDir)
                }
            }
        }
        return nil
    }

    nonisolated private static func loadLaunchServicesIndex() -> [String: (dataPath: String?, bundlePath: String?, name: String?)] {
        let mapPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"
        guard let plist = readPlistDict(atPath: mapPath),
              let userDict = plist["User"] as? [String: Any] else {
            return [:]
        }

        var index: [String: (dataPath: String?, bundlePath: String?, name: String?)] = [:]
        for (bid, rawInfo) in userDict {
            guard let info = rawInfo as? [String: Any] else { continue }
            let key = bid.lowercased()

            var dataPath: String?
            if let c = info["Container"] as? String, !c.isEmpty {
                dataPath = CSStoreEngine.normalizeVarPath(c.replacingOccurrences(of: "file://", with: ""))
            } else if let uuid = info["ContainerUUID"] as? String, !uuid.isEmpty {
                dataPath = "/var/mobile/Containers/Data/Application/\(uuid)"
            }

            var bundlePath: String?
            if let b = info["Path"] as? String, !b.isEmpty {
                bundlePath = b.replacingOccurrences(of: "file://", with: "")
            } else if let b = info["BundleContainer"] as? String, !b.isEmpty {
                bundlePath = b.replacingOccurrences(of: "file://", with: "")
            }

            let appName = (info["DisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            index[key] = (dataPath: dataPath, bundlePath: bundlePath, name: appName)
        }
        return index
    }

    nonisolated private static func collectApps(forceRefresh: Bool) -> (entries: [ScannedAppEntry], debugInfo: String) {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let (_, msgData) = grantRead(at: FSURL.appContainers.path)
        let (_, msgBundle) = grantRead(at: FSURL.appBundles.path)

        let lsIndex = loadLaunchServicesIndex()
        let rawDataContainers = fsHandlers.getDirPaths(FSURL.appContainers.path, forceRefresh: forceRefresh)
        let rawBundleContainers = fsHandlers.getDirPaths(FSURL.appBundles.path, forceRefresh: forceRefresh)

        var bundlePathByBID: [String: String] = [:]
        for (bid, entry) in lsIndex {
            if let bPath = entry.bundlePath, !bPath.isEmpty {
                bundlePathByBID[bid] = findAppBundleFolder(inside: bPath) ?? bPath
            }
        }

        for bContainer in rawBundleContainers {
            guard let appFolder = findAppBundleFolder(inside: bContainer) else { continue }
            let infoPath = (appFolder as NSString).appendingPathComponent("Info.plist")
            if let info = readPlistDict(atPath: infoPath),
               let bid = info["CFBundleIdentifier"] as? String, !bid.isEmpty {
                bundlePathByBID[bid.lowercased()] = appFolder
            }
        }

        var dataContainerByBID: [String: String] = [:]
        for (bid, entry) in lsIndex {
            if let dPath = entry.dataPath, !dPath.isEmpty {
                dataContainerByBID[bid] = CSStoreEngine.normalizeVarPath(dPath)
            }
        }

        var unmappedDataPaths: [String] = []
        for dContainer in rawDataContainers {
            let stdPath = CSStoreEngine.normalizeVarPath((dContainer as NSString).standardizingPath)
            _ = grantRead(at: stdPath)

            var bid = getBIDFromXattr(URL(fileURLWithPath: stdPath))
            if bid == nil || bid?.isEmpty == true {
                let metaPath = (stdPath as NSString)
                    .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                if let meta = readPlistDict(atPath: metaPath) {
                    bid = (meta["MCMMetadataIdentifier"] as? String) ?? (meta["Identifier"] as? String)
                }
            }

            if let bid, !bid.isEmpty {
                let lower = bid.lowercased()
                if dataContainerByBID[lower] == nil {
                    dataContainerByBID[lower] = stdPath
                }
            } else {
                unmappedDataPaths.append(stdPath)
            }
        }

        let allBIDs = Set(bundlePathByBID.keys)
            .union(dataContainerByBID.keys)
            .union(lsIndex.keys)

        var entries: [ScannedAppEntry] = []

        for lowerBID in allBIDs {
            let lsInfo = lsIndex[lowerBID]
            let appBundlePath = bundlePathByBID[lowerBID]
            let dataPath = dataContainerByBID[lowerBID] ?? lsInfo?.dataPath ?? ""

            let infoPlist: [String: Any]? = {
                guard let appBundlePath else { return nil }
                let infoPath = (appBundlePath as NSString).appendingPathComponent("Info.plist")
                return readPlistDict(atPath: infoPath)
            }()

            let realBundleID = (infoPlist?["CFBundleIdentifier"] as? String)
                ?? (lowerBID.isEmpty ? "unknown" : lowerBID)

            let uuid: String = {
                if !dataPath.isEmpty {
                    let last = URL(fileURLWithPath: dataPath).lastPathComponent
                    if !last.isEmpty { return last }
                }
                if let appBundlePath {
                    let parent = URL(fileURLWithPath: appBundlePath).deletingLastPathComponent().lastPathComponent
                    if !parent.isEmpty { return parent }
                }
                return "N/A"
            }()

            let realName = (infoPlist?["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? (infoPlist?["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? lsInfo?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? (appBundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent })
                ?? realBundleID

            let dataSize = dataPath.isEmpty ? 0 : directorySize(atPath: dataPath)
            let bundleSize = appBundlePath.map { directorySize(atPath: $0) } ?? 0
            let icon = loadAppIcon(appBundlePath: appBundlePath, infoPlist: infoPlist)

            entries.append(
                ScannedAppEntry(
                    id: "\(realBundleID)#\(uuid)",
                    name: realName,
                    bundleID: realBundleID,
                    containerUUID: uuid,
                    containerPath: dataPath,
                    bundlePath: appBundlePath,
                    sizeBytes: dataSize + bundleSize,
                    icon: icon
                )
            )
        }

        for rawPath in unmappedDataPaths {
            let uuid = URL(fileURLWithPath: rawPath).lastPathComponent
            let sz = directorySize(atPath: rawPath)
            entries.append(
                ScannedAppEntry(
                    id: "raw#\(uuid)",
                    name: uuid,
                    bundleID: uuid,
                    containerUUID: uuid,
                    containerPath: rawPath,
                    bundlePath: nil,
                    sizeBytes: sz,
                    icon: nil
                )
            )
        }

        let sorted = entries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let info = "LS:\(lsIndex.count) | Data:\(rawDataContainers.count)(\(msgData)) | Bundle:\(rawBundleContainers.count)(\(msgBundle))"
        return (sorted, info)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

struct AppPickerScannerView: View {
    @Binding var selectedBundleID: String
    var onSelectApp: ((ScannedAppEntry) -> Void)? = nil

    @StateObject private var vm = AppScannerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tổng số app: \(vm.filteredApps.count)")
                                .font(.headline)
                            Text("\(vm.statusMessage) • \(ByteCountFormatter.string(fromByteCount: vm.totalSizeBytes, countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            vm.scanApps(forceRefresh: true)
                        } label: {
                            HStack(spacing: 6) {
                                if vm.isScanning {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                }
                                Text(vm.isScanning ? "Đang quét" : "Chạy quét")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isScanning)
                    }

                    if !vm.debugDetail.isEmpty {
                        Text(vm.debugDetail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))

                List(vm.filteredApps) { app in
                    Button {
                        selectedBundleID = app.bundleID
                        if !app.containerPath.isEmpty {
                            zPatchStore.shared.registerContainer(bundleID: app.bundleID, containerPath: app.containerPath)
                        }
                        onSelectApp?(app)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Group {
                                if let uiImage = app.icon {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "app.dashed")
                                        .resizable()
                                        .scaledToFit()
                                        .padding(8)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("Bundle ID: \(app.bundleID)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                Text("UUID: \(app.containerUUID)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text("Size: \(app.formattedSize)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $vm.searchText, prompt: "Tìm tên, Bundle ID hoặc UUID...")
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
                    vm.scanApps(forceRefresh: false)
                }
            }
        }
    }
}
