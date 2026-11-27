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
    let appBundlePath: String
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
    private static func fallbackName(for bundleID: String) -> String {
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.isEmpty ? bundleID : last
    }

    static func iconFromBundlePath(_ appBundlePath: String) -> UIImage? {
        guard !appBundlePath.isEmpty else { return nil }
        let fm = FileManager.default
        let infoPath = (appBundlePath as NSString).appendingPathComponent("Info.plist")

        var candidateFiles: [String] = []
        if let data = fm.contents(atPath: infoPath),
           let plist = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) as? [String: Any] {
            if let iconsDict = plist["CFBundleIcons"] as? [String: Any],
               let primary = iconsDict["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String] {
                candidateFiles.append(contentsOf: files.reversed())
            }
            if let legacyFiles = plist["CFBundleIconFiles"] as? [String] {
                candidateFiles.append(contentsOf: legacyFiles.reversed())
            }
        }

        for base in candidateFiles {
            for suffix in ["@3x.png", "@2x.png", ".png"] {
                let name = base.hasSuffix(".png") ? base : base + suffix
                let full = (appBundlePath as NSString).appendingPathComponent(name)
                if fm.fileExists(atPath: full), let img = UIImage(contentsOfFile: full) {
                    return img
                }
            }
        }

        if let items = try? fm.contentsOfDirectory(atPath: appBundlePath) {
            for file in items where file.lowercased().hasPrefix("appicon") && file.lowercased().hasSuffix(".png") {
                let full = (appBundlePath as NSString).appendingPathComponent(file)
                if let img = UIImage(contentsOfFile: full) {
                    return img
                }
            }
        }

        return nil
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        let _ = forceRefresh
        let ud = UserDefaults.standard
        let savedNames = ud.dictionary(forKey: zPatchStore.appNameMapKey) as? [String: String] ?? [:]
        let savedContainers = ud.dictionary(forKey: zPatchStore.containerMapKey) as? [String: String] ?? [:]

        var merged: [String: ScannedAppEntry] = [:]

        for (rawBID, rawName) in savedNames {
            let bid = zPatchItem.normalizedBundleID(rawBID)
            guard !bid.isEmpty else { continue }
            let lower = bid.lowercased()
            let cPath = CSStoreEngine.normalizeVarPath(savedContainers[lower] ?? savedContainers[rawBID] ?? "")
            let uuid = cPath.isEmpty ? "" : (cPath as NSString).lastPathComponent
            let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = cleanName.isEmpty ? fallbackName(for: bid) : cleanName

            merged[lower] = ScannedAppEntry(
                id: bid,
                name: displayName,
                bundleID: bid,
                containerUUID: uuid,
                containerPath: cPath,
                appBundlePath: "",
                icon: zPatchStore.shared.cachedAppIcon(for: bid)
            )
        }

        for rec in CSStoreEngine.shared.allAppRecords() {
            let bid = zPatchItem.normalizedBundleID(rec.bundleID)
            guard !bid.isEmpty else { continue }
            let lower = bid.lowercased()
            let cPath = !rec.dataContainerPath.isEmpty ? rec.dataContainerPath : rec.bundleContainerPath
            let uuid = cPath.isEmpty ? "" : (cPath as NSString).lastPathComponent
            let title = rec.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallbackName(for: bid)
                : rec.name

            merged[lower] = ScannedAppEntry(
                id: bid,
                name: title,
                bundleID: bid,
                containerUUID: uuid,
                containerPath: cPath,
                appBundlePath: rec.appBundlePath,
                icon: zPatchStore.shared.cachedAppIcon(for: bid)
            )
        }

        if !merged.isEmpty {
            var nextNames = savedNames
            var nextContainers = savedContainers
            for (lower, entry) in merged {
                nextNames[lower] = entry.name
                if !entry.containerPath.isEmpty {
                    nextContainers[lower] = entry.containerPath
                }
            }
            ud.set(nextNames, forKey: zPatchStore.appNameMapKey)
            ud.set(nextContainers, forKey: zPatchStore.containerMapKey)
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
                            appBundlePath: app.appBundlePath,
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
                    vm.scan(forceRefresh: false)
                }
            }
        }
    }
}

private final class BundleIconQueue {
    static let shared = BundleIconQueue()
    private let queue = DispatchQueue(label: "zpatch.bundle.icon.queue", qos: .utility)

    func loadIcon(for app: ScannedAppEntry, completion: @escaping (UIImage?) -> Void) {
        if let cached = zPatchStore.shared.cachedAppIcon(for: app.bundleID) {
            completion(cached)
            return
        }

        queue.async {
            let img = AppScannerEngine.iconFromBundlePath(app.appBundlePath)
            if let img {
                zPatchStore.shared.registerAppMeta(bundleID: app.bundleID, appName: app.name, icon: img)
            }
            DispatchQueue.main.async {
                completion(img)
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
                BundleIconQueue.shared.loadIcon(for: app) { img in
                    if let img {
                        lazyIcon = img
                    }
                }
            }
        }
    }
}
