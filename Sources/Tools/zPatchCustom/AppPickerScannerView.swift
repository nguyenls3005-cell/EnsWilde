import SwiftUI
import Foundation
import UIKit
import UniformTypeIdentifiers

// MARK: - Patch & Tweak Models

struct EnsPatchItem: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var bundleID: String
    var containerPath: String
    var createdAt: Date
    var updatedAt: Date
    /// Lưu payload file/key cần patch: [relativePath: base64Data]
    var payloadFiles: [String: String]
    /// Lưu các thay đổi key/value hoặc config nhanh
    var notes: String
    /// Icon lưu dạng PNG base64 để export .ens mang đi vẫn có icon
    var iconPNGBase64: String?

    var uiIcon: UIImage? {
        guard let b64 = iconPNGBase64, let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }
}

struct TweakFileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let sizeBytes: Int64
    var children: [TweakFileNode]?
}

// MARK: - Patch Manager & .ens Exporter/Importer

@MainActor
final class EnsPatchManager: ObservableObject {
    static let shared = EnsPatchManager()

    @Published var patches: [EnsPatchItem] = []
    @Published var statusBanner: String = ""

    private let storageURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.storageURL = docs.appendingPathComponent("enswilde_patches.json")
        loadSavedPatches()
    }

    func loadSavedPatches() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([EnsPatchItem].self, from: data) else {
            return
        }
        patches = decoded
    }

    func persistPatches() {
        guard let data = try? JSONEncoder().encode(patches) else { return }
        _ = writeFileTemp(data, to: storageURL)
    }

    @discardableResult
    func addPatch(
        name: String,
        bundleID: String,
        icon: UIImage? = nil,
        notes: String = "",
        captureContainerSnapshot: Bool = true
    ) -> EnsPatchItem? {
        let resolved = PatchTargetResolver.prepareAndRegister(bundleID: bundleID)
        let cleanBID = resolved.bundleID.isEmpty ? bundleID.trimmingCharacters(in: .whitespacesAndNewlines) : resolved.bundleID
        guard !cleanBID.isEmpty else {
            statusBanner = "Bundle ID không hợp lệ"
            return nil
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (cleanBID.split(separator: ".").last.map(String.init) ?? cleanBID)
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        var filesMap: [String: String] = [:]
        if captureContainerSnapshot && !resolved.containerPath.isEmpty {
            filesMap = collectContainerPayload(containerPath: resolved.containerPath, maxTotalBytes: 4 * 1024 * 1024)
        }

        let iconB64 = icon?.pngData()?.base64EncodedString()

        let item = EnsPatchItem(
            id: UUID().uuidString,
            name: cleanName,
            bundleID: cleanBID,
            containerPath: resolved.containerPath,
            createdAt: Date(),
            updatedAt: Date(),
            payloadFiles: filesMap,
            notes: notes,
            iconPNGBase64: iconB64
        )

        patches.insert(item, at: 0)
        persistPatches()
        statusBanner = "Đã thêm patch cho \(cleanBID)"
        return item
    }

    func deletePatch(_ item: EnsPatchItem) {
        patches.removeAll { $0.id == item.id }
        persistPatches()
    }

    /// Export full sang file .ens (đã đóng gói đầy đủ để import là dùng ngay)
    func exportPatchToEnsFile(_ item: EnsPatchItem) -> URL? {
        let exportPackage = item
        guard let jsonData = try? JSONEncoder().encode(exportPackage) else {
            statusBanner = "Lỗi mã hoá .ens"
            return nil
        }

        let safeName = item.bundleID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).ens")

        let (ok, msg) = writeFileTemp(jsonData, to: outURL)
        if ok {
            statusBanner = "Đã xuất \(outURL.lastPathComponent)"
            return outURL
        } else {
            statusBanner = "Export lỗi: \(msg)"
            return nil
        }
    }

    /// Import file .ens và tự áp dụng/đăng ký container sẵn
    @discardableResult
    func importEnsFile(from url: URL) -> EnsPatchItem? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url),
              var decoded = try? JSONDecoder().decode(EnsPatchItem.self, from: data) else {
            statusBanner = "File .ens không hợp lệ"
            return nil
        }

        let resolved = PatchTargetResolver.prepareAndRegister(
            bundleID: decoded.bundleID,
            explicitContainerPath: decoded.containerPath
        )

        var updatedItem = EnsPatchItem(
            id: UUID().uuidString,
            name: decoded.name,
            bundleID: decoded.bundleID,
            containerPath: resolved.ok ? resolved.containerPath : decoded.containerPath,
            createdAt: decoded.createdAt,
            updatedAt: Date(),
            payloadFiles: decoded.payloadFiles,
            notes: decoded.notes,
            iconPNGBase64: decoded.iconPNGBase64
        )

        // Nếu có payload và có containerPath hợp lệ thì ghi sẵn vào container
        if resolved.ok && !resolved.containerPath.isEmpty && !updatedItem.payloadFiles.isEmpty {
            applyPayload(updatedItem.payloadFiles, toContainer: resolved.containerPath)
        }

        patches.removeAll { $0.bundleID.caseInsensitiveCompare(updatedItem.bundleID) == .orderedSame }
        patches.insert(updatedItem, at: 0)
        persistPatches()
        statusBanner = "Đã import \(url.lastPathComponent) cho \(updatedItem.bundleID)"
        return updatedItem
    }

    func applyPayload(_ payload: [String: String], toContainer containerPath: String) {
        let base = CSStoreEngine.normalizeVarPath(containerPath)
        for (relPath, b64) in payload {
            guard let fileData = Data(base64Encoded: b64) else { continue }
            let cleanRel = relPath.hasPrefix("/") ? String(relPath.dropFirst()) : relPath
            let targetURL = URL(fileURLWithPath: (base as NSString).appendingPathComponent(cleanRel))
            let parentDir = targetURL.deletingLastPathComponent().path
            _ = WQFullFastReader.grantAccessIfNeeded(path: parentDir, requireWrite: true)
            try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            _ = writeFileTemp(fileData, to: targetURL)
        }
    }

    private func collectContainerPayload(containerPath: String, maxTotalBytes: Int) -> [String: String] {
        let base = CSStoreEngine.normalizeVarPath(containerPath)
        _ = WQFullFastReader.grantAccessIfNeeded(path: base, requireWrite: false)
        let baseURL = URL(fileURLWithPath: base)
        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var map: [String: String] = [:]
        var accumulated = 0

        for case let fileURL as URL in enumerator {
            let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard vals?.isRegularFile == true else { continue }
            let size = vals?.fileSize ?? 0
            if size > 512 * 1024 { continue } // bỏ qua file > 512KB để file .ens gọn nhẹ
            if accumulated + size > maxTotalBytes { break }

            if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
                let rel = fileURL.path.replacingOccurrences(of: base + "/", with: "")
                map[rel] = data.base64EncodedString()
                accumulated += data.count
            }
        }
        return map
    }
}

