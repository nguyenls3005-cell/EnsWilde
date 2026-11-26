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

// MARK: - WQ File Reader Engine (EnsWilde)

enum WQFileReader {
    private static let fileManager = FileManager.default

    static func normalize(_ path: String) -> String {
        CSStoreEngine.normalizeVarPath((path as NSString).standardizingPath)
    }

    @discardableResult
    static func ensureAccess(
        at path: String,
        requireWrite: Bool = false,
        allowFsgetpathFallback: Bool = true
    ) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalized = normalize(trimmed)
        if !requireWrite && fileManager.isReadableFile(atPath: normalized) {
            return true
        }

        let (granted, _, _) = wq.grantAccess(
            path: normalized,
            requireWrite: requireWrite,
            allowFsgetpathFallback: allowFsgetpathFallback
        )

        if granted {
            return true
        }
        return requireWrite
            ? fileManager.isWritableFile(atPath: normalized)
            : fileManager.isReadableFile(atPath: normalized)
    }

    static func listDirectory(at path: String, forceRefresh: Bool = false) -> [String] {
        let normalized = normalize(path)
        guard !normalized.isEmpty else { return [] }

        ensureAccess(at: normalized, requireWrite: false, allowFsgetpathFallback: true)

        let handlerItems = fsHandlers.getDirPaths(normalized, forceRefresh: forceRefresh)
        if !handlerItems.isEmpty {
            return handlerItems.map { normalize($0) }
        }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: normalized) else {
            return []
        }
        return contents.map { (normalized as NSString).appendingPathComponent($0) }
    }

    static func readData(at path: String) -> Data? {
        let normalized = normalize(path)
        guard ensureAccess(at: normalized, requireWrite: false, allowFsgetpathFallback: true) else {
            return nil
        }
        return try? Data(contentsOf: URL(fileURLWithPath: normalized), options: [.mappedIfSafe])
    }

    static func readPlist(at path: String) -> [String: Any]? {
        guard let data = readData(at: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )) as? [String: Any]
    }

    static func readImage(at path: String) -> UIImage? {
        guard let data = readData(at: path) else { return nil }
        return UIImage(data: data)
    }

    static func calculateSize(at path: String) -> Int64 {
        let normalized = normalize(path)
        guard !normalized.isEmpty,
              ensureAccess(at: normalized, requireWrite: false, allowFsgetpathFallback: true) else {
            return 0
        }

        let rootURL = URL(fileURLWithPath: normalized)
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            ensureAccess(at: fileURL.path, requireWrite: false, allowFsgetpathFallback: false)
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    static func resolveBundleID(forDataContainer path: String) -> String? {
        let normalized = normalize(path)
        let url = URL(fileURLWithPath: normalized)

        ensureAccess(at: normalized, requireWrite: false, allowFsgetpathFallback: true)
        if let xattrBID = getBIDFromXattr(url)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !xattrBID.isEmpty {
            return xattrBID
        }

        let metaPath = (normalized as NSString)
            .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        if let meta = readPlist(at: metaPath) {
            let candidate = (meta["MCMMetadataIdentifier"] as? String)
                ?? (meta["Identifier"] as? String)
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    static func scanAppBundles(forceRefresh: Bool = false) -> [String: (appPath: String, info: [String: Any])] {
        let bundleContainers = listDirectory(at: FSURL.appBundles.path, forceRefresh: forceRefresh)
        var result: [String: (appPath: String, info: [String: Any])] = [:]

        for container in bundleContainers {
            let normalizedContainer = normalize(container)
            ensureAccess(at: normalizedContainer, requireWrite: false, allowFsgetpathFallback: true)

            let children = listDirectory(at: normalizedContainer, forceRefresh: forceRefresh)
            for child in children {
                let normalizedChild = normalize(child)
                guard normalizedChild.hasSuffix(".app") else { continue }

                let infoPath = (normalizedChild as NSString).appendingPathComponent("Info.plist")
                if let info = readPlist(at: infoPath),
                   let bid = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !bid.isEmpty {
                    result[bid.lowercased()] = (appPath: normalizedChild, info: info)
                }
            }
        }

        return result
    }

    static func loadAppIcon(appBundlePath: String?, infoPlist: [String: Any]?) -> UIImage? {
        guard let bundlePath = appBundlePath, !bundlePath.isEmpty else { return nil }
        let normalizedBundle = normalize(bundlePath)
        ensureAccess(at: normalizedBundle, requireWrite: false, allowFsgetpathFallback: true)

        let bundleURL = URL(fileURLWithPath: normalizedBundle)
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
                    candidatePaths.append(contentsOf: [
                        "\(baseName)@3x.png",
                        "\(baseName)@2x.png",
                        "\(baseName).png",
                        baseName
                    ].map { bundleURL.appendingPathComponent($0).path })
                }
            }
        }

        for path in candidatePaths {
            if let image = readImage(at: path) {
                return image
            }
        }

        guard let enumerator = fileManager.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var bestImage: UIImage?
        var bestArea: CGFloat = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "png" else { continue }
            let lowerName = fileURL.lastPathComponent.lowercased()
            guard lowerName.contains("icon") || lowerName.contains("logo") else { continue }

            if let image = readImage(at: fileURL.path) {
                let area = image.size.width * image.size.height * image.scale * image.scale
                if area > bestArea {
                    bestArea = area
                    bestImage = image
                }
            }
        }

        return bestImage
    }

    static func collectApps(forceRefresh: Bool = false) -> AppScanReport {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let dataContainers = listDirectory(at: FSURL.appContainers.path, forceRefresh: forceRefresh)
        let bundleContainers = listDirectory(at: FSURL.appBundles.path, forceRefresh: forceRefresh)
        let bundleMap = scanAppBundles(forceRefresh: forceRefresh)

        var entries: [ScannedAppEntry] = []
        var matchedBIDCount = 0

        for rawContainer in dataContainers {
            let containerPath = normalize(rawContainer)
            let uuid = URL(fileURLWithPath: containerPath).lastPathComponent

            let resolvedBIDFromSystem = resolveBundleID(forDataContainer: containerPath)
            let resolvedBID = resolvedBIDFromSystem ?? uuid
            if resolvedBIDFromSystem != nil {
                matchedBIDCount += 1
            }

            let bundleMatch = bundleMap[resolvedBID.lowercased()]
            let infoPlist = bundleMatch?.info

            let displayName = (infoPlist?["CFBundleDisplayName"] as? String)?.trimmedNonEmpty
                ?? (infoPlist?["CFBundleName"] as? String)?.trimmedNonEmpty
                ?? bundleMatch.map { URL(fileURLWithPath: $0.appPath).deletingPathExtension().lastPathComponent }
                ?? resolvedBID

            let totalSize = calculateSize(at: containerPath)
                + (bundleMatch.map { calculateSize(at: $0.appPath) } ?? 0)
            let icon = loadAppIcon(appBundlePath: bundleMatch?.appPath, infoPlist: infoPlist)

            entries.append(
                ScannedAppEntry(
                    id: "\(resolvedBID)#\(uuid)",
                    name: displayName,
                    bundleID: resolvedBID,
                    containerUUID: uuid,
                    containerPath: containerPath,
                    bundlePath: bundleMatch?.appPath,
                    sizeBytes: totalSize,
                    icon: icon
                )
            )
        }

        let sortedEntries = entries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let debug = "Data:\(dataContainers.count) | BundleDirs:\(bundleContainers.count) | BID:\(matchedBIDCount) | Apps:\(bundleMap.count)"
        return AppScanReport(entries: sortedEntries, debugInfo: debug)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.lowercased().contains(query) ||
            $0.bundleID.lowercased().contains(query) ||
            $0.containerUUID.lowercased().contains(query)
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
            let report = WQFileReader.collectApps(forceRefresh: forceRefresh)
            await MainActor.run {
                self.apps = report.entries
                self.isScanning = false
                self.statusMessage = "Đã quét xong: \(report.entries.count) mục"
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
