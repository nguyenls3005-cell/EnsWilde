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
    private static let targetRoot = "/private/var/mobile/Containers/Data/Application"

    private static func fallbackName(from identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        return last.isEmpty ? identifier : last
    }

    private static func readMCMMetadata(at containerPath: String) -> (bundleID: String?, displayName: String?) {
        let metaNames = [
            ".com.apple.mobile_container_manager.metadata.plist",
            "com.apple.mobile_container_manager.metadata.plist"
        ]
        for name in metaNames {
            let full = (containerPath as NSString).appendingPathComponent(name)
            guard let data = fm.contents(atPath: full),
                  let dict = try? PropertyListSerialization.propertyList(
                      from: data,
                      options: [],
                      format: nil
                  ) as? [String: Any] else {
                continue
            }

            let bid = (dict["MCMMetadataIdentifier"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var appName: String? = nil
            for key in ["CFBundleDisplayName", "CFBundleName", "itemName"] {
                if let val = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !val.isEmpty {
                    appName = val
                    break
                }
            }

            if (bid != nil && !bid!.isEmpty) || appName != nil {
                return (
                    bundleID: (bid?.isEmpty == false) ? bid : nil,
                    displayName: appName
                )
            }
        }
        return (nil, nil)
    }

    private static func listContainerDirectories(forceRefresh: Bool) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()

        let granted = wq.grantAccess(path: targetRoot, requireWrite: false, allowFsgetpathFallback: true)
        defer { if granted.0 { wq.releaseAccess(path: targetRoot) } }

        if let names = try? fm.contentsOfDirectory(atPath: targetRoot), !names.isEmpty {
            for name in names {
                let full = (targetRoot as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    if seen.insert(full).inserted {
                        paths.append(full)
                    }
                }
            }
        }

        if paths.isEmpty {
            let fsList = fsHandlers.getDirPaths(targetRoot, forceRefresh: forceRefresh)
            for p in fsList {
                let clean = p.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && seen.insert(clean).inserted {
                    paths.append(clean)
                }
            }
        }

        return paths
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let dirs = listContainerDirectories(forceRefresh: forceRefresh)
        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(dirs.count)

        for path in dirs {
            autoreleasepool {
                let uuid = (path as NSString).lastPathComponent
                let url = URL(fileURLWithPath: path)

                let meta = readMCMMetadata(at: path)
                let fromStore = zPatchStore.shared.bundleIDForContainerUUID(uuid)
                let fromXattr = getBIDFromXattr(url)?.trimmingCharacters(in: .whitespacesAndNewlines)

                let rawBID = [fromStore, fromXattr, meta.bundleID]
                    .compactMap { $0 }
                    .first(where: { !$0.isEmpty }) ?? uuid

                let bundleID = zPatchItem.normalizedBundleID(rawBID).isEmpty ? rawBID : zPatchItem.normalizedBundleID(rawBID)
                let cachedName = zPatchStore.shared.cachedAppName(for: bundleID)
                let resolvedName = [cachedName, meta.displayName]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty }) ?? fallbackName(from: bundleID)

                if bundleID.caseInsensitiveCompare(uuid) != .orderedSame {
                    zPatchStore.shared.registerContainer(bundleID: bundleID, containerPath: path)
                }
                zPatchStore.shared.registerAppMeta(bundleID: bundleID, appName: resolvedName, icon: nil)

                entries.append(
                    ScannedAppEntry(
                        id: "\(uuid)_\(bundleID.lowercased())",
                        name: resolvedName,
                        bundleID: bundleID,
                        containerUUID: uuid,
                        containerPath: path,
                        icon: zPatchStore.shared.cachedAppIcon(for: bundleID)
                    )
                )
            }
        }

        return entries.sorted {
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
            $0.bundleID.lowercased().contains(q) ||
            $0.containerUUID.lowercased().contains(q)
        }
    }

    func scan(forceRefresh: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "Đang quét danh sách app..."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = AppScannerEngine.scan(forceRefresh: forceRefresh)
            DispatchQueue.main.async {
                self.apps = result
                self.isScanning = false
                self.statusMessage = "Đã quét xong: \(result.count) mục"
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        vm.scan(forceRefresh: false)
                    }
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
            if lazyIcon == nil {
                lazyIcon = zPatchStore.shared.cachedAppIcon(for: app.bundleID)
            }
        }
    }
}
