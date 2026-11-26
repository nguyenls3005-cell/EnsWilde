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
    nonisolated private static func grantFileAccess(at path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        if fm.isReadableFile(atPath: path) {
            return true
        }
        let (ok, _, _) = wq.grantAccess(path: path, requireWrite: false, allowFsgetpathFallback: true)
        return ok || fm.isReadableFile(atPath: path)
    }

    nonisolated private static func readPlistDict(atPath path: String) -> [String: Any]? {
        guard grantFileAccess(at: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
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
        let fm = FileManager.default
        let bundleURL = URL(fileURLWithPath: bundlePath)
        var candidates: [String] = []

        if let plist = infoPlist {
            if let icons = plist["CFBundleIcons"] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String] {
                for baseName in files.reversed() {
                    candidates.append(contentsOf: [
                        "\(baseName)@3x.png",
                        "\(baseName)@2x.png",
                        "\(baseName).png",
                        baseName
                    ].map { bundleURL.appendingPathComponent($0).path })
                }
            }
            if let iconFiles = plist["CFBundleIconFiles"] as? [String] {
                for baseName in iconFiles.reversed() {
                    candidates.append(bundleURL.appendingPathComponent(baseName).path)
                    candidates.append(bundleURL.appendingPathComponent("\(baseName)@2x.png").path)
                    candidates.append(bundleURL.appendingPathComponent("\(baseName)@3x.png").path)
                }
            }
        }

        for p in candidates {
            if grantFileAccess(at: p), let img = UIImage(contentsOfFile: p) {
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

                if grantFileAccess(at: fileURL.path), let img = UIImage(contentsOfFile: fileURL.path) {
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

    nonisolated private static func collectApps(forceRefresh: Bool) -> (entries: [ScannedAppEntry], debugInfo: String) {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let rawDataContainers = fsHandlers.getDirPaths(FSURL.appContainers.path, forceRefresh: forceRefresh)
        let rawBundleContainers = fsHandlers.getDirPaths(FSURL.appBundles.path, forceRefresh: forceRefresh)

        // Quét Bundle/Application: xin quyền trực tiếp từng Info.plist bên trong *.app
        var bundleByBID: [String: (appPath: String, info: [String: Any])] = [:]
        let fm = FileManager.default

        for bContainer in rawBundleContainers {
            let stdB = CSStoreEngine.normalizeVarPath((bContainer as NSString).standardizingPath)
            guard let subItems = try? fm.contentsOfDirectory(atPath: stdB) else { continue }

            for item in subItems where item.hasSuffix(".app") {
                let appDir = (stdB as NSString).appendingPathComponent(item)
                let infoPath = (appDir as NSString).appendingPathComponent("Info.plist")
                if let info = readPlistDict(atPath: infoPath),
                   let bid = info["CFBundleIdentifier"] as? String, !bid.isEmpty {
                    bundleByBID[bid.lowercased()] = (appPath: appDir, info: info)
                }
            }
        }

        var entries: [ScannedAppEntry] = []
        var matchedBIDCount = 0

        for dContainer in rawDataContainers {
            let stdPath = CSStoreEngine.normalizeVarPath((dContainer as NSString).standardizingPath)
            let uuid = URL(fileURLWithPath: stdPath).lastPathComponent

            var bid = getBIDFromXattr(URL(fileURLWithPath: stdPath))
            if bid == nil || bid?.isEmpty == true {
                let metaPath = (stdPath as NSString)
                    .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                if let meta = readPlistDict(atPath: metaPath) {
                    bid = (meta["MCMMetadataIdentifier"] as? String) ?? (meta["Identifier"] as? String)
                }
            }

            let resolvedBID = (bid?.isEmpty == false) ? bid! : uuid
            if bid?.isEmpty == false {
                matchedBIDCount += 1
            }

            let bundleMatch = bundleByBID[resolvedBID.lowercased()]
            let infoPlist = bundleMatch?.info

            let realName = (infoPlist?["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? (infoPlist?["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? bundleMatch.map { URL(fileURLWithPath: $0.appPath).deletingPathExtension().lastPathComponent }
                ?? resolvedBID

            let size = directorySize(atPath: stdPath) + (bundleMatch.map { directorySize(atPath: $0.appPath) } ?? 0)
            let icon = loadAppIcon(appBundlePath: bundleMatch?.appPath, infoPlist: infoPlist)

            entries.append(
                ScannedAppEntry(
                    id: "\(resolvedBID)#\(uuid)",
                    name: realName,
                    bundleID: resolvedBID,
                    containerUUID: uuid,
                    containerPath: stdPath,
                    bundlePath: bundleMatch?.appPath,
                    sizeBytes: size,
                    icon: icon
                )
            )
        }

        let sorted = entries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let info = "Data:\(rawDataContainers.count) | BundleDirs:\(rawBundleContainers.count) | BID:\(matchedBIDCount) | Apps:\(bundleByBID.count)"
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
