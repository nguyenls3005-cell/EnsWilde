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
    let bundlePath: String?     // Đường dẫn .app (nếu có)
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

// MARK: - Fast CSStore + FSHandlers Reader (EnsWilde)

enum WQFastEngineReader {
    private static let fm = FileManager.default
    private static let launchServicesMapPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"

    /// Map ngược từ containerUUID -> (bundleID, displayName) đọc 1 lần từ LastLaunchServicesMap.plist
    private static func loadLaunchServicesIndex() -> [String: (bundleID: String, name: String)] {
        guard let data = fm.contents(atPath: launchServicesMapPath),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let user = plist["User"] as? [String: Any] else {
            return [:]
        }

        var byUUID: [String: (bundleID: String, name: String)] = [:]
        byUUID.reserveCapacity(user.count)

        for (bundleID, rawValue) in user {
            guard let dict = rawValue as? [String: Any],
                  let uuid = dict["Container"] as? String,
                  !uuid.isEmpty else {
                continue
            }

            let displayName = (dict["CFBundleDisplayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleName = (dict["CFBundleName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = bundleID.split(separator: ".").last.map(String.init) ?? bundleID

            let resolvedName: String
            if let d = displayName, !d.isEmpty {
                resolvedName = d
            } else if let b = bundleName, !b.isEmpty {
                resolvedName = b
            } else {
                resolvedName = fallbackName
            }

            byUUID[uuid.lowercased()] = (bundleID: bundleID, name: resolvedName)
        }

        return byUUID
    }

    private static func fastContainerSize(atPath path: String) -> Int64 {
        let norm = CSStoreEngine.normalizeVarPath(path)
        let rootURL = URL(fileURLWithPath: norm)
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

    static func collectFast(
        forceRefresh: Bool = false,
        includeSizes: Bool = false,
        onProgress: ((String) -> Void)? = nil
    ) -> AppScanReport {
        if forceRefresh {
            onProgress?("Xoá cache...")
            fsHandlers.invalidateCache()
        }

        onProgress?("Đọc LaunchServices & Containers...")
        let lsByUUID = loadLaunchServicesIndex()
        let containerPaths = fsHandlers.getDirPaths(
            FSURL.appContainers.path,
            forceRefresh: forceRefresh
        )

        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(containerPaths.count)
        var matchedBIDCount = 0

        for (idx, rawPath) in containerPaths.enumerated() {
            let normPath = CSStoreEngine.normalizeVarPath(rawPath)
            let uuid = URL(fileURLWithPath: normPath).lastPathComponent
            let lowerUUID = uuid.lowercased()

            if idx % 25 == 0 {
                onProgress?("Đang ghép \(idx + 1)/\(containerPaths.count)...")
            }

            var resolvedBID: String? = lsByUUID[lowerUUID]?.bundleID
            var resolvedName: String? = lsByUUID[lowerUUID]?.name

            if resolvedBID == nil || resolvedBID?.isEmpty == true {
                if let xattrBID = getBIDFromXattr(URL(fileURLWithPath: normPath))?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !xattrBID.isEmpty {
                    resolvedBID = xattrBID
                }
            }

            let finalBID: String
            if let bid = resolvedBID, !bid.isEmpty {
                finalBID = bid
                matchedBIDCount += 1
            } else {
                finalBID = uuid
            }

            let finalName: String
            if let name = resolvedName, !name.isEmpty {
                finalName = name
            } else if finalBID != uuid {
                finalName = finalBID.split(separator: ".").last.map(String.init) ?? finalBID
            } else {
                finalName = uuid
            }

            let size = includeSizes ? fastContainerSize(atPath: normPath) : 0

            entries.append(
                ScannedAppEntry(
                    id: "\(finalBID)#\(uuid)",
                    name: finalName,
                    bundleID: finalBID,
                    containerUUID: uuid,
                    containerPath: normPath,
                    bundlePath: nil,
                    sizeBytes: size,
                    icon: nil
                )
            )
        }

        let sorted = entries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let debug = "Containers:\(containerPaths.count) | LS:\(lsByUUID.count) | BID:\(matchedBIDCount)"
        return AppScanReport(entries: sorted, debugInfo: debug)
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

    func scanApps(forceRefresh: Bool = false, includeSizes: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "Đang quét..."
        debugDetail = "Khởi tạo..."

        Task.detached(priority: .userInitiated) {
            let report = WQFastEngineReader.collectFast(
                forceRefresh: forceRefresh,
                includeSizes: includeSizes
            ) { step in
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
                            vm.scanApps(forceRefresh: true, includeSizes: false)
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
                            Image(systemName: "app.badge.checkmark")
                                .resizable()
                                .scaledToFit()
                                .padding(10)
                                .frame(width: 48, height: 48)
                                .foregroundStyle(.tint)
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

                                if app.sizeBytes > 0 {
                                    Text("Size: \(app.formattedSize)")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.tint)
                                }
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
                    vm.scanApps(forceRefresh: false, includeSizes: false)
                }
            }
        }
    }
}
