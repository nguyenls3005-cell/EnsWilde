//
//  CustomPatchView.swift
//  EnsWilde
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CryptoKit
import Foundation
import Darwin

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
    var isLegacyV1: Bool = false
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
            syncToToolStoreAndDefaults()
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
        syncToToolStoreAndDefaults()
    }

    func syncToToolStoreAndDefaults() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        UserDefaults.standard.set(config.enabled, forKey: "zPatchCustomEnabled")
        UserDefaults.standard.synchronize()
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

        syncToToolStoreAndDefaults()
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
        let cleanRel = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFileName = sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (cleanRel.isEmpty ? URL(filePath: sourceStoredPath).lastPathComponent : URL(filePath: cleanRel).lastPathComponent)
            : sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines)

        let existingRule = existingID.flatMap { id in
            config.savedRules.first(where: { $0.id == id }) ?? (config.activeRule?.id == id ? config.activeRule : nil)
        }

        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pwdHash: String?
        let hasPassword: Bool
        if !trimmedPassword.isEmpty {
            hasPassword = true
            pwdHash = Self.sha256Hex(trimmedPassword)
        } else if let existingHash = existingRule?.passwordHashSHA256, !existingHash.isEmpty {
            hasPassword = true
            pwdHash = existingHash
        } else {
            hasPassword = false
            pwdHash = nil
        }

        var payloadB64 = data.base64EncodedString()
        var encPayloadB64: String? = nil
        var nonceB64: String? = nil

        if hasPassword, !trimmedPassword.isEmpty {
            let key = SymmetricKey(data: SHA256.hash(data: Data(trimmedPassword.utf8)))
            let sealed = try AES.GCM.seal(data, using: key)
            encPayloadB64 = sealed.combined?.base64EncodedString()
            nonceB64 = Data(sealed.nonce).base64EncodedString()
            payloadB64 = ""
        }

        let pkg = Patch3105Package(
            projectName: cleanName,
            bundleID: cleanBundleID,
            relativePath: cleanRel,
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
            isLegacyV1: false
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
                    isLegacyV1: false
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
                    isLegacyV1: false
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
            bundleID: "",
            relativePath: "",
            sourceFileName: url.lastPathComponent,
            sourceStoredPath: outURL.path,
            packageStoredPath: storedPkgURL.path,
            fileSizeBytes: Int64(rawData.count),
            passwordHashSHA256: nil,
            isLegacyV1: false
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
        syncToToolStoreAndDefaults()
    }

    func saveChanges(showApplyTab: inout Bool) {
        if config.activeRule == nil, let first = config.savedRules.first {
            config.activeRule = first
        }
        if let active = config.activeRule {
            config.savedRules.removeAll { $0.id == active.id }
            config.savedRules.insert(active, at: 0)
        }
        syncToToolStoreAndDefaults()
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
        syncToToolStoreAndDefaults()
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
        UserDefaults.standard.set(false, forKey: "zPatchCustomEnabled")
        UserDefaults.standard.synchronize()
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
    static func activeRulesToApply() -> [CustomPatchRule] {
        let cfg = CustomPatchStore.shared.config
        let flagEnabled = cfg.enabled || UserDefaults.standard.bool(forKey: "zPatchCustomEnabled")
        guard flagEnabled else { return [] }
        if let active = cfg.activeRule {
            return [active]
        }
        if let first = cfg.savedRules.first {
            return [first]
        }
        return []
    }

    static func enabledPatchLabels() -> [String] {
        let rules = activeRulesToApply()
        return rules.map { rule in
            let name = rule.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? (rule.sourceFileName.isEmpty ? "Custom Patch" : rule.sourceFileName) : name
            return "Custom Patch: \(label)"
        }
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

    static func applyRule(_ rule: CustomPatchRule, log: (String) -> Void = { _ in }) async throws {
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

    static func applyIfEnabled(log: (String) -> Void = { _ in }) async throws {
        let cfg = CustomPatchStore.shared.config
        let flagEnabled = cfg.enabled || UserDefaults.standard.bool(forKey: "zPatchCustomEnabled")
        guard flagEnabled else {
            log("[CustomPatch] Đang tắt, bỏ qua.")
            return
        }

        guard let rule = cfg.activeRule ?? cfg.savedRules.first else {
            throw CustomPatchError.missingSourceFile
        }

        try await applyRule(rule, log: log)
    }

    static func apply(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        try await applyIfEnabled(log: onLogUpdate)
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
    @State private var addRulePath: String
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
        _addRulePath = State(initialValue: "")
        _password = State(initialValue: "")
        _draftRule = State(initialValue: base)
    }

    private var resolvedDestinationText: String {
        let baseRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let extraRule = addRulePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if extraRule.isEmpty {
            return baseRel.isEmpty ? draftRule.sourceFileName : baseRel
        }
        if baseRel.isEmpty {
            return extraRule
        }
        return "\(baseRel)/\(extraRule)"
    }

    private var resolvedReplacementFileText: String {
        let extraRule = addRulePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !extraRule.isEmpty {
            let last = URL(filePath: extraRule).lastPathComponent
            if !last.isEmpty { return last }
        }
        if !draftRule.sourceFileName.isEmpty {
            return draftRule.sourceFileName
        }
        let baseRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !baseRel.isEmpty {
            return URL(filePath: baseRel).lastPathComponent
        }
        return "Choose file"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Patch Name")) {
                    TextField("Patch Name", text: $projectName)
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
                                .foregroundStyle(Color(red: 0.90, green: 0.42, blue: 0.05))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(resolvedReplacementFileText)
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

                Section(header: Text("Add Rules")) {
                    TextField("Thêm đuôi cần patch (vd: Library/Preferences/file.plist)", text: $addRulePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(header: Text("Password (Optional)")) {
                    SecureField("Password", text: $password)
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
                            let finalDest = resolvedDestinationText
                            let finalSourceName = resolvedReplacementFileText == "Choose file" ? draftRule.sourceFileName : resolvedReplacementFileText
                            _ = try patchStore.createAndSave3105(
                                projectName: projectName,
                                bundleID: bundleID,
                                relativePath: finalDest,
                                sourceStoredPath: draftRule.sourceStoredPath,
                                sourceFileName: finalSourceName,
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
    @State private var exportItem: ExportFileItem?
    @State private var alertMessage: String?
    @State private var showAlert = false

    private let deepOrange = Color(red: 0.90, green: 0.42, blue: 0.05)

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

    private var destinationDisplay: String {
        let rel = rule.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rel.isEmpty { return rel }
        return rule.sourceFileName
    }

    private var replacementDisplay: String {
        let src = rule.sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !src.isEmpty { return src }
        let rel = rule.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rel.isEmpty {
            return URL(filePath: rel).lastPathComponent
        }
        return ""
    }

    var body: some View {
        List {
            Section(header: Text("Rules")) {
                Button {
                    patchStore.selectRule(rule)
                    showEditRuleSheet = true
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.bundleID)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.black)

                            Text(destinationDisplay)
                                .font(.subheadline)
                                .foregroundStyle(.gray)

                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(deepOrange)
                                Text(replacementDisplay)
                                    .font(.subheadline)
                                    .foregroundStyle(deepOrange)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section(header: Text("Password")) {
                Button {
                    // Bản gốc: ổ khoá màu cam đậm, chữ màu đen, ấn không hiện gì
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(deepOrange)
                        Text("Set permanently")
                            .foregroundStyle(.black)
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
                            .foregroundStyle(deepOrange)
                        Text("Export .3105")
                            .foregroundStyle(deepOrange)
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
                .foregroundStyle(deepOrange)
            }
        }
        .sheet(isPresented: $showEditRuleSheet) {
            EditPatchRuleSheetView(patchStore: patchStore, initialRule: rule)
        }
        .sheet(item: $exportItem) { item in
            ShareSheetView(activityItems: [item.url])
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
                    .onChange(of: patchStore.config.enabled) { newValue in
                        toolStore.zPatchCustomEnabled = newValue
                        var dummy = showApplyTab
                        patchStore.saveChanges(showApplyTab: &dummy)
                    }
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
                        toolStore.zPatchCustomEnabled = patchStore.config.enabled
                    }
                }
            }

            Section(header: Text(L("section_save_reset"))) {
                Button {
                    if patchStore.config.activeRule == nil, let first = patchStore.config.savedRules.first {
                        patchStore.selectRule(first)
                    }
                    if !patchStore.config.savedRules.isEmpty {
                        patchStore.config.enabled = true
                    }
                    toolStore.zPatchCustomEnabled = patchStore.config.enabled
                    patchStore.saveChanges(showApplyTab: &showApplyTab)
                    activeAlert = .info("Đã lưu thay đổi và đồng bộ trạng thái Apply.")
                } label: {
                    Label("Save Changes", systemImage: "square.and.arrow.down")
                }

                Button(role: .destructive) {
                    patchStore.restoreDefaults()
                    toolStore.zPatchCustomEnabled = false
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
                toolStore.zPatchCustomEnabled = patchStore.config.enabled
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
