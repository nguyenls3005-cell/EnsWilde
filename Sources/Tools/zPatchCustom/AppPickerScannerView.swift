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
    private static let launchServicesCandidates = [
        "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist",
        "/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.plist/Library/Caches/com.apple.LaunchServices-054.csstore"
    ]

    private static func readPlistWithWQ(at path: String) -> [String: Any]? {
        let granted = wq.grantAccess(path: path, requireWrite: false, allowFsgetpathFallback: true)
        defer {
            if granted.0 {
                wq.releaseAccess(path: path)
            }
        }

        if let data = fm.contents(atPath: path),
           let plist = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) as? [String: Any] {
            return plist
        }

        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let plist = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) as? [String: Any] {
            return plist
        }

        return nil
    }

    private static func parseAppRecords(from plist: [String: Any]) -> (
        byUUID: [String: (bundleID: String, name: String)],
        byBID: [String: (uuid: String, name: String)]
    ) {
        var byUUID: [String: (bundleID: String, name: String)] = [:]
        var byBID: [String: (uuid: String, name: String)] = [:]

        let containersRoot = [
            plist["User"] as? [String: Any],
            plist["System"] as? [String: Any],
            plist["Internal"] as? [String: Any]
        ]

        for group in containersRoot {
            guard let dictGroup = group else { continue }
            for (bid, rawInfo) in dictGroup {
                guard let info = rawInfo as? [String: Any] else { continue }
                let disp = (info["CFBundleDisplayName"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let bname = (info["CFBundleName"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = bid.split(separator: ".").last.map(String.init) ?? bid
                let title = (disp?.isEmpty == false) ? disp! : ((bname?.isEmpty == false) ? bname! : fallback)

                let rawContainer = (info["Container"] as? String) ?? ""
                let uuid = rawContainer.isEmpty
                    ? ""
                    : ((rawContainer as NSString).lastPathComponent)

                if !uuid.isEmpty {
                    byUUID[uuid.lowercased()] = (bundleID: bid, name: title)
                }
                byBID[bid.lowercased()] = (uuid: uuid, name: title)
            }
        }

        return (byUUID, byBID)
    }

    private static func loadLaunchServicesRecords() -> (
        byUUID: [String: (bundleID: String, name: String)],
        byBID: [String: (uuid: String, name: String)]
    ) {
        for path in launchServicesCandidates where path.hasSuffix(".plist") {
            if let plist = readPlistWithWQ(at: path) {
                let parsed = parseAppRecords(from: plist)
                if !parsed.byUUID.isEmpty || !parsed.byBID.isEmpty {
                    return parsed
                }
            }
        }
        return ([:], [:])
    }

    private static func inspectInfoPlist(inDirectory dirPath: String) -> (bundleID: String?, name: String?) {
        let infoPath = (dirPath as NSString).appendingPathComponent("Info.plist")
        let granted = wq.grantAccess(path: infoPath, requireWrite: false, allowFsgetpathFallback: true)
        defer {
            if granted.0 {
                wq.releaseAccess(path: infoPath)
            }
        }

        guard let data = fm.contents(atPath: infoPath),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            return (nil, nil)
        }

        let bid = (plist["CFBundleIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let disp = (plist["CFBundleDisplayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bname = (plist["CFBundleName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let chosenName: String?
        if let disp, !disp.isEmpty {
            chosenName = disp
        } else if let bname, !bname.isEmpty {
            chosenName = bname
        } else {
            chosenName = nil
        }

        return (
            (bid?.isEmpty == false) ? bid : nil,
            chosenName
        )
    }

    private static func findBundleIDAndName(
        forContainerPath normPath: String,
        uuid: String,
        lsRecords: (
            byUUID: [String: (bundleID: String, name: String)],
            byBID: [String: (uuid: String, name: String)]
        )
    ) -> (bundleID: String, name: String) {
        let lowerUUID = uuid.lowercased()

        if let hit = lsRecords.byUUID[lowerUUID] {
            return (hit.bundleID, hit.name)
        }

        var detectedBID: String? = nil
        var detectedName: String? = nil

        let wqDir = wq.grantAccess(path: normPath, requireWrite: false, allowFsgetpathFallback: true)
        defer {
            if wqDir.0 {
                wq.releaseAccess(path: normPath)
            }
        }

        if let xattrBID = getBIDFromXattr(URL(fileURLWithPath: normPath))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !xattrBID.isEmpty {
            detectedBID = xattrBID
        }

        if detectedBID == nil {
            let candidates = [
                (normPath as NSString).appendingPathComponent("iTunesMetadata.plist"),
                (normPath as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            ]
            for metaPath in candidates {
                let g = wq.grantAccess(path: metaPath, requireWrite: false, allowFsgetpathFallback: true)
                defer { if g.0 { wq.releaseAccess(path: metaPath) } }
                if let d = fm.contents(atPath: metaPath),
                   let p = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any] {
                    if let b = (p["softwareVersionBundleId"] as? String) ?? (p["MCMMetadataIdentifier"] as? String),
                       !b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detectedBID = b.trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
        }

        let parentDir = (normPath as NSString).deletingLastPathComponent
        if let appDirs = try? fm.contentsOfDirectory(atPath: parentDir) {
            for entry in appDirs where entry.hasSuffix(".app") {
                let appBundlePath = (parentDir as NSString).appendingPathComponent(entry)
                let info = inspectInfoPlist(inDirectory: appBundlePath)
                if detectedBID == nil, let b = info.bundleID {
                    detectedBID = b
                }
                if detectedName == nil, let n = info.name {
                    detectedName = n
                }
                if detectedBID != nil && detectedName != nil {
                    break
                }
            }
        }

        let finalBID = detectedBID ?? uuid
        if let bidMatch = lsRecords.byBID[finalBID.lowercased()] {
            return (finalBID, detectedName ?? bidMatch.name)
        }

        if let name = detectedName, !name.isEmpty {
            return (finalBID, name)
        }

        if finalBID != uuid {
            let shortName = finalBID.split(separator: ".").last.map(String.init) ?? finalBID
            return (finalBID, shortName)
        }

        return (uuid, uuid)
    }

    static func scan(forceRefresh: Bool = false) -> [ScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        let rootPath = CSStoreEngine.normalizeVarPath(FSURL.appContainers.path)
        let wqRoot = wq.grantAccess(path: rootPath, requireWrite: false, allowFsgetpathFallback: true)
        defer {
            if wqRoot.0 {
                wq.releaseAccess(path: rootPath)
            }
        }

        let rawContainers = fsHandlers.getDirPaths(
            FSURL.appContainers.path,
            forceRefresh: forceRefresh
        )
        let lsRecords = loadLaunchServicesRecords()

        var list: [ScannedAppEntry] = []
        list.reserveCapacity(rawContainers.count)

        for rawPath in rawContainers {
            autoreleasepool {
                let normPath = CSStoreEngine.normalizeVarPath(rawPath)
                guard !normPath.isEmpty else { return }

                let uuid = (normPath as NSString).lastPathComponent
                guard !uuid.isEmpty else { return }

                let resolved = findBundleIDAndName(
                    forContainerPath: normPath,
                    uuid: uuid,
                    lsRecords: lsRecords
                )

                list.append(
                    ScannedAppEntry(
                        id: "\(resolved.bundleID)#\(uuid)",
                        name: resolved.name,
                        bundleID: resolved.bundleID,
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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
                            Image(systemName: "app.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .padding(9)
                                .foregroundStyle(.tint)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

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
