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
    private static func readFromWorkspace() -> [(bid: String, name: String)] {
        guard let wsClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              wsClass.responds(to: NSSelectorFromString("defaultWorkspace")),
              let workspace = wsClass.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
              workspace.responds(to: NSSelectorFromString("allApplications")),
              let rawApps = workspace.perform(NSSelectorFromString("allApplications"))?.takeUnretainedValue() as? [NSObject] else {
            return []
        }

        var items: [(bid: String, name: String)] = []
        items.reserveCapacity(rawApps.count)

        for proxy in rawApps {
            let rawBID = proxy.value(forKey: "applicationIdentifier") as? String ?? ""
            let bid = zPatchItem.normalizedBundleID(rawBID)
            guard !bid.isEmpty else { continue }

            let localized = (proxy.value(forKey: "localizedName") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let itemName = (proxy.value(forKey: "itemName") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = bid.split(separator: ".").last.map(String.init) ?? bid

            let displayName: String
            if let localized, !localized.isEmpty {
                displayName = localized
            } else if let itemName, !itemName.isEmpty {
                displayName = itemName
            } else {
                displayName = fallback
            }

            items.append((bid: bid, name: displayName))
        }

        return items
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        let _ = forceRefresh
        let ud = UserDefaults.standard
        let savedNames = ud.dictionary(forKey: zPatchStore.appNameMapKey) as? [String: String] ?? [:]

        var merged: [String: (bid: String, name: String)] = [:]

        for (rawBID, rawName) in savedNames {
            let bid = zPatchItem.normalizedBundleID(rawBID)
            guard !bid.isEmpty else { continue }
            let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = cleanName.isEmpty
                ? (bid.split(separator: ".").last.map(String.init) ?? bid)
                : cleanName
            merged[bid.lowercased()] = (bid: bid, name: finalName)
        }

        for item in readFromWorkspace() {
            let key = item.bid.lowercased()
            if let existing = merged[key] {
                merged[key] = (
                    bid: existing.bid,
                    name: item.name.isEmpty ? existing.name : item.name
                )
            } else {
                merged[key] = item
            }
        }

        if let data = ud.data(forKey: zPatchStore.itemsKey),
           let decoded = try? JSONDecoder().decode([zPatchItem].self, from: data) {
            for patch in decoded {
                let bid = zPatchItem.normalizedBundleID(patch.bundleID)
                guard !bid.isEmpty else { continue }
                let key = bid.lowercased()
                if merged[key] == nil {
                    let fallback = bid.split(separator: ".").last.map(String.init) ?? bid
                    merged[key] = (bid: bid, name: fallback)
                }
            }
        }

        return merged.values
            .map { item in
                ScannedAppEntry(
                    id: item.bid,
                    name: item.name,
                    bundleID: item.bid,
                    containerUUID: "",
                    containerPath: "",
                    icon: nil
                )
            }
            .sorted {
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

        let result = AppScannerEngine.scan(forceRefresh: forceRefresh)
        self.apps = result
        self.isScanning = false
        self.statusMessage = "Đã quét xong: \(result.count) app"
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
                    vm.scan(forceRefresh: false)
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
