import SwiftUI
import Foundation
import UIKit
import UniformTypeIdentifiers
import Combine

// MARK: - .ens Package & Patch Models

struct EnsPatchPackage: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var bundleID: String
    var relativeDestPath: String
    var containerPath: String
    var payloadBase64: String?
    var payloadFiles: [String: String]
    var notes: String
    var isEnabled: Bool
    var iconPNGBase64: String?
    var createdAt: Date
    var updatedAt: Date

    var uiIcon: UIImage? {
        guard let b64 = iconPNGBase64,
              !b64.isEmpty,
              let data = Data(base64Encoded: b64) else {
            return nil
        }
        return UIImage(data: data)
    }
}

struct EnsScannedAppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let containerUUID: String
    let containerPath: String
    let icon: UIImage?

    static func == (lhs: EnsScannedAppEntry, rhs: EnsScannedAppEntry) -> Bool {
        lhs.id == rhs.id && lhs.containerUUID == rhs.containerUUID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(containerUUID)
    }
}

// MARK: - App Icon & Container Helper

private enum EnsAppResolver {
    private static let fm = FileManager.default
    private static let launchServicesMapPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"

    static func resolveIcon(for bundleID: String, containerPath: String) -> UIImage? {
        if let jitIcon = try? JITEnableContext.shared.getAppIcon(withBundleId: bundleID) {
            return jitIcon
        }

        let normContainer = CSStoreEngine.normalizeVarPath(containerPath)
        if !normContainer.isEmpty {
            let bundleDir = (normContainer as NSString).deletingLastPathComponent
            if let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: bundleDir),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator {
                    let lower = url.lastPathComponent.lowercased()
                    if lower.contains("appicon") && lower.hasSuffix(".png"),
                       let img = UIImage(contentsOfFile: url.path) {
                        return img
                    }
                }
            }
        }
        return nil
    }

    static func resolveContainerPath(for bundleID: String, explicitPath: String? = nil) -> String {
        let bid = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bid.isEmpty else { return "" }

        if let explicit = explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            let norm = CSStoreEngine.normalizeVarPath(explicit)
            zPatchStore.shared.registerContainer(bundleID: bid, containerPath: norm)
            return norm
        }

        if let saved = zPatchStore.shared.cachedContainer(for: bid), !saved.isEmpty {
            return CSStoreEngine.normalizeVarPath(saved)
        }

        let (_, fastHit) = CSStoreEngine.shared.lookupAppContainer(forBundleID: bid)
        if let fastHit, !fastHit.isEmpty {
            let norm = CSStoreEngine.normalizeVarPath(fastHit)
            zPatchStore.shared.registerContainer(bundleID: bid, containerPath: norm)
            return norm
        }

        let viaFS = fsHandlers.getContainerPath(at: FSURL.appContainers, forMatch: bid, hashOnly: false)
        if !viaFS.isEmpty {
            let norm = CSStoreEngine.normalizeVarPath(viaFS)
            zPatchStore.shared.registerContainer(bundleID: bid, containerPath: norm)
            return norm
        }

        return "/var/mobile/Containers/Data/Application/\(bid)"
    }

    static func scanApps(forceRefresh: Bool = false) -> [EnsScannedAppEntry] {
        if forceRefresh {
            fsHandlers.invalidateCache()
        }

        var lsByUUID: [String: (bundleID: String, name: String)] = [:]
        if let data = fm.contents(atPath: launchServicesMapPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let user = plist["User"] as? [String: Any] {
            for (bid, rawVal) in user {
                guard let dict = rawVal as? [String: Any],
                      let uuid = dict["Container"] as? String,
                      !uuid.isEmpty else { continue }
                let disp = (dict["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let bname = (dict["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = bid.split(separator: ".").last.map(String.init) ?? bid
                let title = (disp?.isEmpty == false) ? disp! : ((bname?.isEmpty == false) ? bname! : fallback)
                lsByUUID[uuid.lowercased()] = (bundleID: bid, name: title)
            }
        }

        let containerPaths = fsHandlers.getDirPaths(FSURL.appContainers.path, forceRefresh: forceRefresh)
        var list: [EnsScannedAppEntry] = []
        list.reserveCapacity(containerPaths.count)

        for raw in containerPaths {
            let norm = CSStoreEngine.normalizeVarPath(raw)
            let uuid = URL(fileURLWithPath: norm).lastPathComponent
            let lowerUUID = uuid.lowercased()

            var bid = lsByUUID[lowerUUID]?.bundleID
            let name = lsByUUID[lowerUUID]?.name

            if bid == nil || bid?.isEmpty == true {
                if let xattrBID = getBIDFromXattr(URL(fileURLWithPath: norm))?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !xattrBID.isEmpty {
                    bid = xattrBID
                }
            }

            let finalBID = (bid?.isEmpty == false) ? bid! : uuid
            let finalName: String
            if let name, !name.isEmpty {
                finalName = name
            } else if finalBID != uuid {
                finalName = finalBID.split(separator: ".").last.map(String.init) ?? finalBID
            } else {
                finalName = uuid
            }

            let icon = resolveIcon(for: finalBID, containerPath: norm)

            list.append(
                EnsScannedAppEntry(
                    id: "\(finalBID)#\(uuid)",
                    name: finalName,
                    bundleID: finalBID,
                    containerUUID: uuid,
                    containerPath: norm,
                    icon: icon
                )
            )
        }

        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - .ens Manager (Add, Export .ens, Import & Apply Immediately)

@MainActor
final class EnsPatchStore: ObservableObject {
    static let shared = EnsPatchStore()

    @Published var items: [EnsPatchPackage] = []
    @Published var statusMessage: String = ""

    private let saveURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.saveURL = docs.appendingPathComponent("ens_patches_v2.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([EnsPatchPackage].self, from: data) else {
            return
        }
        items = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        _ = writeFileTemp(data, to: saveURL)
    }

    @discardableResult
    func addPatch(
        name: String,
        bundleID: String,
        relativeDestPath: String = "",
        sourceFileURL: URL? = nil,
        icon: UIImage? = nil,
        notes: String = ""
    ) -> EnsPatchPackage? {
        let cleanBID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBID.isEmpty else {
            statusMessage = "Vui lòng nhập hoặc chọn Bundle ID"
            return nil
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (cleanBID.split(separator: ".").last.map(String.init) ?? cleanBID)
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        let containerPath = EnsAppResolver.resolveContainerPath(for: cleanBID)
        let resolvedIcon = icon ?? EnsAppResolver.resolveIcon(for: cleanBID, containerPath: containerPath)
        let iconB64 = resolvedIcon?.pngData()?.base64EncodedString()

        var payloadB64: String? = nil
        var filesMap: [String: String] = [:]

        if let srcURL = sourceFileURL {
            let accessing = srcURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { srcURL.stopAccessingSecurityScopedResource() }
            }
            if let data = try? Data(contentsOf: srcURL) {
                payloadB64 = data.base64EncodedString()
                let rel = relativeDestPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? srcURL.lastPathComponent
                    : relativeDestPath.trimmingCharacters(in: .whitespacesAndNewlines)
                filesMap[rel] = data.base64EncodedString()
            }
        }

        let pkg = EnsPatchPackage(
            id: UUID().uuidString,
            name: cleanName,
            bundleID: cleanBID,
            relativeDestPath: relativeDestPath.trimmingCharacters(in: .whitespacesAndNewlines),
            containerPath: containerPath,
            payloadBase64: payloadB64,
            payloadFiles: filesMap,
            notes: notes,
            isEnabled: true,
            iconPNGBase64: iconB64,
            createdAt: Date(),
            updatedAt: Date()
        )

        items.removeAll { $0.bundleID.caseInsensitiveCompare(cleanBID) == .orderedSame }
        items.insert(pkg, at: 0)
        persist()
        statusMessage = "Đã tạo patch cho \(cleanBID)"
        return pkg
    }

    func exportEns(_ pkg: EnsPatchPackage) -> URL? {
        guard let jsonData = try? JSONEncoder().encode(pkg) else {
            statusMessage = "Lỗi đóng gói file .ens"
            return nil
        }
        let safeBID = pkg.bundleID.replacingOccurrences(of: "/", with: "_")
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeBID).ens")
        let (ok, err) = writeFileTemp(jsonData, to: outURL)
        if ok {
            statusMessage = "Đã xuất \(outURL.lastPathComponent)"
            return outURL
        } else {
            statusMessage = "Export lỗi: \(err)"
            return nil
        }
    }

    @discardableResult
    func importAndRunEns(from url: URL) -> EnsPatchPackage? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(EnsPatchPackage.self, from: data) else {
            statusMessage = "File .ens không hợp lệ"
            return nil
        }

        let resolvedContainer = EnsAppResolver.resolveContainerPath(
            for: decoded.bundleID,
            explicitPath: decoded.containerPath
        )

        let activePkg = EnsPatchPackage(
            id: UUID().uuidString,
            name: decoded.name.isEmpty
                ? (decoded.bundleID.split(separator: ".").last.map(String.init) ?? decoded.bundleID)
                : decoded.name,
            bundleID: decoded.bundleID,
            relativeDestPath: decoded.relativeDestPath,
            containerPath: resolvedContainer,
            payloadBase64: decoded.payloadBase64,
            payloadFiles: decoded.payloadFiles,
            notes: decoded.notes,
            isEnabled: true,
            iconPNGBase64: decoded.iconPNGBase64,
            createdAt: decoded.createdAt,
            updatedAt: Date()
        )

        applyPackageImmediately(activePkg)

        items.removeAll { $0.bundleID.caseInsensitiveCompare(activePkg.bundleID) == .orderedSame }
        items.insert(activePkg, at: 0)
        persist()
        statusMessage = "Đã import & áp dụng ngay: \(activePkg.name) (\(activePkg.bundleID))"
        return activePkg
    }

    func applyPackageImmediately(_ pkg: EnsPatchPackage) {
        let base = CSStoreEngine.normalizeVarPath(pkg.containerPath)
        guard !base.isEmpty else { return }

        zPatchStore.shared.registerContainer(bundleID: pkg.bundleID, containerPath: base)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let payloadDir = docs.appendingPathComponent("zPatchImportedPayloads/\(pkg.bundleID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        for (relPath, b64) in pkg.payloadFiles {
            guard let fileData = Data(base64Encoded: b64) else { continue }
            let cleanRel = relPath.hasPrefix("/") ? String(relPath.dropFirst()) : relPath
            let localFileURL = payloadDir.appendingPathComponent((cleanRel as NSString).lastPathComponent)
            _ = writeFileTemp(fileData, to: localFileURL)

            let destPath = (base as NSString).appendingPathComponent(cleanRel)
            let parentDir = (destPath as NSString).deletingLastPathComponent
            _ = wq.grantAccess(path: parentDir, requireWrite: true, allowFsgetpathFallback: true)
            _ = wq.grantAccess(path: destPath, requireWrite: true, allowFsgetpathFallback: true)
            try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            _ = writeFileTemp(fileData, to: URL(fileURLWithPath: destPath))

            zPatchStore.shared.saveNewPatch(
                bundleID: pkg.bundleID,
                relativeDestPath: cleanRel,
                sourcePath: localFileURL.path
            )
        }

        if pkg.payloadFiles.isEmpty,
           let b64 = pkg.payloadBase64,
           let fileData = Data(base64Encoded: b64),
           !pkg.relativeDestPath.isEmpty {
            let cleanRel = pkg.relativeDestPath.hasPrefix("/") ? String(pkg.relativeDestPath.dropFirst()) : pkg.relativeDestPath
            let localFileURL = payloadDir.appendingPathComponent((cleanRel as NSString).lastPathComponent)
            _ = writeFileTemp(fileData, to: localFileURL)

            let destPath = (base as NSString).appendingPathComponent(cleanRel)
            let parentDir = (destPath as NSString).deletingLastPathComponent
            _ = wq.grantAccess(path: parentDir, requireWrite: true, allowFsgetpathFallback: true)
            _ = wq.grantAccess(path: destPath, requireWrite: true, allowFsgetpathFallback: true)
            try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            _ = writeFileTemp(fileData, to: URL(fileURLWithPath: destPath))

            zPatchStore.shared.saveNewPatch(
                bundleID: pkg.bundleID,
                relativeDestPath: cleanRel,
                sourcePath: localFileURL.path
            )
        }

        zPatchStore.shared.setTweakEnabledImmediate(true)
        zPatchStore.shared.saveChange(enableTweak: true)
    }

    func delete(_ pkg: EnsPatchPackage) {
        items.removeAll { $0.id == pkg.id }
        persist()
    }
}

// MARK: - App Picker (Có Icon + Tên + Bundle ID)

struct EnsAppPickerSheet: View {
    @Binding var selectedBundleID: String
    @Binding var selectedName: String
    @Binding var selectedIcon: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var apps: [EnsScannedAppEntry] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false

    private var filtered: [EnsScannedAppEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.name.lowercased().contains(q) ||
            $0.bundleID.lowercased().contains(q) ||
            $0.containerUUID.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { app in
                Button {
                    selectedBundleID = app.bundleID
                    if selectedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        selectedName = app.name
                    }
                    selectedIcon = app.icon
                    zPatchStore.shared.registerContainer(bundleID: app.bundleID, containerPath: app.containerPath)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        EnsAppIconThumbnail(icon: app.icon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(app.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Tìm tên hoặc Bundle ID...")
            .navigationTitle("Chọn App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reloadApps(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                if apps.isEmpty { reloadApps(force: false) }
            }
        }
    }

    private func reloadApps(force: Bool) {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let result = EnsAppResolver.scanApps(forceRefresh: force)
            await MainActor.run {
                apps = result
                isLoading = false
            }
        }
    }
}

private struct EnsAppIconThumbnail: View {
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
        .frame(width: 44, height: 44)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Main View (Nhập Bundle ID / Chọn App + Import .ens + Export .ens)

struct EnsPatchManagerView: View {
    @StateObject private var store = EnsPatchStore.shared

    @State private var showAddSheet = false
    @State private var showAppPicker = false
    @State private var showEnsImporter = false
    @State private var showPayloadPicker = false
    @State private var shareURL: URL?

    @State private var inputName = ""
    @State private var inputBundleID = ""
    @State private var inputRelDest = ""
    @State private var inputNotes = ""
    @State private var inputIcon: UIImage? = nil
    @State private var pickedPayloadURL: URL? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !store.statusMessage.isEmpty {
                    Text(store.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                }

                List {
                    ForEach(store.items) { pkg in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                EnsAppIconThumbnail(icon: pkg.uiIcon)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pkg.name)
                                        .font(.headline)
                                    Text(pkg.bundleID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    if !pkg.relativeDestPath.isEmpty {
                                        Text("Đích: \(pkg.relativeDestPath)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Button {
                                    if let url = store.exportEns(pkg) {
                                        shareURL = url
                                    }
                                } label: {
                                    Label("Export .ens", systemImage: "square.and.arrow.up")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    store.applyPackageImmediately(pkg)
                                    store.statusMessage = "Đã chạy áp dụng: \(pkg.name)"
                                } label: {
                                    Label("Chạy Patch", systemImage: "play.fill")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Button(role: .destructive) {
                                    store.delete(pkg)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("zPatch .ens")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showEnsImporter = true
                    } label: {
                        Label("Import .ens", systemImage: "square.and.arrow.down")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetForm()
                        showAddSheet = true
                    } label: {
                        Label("Add Patch", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showAddSheet) {
                NavigationStack {
                    Form {
                        Section("App & Bundle ID") {
                            HStack(spacing: 10) {
                                EnsAppIconThumbnail(icon: inputIcon)
                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("Tên hiển thị (tuỳ chọn)", text: $inputName)
                                    TextField("Nhập Bundle ID (vd: com.example.app)", text: $inputBundleID)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }
                            }

                            Button {
                                showAppPicker = true
                            } label: {
                                Label("Chọn App từ danh sách", systemImage: "list.bullet.rectangle")
                            }
                        }

                        Section("File Patch (tuỳ chọn)") {
                            TextField("Đường dẫn tương đối (vd: Library/Preferences/x.plist)", text: $inputRelDest)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Button {
                                showPayloadPicker = true
                            } label: {
                                HStack {
                                    Text(pickedPayloadURL?.lastPathComponent ?? "Chọn file payload")
                                    Spacer()
                                    Image(systemName: "doc.badge.plus")
                                }
                            }

                            TextField("Ghi chú", text: $inputNotes)
                        }

                        Section {
                            Button("Tạo Patch") {
                                _ = store.addPatch(
                                    name: inputName,
                                    bundleID: inputBundleID,
                                    relativeDestPath: inputRelDest,
                                    sourceFileURL: pickedPayloadURL,
                                    icon: inputIcon,
                                    notes: inputNotes
                                )
                                showAddSheet = false
                            }
                            .disabled(inputBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .navigationTitle("Add Patch")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Huỷ") { showAddSheet = false }
                        }
                    }
                    .sheet(isPresented: $showAppPicker) {
                        EnsAppPickerSheet(
                            selectedBundleID: $inputBundleID,
                            selectedName: $inputName,
                            selectedIcon: $inputIcon
                        )
                    }
                    .fileImporter(
                        isPresented: $showPayloadPicker,
                        allowedContentTypes: [.item, .data],
                        allowsMultipleSelection: false
                    ) { res in
                        if case .success(let urls) = res, let url = urls.first {
                            pickedPayloadURL = url
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showEnsImporter,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let fileURL = urls.first {
                    _ = store.importAndRunEns(from: fileURL)
                }
            }
            .sheet(item: Binding(
                get: { shareURL.map { EnsShareURLItem(url: $0) } },
                set: { shareURL = $0?.url }
            )) { wrapper in
                EnsActivityShareController(items: [wrapper.url])
            }
        }
    }

    private func resetForm() {
        inputName = ""
        inputBundleID = ""
        inputRelDest = ""
        inputNotes = ""
        inputIcon = nil
        pickedPayloadURL = nil
    }
}

private struct EnsShareURLItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct EnsActivityShareController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
