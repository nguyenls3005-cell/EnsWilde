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
    private static let targetRoot = "/var/mobile/Containers/Data/Application"

    private static func extractUUID(from containerPath: String) -> String {
        let norm = CSStoreEngine.normalizeVarPath(containerPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !norm.isEmpty else { return "" }
        let last = (norm as NSString).lastPathComponent
        return last == "Application" ? "" : last
    }

    private static func fallbackName(from bundleID: String, uuid: String) -> String {
        if !bundleID.isEmpty {
            let parts = bundleID.split(separator: ".").map(String.init)
            if let last = parts.last, !last.isEmpty {
                return last
            }
            return bundleID
        }
        return uuid.isEmpty ? "Unknown App" : "App (\(String(uuid.prefix(8))))"
    }

    private static func listPhysicalContainerUUIDs() -> [String: String] {
        var uuidToPath: [String: String] = [:]
        let roots = [
            "/private/var/mobile/Containers/Data/Application",
            "/var/mobile/Containers/Data/Application"
        ]

        for root in roots {
            let granted = wq.grantAccess(path: root, requireWrite: false, allowFsgetpathFallback: true)
            defer { if granted.0 { wq.releaseAccess(path: root) } }

            if let names = try? fm.contentsOfDirectory(atPath: root), !names.isEmpty {
                for name in names {
                    let full = CSStoreEngine.normalizeVarPath((root as NSString).appendingPathComponent(name))
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                        let key = name.lowercased()
                        if uuidToPath[key] == nil {
                            uuidToPath[key] = full
                        }
                    }
                }
            }
        }

        return uuidToPath
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let records = CSStoreEngine.shared.allAppRecords()
        let physicalUUIDs = listPhysicalContainerUUIDs()

        var entries: [ScannedAppEntry] = []
        entries.reserveCapacity(records.count)
        var seenBIDs = Set<String>()

        for rec in records {
            autoreleasepool {
                let rawBID = zPatchItem.normalizedBundleID(rec.bundleID)
                guard !rawBID.isEmpty else { return }

                let lowerBID = rawBID.lowercased()
                guard seenBIDs.insert(lowerBID).inserted else { return }

                let normalizedDataPath = CSStoreEngine.normalizeVarPath(rec.dataContainerPath)
                var uuid = extractUUID(from: normalizedDataPath)

                if uuid.isEmpty, let (_, hitPath) = CSStoreEngine.shared.lookupAppContainer(forBundleID: rawBID),
                   let hitPath, !hitPath.isEmpty {
                    let normHit = CSStoreEngine.normalizeVarPath(hitPath)
                    uuid = extractUUID(from: normHit)
                }

                let resolvedContainerPath: String = {
                    if !normalizedDataPath.isEmpty {
                        return normalizedDataPath
                    }
                    if !uuid.isEmpty, let phys = physicalUUIDs[uuid.lowercased()] {
                        return phys
                    }
                    return ""
                }()

                let resolvedName: String = {
                    if let cached = zPatchStore.shared.cachedAppName(for: rawBID)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !cached.isEmpty {
                        return cached
                    }
                    let cleanRecName = rec.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanRecName.isEmpty, cleanRecName.caseInsensitiveCompare(rawBID) != .orderedSame {
                        return cleanRecName
                    }
                    return fallbackName(from: rawBID, uuid: uuid)
                }()

                if !resolvedContainerPath.isEmpty {
                    zPatchStore.shared.registerContainer(bundleID: rawBID, containerPath: resolvedContainerPath)
                }
                zPatchStore.shared.registerAppMeta(bundleID: rawBID, appName: resolvedName, icon: nil)

                let entryID = uuid.isEmpty ? lowerBID : "\(uuid.lowercased())_\(lowerBID)"
                entries.append(
                    ScannedAppEntry(
                        id: entryID,
                        name: resolvedName,
                        bundleID: rawBID,
                        containerUUID: uuid,
                        containerPath: resolvedContainerPath,
                        icon: zPatchStore.shared.cachedAppIcon(for: rawBID)
                    )
                )
            }
        }

        if entries.isEmpty {
            let dirs = fsHandlers.getDirPaths(targetRoot, forceRefresh: forceRefresh)
            for path in dirs {
                let norm = CSStoreEngine.normalizeVarPath(path)
                let uuid = (norm as NSString).lastPathComponent
                let bid = zPatchStore.shared.bundleIDForContainerUUID(uuid)
                    ?? getBIDFromXattr(URL(fileURLWithPath: norm))
                    ?? uuid
                let cleanBID = zPatchItem.normalizedBundleID(bid)
                let name = zPatchStore.shared.cachedAppName(for: cleanBID) ?? fallbackName(from: cleanBID, uuid: uuid)
                entries.append(
                    ScannedAppEntry(
                        id: "\(uuid)_\(cleanBID.lowercased())",
                        name: name,
                        bundleID: cleanBID,
                        containerUUID: uuid,
                        containerPath: norm,
                        icon: zPatchStore.shared.cachedAppIcon(for: cleanBID)
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
            if lazyIcon == nil {
                lazyIcon = zPatchStore.shared.cachedAppIcon(for: app.bundleID)
            }
        }
    }
}
