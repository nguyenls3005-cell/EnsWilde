import SwiftUI
import Foundation
import UIKit

// MARK: - Models

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

struct AppScanReport {
    let entries: [ScannedAppEntry]
    let debugInfo: String
}

// MARK: - WQ Full Reader (EnsWilde)

enum WQFullReader {
    private static let fm = FileManager.default

    @inline(__always)
    static func normalize(_ path: String) -> String {
        CSStoreEngine.normalizeVarPath((path as NSString).standardizingPath)
    }

    @discardableResult
    @inline(__always)
    static func ensureAccess(
        at path: String,
        requireWrite: Bool = false,
        allowFsgetpathFallback: Bool = true
    ) -> Bool {
        guard !path.isEmpty else { return false }
        if !requireWrite && fm.isReadableFile(atPath: path) {
            return true
        }
        let (ok, _, _) = wq.grantAccess(
            path: path,
            requireWrite: requireWrite,
            allowFsgetpathFallback: allowFsgetpathFallback
        )
        return ok || (requireWrite ? fm.isWritableFile(atPath: path) : fm.isReadableFile(atPath: path))
    }

    static func listTopDirs(at rawPath: String, forceRefresh: Bool) -> [String] {
        let path = normalize(rawPath)
        guard !path.isEmpty else { return [] }

        let items = fsHandlers.getDirPaths(path, forceRefresh: forceRefresh)
        if !items.isEmpty {
            return items
        }

        ensureAccess(at: path, requireWrite: false, allowFsgetpathFallback: true)
        let retry = fsHandlers.getDirPaths(path, forceRefresh: forceRefresh)
        if !retry.isEmpty {
            return retry
        }

        guard let subs = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        return subs.map { (path as NSString).appendingPathComponent($0) }
    }

    static func readDataFast(at rawPath: String) -> Data? {
        let path = normalize(rawPath)
        let url = URL(fileURLWithPath: path)

        if let data = try? Data(contentsOf: url), !data.isEmpty {
            return data
        }

        guard ensureAccess(at: path, requireWrite: false, allowFsgetpathFallback: true),
              let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        return data
    }

