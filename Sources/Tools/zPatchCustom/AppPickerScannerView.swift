import SwiftUI
import Foundation
import UIKit

struct ScannedAppEntry: Identifiable, Hashable {
    let id: String              // Bundle ID
    let name: String            // Tên app
    let bundleID: String        // Bundle ID
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
        apps.reduce(0) { $0 + $1.sizeBytes }
    }

    func scanApps(forceRefresh: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "Đang quét container qua EnsWilde..."

        Task.detached(priority: .userInitiated) {
            let scanned = Self.collectAppsViaWorseQuery(forceRefresh: forceRefresh)
            await MainActor.run {
                self.apps = scanned
                self.isScanning = false
                self.statusMessage = "Đã quét xong: \(self.apps.count) app"
            }
        }
    }

    @discardableResult
    private static func ensureReadAccess(at path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        if fm.isReadableFile(atPath: path) {
            return true
        }
        let (ok, _, _) = wq.grantAccess(path: path, requireWrite: false, allowFsgetpathFallback: true)
        return ok || fm.isReadableFile(atPath: path)
    }

    private static func readPlistDict(atPath path: String) -> [String: Any]? {
        guard ensureReadAccess(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return (try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )) as? [String: Any]
    }

    private static func directorySize(atPath path: String) -> Int64 {
        guard !path.isEmpty else { return 0 }
        _ = ensureReadAccess(atPath: path)

        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            var st = stat()
            if stat(path, &st) == 0 && st.st_size > 0 {
                return Int64(st.st_size)
            }
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

    private static func loadAppIcon(appBundlePath: String?, infoPlist: [String: Any]?) -> UIImage? {
        guard let bundlePath = appBundlePath, !bundlePath.isEmpty else { return nil }
        _ = ensureReadAccess(atPath: bundlePath)

        let bundleURL = URL(fileURLWithPath: bundlePath)
        let fm = FileManager.default

        if let plist = infoPlist,
           let icons = plist["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let lastIcon = files.last {
            let candidates = [
                "\(lastIcon)@3x.png",
                "\(lastIcon)@2x.png",
                "\(lastIcon).png",
                lastIcon
            ]
            for name in candidates {
                let iconPath = bundleURL.appendingPathComponent(name).path
                _ = ensureReadAccess(atPath: iconPath)
                if let img = UIImage(contentsOfFile: iconPath) {
                    return img
                }
            }
        }

        if let items = try? fm.contentsOfDirectory(atPath: bundlePath) {
            for item in items where item.lowercased().contains("appicon") && item.lowercased().hasSuffix(".png") {
                let iconPath = bundleURL.appendingPathComponent(item).path
                _ = ensureReadAccess(atPath: iconPath)
                if let img = UIImage(contentsOfFile: iconPath) {
                    return img
                }
            }
        }
        return nil
    }

    private static func mapBundleToAppBundlePath() -> [String: String] {
        var result: [String: String] = [:]
        let bundlePaths = fsHandlers.getDirPaths(FSURL.appBundles.path)

        for bPath in bundlePaths {
            _ = ensureReadAccess(atPath: bPath)
            guard let subItems = try? FileManager.default.contentsOfDirectory(atPath: bPath),
                  let appFolder = subItems.first(where: { $0.hasSuffix(".app") }) else {
                continue
            }
            let appDir = (bPath as NSString).appendingPathComponent(appFolder)
            let infoPath = (appDir as NSString).appendingPathComponent("Info.plist")
            if let info = readPlistDict(atPath: infoPath),
               let bid = info["CFBundleIdentifier"] as? String, !bid.isEmpty {
                result[bid.lowercased()] = appDir
            }
        }
        return result
    }

    private static func collectAppsViaWorseQuery(forceRefresh: Bool) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        _ = ensureReadAccess(atPath: FSURL.appContainers.path)
        _ = ensureReadAccess(atPath: "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist")

        let dataContainerPaths = fsHandlers.getDirPaths(FSURL.appContainers.path, forceRefresh: forceRefresh)
        let bundleLookup = mapBundleToAppBundlePath()

        var entries: [ScannedAppEntry] = []
        var seenBIDs: Set<String> = []

        for containerPath in dataContainerPaths {
            let stdPath = (containerPath as NSString).standardizingPath
            let uuid = URL(fileURLWithPath: stdPath).lastPathComponent

            var bid = getBIDFromXattr(URL(fileURLWithPath: stdPath))
            if bid == nil || bid?.isEmpty == true {
                let metaPath = (stdPath as NSString)
                    .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                if let meta = readPlistDict(atPath: metaPath) {
                    bid = (meta["MCMMetadataIdentifier"] as? String) ?? (meta["Identifier"] as? String)
                }
            }

            let bundleID = (bid?.isEmpty == false) ? bid! : uuid
            let lowerBID = bundleID.lowercased()
            if seenBIDs.contains(lowerBID) { continue }
            seenBIDs.insert(lowerBID)

            let appBundlePath = bundleLookup[lowerBID]
            let infoPlist: [String: Any]? = {
                guard let appBundlePath else { return nil }
                let infoPath = (appBundlePath as NSString).appendingPathComponent("Info.plist")
                return readPlistDict(atPath: infoPath)
            }()

            let displayName = (infoPlist?["CFBundleDisplayName"] as? String)
                ?? (infoPlist?["CFBundleName"] as? String)
                ?? (appBundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? bundleID)

            let dataSize = directorySize(atPath: stdPath)
            let bundleSize = appBundlePath.map { directorySize(atPath: $0) } ?? 0
            let totalSize = dataSize + bundleSize
            let icon = loadAppIcon(appBundlePath: appBundlePath, infoPlist: infoPlist)

            entries.append(
                ScannedAppEntry(
                    id: bundleID,
                    name: displayName,
                    bundleID: bundleID,
                    containerUUID: uuid,
                    containerPath: stdPath,
                    bundlePath: appBundlePath,
                    sizeBytes: totalSize,
                    icon: icon
                )
            )
        }

        return entries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tổng số app: \(vm.apps.count)")
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
                .padding()
                .background(Color(.secondarySystemBackground))

                List(vm.filteredApps) { app in
                    Button {
                        selectedBundleID = app.bundleID
                        zPatchStore.shared.registerContainer(bundleID: app.bundleID, containerPath: app.containerPath)
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