// MARK: - Tweak Directory & Live File Editor Engine

enum TweakFileEngine {
    private static let fm = FileManager.default

    static func scanTree(at rootPath: String, maxDepth: Int = 5, currentDepth: Int = 0) -> [TweakFileNode] {
        let norm = CSStoreEngine.normalizeVarPath(rootPath)
        guard !norm.isEmpty, currentDepth <= maxDepth else { return [] }
        _ = WQFullFastReader.grantAccessIfNeeded(path: norm, requireWrite: false)

        guard let names = try? fm.contentsOfDirectory(atPath: norm) else { return [] }

        var nodes: [TweakFileNode] = []
        for name in names.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let fullPath = (norm as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            let size: Int64
            if isDir.boolValue {
                size = 0
            } else {
                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            }

            let children: [TweakFileNode]? = isDir.boolValue
                ? scanTree(at: fullPath, maxDepth: maxDepth, currentDepth: currentDepth + 1)
                : nil

            nodes.append(
                TweakFileNode(
                    id: fullPath,
                    name: name,
                    path: fullPath,
                    isDirectory: isDir.boolValue,
                    sizeBytes: size,
                    children: children
                )
            )
        }
        return nodes
    }

    static func readTextFile(at path: String) -> String {
        let norm = CSStoreEngine.normalizeVarPath(path)
        _ = WQFullFastReader.grantAccessIfNeeded(path: norm, requireWrite: false)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: norm)) else { return "" }

        if let str = String(data: data, encoding: .utf8) {
            return str
        }
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let xmlData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
           let xmlStr = String(data: xmlData, encoding: .utf8) {
            return xmlStr
        }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func saveTextFile(content: String, to path: String) -> (Bool, String) {
        let norm = CSStoreEngine.normalizeVarPath(path)
        let url = URL(fileURLWithPath: norm)
        _ = WQFullFastReader.grantAccessIfNeeded(path: norm, requireWrite: true)

        guard let data = content.data(using: .utf8) else {
            return (false, "Không mã hoá được UTF-8")
        }

        if fm.fileExists(atPath: norm) {
            let atomic = writeFileAtomically(data, to: url, allowEmpty: true)
            if atomic.0 { return atomic }
        }
        return writeFileTemp(data, to: url)
    }

    static func createFile(named name: String, inDirectory dirPath: String, initialContent: String = "") -> (Bool, String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return (false, "Tên file trống") }
        let normDir = CSStoreEngine.normalizeVarPath(dirPath)
        _ = WQFullFastReader.grantAccessIfNeeded(path: normDir, requireWrite: true)
        try? fm.createDirectory(atPath: normDir, withIntermediateDirectories: true)

        let fileURL = URL(fileURLWithPath: (normDir as NSString).appendingPathComponent(cleanName))
        let data = initialContent.data(using: .utf8) ?? Data()
        return writeFileTemp(data, to: fileURL)
    }

    static func deleteItem(at path: String) -> (Bool, String) {
        let norm = CSStoreEngine.normalizeVarPath(path)
        _ = WQFullFastReader.grantAccessIfNeeded(path: norm, requireWrite: true)
        do {
            try fm.removeItem(atPath: norm)
            return (true, "Đã xoá")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Extensions & Resolver

extension WQFullFastReader {
    @discardableResult
    static func grantAccessIfNeeded(path: String, requireWrite: Bool = false) -> Bool {
        let norm = CSStoreEngine.normalizeVarPath(path)
        guard !norm.isEmpty else { return false }
        let fm = FileManager.default
        if !requireWrite && fm.isReadableFile(atPath: norm) { return true }
        let (ok, _, _) = wq.grantAccess(path: norm, requireWrite: requireWrite, allowFsgetpathFallback: true)
        return ok || (requireWrite ? fm.isWritableFile(atPath: norm) : fm.isReadableFile(atPath: norm))
    }
}

enum PatchTargetResolver {
    @discardableResult
    static func prepareAndRegister(
        bundleID rawBundleID: String,
        explicitContainerPath: String? = nil
    ) -> (ok: Bool, bundleID: String, containerPath: String) {
        let bid = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bid.isEmpty else { return (false, "", "") }

        var containerPath = (explicitContainerPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !containerPath.isEmpty {
            containerPath = CSStoreEngine.normalizeVarPath(containerPath)
        }

        if containerPath.isEmpty {
            let (_, fastHit) = CSStoreEngine.shared.lookupAppContainer(forBundleID: bid)
            if let fastHit, !fastHit.isEmpty {
                containerPath = CSStoreEngine.normalizeVarPath(fastHit)
            }
        }

        if containerPath.isEmpty {
            let found = fsHandlers.getContainerPath(at: FSURL.appContainers, forMatch: bid, hashOnly: false)
            if !found.isEmpty {
                containerPath = CSStoreEngine.normalizeVarPath(found)
            }
        }

        if containerPath.isEmpty {
            let allContainers = fsHandlers.getDirPaths(FSURL.appContainers.path, forceRefresh: false)
            for raw in allContainers {
                let norm = CSStoreEngine.normalizeVarPath(raw)
                if let xattrBID = getBIDFromXattr(URL(fileURLWithPath: norm))?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   xattrBID.caseInsensitiveCompare(bid) == .orderedSame {
                    containerPath = norm
                    break
                }
            }
        }

        guard !containerPath.isEmpty else {
            return (false, bid, "")
        }

        zPatchStore.shared.registerContainer(bundleID: bid, containerPath: containerPath)
        return (true, bid, containerPath)
    }
}

// MARK: - Tweak Editor View (Đọc thư mục + Sửa/Xoá/Ghi trực tiếp)

struct TweakContainerEditorView: View {
    let bundleID: String
    let initialContainerPath: String

    @State private var containerPath: String = ""
    @State private var tree: [TweakFileNode] = []
    @State private var activeFilePath: String?
    @State private var editorText: String = ""
    @State private var statusText: String = ""
    @State private var newFileName: String = ""
    @State private var showNewFileAlert: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bundle ID: \(bundleID)")
                    .font(.subheadline.bold())
                Text(containerPath.isEmpty ? "Chưa tìm thấy container" : containerPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))

            if let filePath = activeFilePath {
                VStack(spacing: 8) {
                    HStack {
                        Text((filePath as NSString).lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Button("Lưu ghi") {
                            let res = TweakFileEngine.saveTextFile(content: editorText, to: filePath)
                            statusText = res.1
                            reloadTree()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Đóng file") {
                            activeFilePath = nil
                        }
                        .buttonStyle(.bordered)
                    }

                    TextEditor(text: $editorText)
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            } else {
                List {
                    ForEach(tree) { node in
                        TweakNodeRow(
                            node: node,
                            onSelectFile: { path in
                                activeFilePath = path
                                editorText = TweakFileEngine.readTextFile(at: path)
                                statusText = "Đang mở: \((path as NSString).lastPathComponent)"
                            },
                            onDeletePath: { path in
                                let res = TweakFileEngine.deleteItem(at: path)
                                statusText = res.1
                                reloadTree()
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Tweak Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button {
                        showNewFileAlert = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    Button {
                        reloadTree()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .alert("Tạo file mới trong container", isPresented: $showNewFileAlert) {
            TextField("Tên file (vd: config.plist)", text: $newFileName)
            Button("Tạo") {
                let targetDir = activeFilePath.map { ($0 as NSString).deletingLastPathComponent } ?? containerPath
                let res = TweakFileEngine.createFile(named: newFileName, inDirectory: targetDir)
                statusText = res.1
                newFileName = ""
                reloadTree()
            }
            Button("Huỷ", role: .cancel) { newFileName = "" }
        }
        .onAppear {
            let resolved = PatchTargetResolver.prepareAndRegister(
                bundleID: bundleID,
                explicitContainerPath: initialContainerPath
            )
            containerPath = resolved.containerPath
            reloadTree()
        }
    }

    private func reloadTree() {
        guard !containerPath.isEmpty else {
            tree = []
            return
        }
        tree = TweakFileEngine.scanTree(at: containerPath)
    }
}

private struct TweakNodeRow: View {
    let node: TweakFileNode
    let onSelectFile: (String) -> Void
    let onDeletePath: (String) -> Void

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(node.name) {
                ForEach(node.children ?? []) { child in
                    TweakNodeRow(
                        node: child,
                        onSelectFile: onSelectFile,
                        onDeletePath: onDeletePath
                    )
                }
            }
        } else {
            HStack {
                Button {
                    onSelectFile(node.path)
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(node.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(ByteCountFormatter.string(fromByteCount: node.sizeBytes, countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    onDeletePath(node.path)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Main Patch Hub View (+ Add Patch, Export .ens, Import .ens, Tweak)

struct EnsPatchHubView: View {
    @StateObject private var patchManager = EnsPatchManager.shared
    @State private var showAddSheet = false
    @State private var showImporter = false
    @State private var shareURL: URL?
    @State private var selectedTweakTarget: EnsPatchItem?

    @State private var manualName = ""
    @State private var manualBundleID = ""
    @State private var manualNotes = ""
    @State private var selectedBundleIDFromPicker = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !patchManager.statusBanner.isEmpty {
                    Text(patchManager.statusBanner)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                }

                List {
                    ForEach(patchManager.patches) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Group {
                                    if let img = item.uiIcon {
                                        Image(uiImage: img)
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
                                .frame(width: 48, height: 48)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.headline)
                                    Text(item.bundleID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Button {
                                    if let url = patchManager.exportPatchToEnsFile(item) {
                                        shareURL = url
                                    }
                                } label: {
                                    Label("Export .ens", systemImage: "square.and.arrow.up")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent)

                                NavigationLink {
                                    TweakContainerEditorView(
                                        bundleID: item.bundleID,
                                        initialContainerPath: item.containerPath
                                    )
                                } label: {
                                    Label("Tweak", systemImage: "folder.badge.gearshape")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Button(role: .destructive) {
                                    patchManager.deletePatch(item)
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
            .navigationTitle("EnsWilde Patch")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import .ens", systemImage: "square.and.arrow.down")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manualName = ""
                        manualBundleID = ""
                        manualNotes = ""
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
                        Section("Thông tin Patch") {
                            TextField("Tên hiển thị (tuỳ chọn)", text: $manualName)
                            TextField("Bundle ID (vd: com.example.app)", text: $manualBundleID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Ghi chú", text: $manualNotes)
                        }

                        Section {
                            Button("Lưu & Tạo Patch") {
                                let bid = manualBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !bid.isEmpty else { return }
                                _ = patchManager.addPatch(
                                    name: manualName,
                                    bundleID: bid,
                                    notes: manualNotes,
                                    captureContainerSnapshot: true
                                )
                                showAddSheet = false
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .navigationTitle("+ Add Patch")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Đóng") { showAddSheet = false }
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let fileURL = urls.first {
                    _ = patchManager.importEnsFile(from: fileURL)
                }
            }
            .sheet(item: Binding(
                get: { shareURL.map { ShareFileWrapper(url: $0) } },
                set: { shareURL = $0?.url }
            )) { wrapper in
                ActivityShareSheet(activityItems: [wrapper.url])
            }
        }
    }
}

private struct ShareFileWrapper: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