    static func readPlistFast(at rawPath: String) -> [String: Any]? {
        guard let data = readDataFast(at: rawPath) else { return nil }
        return (try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )) as? [String: Any]
    }

    static func readImageFast(at rawPath: String) -> UIImage? {
        let path = normalize(rawPath)
        if fm.isReadableFile(atPath: path), let img = UIImage(contentsOfFile: path) {
            return img
        }
        guard let data = readDataFast(at: path) else { return nil }
        return UIImage(data: data)
    }

    static func directorySizeFast(at rawPath: String) -> Int64 {
        let path = normalize(rawPath)
        guard !path.isEmpty else { return 0 }

        let rootURL = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
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

    static func resolveBundleID(forDataContainer containerPath: String) -> String? {
        let url = URL(fileURLWithPath: containerPath)
        if let bid = getBIDFromXattr(url)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bid.isEmpty {
            return bid
        }

        let metaPath = (containerPath as NSString)
            .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        if let meta = readPlistFast(at: metaPath) {
            let candidate = (meta["MCMMetadataIdentifier"] as? String)
                ?? (meta["Identifier"] as? String)
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    static func scanAppBundles(
        forceRefresh: Bool,
        onProgress: ((String) -> Void)?
    ) -> [String: (appPath: String, info: [String: Any])] {
        let bundleContainers = listTopDirs(at: FSURL.appBundles.path, forceRefresh: forceRefresh)
        var map: [String: (appPath: String, info: [String: Any])] = [:]
        map.reserveCapacity(bundleContainers.count)

        for (idx, rawContainer) in bundleContainers.enumerated() {
            let container = normalize(rawContainer)
            onProgress?("Bundle \(idx + 1)/\(bundleContainers.count)")

            var subNames = (try? fm.contentsOfDirectory(atPath: container)) ?? []
            if subNames.isEmpty {
                ensureAccess(at: container, requireWrite: false, allowFsgetpathFallback: true)
                subNames = (try? fm.contentsOfDirectory(atPath: container)) ?? []
            }

            for name in subNames where name.hasSuffix(".app") {
                let child = (container as NSString).appendingPathComponent(name)
                let infoPath = (child as NSString).appendingPathComponent("Info.plist")
                if let info = readPlistFast(at: infoPath),
                   let bid = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !bid.isEmpty {
                    map[bid.lowercased()] = (appPath: child, info: info)
                }
            }
        }

        return map
    }

    static func loadAppIcon(appBundlePath: String?, infoPlist: [String: Any]?) -> UIImage? {
        guard let bundlePath = appBundlePath, !bundlePath.isEmpty else { return nil }
        let bundleURL = URL(fileURLWithPath: bundlePath)
        var candidates: [String] = []
        candidates.reserveCapacity(12)

        if let plist = infoPlist {
            if let icons = plist["CFBundleIcons"] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String] {
                for name in files.reversed() {
                    candidates.append((bundleURL.appendingPathComponent("\(name)@3x.png")).path)
                    candidates.append((bundleURL.appendingPathComponent("\(name)@2x.png")).path)
                    candidates.append((bundleURL.appendingPathComponent("\(name).png")).path)
                    candidates.append((bundleURL.appendingPathComponent(name)).path)
                }
            }
            if let iconFiles = plist["CFBundleIconFiles"] as? [String] {
                for name in iconFiles.reversed() {
                    candidates.append((bundleURL.appendingPathComponent("\(name)@3x.png")).path)
                    candidates.append((bundleURL.appendingPathComponent("\(name)@2x.png")).path)
                    candidates.append((bundleURL.appendingPathComponent("\(name).png")).path)
                }
            }
        }

        for path in candidates {
            if let img = readImageFast(at: path) {
                return img
            }
        }

        if let topItems = try? fm.contentsOfDirectory(atPath: bundlePath) {
            var bestImage: UIImage?
            var bestArea: CGFloat = 0

            for item in topItems where item.lowercased().hasSuffix(".png") {
                let lower = item.lowercased()
                guard lower.contains("icon") || lower.contains("logo") else { continue }
                let fullPath = (bundlePath as NSString).appendingPathComponent(item)
                if let img = readImageFast(at: fullPath) {
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

    static func collectFullApps(
        forceRefresh: Bool = false,
        onProgress: ((String) -> Void)? = nil
    ) -> AppScanReport {
        if forceRefresh {
            onProgress?("Xoá cache...")
            fsHandlers.invalidateCache()
        }

        onProgress?("Quét Data Containers...")
        let rawDataContainers = listTopDirs(at: FSURL.appContainers.path, forceRefresh: forceRefresh)

        onProgress?("Quét Bundle Containers...")
        let rawBundleContainers = listTopDirs(at: FSURL.appBundles.path, forceRefresh: forceRefresh)

        onProgress?("Đọc Info.plist...")
        let bundleMap = scanAppBundles(forceRefresh: forceRefresh, onProgress: onProgress)

        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(rawDataContainers.count)
        var matchedBIDCount = 0

        for (index, rawContainer) in rawDataContainers.enumerated() {
            let containerPath = normalize(rawContainer)
            let uuid = URL(fileURLWithPath: containerPath).lastPathComponent

            if index % 10 == 0 {
                onProgress?("Đang xử lý \(index + 1)/\(rawDataContainers.count)...")
            }

            let resolvedBIDFromSystem = resolveBundleID(forDataContainer: containerPath)
            let resolvedBID = resolvedBIDFromSystem ?? uuid
            if resolvedBIDFromSystem != nil {
                matchedBIDCount += 1
            }

            let bundleMatch = bundleMap[resolvedBID.lowercased()]
            let infoPlist = bundleMatch?.info

            let realName = (infoPlist?["CFBundleDisplayName"] as? String)?.trimmedNonEmpty
                ?? (infoPlist?["CFBundleName"] as? String)?.trimmedNonEmpty
                ?? bundleMatch.map { URL(fileURLWithPath: $0.appPath).deletingPathExtension().lastPathComponent }
                ?? resolvedBID

            let size = directorySizeFast(at: containerPath)
            let icon = loadAppIcon(appBundlePath: bundleMatch?.appPath, infoPlist: infoPlist)

            entries.append(
                ScannedAppEntry(
                    id: "\(resolvedBID)#\(uuid)",
                    name: realName,
                    bundleID: resolvedBID,
                    containerUUID: uuid,
                    containerPath: containerPath,
                    bundlePath: bundleMatch?.appPath,
                    sizeBytes: size,
                    icon: icon
                )
            )
        }

        let sorted = entries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let info = "Data:\(rawDataContainers.count) | BundleDirs:\(rawBundleContainers.count) | BID:\(matchedBIDCount) | Apps:\(bundleMap.count)"
        return AppScanReport(entries: sorted, debugInfo: info)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let v = trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}

// MARK: - ViewModel

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
        statusMessage = "Đang quét full..."
        debugDetail = "Khởi tạo..."

        Task.detached(priority: .userInitiated) {
            let report = WQFullReader.collectFullApps(forceRefresh: forceRefresh) { step in
                Task { @MainActor in
                    self.debugDetail = step
                }
            }
            await MainActor.run {
                self.apps = report.entries
                self.isScanning = false
                self.statusMessage = "Đã quét xong: \(report.entries.count) app"
                self.debugDetail = report.debugInfo
            }
        }
    }
}

// MARK: - View

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
