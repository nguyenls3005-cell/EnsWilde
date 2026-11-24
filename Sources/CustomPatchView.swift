//
//  CustomPatchView.swift
//  EnsWilde
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CryptoKit

enum ImportAlert: Identifiable {
    case info(String)

    var id: String {
        switch self {
        case .info(let message):
            return "info_\(message)"
        }
    }
}

struct PendingPasswordImport: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let patchName: String
    var errorMessage: String? = nil
}

struct ExportFileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

struct CustomPatchRule: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var projectName: String = ""
    var bundleID: String = ""
    var relativePath: String = ""
    var sourceFileName: String = ""
    var sourceStoredPath: String = ""
    var packageStoredPath: String = ""
    var fileSizeBytes: Int64 = 0
    var passwordHashSHA256: String? = nil
    var isLegacyV1: Bool = true
}

struct Patch3105Package: Codable {
    var formatVersion: Int = 1
    var projectName: String
    var bundleID: String
    var relativePath: String
    var fileName: String
    var fileDataBase64: String
    var passwordRequired: Bool? = false
    var passwordHashSHA256: String? = nil
    var encryptedPayloadBase64: String? = nil
    var encryptionNonceBase64: String? = nil
}

enum Patch3105ImportResult {
    case imported(CustomPatchRule)
    case needsPassword(url: URL, suggestedName: String, expectedHash: String?, pkg: Patch3105Package?)
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

    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func cleanPatchDisplayName(rawProjectName: String?, fileURL: URL) -> String {
        if let name = rawProjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let base = fileURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "Custom Patch" : base
    }

    static var supportedFileTypes: [UTType] {
        var types: [UTType] = [.item, .data, .content]
        if let t3105 = UTType(filenameExtension: "3105") {
            types.insert(t3105, at: 0)
        }
        return types
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
            try FileManager.default.removeItem(atPath: destURL.path)
        }
        try data.write(to: destURL, options: .atomic)
        chmod(destURL.path, 0o644)

