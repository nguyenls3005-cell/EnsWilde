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
    private static func cleanContainerPath(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let stripped = raw
            .replacingOccurrences(of: "file://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return "" }
        let norm = CSStoreEngine.normalizeVarPath(stripped)
        if norm.hasPrefix("/") {
            return (norm as NSString).standardizingPath
        }
        return "/var/mobile/Containers/Data/Application/\(norm)"
    }

    private static func displayNameFromInfo(_ info: [String: Any], bundleID: String) -> String {
        if let disp = (info["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !disp.isEmpty {
            return disp
        }
        if let bname = (info["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bname.isEmpty {
            return bname
        }
        if let item = (info["itemName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !item.isEmpty {
            return item
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private static func readLaunchServicesMap() -> [String: (name: String, containerPath: String)] {
        var result: [String: (name: String, containerPath: String)] = [:]
        let candidates = [
            "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist",
            "/private/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"
        ]

        for path in candidates {
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data,
                      options: [],
                      format: nil
                  ) as? [String: Any] else {
                continue
            }

            for sectionKey in ["User", "System", "Internal"] {
                guard let section = plist[sectionKey] as? [String: Any] else { continue }
                for (rawBID, rawInfo) in section {
                    let bid = rawBID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !bid.isEmpty, let info = rawInfo as? [String: Any] else { continue }
                    let name = displayNameFromInfo(info, bundleID: bid)
                    let cPath = cleanContainerPath(info["Container"] as? String)
                    let key = bid.lowercased()
                    if let prev = result[key] {
                        result[key] = (
                            name: name.isEmpty ? prev.name : name,
                            containerPath: cPath.isEmpty ? prev.containerPath : cPath
                        )
                    } else {
                        result[key] = (name: name, containerPath: cPath)
                    }
                }
            }

            if !result.isEmpty {
                break
            }
        }

        return result
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        var merged: [String: ScannedAppEntry] = [:]

        // 1. Lấy từ cache đã lưu trong UserDefaults của zPatchStore
        let ud = UserDefaults.standard
        let savedNames = ud.dictionary(forKey: zPatchStore.appNameMapKey) as? [String: String] ?? [:]
        let savedContainers = ud.dictionary(forKey: zPatchStore.containerMapKey) as? [String: String] ?? [:]

        for (rawKey, rawName) in savedNames {
            let bid = zPatchItem.normalizedBundleID(rawKey)
            guard !bid.isEmpty else { continue }
            let lower = bid.lowercased()
            let cPath = cleanContainerPath(savedContainers[lower] ?? savedContainers[rawKey])
            let uuid = cPath.isEmpty ? "" : (cPath as NSString).lastPathComponent
            let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = cleanName.isEmpty
                ? (bid.split(separator: ".").last.map(String.init) ?? bid)
                : cleanName

            merged[lower] = ScannedAppEntry(
                id: bid,
                name: finalName,
                bundleID: bid,
                containerUUID: uuid,
                containerPath: cPath,
                icon: nil
            )
        }

        // 2. Đọc LastLaunchServicesMap.plist để có đầy đủ Bundle ID + Tên + Container
        let lsMap = readLaunchServicesMap()
        for (lowerBID, entry) in lsMap {
            let bid = zPatchItem.normalizedBundleID(lowerBID)
            guard !bid.isEmpty else { continue }
            let uuid = entry.containerPath.isEmpty ? "" : (entry.containerPath as NSString).lastPathComponent

            if let old = merged[lowerBID] {
                merged[lowerBID] = ScannedAppEntry(
                    id: old.bundleID,
                    name: entry.name.isEmpty ? old.name : entry.name,
                    bundleID: old.bundleID,
                    containerUUID: uuid.isEmpty ? old.containerUUID : uuid,
                    containerPath: entry.containerPath.isEmpty ? old.containerPath : entry.containerPath,
                    icon: nil
                )
            } else {
                merged[lowerBID] = ScannedAppEntry(
                    id: bid,
                    name: entry.name,
                    bundleID: bid,
                    containerUUID: uuid,
                    containerPath: entry.containerPath,
                    icon: nil
                )
            }
        }

        // 3. Nếu vẫn trống hoặc forceRefresh, thử lấy danh sách container qua CSStoreEngine
        if forceRefresh || merged.isEmpty {
            if let paths = CSStoreEngine.shared.containerPaths(forRoot: FSURL.appContainers.path) {
                for rawPath in paths {
                    let cPath = cleanContainerPath(rawPath)
                    guard !cPath.isEmpty else { continue }
                    let uuid = (cPath as NSString).lastPathComponent
                    let bidFromXattr = getBIDFromXattr(URL(fileURLWithPath: cPath))?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let bidFromStore = zPatchStore.shared.bundleIDForContainerUUID(uuid)
                    guard let rawBID = (bidFromXattr?.isEmpty == false ? bidFromXattr : bidFromStore),
                          !rawBID.isEmpty else { continue }

                    let bid = zPatchItem.normalizedBundleID(rawBID)
                    let lower = bid.lowercased()
                    if merged[lower] == nil {
                        let fallbackName = bid.split(separator: ".").last.map(String.init) ?? bid
                        merged[lower] = ScannedAppEntry(
                            id: bid,
                            name: fallbackName,
                            bundleID: bid,
                            containerUUID: uuid,
                            containerPath: cPath,
                            icon: nil
                        )
                    } else if merged[lower]?.containerPath.isEmpty == true {
                        let existing = merged[lower]!
                        merged[lower] = ScannedAppEntry(
                            id: existing.id,
                            name: existing.name,
                            bundleID: existing.bundleID,
                            containerUUID: uuid,
                            containerPath: cPath,
                            icon: nil
                        )
                    }
                }
            }
        }

        // Lưu gộp 1 lần duy nhất sau khi quét xong
        if !merged.isEmpty {
            var nameUpdate: [String: String] = savedNames
            var containerUpdate: [String: String] = savedContainers
            for (lower, item) in merged {
                nameUpdate[lower] = item.name
                if !item.containerPath.isEmpty {
                    containerUpdate[lower] = item.containerPath
                }
            }
            ud.set(nameUpdate, forKey: zPatchStore.appNameMapKey)
            ud.set(containerUpdate, forKey: zPatchStore.containerMapKey)
        }

        return merged.values.sorted {
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
            $0.bundleID.lowercased().contains(q)
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
            if lazyIcon == nil, let cached = zPatchStore.shared.cachedAppIcon(for: app.bundleID) {
                lazyIcon = cached
            }
        }
    }
}
