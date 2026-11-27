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
        guard fm.isReadableFile(atPath: launchServicesPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: launchServicesPath)),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            return [:]
        }

        var result: [String: (bundleID: String, name: String)] = [:]
        for sectionKey in ["User", "System", "Internal"] {
            guard let section = plist[sectionKey] as? [String: Any] else { continue }
            for (bid, raw) in section {
                guard let info = raw as? [String: Any] else { continue }
                let disp = (info["CFBundleDisplayName"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let bname = (info["CFBundleName"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = bid.split(separator: ".").last.map(String.init) ?? bid
                let title = (disp?.isEmpty == false) ? disp! : ((bname?.isEmpty == false) ? bname! : fallback)

                let rawContainer = (info["Container"] as? String) ?? ""
                let uuid = rawContainer.isEmpty ? "" : (rawContainer as NSString).lastPathComponent
                if !uuid.isEmpty {
                    result[uuid.lowercased()] = (bundleID: bid, name: title)
                }
            }
        }
        return result
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let rawContainers = fsHandlers.getDirPaths(
            FSURL.appContainers.path,
            forceRefresh: forceRefresh
        )
        let lsMap = loadLaunchServicesMap()

        var list: [ScannedAppEntry] = []
        list.reserveCapacity(rawContainers.count)

        for rawPath in rawContainers {
            autoreleasepool {
                let normPath = CSStoreEngine.normalizeVarPath(rawPath)
                guard !normPath.isEmpty else { return }

                let uuid = (normPath as NSString).lastPathComponent
                guard !uuid.isEmpty else { return }

                let hit = lsMap[uuid.lowercased()]
                let bid = (hit?.bundleID.isEmpty == false) ? hit!.bundleID : uuid
                let name: String
                if let n = hit?.name, !n.isEmpty {
                    name = n
                } else if bid != uuid {
                    name = bid.split(separator: ".").last.map(String.init) ?? bid
                } else {
                    name = "App \(uuid.prefix(8))"
                }

                list.append(
                    ScannedAppEntry(
                        id: "\(bid)#\(uuid)",
                        name: name,
                        bundleID: bid,
                        containerUUID: uuid,
                        containerPath: normPath,
                        icon: nil
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

        Task.detached(priority: .userInitiated) {
            let result = AppScannerEngine.scan(forceRefresh: forceRefresh)
            await MainActor.run {
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
                            Image(systemName: "app.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .foregroundStyle(.tint)
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

                                Text(app.containerUUID)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 3)
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