        target.sourceFileName = url.lastPathComponent
        target.sourceStoredPath = destURL.path
        target.fileSizeBytes = Int64(data.count)
    }

    @discardableResult
    func upsertRule(_ rule: CustomPatchRule, setActive: Bool = true, enableTweak: Bool? = nil) -> CustomPatchRule {
        var updated = rule
        if updated.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.projectName = updated.sourceFileName.isEmpty ? "Custom Patch" : updated.sourceFileName
        }

        config.savedRules.removeAll { $0.id == updated.id }
        config.savedRules.insert(updated, at: 0)

        if setActive {
            config.activeRule = updated
        } else if config.activeRule?.id == updated.id {
            config.activeRule = updated
        }

        if let enableTweak {
            config.enabled = enableTweak
        }

        saveToDefaults()
        return updated
    }

    func createAndSave3105(
        projectName: String,
        bundleID: String,
        relativePath: String,
        sourceStoredPath: String,
        sourceFileName: String,
        password: String? = nil,
        existingID: UUID? = nil
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

        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasPassword = !trimmedPassword.isEmpty
        let pwdHash = hasPassword ? Self.sha256Hex(trimmedPassword) : nil

        var payloadB64 = data.base64EncodedString()
        var encPayloadB64: String? = nil
        var nonceB64: String? = nil

        if hasPassword {
            let key = SymmetricKey(data: SHA256.hash(data: Data(trimmedPassword.utf8)))
            let sealed = try AES.GCM.seal(data, using: key)
            encPayloadB64 = sealed.combined?.base64EncodedString()
            nonceB64 = Data(sealed.nonce).base64EncodedString()
            payloadB64 = ""
        }

        let pkg = Patch3105Package(
            projectName: cleanName,
            bundleID: cleanBundleID,
            relativePath: relativePath.trimmingCharacters(in: .whitespacesAndNewlines),
            fileName: cleanFileName,
            fileDataBase64: payloadB64,
            passwordRequired: hasPassword,
            passwordHashSHA256: pwdHash,
            encryptedPayloadBase64: encPayloadB64,
            encryptionNonceBase64: nonceB64
        )

        let pkgData = try JSONEncoder().encode(pkg)
        let folder = try patchFolderURL()
        let fileSlug = pkg.projectName.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let pkgURL = folder.appendingPathComponent("\(fileSlug)_\(UUID().uuidString.prefix(6)).3105")
        try pkgData.write(to: pkgURL, options: .atomic)

        let extractedURL = folder.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(pkg.fileName)")
        try data.write(to: extractedURL, options: .atomic)
        chmod(extractedURL.path, 0o644)

        let rule = CustomPatchRule(
            id: existingID ?? UUID(),
            projectName: pkg.projectName,
            bundleID: pkg.bundleID,
            relativePath: pkg.relativePath,
            sourceFileName: pkg.fileName,
            sourceStoredPath: extractedURL.path,
            packageStoredPath: pkgURL.path,
            fileSizeBytes: Int64(data.count),
            passwordHashSHA256: pwdHash,
            isLegacyV1: true
        )

        return upsertRule(rule, setActive: true, enableTweak: true)
    }

    func export3105URL(for rule: CustomPatchRule) throws -> URL {
        if !rule.packageStoredPath.isEmpty, FileManager.default.fileExists(atPath: rule.packageStoredPath) {
            return URL(filePath: rule.packageStoredPath)
        }
        let created = try createAndSave3105(
            projectName: rule.projectName,
            bundleID: rule.bundleID,
            relativePath: rule.relativePath,
            sourceStoredPath: rule.sourceStoredPath,
            sourceFileName: rule.sourceFileName,
            existingID: rule.id
        )
        return URL(filePath: created.packageStoredPath)
    }

    func prepareImport3105(from url: URL, password: String? = nil) throws -> Patch3105ImportResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let rawData = try Data(contentsOf: url, options: .mappedIfSafe)
        let folder = try patchFolderURL()
        let storedPkgURL = folder.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(url.lastPathComponent)")
        try rawData.write(to: storedPkgURL, options: .atomic)

        if let pkg = try? JSONDecoder().decode(Patch3105Package.self, from: rawData) {
            let displayName = Self.cleanPatchDisplayName(rawProjectName: pkg.projectName, fileURL: url)
            let requiresPwd = (pkg.passwordRequired == true)
                || !(pkg.passwordHashSHA256?.isEmpty ?? true)
                || !(pkg.encryptedPayloadBase64?.isEmpty ?? true)

            if requiresPwd {
                let enteredPwd = password ?? ""
                if enteredPwd.isEmpty {
                    return .needsPassword(
                        url: storedPkgURL,
                        suggestedName: displayName,
                        expectedHash: pkg.passwordHashSHA256,
                        pkg: pkg
                    )
                }

                if let expectedHash = pkg.passwordHashSHA256, !expectedHash.isEmpty {
                    if Self.sha256Hex(enteredPwd).lowercased() != expectedHash.lowercased() {
                        throw CustomPatchError.invalidPassword
                    }
                }

                let payloadData: Data
                if let encB64 = pkg.encryptedPayloadBase64, !encB64.isEmpty {
                    let key = SymmetricKey(data: SHA256.hash(data: Data(enteredPwd.utf8)))
                    guard let combined = Data(base64Encoded: encB64),
                          let sealedBox = try? AES.GCM.SealedBox(combined: combined),
                          let opened = try? AES.GCM.open(sealedBox, using: key) else {
                        throw CustomPatchError.invalidPassword
                    }
                    payloadData = opened
                } else if let plainData = Data(base64Encoded: pkg.fileDataBase64), !plainData.isEmpty {
                    payloadData = plainData
                } else {
                    throw CustomPatchError.invalidPackageData
                }

                let outName = pkg.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? url.lastPathComponent
                    : pkg.fileName
                let outURL = folder.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(outName)")
                try payloadData.write(to: outURL, options: .atomic)
                chmod(outURL.path, 0o644)

                let rule = CustomPatchRule(
                    projectName: displayName,
                    bundleID: pkg.bundleID.trimmingCharacters(in: .whitespacesAndNewlines),
                    relativePath: pkg.relativePath.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceFileName: outName,
                    sourceStoredPath: outURL.path,
                    packageStoredPath: storedPkgURL.path,
                    fileSizeBytes: Int64(payloadData.count),
                    passwordHashSHA256: pkg.passwordHashSHA256,
                    isLegacyV1: true
                )
                return .imported(upsertRule(rule, setActive: true))
            }

            if let payload = Data(base64Encoded: pkg.fileDataBase64) {
                let outName = pkg.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? url.lastPathComponent
                    : pkg.fileName
                let outURL = folder.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(outName)")
                try payload.write(to: outURL, options: .atomic)
                chmod(outURL.path, 0o644)

                let rule = CustomPatchRule(
                    projectName: displayName,
                    bundleID: pkg.bundleID.trimmingCharacters(in: .whitespacesAndNewlines),
                    relativePath: pkg.relativePath.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceFileName: outName,
                    sourceStoredPath: outURL.path,
                    packageStoredPath: storedPkgURL.path,
                    fileSizeBytes: Int64(payload.count),
                    passwordHashSHA256: pkg.passwordHashSHA256,
                    isLegacyV1: true
                )
                return .imported(upsertRule(rule, setActive: true))
            }
        }

        let displayName = Self.cleanPatchDisplayName(rawProjectName: nil, fileURL: url)
        let outURL = folder.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(url.lastPathComponent)")
        try rawData.write(to: outURL, options: .atomic)
        chmod(outURL.path, 0o644)

        let rule = CustomPatchRule(
            projectName: displayName,
            bundleID: config.activeRule?.bundleID ?? "",
            relativePath: config.activeRule?.relativePath ?? "",
            sourceFileName: url.lastPathComponent,
            sourceStoredPath: outURL.path,
            packageStoredPath: storedPkgURL.path,
            fileSizeBytes: Int64(rawData.count),
            passwordHashSHA256: nil,
            isLegacyV1: true
        )
        return .imported(upsertRule(rule, setActive: true))
    }

    func import3105Package(from url: URL, password: String? = nil) throws -> CustomPatchRule {
        let result = try prepareImport3105(from: url, password: password)
        switch result {
        case .imported(let rule):
            return rule
        case .needsPassword:
            throw CustomPatchError.passwordRequired
        }
    }

    func selectRule(_ rule: CustomPatchRule) {
        config.activeRule = rule
        saveToDefaults()
    }

    func saveChanges(showApplyTab: inout Bool) {
        if config.activeRule == nil, let first = config.savedRules.first {
            config.activeRule = first
        }
        if let active = config.activeRule {
            config.savedRules.removeAll { $0.id == active.id }
            config.savedRules.insert(active, at: 0)
        }
        saveToDefaults()
        showApplyTab = true
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
            if !removed.packageStoredPath.isEmpty {
                try? FileManager.default.removeItem(atPath: removed.packageStoredPath)
            }
        }
        config.savedRules.remove(atOffsets: offsets)
        if let activeID = config.activeRule?.id, removedIDs.contains(activeID) {
            config.activeRule = config.savedRules.first
        }
        saveToDefaults()
    }

    func restoreDefaults() {
        for r in config.savedRules {
            if !r.sourceStoredPath.isEmpty {
                try? FileManager.default.removeItem(atPath: r.sourceStoredPath)
            }
            if !r.packageStoredPath.isEmpty {
                try? FileManager.default.removeItem(atPath: r.packageStoredPath)
            }
        }
        if let active = config.activeRule {
            if !active.sourceStoredPath.isEmpty {
                try? FileManager.default.removeItem(atPath: active.sourceStoredPath)
            }
            if !active.packageStoredPath.isEmpty {
                try? FileManager.default.removeItem(atPath: active.packageStoredPath)
            }
        }
        config = CustomPatchConfig()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

enum CustomPatchError: LocalizedError {
    case disabled
    case missingBundleID
    case missingSourceFile
    case passwordRequired
    case invalidPassword
    case invalidPackageData
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
        case .passwordRequired:
            return "File .3105 này yêu cầu mật khẩu."
        case .invalidPassword:
            return "Mật khẩu không đúng. Vui lòng thử lại."
        case .invalidPackageData:
            return "Dữ liệu trong file .3105 không hợp lệ hoặc bị hỏng."
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
    static func enabledPatchLabels() -> [String] {
        let cfg = CustomPatchStore.shared.config
        guard cfg.enabled else { return [] }
        if let active = cfg.activeRule {
            let name = active.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? (active.sourceFileName.isEmpty ? "Custom Patch" : active.sourceFileName) : name
            return ["Custom Patch: \(label)"]
        }
        if let first = cfg.savedRules.first {
            let name = first.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? (first.sourceFileName.isEmpty ? "Custom Patch" : first.sourceFileName) : name
            return ["Custom Patch: \(label)"]
        }
        return ["Custom Patch"]
    }

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

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct PasswordImportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let patchName: String
    var errorMessage: String?
    let onSubmit: (String) -> Void

    @State private var passwordInput: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Patch")) {
                    Text(patchName)
                        .font(.body.weight(.medium))
                }

                Section(header: Text("Mật khẩu")) {
                    SecureField("Nhập mật khẩu file .3105", text: $passwordInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Nhập mật khẩu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("alert_ok")) {
                        let pwd = passwordInput
                        dismiss()
                        onSubmit(pwd)
                    }
                }
            }
        }
    }
}

