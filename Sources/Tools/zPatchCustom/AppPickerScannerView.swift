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
    private static let launchServicesPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"

    private static func loadLaunchServicesMap() -> [String: (bundleID: String, name: String)] {
        guard fm.fileExists(atPath: launchServicesPath),
              let data = fm.contents(atPath: launchServicesPath),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let userApps = plist["User"] as? [String: Any] else {
            return [:]
        }

        var result: [String: (bundleID: String, name: String)] = [:]
        result.reserveCapacity(userApps.count)

        for (bundleID, rawValue) in userApps {
            guard let info = rawValue as? [String: Any],
                  let uuid = info["Container"] as? String,
                  !uuid.isEmpty else {
                continue
            }

            let displayName = (info["CFBundleDisplayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleName = (info["CFBundleName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = bundleID.split(separator: ".").last.map(String.init) ?? bundleID

            let resolvedName: String
            if let displayName, !displayName.isEmpty {
                resolvedName = displayName
            } else if let bundleName, !bundleName.isEmpty {
                resolvedName = bundleName
            } else {
                resolvedName = fallback
            }

            result[uuid.lowercased()] = (bundleID: bundleID, name: resolvedName)
        }

        return result
    }

    private static func safeIcon(for bundleID: String) -> UIImage? {
        guard !bundleID.isEmpty, !bundleID.contains("/") else { return nil }
        return try? JITEnableContext.shared.getAppIcon(withBundleId: bundleID)
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        var rawContainers: [String] = []

        autoreleasepool {
            if forceRefresh {
                fsHandlers.invalidateCache()
            }
            rawContainers = fsHandlers.getDirPaths(
                FSURL.appContainers.path,
                forceRefresh: forceRefresh
            )
        }

        let lsMap = loadLaunchServicesMap()
        var list: [ScannedAppEntry] = []
        list.reserveCapacity(rawContainers.count)

        for rawPath in rawContainers {
            autoreleasepool {
                let normPath = CSStoreEngine.normalizeVarPath(rawPath)
                guard !normPath.isEmpty else { return }

                let uuid = (normPath as NSString).lastPathComponent
                guard !uuid.isEmpty else { return }
                let lowerUUID = uuid.lowercased()

                var resolvedBID = lsMap[lowerUUID]?.bundleID
                let resolvedName = lsMap[lowerUUID]?.name

                if resolvedBID == nil || resolvedBID?.isEmpty == true {
                    if let xattrBID = getBIDFromXattr(URL(fileURLWithPath: normPath))?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !xattrBID.isEmpty {
                        resolvedBID = xattrBID
                    }
                }

                let finalBID = (resolvedBID?.isEmpty == false) ? resolvedBID! : uuid
                let finalName: String
                if let resolvedName, !resolvedName.isEmpty {
                    finalName = resolvedName
                } else if finalBID != uuid {
                    finalName = finalBID.split(separator: ".").last.map(String.init) ?? finalBID
                } else {
                    finalName = uuid
                }

                let icon = safeIcon(for: finalBID)

                list.append(
                    ScannedAppEntry(
                        id: "\(finalBID)#\(uuid)",
                        name: finalName,
                        bundleID: finalBID,
                        containerUUID: uuid,
                        containerPath: normPath,
                        icon: icon
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.lowercased().contains(query) ||
            $0.bundleID.lowercased().contains(query) ||
            $0.containerUUID.lowercased().contains(query)
        }
    }

    func scan(forceRefresh: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "Đang quét danh sách app..."

        DispatchQueue.main.async {
            let result = AppScannerEngine.scan(forceRefresh: forceRefresh)
            self.apps = result
            self.isScanning = false
            self.statusMessage = "Đã quét xong: \(result.count) app"
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
                            .font(.headline)
                        Text(vm.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        vm.scan(forceRefresh: true)
                    } label: {
                        HStack(spacing: 6) {
                            if vm.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(vm.isScanning ? "Đang quét" : "Quét lại")
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

                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(app.bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                Text(app.containerUUID)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 4)
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
                    .padding(10)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 46, height: 46)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
