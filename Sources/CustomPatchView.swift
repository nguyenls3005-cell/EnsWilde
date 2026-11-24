//
//  CustomPatchView.swift
//  EnsWilde
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CustomPatchRule: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var projectName: String = ""
    var bundleID: String = ""
    var relativePath: String = ""
    var sourceFileName: String = ""
    var sourceStoredPath: String = ""
    var fileSizeBytes: Int64 = 0
}

struct Patch3105Package: Codable {
    var formatVersion: Int = 1
    var projectName: String
    var bundleID: String
    var relativePath: String
    var fileName: String
    var fileDataBase64: String
}

struct CustomPatchConfig: Codable, Equatable {
    var enabled: Bool = false
    var activeRule: CustomPatchRule? = nil
    var savedRules: [CustomPatchRule] = []
}

final class CustomPatchStore: ObservableObject {
    static let shared = CustomPatchStore()

    private let storageKey = "EnsWilde.CustomPatchConfig.v2"

    @Published var config: CustomPatchConfig {
        didSet {
            saveToDefaults()
            objectWillChange.send()
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(CustomPatchConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = CustomPatchConfig()
        }
    }

    private func saveToDefaults() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useBytes]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func patchFolderURL() throws -> URL {
        let folder = URL.documentsDirectory.appendingPathComponent("CustomPatch", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func importReplacementFile(from url: URL, intoRule target: inout CustomPatchRule) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let folder = try patchFolderURL()
        let safeName = "\(UUID().uuidString.prefix(8))_\(url.lastPathComponent)"
        let destURL = folder.appendingPathComponent(safeName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try data.write(to: destURL, options: .atomic)
        chmod(destURL.path, 0o644)

        target.sourceFileName = url.lastPathComponent
        target.sourceStoredPath = destURL.path
        target.fileSizeBytes = Int64(data.count)
    }

    func createAndSave3105(
        projectName: String,
        bundleID: String,
        relativePath: String,
        sourceStoredPath: String,
        sourceFileName: String
    ) throws -> CustomPatchRule {
        let cleanBundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBundleID.isEmpty else {
            throw CustomPatchError.missingBundleID
        }

        guard !sourceStoredPath.isEmpty,
              FileManager.default.fileExists(atPath: sourceStoredPath) else {
            throw CustomPatchError.missingSourceFile
        }

        let data = try Data(contentsOf: URL(filePath: sourceStoredPath), options: .mappedIfSafe)
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = trimmedName.isEmpty ? cleanBundleID : trimmedName
        let cleanFileName = sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? URL(filePath: sourceStoredPath).lastPathComponent
            : sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines)

        let pkg = Patch3105Package(
            projectName: cleanName,
            bundleID: cleanBundleID,
            relativePath: relativePath.trimmingCharacters(in: .whitespacesAndNewlines),
            fileName: cleanFileName,
            fileDataBase64: data.base64EncodedString()
        )

        let pkgData = try JSONEncoder().encode(pkg)
        let folder = try patchFolderURL()
        let fileSlug = pkg.projectName.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let pkgURL = folder.appendingPathComponent("\(fileSlug)_\(UUID().uuidString.prefix(6)).3105")
        try pkgData.write(to: pkgURL, options: .atomic)

        let extractedURL = folder.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(pkg.fileName)")
        try data.write(to: extractedURL, options: .atomic)

        let rule = CustomPatchRule(
            projectName: pkg.projectName,
            bundleID: pkg.bundleID,
            relativePath: pkg.relativePath,
            sourceFileName: pkg.fileName,
            sourceStoredPath: extractedURL.path,
            fileSizeBytes: Int64(data.count)
        )

        config.savedRules.removeAll { $0.id == rule.id }
        config.savedRules.insert(rule, at: 0)
        config.activeRule = rule
        config.enabled = true
        return rule
    }

    func import3105Package(from url: URL) throws -> CustomPatchRule {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let rawData = try Data(contentsOf: url, options: .mappedIfSafe)
        let folder = try patchFolderURL()

        if let pkg = try? JSONDecoder().decode(Patch3105Package.self, from: rawData),
           let payload = Data(base64Encoded: pkg.fileDataBase64) {
            let outURL = folder.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(pkg.fileName)")
            try payload.write(to: outURL, options: .atomic)

            let rule = CustomPatchRule(
                projectName: pkg.projectName,
                bundleID: pkg.bundleID,
                relativePath: pkg.relativePath,
                sourceFileName: pkg.fileName,
                sourceStoredPath: outURL.path,
                fileSizeBytes: Int64(payload.count)
            )
            config.savedRules.insert(rule, at: 0)
            config.activeRule = rule
            return rule
        }

        let fallbackName = url.deletingPathExtension().lastPathComponent
        let outURL = folder.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(url.lastPathComponent)")
        try rawData.write(to: outURL, options: .atomic)

        let rule = CustomPatchRule(
            projectName: fallbackName.isEmpty ? "Imported .3105" : fallbackName,
            bundleID: config.activeRule?.bundleID ?? "",
            relativePath: config.activeRule?.relativePath ?? "",
            sourceFileName: url.lastPathComponent,
            sourceStoredPath: outURL.path,
            fileSizeBytes: Int64(rawData.count)
        )
        config.savedRules.insert(rule, at: 0)
        config.activeRule = rule
        return rule
    }

    func selectRule(_ rule: CustomPatchRule) {
        config.activeRule = rule
    }

    func deleteRule(at offsets: IndexSet) {
        let removedIDs = Set(offsets.compactMap { idx in
            config.savedRules.indices.contains(idx) ? config.savedRules[idx].id : nil
        })
        for idx in offsets {
            let removed = config.savedRules[idx]
            if !removed.sourceStoredPath.isEmpty {
                try? FileManager.default.removeItem(atPath: removed.sourceStoredPath)
            }
        }
        config.savedRules.remove(atOffsets: offsets)
        if let activeID = config.activeRule?.id, removedIDs.contains(activeID) {
            config.activeRule = config.savedRules.first
        }
    }

    func restoreDefaults() {
        for r in config.savedRules where !r.sourceStoredPath.isEmpty {
            try? FileManager.default.removeItem(atPath: r.sourceStoredPath)
        }
        if let activePath = config.activeRule?.sourceStoredPath, !activePath.isEmpty {
            try? FileManager.default.removeItem(atPath: activePath)
        }
        config = CustomPatchConfig()
    }
}

enum CustomPatchError: LocalizedError {
    case disabled
    case missingBundleID
    case missingSourceFile
    case targetNotFound(String)
    case openFailed(String)
    case truncateFailed(String)
    case writeFailed(Int, Int)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Custom Patch đang tắt."
        case .missingBundleID:
            return "Vui lòng nhập Bundle ID của app."
        case .missingSourceFile:
            return "Chưa nhập Replacement File hoặc file không tồn tại."
        case .targetNotFound(let bid):
            return "Không tìm thấy thư mục của Bundle ID: \(bid)"
        case .openFailed(let reason):
            return "Không mở được file đích: \(reason)"
        case .truncateFailed(let reason):
            return "Lỗi ftruncate file đích: \(reason)"
        case .writeFailed(let written, let total):
            return "Lỗi pwrite tại \(written)/\(total) bytes."
        }
    }
}