struct EditPatchRuleSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var patchStore: CustomPatchStore

    let ruleID: UUID?
    @State private var projectName: String
    @State private var bundleID: String
    @State private var relativePath: String
    @State private var password: String
    @State private var draftRule: CustomPatchRule
    @State private var showFilePicker = false
    @State private var errMessage: String?

    init(patchStore: CustomPatchStore, initialRule: CustomPatchRule?) {
        self.patchStore = patchStore
        let base = initialRule ?? CustomPatchRule()
        self.ruleID = initialRule?.id
        _projectName = State(initialValue: base.projectName)
        _bundleID = State(initialValue: base.bundleID)
        _relativePath = State(initialValue: base.relativePath)
        _password = State(initialValue: "")
        _draftRule = State(initialValue: base)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Patch Name")) {
                    TextField("Tên patch", text: $projectName)
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
                        HStack(spacing: 10) {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                let fileTitle = draftRule.sourceFileName.isEmpty ? "Choose file" : draftRule.sourceFileName
                                Text(fileTitle)
                                    .foregroundStyle(.primary)
                                Text("Tap to choose another file")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
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

                Section(header: Text("Password (Optional)")) {
                    SecureField("Nhập mật khẩu nếu muốn khóa file .3105", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let errMessage {
                    Section {
                        Text(errMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        do {
                            _ = try patchStore.createAndSave3105(
                                projectName: projectName,
                                bundleID: bundleID,
                                relativePath: relativePath,
                                sourceStoredPath: draftRule.sourceStoredPath,
                                sourceFileName: draftRule.sourceFileName,
                                password: password,
                                existingID: ruleID
                            )
                            dismiss()
                        } catch {
                            errMessage = error.localizedDescription
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView(
                    allowedContentTypes: CustomPatchStore.supportedFileTypes,
                    onPick: { url in
                        showFilePicker = false
                        do {
                            try patchStore.importReplacementFile(from: url, intoRule: &draftRule)
                            if relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                relativePath = url.lastPathComponent
                            }
                            errMessage = nil
                        } catch {
                            errMessage = error.localizedDescription
                        }
                    },
                    onCancel: {
                        showFilePicker = false
                    }
                )
            }
        }
    }
}

struct PatchDetailView: View {
    @ObservedObject var patchStore: CustomPatchStore
    let ruleID: UUID

    @State private var showEditRuleSheet = false
    @State private var showSetPasswordAlert = false
    @State private var newPasswordText = ""
    @State private var exportItem: ExportFileItem?
    @State private var alertMessage: String?
    @State private var showAlert = false

    private var rule: CustomPatchRule {
        patchStore.config.savedRules.first(where: { $0.id == ruleID })
            ?? patchStore.config.activeRule
            ?? CustomPatchRule(id: ruleID)
    }

    private var patchTitle: String {
        let trimmed = rule.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return rule.sourceFileName.isEmpty ? "Custom Patch" : rule.sourceFileName
    }

    var body: some View {
        List {
            Section(header: Text("Rules")) {
                Button {
                    patchStore.selectRule(rule)
                    showEditRuleSheet = true
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.bundleID.isEmpty ? "com.lemon.lvoverseas" : rule.bundleID)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(rule.relativePath.isEmpty ? rule.sourceFileName : rule.relativePath)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text(rule.sourceFileName.isEmpty ? "No file" : rule.sourceFileName)
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if rule.isLegacyV1 {
                Section {
                    Text("Legacy v1 patch. It remains fully usable in this version of 3105.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("Password")) {
                Button {
                    newPasswordText = ""
                    showSetPasswordAlert = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                        Text(rule.passwordHashSHA256 == nil ? "Set permanently" : "Password set permanently")
                            .foregroundStyle(.primary)
                    }
                }
            }

            Section(
                footer: Text("Before writing, 3105 resolves each bundle on this device and saves every original file for recovery.")
            ) {
                Button {
                    do {
                        let url = try patchStore.export3105URL(for: rule)
                        exportItem = ExportFileItem(url: url)
                    } catch {
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.orange)
                        Text("Export .3105")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle(patchTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    patchStore.selectRule(rule)
                    showEditRuleSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditRuleSheet) {
            EditPatchRuleSheetView(patchStore: patchStore, initialRule: rule)
        }
        .sheet(item: $exportItem) { item in
            ShareSheetView(activityItems: [item.url])
        }
        .alert("Set Password", isPresented: $showSetPasswordAlert) {
            SecureField("Password", text: $newPasswordText)
            Button(L("alert_cancel"), role: .cancel) {
                newPasswordText = ""
            }
            Button(L("alert_ok")) {
                let pwd = newPasswordText.trimmingCharacters(in: .whitespacesAndNewlines)
                newPasswordText = ""
                do {
                    _ = try patchStore.createAndSave3105(
                        projectName: rule.projectName,
                        bundleID: rule.bundleID,
                        relativePath: rule.relativePath,
                        sourceStoredPath: rule.sourceStoredPath,
                        sourceFileName: rule.sourceFileName,
                        password: pwd,
                        existingID: rule.id
                    )
                    alertMessage = pwd.isEmpty ? "Đã xóa mật khẩu patch." : "Đã đặt mật khẩu cho patch."
                } catch {
                    alertMessage = error.localizedDescription
                }
                showAlert = true
            }
        } message: {
            Text("Nhập mật khẩu cố định cho file .3105 của patch này.")
        }
        .alert(L("alert_message_title"), isPresented: $showAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(alertMessage ?? L("msg_error_unknown"))
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
    @State private var selectedDetailRuleID: UUID? = nil

    @State private var pendingPasswordImport: PendingPasswordImport?
    @State private var activeAlert: ImportAlert?

    var body: some View {
        List {
            Section {
                Toggle(L("enable_tweak"), isOn: $patchStore.config.enabled)
            }

            Section(header: Text("Created Patches")) {
                if patchStore.config.savedRules.isEmpty {
                    Text("Chưa có patch nào được tạo.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(patchStore.config.savedRules) { rule in
                        ruleRow(for: rule)
                    }
                    .onDelete { offsets in
                        patchStore.deleteRule(at: offsets)
                    }
                }
            }

            Section(header: Text(L("section_save_reset"))) {
                Button {
                    patchStore.saveChanges(showApplyTab: &showApplyTab)
                    activeAlert = .info("Đã lưu thay đổi. Chuyển sang trang Apply để áp dụng.")
                } label: {
                    Label("Save Changes", systemImage: "square.and.arrow.down")
                }

                Button(role: .destructive) {
                    patchStore.restoreDefaults()
                    showApplyTab = false
                    activeAlert = .info("Đã khôi phục mặc định và xóa toàn bộ patch đã tạo.")
                } label: {
                    Label(L("mg_revert_tweaks"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Custom Patch")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedDetailRuleID) { ruleID in
            PatchDetailView(patchStore: patchStore, ruleID: ruleID)
        }
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
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreatePatchSheet) {
            EditPatchRuleSheetView(patchStore: patchStore, initialRule: nil)
        }
        .sheet(isPresented: $show3105FilePicker) {
            DocumentPickerView(
                allowedContentTypes: CustomPatchStore.supportedFileTypes,
                onPick: { url in
                    show3105FilePicker = false
                    handleImport3105(url: url, password: nil)
                },
                onCancel: {
                    show3105FilePicker = false
                }
            )
        }
        .sheet(item: $pendingPasswordImport) { pending in
            PasswordImportSheetView(
                patchName: pending.patchName,
                errorMessage: pending.errorMessage
            ) { pwd in
                handleImport3105(url: pending.url, password: pwd)
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .info(let message):
                return Alert(
                    title: Text(L("alert_message_title")),
                    message: Text(message),
                    dismissButton: .default(Text(L("alert_ok")))
                )
            }
        }
    }

    private func displayTitle(for rule: CustomPatchRule) -> String {
        let trimmedProject = rule.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProject.isEmpty {
            return trimmedProject
        }
        let trimmedFile = rule.sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFile.isEmpty ? "Custom Patch" : trimmedFile
    }

    @ViewBuilder
    private func ruleRow(for rule: CustomPatchRule) -> some View {
        let title = displayTitle(for: rule)
        let isSelected = patchStore.config.activeRule?.id == rule.id
        let sizeText = CustomPatchStore.formattedSize(rule.fileSizeBytes)

        Button {
            patchStore.selectRule(rule)
            selectedDetailRuleID = rule.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .font(.body.weight(.medium))

                    if !rule.bundleID.isEmpty || !rule.relativePath.isEmpty {
                        Text("\(rule.bundleID) • \(rule.relativePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text("\(rule.sourceFileName) • \(sizeText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func handleImport3105(url: URL, password: String?) {
        do {
            let outcome = try patchStore.prepareImport3105(from: url, password: password)
            switch outcome {
            case .needsPassword(let targetURL, let suggestedName, _, _):
                pendingPasswordImport = PendingPasswordImport(
                    url: targetURL,
                    patchName: suggestedName,
                    errorMessage: nil
                )

            case .imported(let rule):
                pendingPasswordImport = nil
                selectedDetailRuleID = rule.id
                activeAlert = .info("Đã import patch: \(displayTitle(for: rule))")
            }
        } catch {
            if case CustomPatchError.invalidPassword = error {
                let fallbackName = CustomPatchStore.cleanPatchDisplayName(rawProjectName: nil, fileURL: url)
                pendingPasswordImport = PendingPasswordImport(
                    url: url,
                    patchName: fallbackName,
                    errorMessage: error.localizedDescription
                )
            } else {
                pendingPasswordImport = nil
                activeAlert = .info(error.localizedDescription)
            }
        }
    }
}

//
//  SettingsView.swift
//  EnsWilde
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network
import AirliftFFI
import Darwin
import Security
import XPC

// MARK: - Private Security Framework APIs
@_silgen_name("SecTaskCreateFromSelf")
func SecTaskCreateFromSelf(_ allocator: UnsafeRawPointer?) -> CFTypeRef?

@_silgen_name("SecTaskCopyValueForEntitlement")
func SecTaskCopyValueForEntitlement(
    _ task: CFTypeRef,
    _ entitlement: CFString,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> CFTypeRef?

// MARK: - Private Sandbox & File APIs
@_silgen_name("sandbox_extension_consume")
private func sandbox_extension_consume(_ token: UnsafePointer<CChar>) -> Int64

@_silgen_name("sandbox_extension_release")
private func sandbox_extension_release(_ handle: Int64) -> Int

@_silgen_name("fsgetpath")
private func fsgetpath(_ buf: UnsafeMutablePointer<CChar>, _ buflen: Int, _ fsid: UnsafePointer<fsid_t>, _ objid: UInt64) -> Int

// MARK: - Native WorseQuery Bridge (Bypass AirliftFFI)
typealias ContainerQueryCreateFn = @convention(c) () -> OpaquePointer?
typealias ContainerQuerySetClassFn = @convention(c) (OpaquePointer?, UInt64) -> Void
typealias ContainerQuerySetGroupIdentifiersFn = @convention(c) (OpaquePointer?, xpc_object_t) -> Void
typealias ContainerQuerySetFlagsFn = @convention(c) (OpaquePointer?, UInt64) -> Void
typealias ContainerQuerySetPartFn = @convention(c) (OpaquePointer?, UInt64) -> Void
typealias ContainerQueryGetSingleResultFn = @convention(c) (OpaquePointer?) -> OpaquePointer?
typealias ContainerQueryFreeFn = @convention(c) (OpaquePointer?) -> Void
typealias ContainerCopySandboxTokenFn = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
typealias SandboxExtensionConsumeFn = @convention(c) (UnsafePointer<CChar>) -> Int64
typealias SandboxExtensionReleaseFn = @convention(c) (Int64) -> Int32
typealias XPCStringCreateFn = @convention(c) (UnsafePointer<CChar>) -> xpc_object_t
typealias XPCReleaseFn = @convention(c) (xpc_object_t) -> Void

final class NativeWorseQuery {
    static let shared = NativeWorseQuery()
    private var activeHandles: [Int64] = []

    private let RTLD_DEFAULT_HANDLE = UnsafeMutableRawPointer(bitPattern: -2)

    private var mcmHandle: UnsafeMutableRawPointer?
    private var queryCreate: ContainerQueryCreateFn?
    private var querySetClass: ContainerQuerySetClassFn?
    private var querySetGroupIds: ContainerQuerySetGroupIdentifiersFn?
    private var querySetFlags: ContainerQuerySetFlagsFn?
    private var querySetPart: ContainerQuerySetPartFn?
    private var queryGetSingleResult: ContainerQueryGetSingleResultFn?
    private var queryFree: ContainerQueryFreeFn?
    private var copySandboxToken: ContainerCopySandboxTokenFn?
    private var sandboxConsume: SandboxExtensionConsumeFn?
    private var sandboxRelease: SandboxExtensionReleaseFn?
    private var xpcStringCreate: XPCStringCreateFn?
    private var xpcRelease: XPCReleaseFn?

    init() {
        loadMCM()
    }

    private func loadMCM() {
        mcmHandle = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL)
        guard let handle = mcmHandle else { return }

        func sym<T>(_ name: String) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        queryCreate = sym("container_query_create")
        querySetClass = sym("container_query_set_class")
        querySetGroupIds = sym("container_query_set_group_identifiers")
        querySetFlags = sym("container_query_operation_set_flags")
        querySetPart = sym("container_query_operation_set_part")
        queryGetSingleResult = sym("container_query_get_single_result")
        queryFree = sym("container_query_free")
        copySandboxToken = sym("container_copy_sandbox_token")

        sandboxConsume = unsafeBitCast(dlsym(RTLD_DEFAULT_HANDLE, "sandbox_extension_consume"), to: SandboxExtensionConsumeFn.self)
        sandboxRelease = unsafeBitCast(dlsym(RTLD_DEFAULT_HANDLE, "sandbox_extension_release"), to: SandboxExtensionReleaseFn.self)
        xpcStringCreate = unsafeBitCast(dlsym(RTLD_DEFAULT_HANDLE, "xpc_string_create"), to: XPCStringCreateFn.self)
        xpcRelease = unsafeBitCast(dlsym(RTLD_DEFAULT_HANDLE, "xpc_release"), to: XPCReleaseFn.self)
    }

    private func getPathFromInode(_ inode: UInt64, volumePath: String = "/private/var") -> String? {
        var sfs = statfs()
        if statfs(volumePath, &sfs) != 0 { return nil }
        var fsid = sfs.f_fsid

        var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = pathBuffer.withUnsafeMutableBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return fsgetpath(base, Int(PATH_MAX), &fsid, inode)
        }
        guard result > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    private func scanInodes(in directory: String) -> [UInt64] {
        var inodes: [UInt64] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return [] }
        for case let path as String in enumerator {
            let fullPath = (directory as NSString).appendingPathComponent(path)
            var st = stat()
            if stat(fullPath, &st) == 0 { inodes.append(st.st_ino) }
        }
        return inodes
    }

    func grantAccess(targetPath: String, appGroupID: String) -> (Int64, String) {
        guard let create = queryCreate, let setClass = querySetClass, let setGroupIds = querySetGroupIds,
              let setFlags = querySetFlags, let setPart = querySetPart, let getResult = queryGetSingleResult,
              let qFree = queryFree, let copyToken = copySandboxToken, let consume = sandboxConsume,
              let strCreate = xpcStringCreate, let xpcRel = xpcRelease else {
            return (-1, L("log_mcm_load_failed"))
        }

        let fm = FileManager.default
        guard let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return (-1, L("log_app_group_url_failed") + " \(appGroupID)")
        }

        let cachesPath = groupURL.appendingPathComponent("Library/Caches").path
        let libPath = groupURL.appendingPathComponent("Library").path
        let backupCaches = groupURL.appendingPathComponent("Library/Caches.bqtool").path

        try? fm.createDirectory(atPath: libPath, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: backupCaches)
        if fm.fileExists(atPath: cachesPath) { try? fm.moveItem(atPath: cachesPath, toPath: backupCaches) }

        do {
            try fm.createSymbolicLink(atPath: cachesPath, withDestinationPath: targetPath)
        } catch {
            return (-1, L("log_symlink_failed") + " \(error.localizedDescription)")
        }

        guard let query = create() else {
            cleanup(cachesPath, backupCaches)
            return (-2, L("log_query_failed"))
        }

        setClass(query, 7)
        let ident = appGroupID.withCString { strCreate($0) }
        setGroupIds(query, ident)
        setPart(query, 3)

        var result: OpaquePointer? = nil
        setFlags(query, 0x8100000000)
        result = getResult(query)

        if result == nil {
            setFlags(query, 0x8000000000)
            result = getResult(query)
        }

        guard result != nil else {
            qFree(query)
            xpcRel(ident)
            cleanup(cachesPath, backupCaches)
            return (-3, L("log_xpc_error"))
        }

        guard let tokenPtr = copyToken(result) else {
            qFree(query)
            xpcRel(ident)
            cleanup(cachesPath, backupCaches)
            return (-4, L("log_kernel_token_failed"))
        }

        let consumed = consume(tokenPtr)
        free(tokenPtr)
        qFree(query)
        xpcRel(ident)
        cleanup(cachesPath, backupCaches)

        if consumed < 0 { return (-5, L("log_consume_token_failed") + " \(errno))") }

        activeHandles.append(consumed)
        return (consumed, L("log_mcm_success"))
    }

    func grantViaFsgetpath(targetFile: String) -> (Int64, String) {
        let targetDir = (targetFile as NSString).deletingLastPathComponent
        let inodes = scanInodes(in: targetDir)

        let wq = WorseQuery()
        for inode in inodes {
            guard let realPath = getPathFromInode(inode) else { continue }
            let (granted, handle, _) = wq.grantAccess(atPath: realPath)
            if granted, handle > 0 {
                let res = consumeToken(handle: handle)
                if res.0 > 0 { return (res.0, L("log_fsgetpath_success") + " \(realPath)") }
            }
        }
        return (-1, L("log_fsgetpath_failed"))
    }

    private func consumeToken(handle: Int64) -> (Int64, String) {
        guard let tokenPtr = UnsafePointer<CChar>(bitPattern: UInt(handle)) else { return (-1, L("log_pointer_error")) }
        let consumed = sandboxConsume?(tokenPtr) ?? -1
        if consumed < 0 { return (-1, L("log_consume_errno") + " \(errno)") }
        activeHandles.append(consumed)
        return (consumed, "OK")
    }

    private func cleanup(_ cachesPath: String, _ backupCaches: String) {
        let fm = FileManager.default
        try? fm.removeItem(atPath: cachesPath)
        if fm.fileExists(atPath: backupCaches) { try? fm.moveItem(atPath: backupCaches, toPath: cachesPath) }
    }

    func releaseAll() {
        if let release = sandboxRelease {
            for h in activeHandles { _ = release(h) }
        }
        activeHandles.removeAll()
    }
}

// MARK: - Unified Document Picker
struct DocumentPickerView: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType] = [.data, .item]
    let onPick: (URL) -> Void
    var onCancel: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        init(_ parent: DocumentPickerView) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
            parent.onPick(url)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel?()
            parent.dismiss()
        }
    }
}

// MARK: - Main Settings View
struct SettingsView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @State private var showPairingPicker = false
    @State private var showOnDevicePairing = false
    @State private var vpnActive: Bool = false
    @State private var monitor: NWPathMonitor?
    @AppStorage("isAirLiftMode") private var isAirLiftMode: Bool = false

    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @State private var isTestingWrite = false
    @State private var writeTestLog = ""
    @State private var writeTestSuccess: Bool? = nil

    private var tintOptions: [(name: String, hex: String)] {
        [
            (L("color_orange"), "#ef9f76"),
            (L("color_pink"),   "#f4b8e4"),
            (L("color_mauve"),  "#ca9ee6"),
            (L("color_red"),    "#e78284"),
            (L("color_green"),  "#a6d189"),
            (L("color_blue"),   "#8caaee"),
        ]
    }

    var body: some View {
        Form {
            runTestSection
            respringSection
            connectionStatusSection
            pairingFileSection
            languageSection
            accentColorSection
            appInfoSection
        }
        .navigationTitle(L("nav_settings"))
        .onAppear { startMonitoringVPN() }
        .onDisappear { monitor?.cancel() }
        .sheet(isPresented: $showPairingPicker) {
            DocumentPickerView(allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing") ?? .data]) { url in handlePairingImport(url) }
        }
        .sheet(isPresented: $showOnDevicePairing) {
            NavigationStack {
                OnDevicePairingView().toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("alert_close")) { showOnDevicePairing = false }
                    }
                }
            }
        }
        .alert(L("pairing_error_title"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var runTestSection: some View {
        Section(header: Text(L("settings_run_test_header"))) {
            Button(action: runMobileGestaltTest) {
                HStack {
                    Label(L("settings_run_test_btn"), systemImage: "doc.badge.plus")
                        .foregroundStyle(.primary)
                    Spacer()
                    if isTestingWrite { ProgressView() }
                }
            }
            .disabled(isTestingWrite)

            if !writeTestLog.isEmpty {
                ScrollView {
                    Text(writeTestLog)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(writeTestSuccess == true ? .green : (writeTestSuccess == false ? .red : .primary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 250)
            }
        }
    }

    private var respringSection: some View {
        Section(header: Text(L("settings_respring_header"))) {
            Button {
                do {
                    try RespringHelper.respring()
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.blue)
                    Text(L("settings_respring_btn"))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var connectionStatusSection: some View {
        Section(header: Text(L("connection_status"))) {
            statusRow(title: L("pairing_file"), subtitle: pairingFile != nil ? L("status_ready") : L("status_not_ready"), ok: pairingFile != nil)
            statusRow(title: L("settings_tunnel_status"), subtitle: vpnActive ? L("status_ready") : L("status_not_ready"), ok: vpnActive)
            if isAirLiftMode { statusRow(title: L("airlift_mode"), subtitle: L("enabled"), ok: true) }
        }
    }

    private var pairingFileSection: some View {
        Section(header: Text(L("pairing_file"))) {
            if pairingFile != nil {
                Button(role: .destructive) {
                    pairingFile = nil
                    try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                } label: { Label(L("button_reset_pairing"), systemImage: "trash") }
            } else {
                Button { showPairingPicker = true } label: { Label(L("import_pairing"), systemImage: "doc.badge.plus") }

                if #available(iOS 27.0, *) {
                    Button { showOnDevicePairing = true } label: {
                        Label(L("pair_on_device"), systemImage: "iphone.radiowaves.left.and.right")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var languageSection: some View {
        Section(header: Text(L("settings_language"))) {
            NavigationLink(destination: LanguageSettingsView()) {
                Label(L("settings_language"), systemImage: "globe")
            }
        }
    }

    private var accentColorSection: some View {
        Section(header: Text(L("settings_accent_color"))) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(tintOptions, id: \.hex) { option in
                        colorOptionView(option: option)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var appInfoSection: some View {
        Section(header: Text(L("settings_app_info"))) {
            HStack { Label("EnsWilde", systemImage: "sparkles"); Spacer(); Text("v3.1.3 Beta 3").font(.footnote).foregroundStyle(.secondary) }
            HStack { Label(L("app_ios"), systemImage: "iphone"); Spacer(); Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary) }
            HStack { Label(L("app_device"), systemImage: "apps.iphone"); Spacer(); Text(settingsDeviceModelName()).font(.footnote).foregroundStyle(.secondary) }
            Text(L("app_info_footer")).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private func runMobileGestaltTest() {
        isTestingWrite = true
        writeTestSuccess = nil
        writeTestLog = "[*] Starting permission test (Native MCM & fsgetpath)...\n"

        let work = DispatchWorkItem {
            let testFile = MobileGestaltApplyTask.onDeviceMGPath
            let bridge = NativeWorseQuery.shared
            let runtimeGroups = self.getAllRuntimeAppGroups()
            let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"

            DispatchQueue.main.async { self.writeTestLog += "📱 Runtime Groups: \(runtimeGroups.joined(separator: ", "))\n" }

            var finalHandle: Int64 = -1
            var lastError = ""

            for group in runtimeGroups {
                if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) == nil { continue }

                DispatchQueue.main.async { self.writeTestLog += "[*] Try requesting permission via App Group: \(group)...\n" }

                let (handle, error) = bridge.grantAccess(targetPath: targetDir, appGroupID: group)

                if handle > 0 {
                    finalHandle = handle
                    DispatchQueue.main.async { self.writeTestLog += "✅ Success: \(error)\n" }
                    break
                } else {
                    lastError = error
                    DispatchQueue.main.async { self.writeTestLog += " ⚠️ Failure: \(error)\n" }
                }
            }

            if finalHandle <= 0 {
                DispatchQueue.main.async { self.writeTestLog += "[*] Fallback: Try fsgetpath inode traversal...\n" }
                let (handle, error) = bridge.grantViaFsgetpath(targetFile: testFile)
                if handle > 0 {
                    finalHandle = handle
                    DispatchQueue.main.async { self.writeTestLog += "✅ Success: \(error)\n" }
                } else {
                    lastError = error
                    DispatchQueue.main.async { self.writeTestLog += " ⚠️ Failure: \(error)\n" }
                }
            }

            guard finalHandle > 0 else {
                DispatchQueue.main.async {
                    self.writeTestLog += "\n❌ ALL METHODS HAVE FAILED!\n"
                    self.writeTestLog += "👉 The Final Error: \(lastError)\n"
                    self.writeTestLog += "👉 DIAGNOSE:\n"
                    self.writeTestLog += "   - Fake certificate signing or an XPC-related flaw in the AirliftFFI framework.\n"
                    self.writeTestSuccess = false; self.isTestingWrite = false
                }
                return
            }

            DispatchQueue.main.async { self.writeTestLog += "✅ Token acquired! Testing file writing...\n" }
            do {
                let originalData = try Data(contentsOf: URL(fileURLWithPath: testFile))
                var st = stat()
                if stat(testFile, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
                    _ = chflags(testFile, st.st_flags & ~UInt32(UF_IMMUTABLE))
                }

                let fd = open(testFile, O_RDWR | O_CLOEXEC)
                guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                defer { close(fd) }

                let bytesWritten = originalData.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
                guard bytesWritten == originalData.count else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "pwrite errno: \(errno)"])
                }

                _ = fcntl(fd, F_FULLFSYNC)
                bridge.releaseAll()
                DispatchQueue.main.async {
                    self.writeTestLog += "✅ FILE WRITE SUCCESSFULLY!\n"
                    self.writeTestSuccess = true; self.isTestingWrite = false
                }
            } catch {
                bridge.releaseAll()
                DispatchQueue.main.async {
                    self.writeTestLog += "❌ WRITE ERROR: \(error.localizedDescription)\n"
                    self.writeTestSuccess = false; self.isTestingWrite = false
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func getAllRuntimeAppGroups() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [] }
        guard let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) else { return [] }
        return (entitlements as? [String]) ?? []
    }

    @ViewBuilder private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack { Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red); Spacer(); Text(subtitle).font(.caption).foregroundStyle(ok ? .green : .red) }
    }

    @ViewBuilder private func colorOptionView(option: (name: String, hex: String)) -> some View {
        let color = Color(hex: option.hex)
        let isSelected = userTintColorHex.lowercased() == option.hex.lowercased()
        VStack(spacing: 6) {
            Circle().fill(color).frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay(Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.white).opacity(isSelected ? 1 : 0))
            Text(option.name).font(.caption).foregroundColor(isSelected ? .primary : .secondary)
        }
        .onTapGesture {
            userTintColorHex = option.hex
            let uiColor = UIColor(Color(hex: option.hex))
            UITabBar.appearance().tintColor = uiColor
            UINavigationBar.appearance().tintColor = uiColor
        }
    }

    private func handlePairingImport(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try RPPairingParser.parse(url: url)
            let data = try Data(contentsOf: url)
            let destURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
            try data.write(to: destURL)
            pairingFile = url.lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func startMonitoringVPN() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.vpnActive = path.availableInterfaces.contains { $0.type == .other || $0.name.hasPrefix("utun") || $0.name.hasPrefix("ipsec") }
            }
        }
        monitor?.start(queue: DispatchQueue(label: "VPNMonitor"))
    }

    private func settingsDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return "\(UIDevice.current.model) (\(identifier))"
    }
}

// MARK: - About View
struct AboutView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"

    var body: some View {
        Form {
            aboutHeroSection
            aboutSocialSection
            aboutThanksSection
            aboutTranslatorsSection
        }
        .navigationTitle(L("nav_about"))
        .onAppear {
            if localizationManager.availableLanguages.isEmpty {
                Task { await localizationManager.fetchAvailableLanguages() }
            }
        }
    }

    private var aboutHeroSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(.pink)
                Text(L("about_desc")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: "https://dangdi.dev/donate") { UIApplication.shared.open(url) }
                } label: {
                    Text(L("button_donate"))
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(hex: userTintColorHex))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutSocialSection: some View {
        Section {
            Button(action: { if let url = URL(string: "https://t.me/yangjiiidibo") { UIApplication.shared.open(url) } }) {
                Label(L("about_group_yang"), systemImage: "safari")
            }
            Button(action: { if let url = URL(string: "https://t.me/lsnguyengr") { UIApplication.shared.open(url) } }) {
                Label(L("about_group_ls"), systemImage: "safari")
            }
            Button(action: { if let url = URL(string: "https://t.me/lsnguyyniu") { UIApplication.shared.open(url) } }) {
                Label(L("about_contact"), systemImage: "paperplane.fill")
            }
        }
    }

    private var aboutThanksSection: some View {
        Section(header: Text(L("settings_thanks_to"))) {
            creditRow(name: "@YangJiii", desc: L("credit_yang_support"))
            creditRow(name: "@YangJiii", desc: L("credit_yang_original"))
            creditRow(name: "@LSNguyen", desc: L("credit_ls_new"))
            creditRow(name: "@forcequitOS", desc: L("credit_forcequit_badquery"))
            creditRow(name: "@0xjohnnydev", desc: L("credit_johnny_airlift"))
            creditRow(name: "@mak5er", desc: L("credit_mak5er_aod"))
            creditRow(name: "@jailbreakdotparty", desc: L("credit_jailbreak_config"))
            creditRow(name: "@LikePass888", desc: L("credit_likepass_sound"))
            creditRow(name: "@Little_34306", desc: L("credit_little_34306_concept"))
            creditRow(name: "@YiHoooong", desc: L("credit_yihooong_silent"))
            creditRow(name: "@Kianuni", desc: L("credit_kianuni_erosion"))
            creditRow(name: "Cộng đồng LSNguyen & YangJiii và những người bạn chat ⚡️", desc: L("credit_community"))
        }
    }

    private var aboutTranslatorsSection: some View {
        Section(header: Text(L("settings_translators"))) {
            ForEach(translatorLanguages) { langInfo in
                creditRow(name: langInfo.translator ?? "", desc: String(format: L("translation_by"), langInfo.nativeName, langInfo.name))
            }
        }
    }

    private var translatorLanguages: [LanguageInfo] {
        localizationManager.availableLanguages.filter { (info: LanguageInfo) -> Bool in
            guard let tr = info.translator else { return false }
            return !tr.isEmpty
        }
    }

    @ViewBuilder
    private func creditRow(name: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).fontWeight(.semibold)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
