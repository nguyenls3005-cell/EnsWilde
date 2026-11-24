//
//  CustomPatchView.swift
//  EnsWilde
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CustomPatchConfig: Codable, Equatable {
    var enabled: Bool = false
    var targetMode: TargetMode = .filePath
    var targetFilePath: String = ""
    var targetBundleID: String = ""
    var bundleRelativeSubpath: String = ""
    var sourceFileName: String = ""
    var sourceStoredPath: String = ""

    enum TargetMode: String, Codable, CaseIterable {
        case filePath
        case bundleID
    }
}

final class CustomPatchStore: ObservableObject {
    static let shared = CustomPatchStore()

    private let storageKey = "EnsWilde.CustomPatchConfig.v1"

    @Published var config: CustomPatchConfig {
        didSet {
            saveToDefaults()
            objectWillChange.send()
        }
    }

    var isEnabled: Bool {
        get { config.enabled }
        set { config.enabled = newValue }
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

    func importSourceFile(from url: URL) throws {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let folder = URL.documentsDirectory.appendingPathComponent("CustomPatch", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let destURL = folder.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try data.write(to: destURL, options: .atomic)
        chmod(destURL.path, 0o644)

        config.sourceFileName = url.lastPathComponent
        config.sourceStoredPath = destURL.path
    }

    func clearSourceFile() {
        if !config.sourceStoredPath.isEmpty {
            try? FileManager.default.removeItem(at: URL(filePath: config.sourceStoredPath))
        }
        config.sourceFileName = ""
        config.sourceStoredPath = ""
    }
}

enum CustomPatchError: LocalizedError {
    case disabled
    case missingSourceFile
    case invalidTarget
    case bundleNotFound(String)
    case openFailed(String)
    case truncateFailed(String)
    case writeFailed(Int, Int)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Custom Patch đang tắt."
        case .missingSourceFile:
            return "Chưa chọn file nguồn hoặc file patch không tồn tại."
        case .invalidTarget:
            return "Đường dẫn file đích hoặc Bundle ID đang trống."
        case .bundleNotFound(let bid):
            return "Không tìm thấy app/bundle cho Bundle ID: \(bid)"
        case .openFailed(let reason):
            return "Không mở được file đích để ghi: \(reason)"
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
        return 10_000_000
    }

    private static func findBundlePath(for bundleID: String, log: (String) -> Void) -> String? {
        if let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
           let _ = cls.perform(Selector("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
           let appProxyClass = NSClassFromString("LSApplicationProxy") as? NSObject.Type,
           let proxy = appProxyClass.perform(Selector("applicationProxyForIdentifier:"), with: bundleID)?.takeUnretainedValue() as? NSObject,
           let bundleURL = proxy.value(forKey: "bundleURL") as? URL {
            log("[CustomPatch] Tìm thấy bundle qua LSApplicationProxy: \(bundleURL.path)")
            return bundleURL.path
        }

        log("[CustomPatch] Đang dò bundle qua pathleak cho \(bundleID)...")
        let maxInode = estimatedMaxInode()
        let searchRoots = ["/var/containers/Bundle/Application", "/private/var/containers/Bundle/Application"]

        for root in searchRoots {
            _ = wq.grantAccess(path: root, requireWrite: false)
            if let uuidDirs = pathleak(root, maxInode) as? [String] {
                for uuidDir in uuidDirs {
                    _ = wq.grantAccess(path: uuidDir, requireWrite: false)
                    guard let items = try? FileManager.default.contentsOfDirectory(atPath: uuidDir) else { continue }
                    for item in items where item.hasSuffix(".app") {
                        let appPath = (uuidDir as NSString).appendingPathComponent(item)
                        let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
                        if let dict = NSDictionary(contentsOfFile: infoPath),
                           let cfBundleID = dict["CFBundleIdentifier"] as? String,
                           cfBundleID == bundleID {
                            log("[CustomPatch] Tìm thấy bundle qua pathleak: \(appPath)")
                            return appPath
                        }
                    }
                }
            }
        }

        return nil
    }

    static func resolveTargetPath(config: CustomPatchConfig, log: (String) -> Void = { _ in }) throws -> String {
        switch config.targetMode {
        case .filePath:
            let trimmed = config.targetFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CustomPatchError.invalidTarget }
            return (trimmed as NSString).standardizingPath

        case .bundleID:
            let bid = config.targetBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bid.isEmpty else { throw CustomPatchError.invalidTarget }

            if bid.hasPrefix("/") {
                return (bid as NSString).standardizingPath
            }

            guard let baseBundlePath = findBundlePath(for: bid, log: log) else {
                throw CustomPatchError.bundleNotFound(bid)
            }

            let sub = config.bundleRelativeSubpath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            if sub.isEmpty {
                return baseBundlePath
            }
            return URL(filePath: baseBundlePath).appendingPathComponent(sub).path
        }
    }

    static func applyIfEnabled(log: (String) -> Void = { _ in }) async throws {
        let cfg = CustomPatchStore.shared.config
        guard cfg.enabled else {
            log("[CustomPatch] Đang tắt, bỏ qua.")
            return
        }

        guard !cfg.sourceStoredPath.isEmpty,
              FileManager.default.fileExists(atPath: cfg.sourceStoredPath),
              let patchData = try? Data(contentsOf: URL(filePath: cfg.sourceStoredPath)) else {
            throw CustomPatchError.missingSourceFile
        }

        let targetPath = try resolveTargetPath(config: cfg, log: log)
        let targetURL = URL(filePath: targetPath)
        let parentDir = targetURL.deletingLastPathComponent().path

        log("[CustomPatch] Cấp quyền WorseQuery cho thư mục cha: \(parentDir)")
        _ = wq.grantAccess(path: parentDir, requireWrite: true)

        log("[CustomPatch] Cấp quyền WorseQuery cho file đích: \(targetPath)")
        let granted = wq.grantAccess(path: targetPath, requireWrite: true)
        if !granted.0 {
            log("[CustomPatch] ⚠️ WorseQuery cảnh báo: \(granted.2) (code \(granted.1))")
        }

        log("[CustomPatch] Đang ghi \(patchData.count) bytes vào \(targetPath)...")
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
        log("[CustomPatch] ✅ Ghi hoàn tất \(totalWritten) bytes.")
    }
}

struct CustomPatchView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @StateObject private var patchStore = CustomPatchStore.shared
    @ObservedObject var toolStore: ToolStore

    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false

    @State private var showFilePicker = false
    @State private var statusMessage: String?
    @State private var showAlert = false
    @State private var isApplying = false

    var body: some View {
        Form {
            Section(header: Text("Custom Patch")) {
                Toggle(L("enable_tweak"), isOn: $patchStore.config.enabled)
                    .onChange(of: patchStore.config.enabled) { enabled in
                        if enabled { showApplyTab = true }
                    }
            }

            Section(header: Text("Đích cần ghi")) {
                Picker("Chế độ", selection: $patchStore.config.targetMode) {
                    Text("Đường dẫn file").tag(CustomPatchConfig.TargetMode.filePath)
                    Text("Bundle ID").tag(CustomPatchConfig.TargetMode.bundleID)
                }
                .pickerStyle(.segmented)

                if patchStore.config.targetMode == .filePath {
                    TextField("/var/...", text: $patchStore.config.targetFilePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    TextField("com.apple.example", text: $patchStore.config.targetBundleID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("File bên trong bundle (tuỳ chọn, vd: Info.plist)", text: $patchStore.config.bundleRelativeSubpath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section(header: Text("File cần thay đổi")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(patchStore.config.sourceFileName.isEmpty ? "Chưa chọn file" : patchStore.config.sourceFileName)
                            .font(.body)
                        if !patchStore.config.sourceStoredPath.isEmpty {
                            Text(patchStore.config.sourceStoredPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("Chọn file") {
                        showFilePicker = true
                    }
                }

                if !patchStore.config.sourceFileName.isEmpty {
                    Button(role: .destructive) {
                        patchStore.clearSourceFile()
                    } label: {
                        Text("Xoá file")
                    }
                }
            }

            Section(header: Text(L("section_save_reset"))) {
                Button {
                    Task { await runApplyNow() }
                } label: {
                    HStack {
                        Label("Apply ngay", systemImage: "play.fill")
                        if isApplying {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isApplying)
            }
        }
        .navigationTitle("Custom Patch")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        try patchStore.importSourceFile(from: url)
                        showApplyTab = true
                        statusMessage = "Đã nạp file: \(url.lastPathComponent)"
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

    private func runApplyNow() async {
        isApplying = true
        defer { isApplying = false }
        do {
            try await CustomPatchApplyTask.applyIfEnabled()
            statusMessage = L("apply_done")
            showAlert = true
        } catch {
            statusMessage = error.localizedDescription
            showAlert = true
        }
    }
}