enum CustomPatchApplyTask {
    private static func estimatedMaxInode() -> UInt64 {
        let tmpURL = URL.documentsDirectory.appendingPathComponent(".inode_probe_\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmpURL.path, contents: Data([0x00]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        var st = stat()
        if lstat(tmpURL.path, &st) == 0 && st.st_ino > 0 {
            return UInt64(st.st_ino) * 4
        }
        return 12_000_000
    }

    private static func findContainerBasePath(for bundleID: String, preferDataContainer: Bool, log: (String) -> Void) -> String? {
        if let appProxyClass = NSClassFromString("LSApplicationProxy") as? NSObject.Type,
           let proxy = appProxyClass.perform(Selector("applicationProxyForIdentifier:"), with: bundleID)?.takeUnretainedValue() as? NSObject {
            if preferDataContainer, let dataURL = proxy.value(forKey: "dataContainerURL") as? URL {
                log("[CustomPatch] Tìm thấy Data Container qua LSApplicationProxy: \(dataURL.path)")
                return dataURL.path
            }
            if let bundleURL = proxy.value(forKey: "bundleURL") as? URL {
                log("[CustomPatch] Tìm thấy Bundle qua LSApplicationProxy: \(bundleURL.path)")
                return bundleURL.path
            }
        }

        log("[CustomPatch] Đang dò \(bundleID) bằng pathleak...")
        let maxInode = estimatedMaxInode()
        let roots = preferDataContainer
            ? ["/var/mobile/Containers/Data/Application", "/private/var/mobile/Containers/Data/Application", "/var/containers/Bundle/Application"]
            : ["/var/containers/Bundle/Application", "/private/var/containers/Bundle/Application", "/var/mobile/Containers/Data/Application"]

        for root in roots {
            _ = wq.grantAccess(path: root, requireWrite: false)
            if let uuidDirs = pathleak(root, maxInode) as? [String] {
                for dir in uuidDirs {
                    _ = wq.grantAccess(path: dir, requireWrite: false)
                    let metaPlist = (dir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                    if let meta = NSDictionary(contentsOfFile: metaPlist),
                       let id = meta["MCMMetadataIdentifier"] as? String,
                       id == bundleID {
                        log("[CustomPatch] Khớp MCMMetadataIdentifier tại: \(dir)")
                        return dir
                    }
                    if let items = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                        for item in items where item.hasSuffix(".app") {
                            let appPath = (dir as NSString).appendingPathComponent(item)
                            let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
                            if let info = NSDictionary(contentsOfFile: infoPath),
                               let cfID = info["CFBundleIdentifier"] as? String,
                               cfID == bundleID {
                                log("[CustomPatch] Khớp CFBundleIdentifier tại: \(appPath)")
                                return appPath
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    static func resolveTargetPath(rule: CustomPatchRule, log: (String) -> Void = { _ in }) throws -> String {
        let bid = rule.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bid.isEmpty else { throw CustomPatchError.missingBundleID }

        let rel = rule.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let wantsDataContainer = rel.lowercased().hasPrefix("library/")
            || rel.lowercased().hasPrefix("documents/")
            || rel.lowercased().hasPrefix("tmp/")

        guard let basePath = findContainerBasePath(for: bid, preferDataContainer: wantsDataContainer, log: log) else {
            throw CustomPatchError.targetNotFound(bid)
        }

        if rel.isEmpty {
            return basePath
        }
        return URL(filePath: basePath).appendingPathComponent(rel).path
    }

    static func applyIfEnabled(log: (String) -> Void = { _ in }) async throws {
        let cfg = CustomPatchStore.shared.config
        guard cfg.enabled else {
            log("[CustomPatch] Đang tắt, bỏ qua.")
            return
        }

        guard let rule = cfg.activeRule ?? cfg.savedRules.first else {
            throw CustomPatchError.missingSourceFile
        }

        guard !rule.sourceStoredPath.isEmpty,
              FileManager.default.fileExists(atPath: rule.sourceStoredPath),
              let patchData = try? Data(contentsOf: URL(filePath: rule.sourceStoredPath)) else {
            throw CustomPatchError.missingSourceFile
        }

        let targetPath = try resolveTargetPath(rule: rule, log: log)
        let targetURL = URL(filePath: targetPath)
        let parentDir = targetURL.deletingLastPathComponent().path

        log("[CustomPatch] Cấp quyền WorseQuery cho thư mục cha: \(parentDir)")
        _ = wq.grantAccess(path: parentDir, requireWrite: true)

        log("[CustomPatch] Cấp quyền WorseQuery cho file đích: \(targetPath)")
        let granted = wq.grantAccess(path: targetPath, requireWrite: true)
        if !granted.0 {
            log("[CustomPatch] ⚠️ WorseQuery: \(granted.2) (code \(granted.1))")
        }

        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fd = open(targetPath, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard fd >= 0 else {
            throw CustomPatchError.openFailed(String(cString: strerror(errno)))
        }
        defer { close(fd) }

        if ftruncate(fd, 0) != 0 {
            throw CustomPatchError.truncateFailed(String(cString: strerror(errno)))
        }

        var totalWritten = 0
        try patchData.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.baseAddress else { return }
            while totalWritten < patchData.count {
                let n = pwrite(fd, base.advanced(by: totalWritten), patchData.count - totalWritten, off_t(totalWritten))
                if n <= 0 {
                    throw CustomPatchError.writeFailed(totalWritten, patchData.count)
                }
                totalWritten += n
            }
        }

        if fcntl(fd, F_FULLFSYNC) != 0 {
            _ = fsync(fd)
        }
        chmod(targetPath, 0o644)
        log("[CustomPatch] ✅ Đã ghi \(totalWritten) bytes vào \(targetPath)")
    }
}

struct CreatePatchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var patchStore: CustomPatchStore

    @State private var projectName: String = ""
    @State private var bundleID: String = ""
    @State private var relativePath: String = ""
    @State private var draftRule: CustomPatchRule = CustomPatchRule()
    @State private var showFilePicker = false
    @State private var errMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Project Name")) {
                    TextField("Tên project / app", text: $projectName)
                        .autocorrectionDisabled()
                }

                Section(
                    header: Text("Destination"),
                    footer: Text("Use the bundle identifier, for example com.lemon.lvoverseas. Never paste a container UUID or an absolute /var path.")
                ) {
                    TextField("com.lemon.lvoverseas", text: $bundleID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Library/Cookies/Cookies.binarycookies", text: $relativePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(header: Text("Replacement File")) {
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(draftRule.sourceFileName.isEmpty ? "Choose file" : draftRule.sourceFileName)
                                    .foregroundStyle(.primary)
                                Text("Tap to choose a replacement file")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !draftRule.sourceFileName.isEmpty {
                        HStack {
                            Text("Size")
                            Spacer()
                            Text(CustomPatchStore.formattedSize(draftRule.fileSizeBytes))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errMessage {
                    Section {
                        Text(errMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Create Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("alert_ok")) {
                        do {
                            _ = try patchStore.createAndSave3105(
                                projectName: projectName,
                                bundleID: bundleID,
                                relativePath: relativePath,
                                sourceStoredPath: draftRule.sourceStoredPath,
                                sourceFileName: draftRule.sourceFileName
                            )
                            dismiss()
                        } catch {
                            errMessage = error.localizedDescription
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.data, .item, .content],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        do {
                            try patchStore.importReplacementFile(from: url, intoRule: &draftRule)
                            errMessage = nil
                        } catch {
                            errMessage = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    errMessage = error.localizedDescription
                }
            }
        }
    }
}

struct CustomPatchView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @StateObject private var patchStore = CustomPatchStore.shared
    @ObservedObject var toolStore: ToolStore

    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false

    @State private var show3105FilePicker = false
    @State private var showCreatePatchSheet = false
    @State private var statusMessage: String?
    @State private var showAlert = false

    var body: some View {
        List {
            Section {
                Toggle(L("enable_tweak"), isOn: $patchStore.config.enabled)
                    .onChange(of: patchStore.config.enabled) { enabled in
                        if enabled { showApplyTab = true }
                    }
            }

            Section(header: Text("Created Patches")) {
                if patchStore.config.savedRules.isEmpty {
                    Text("Chưa có patch nào được tạo.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(patchStore.config.savedRules) { rule in
                        Button {
                            patchStore.selectRule(rule)
                            patchStore.config.enabled = true
                            showApplyTab = true
                            statusMessage = "Đã chọn patch: \(rule.projectName)"
                            showAlert = true
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rule.projectName.isEmpty ? rule.bundleID : rule.projectName)
                                        .foregroundStyle(.primary)
                                        .font(.body.weight(.medium))

                                    Text("\(rule.bundleID) • \(rule.relativePath)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    Text("\(rule.sourceFileName) • \(CustomPatchStore.formattedSize(rule.fileSizeBytes))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if patchStore.config.activeRule?.id == rule.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        patchStore.deleteRule(at: offsets)
                    }
                }
            }
        }
        .navigationTitle("Custom Patch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showCreatePatchSheet = true
                    } label: {
                        Label("Create Patch", systemImage: "plus")
                    }

                    Button {
                        show3105FilePicker = true
                    } label: {
                        Label("Import .3105 File", systemImage: "square.and.arrow.down")
                    }

                    if !patchStore.config.savedRules.isEmpty {
                        Button(role: .destructive) {
                            patchStore.restoreDefaults()
                            statusMessage = "Đã xóa toàn bộ patch đã tạo."
                            showAlert = true
                        } label: {
                            Label(L("mg_revert_tweaks"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreatePatchSheet) {
            CreatePatchSheetView(patchStore: patchStore)
        }
        .fileImporter(
            isPresented: $show3105FilePicker,
            allowedContentTypes: [.data, .item, .content],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        let imported = try patchStore.import3105Package(from: url)
                        patchStore.config.enabled = true
                        showApplyTab = true
                        statusMessage = "Đã thêm patch: \(imported.projectName)"
                        showAlert = true
                    } catch {
                        statusMessage = error.localizedDescription
                        showAlert = true
                    }
                }
            case .failure(let error):
                statusMessage = error.localizedDescription
                showAlert = true
            }
        }
        .alert(L("alert_message_title"), isPresented: $showAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(statusMessage ?? L("msg_error_unknown"))
        }
    }
}
