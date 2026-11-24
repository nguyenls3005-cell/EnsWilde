import Foundation
import SwiftUI
import Combine

// MARK: - Limits & Errors

enum PatchPackageLimits {
    static let maximumAuthorBytes = 128
}

enum PatchPackageError: Error {
    case invalidBundleIdentifier
    case invalidRelativePath
    case invalidProject
    case targetAppUnavailable(String)
    case privateOperationRestricted

    var localizationKey: String {
        switch self {
        case .invalidBundleIdentifier:
            return "patch.error.invalid_bundle"
        case .invalidRelativePath:
            return "patch.error.invalid_path"
        case .invalidProject:
            return "patch.error.invalid_project"
        case .targetAppUnavailable:
            return "patch.error.target_unavailable"
        case .privateOperationRestricted:
            return "patch.error.private_operation"
        }
    }

    var localizationArgument: String? {
        switch self {
        case .targetAppUnavailable(let bundleID):
            return bundleID
        default:
            return nil
        }
    }
}

// MARK: - Path & Bundle Validator

enum PatchPathValidator {
    static func canonicalBundleIdentifier(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains(".."),
              trimmed.contains(".") else {
            throw PatchPackageError.invalidBundleIdentifier
        }
        return trimmed
    }

    static func canonicalRelativePath(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty,
              !components.contains(".."),
              !components.contains(".") else {
            throw PatchPackageError.invalidRelativePath
        }
        return components.joined(separator: "/")
    }

    static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

// MARK: - Models

struct PatchDirectory: Identifiable, Codable, Hashable {
    var id: String { "\(bundleID)::\(relativePath)" }
    var bundleID: String
    var relativePath: String
}

struct PatchRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var bundleID: String
    var relativePath: String
    var replacementFilename: String
    var replacementData: Data

    var hasReplacement: Bool {
        !replacementFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct PatchProject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var author: String = ""
    var isPrivate: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var bundleIdentifiers: [String] = []
    var directories: [PatchDirectory] = []
    var rules: [PatchRule] = []

    var allBundleIdentifiers: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for id in bundleIdentifiers where seen.insert(id).inserted {
            ordered.append(id)
        }
        for rule in rules where seen.insert(rule.bundleID).inserted {
            ordered.append(rule.bundleID)
        }
        for dir in directories where seen.insert(dir.bundleID).inserted {
            ordered.append(dir.bundleID)
        }
        return ordered
    }
}

struct PatchProjectDraft: Hashable {
    var name: String
    var bundleIdentifiers: [String]
    var directories: [PatchDirectory] = []
    var rules: [PatchRule] = []
}

struct PatchDraftCandidate: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var relativePath: String
    var byteCount: Int64
}

struct PatchOrigin: Codable, Hashable {
    var repositoryName: String
    var sourceURL: URL?
}

struct PatchProjectSummary: Codable, Hashable {
    var schemaVersion: Int = 2
    var isPasswordProtected: Bool = false
}

struct PatchLibraryItem: Identifiable, Hashable {
    var id: UUID { project?.id ?? UUID() }
    var project: PatchProject?
    var summary: PatchProjectSummary = PatchProjectSummary()
    var origin: PatchOrigin? = nil
    var canInspectContents: Bool = true
    var isAuthorCopy: Bool = true
    var workspaceURL: URL? = nil
    var packageURL: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("patch.3105")
}

struct PatchPasswordRequest: Identifiable {
    let id = UUID()
    let itemID: UUID
    let origin: PatchOrigin?
}

struct PatchStoreAlert: Identifiable {
    let id = UUID()
    let titleKey: String
    let messageKey: String
    let messageArgument: String?

    init(titleKey: String, messageKey: String, messageArgument: String? = nil) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.messageArgument = messageArgument
    }

    func message(language: AppLanguage) -> String {
        if let messageArgument {
            return language.text(messageKey, messageArgument)
        }
        return language.text(messageKey)
    }
}

// MARK: - Codec & Draft Service

enum PatchPackageCodec {
    static func validate(_ project: PatchProject) throws {
        let trimmedName = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.utf8.count <= 120 else {
            throw PatchPackageError.invalidProject
        }
        guard project.author.utf8.count <= PatchPackageLimits.maximumAuthorBytes else {
            throw PatchPackageError.invalidProject
        }
        for rule in project.rules {
            _ = try PatchPathValidator.canonicalBundleIdentifier(rule.bundleID)
            _ = try PatchPathValidator.canonicalRelativePath(rule.relativePath)
            guard rule.hasReplacement else {
                throw PatchPackageError.invalidProject
            }
        }
    }
}

enum PatchDraftService {
    static func makeDraft(
        bundleID: String,
        containerRoot: URL,
        itemURL: URL,
        suggestedName: String
    ) throws -> PatchProjectDraft {
        let canonicalBundle = try PatchPathValidator.canonicalBundleIdentifier(bundleID)
        let canonicalRoot = PatchPathValidator.canonicalFileURL(containerRoot)
        let canonicalItem = PatchPathValidator.canonicalFileURL(itemURL)
        let rootPath = canonicalRoot.path
        let itemPath = canonicalItem.path
        let relRaw = itemPath.hasPrefix(rootPath)
            ? String(itemPath.dropFirst(rootPath.count))
            : canonicalItem.lastPathComponent
        let canonicalRel = try PatchPathValidator.canonicalRelativePath(relRaw)

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDir)

        if isDir.boolValue {
            let dir = PatchDirectory(bundleID: canonicalBundle, relativePath: canonicalRel)
            return PatchProjectDraft(
                name: suggestedName,
                bundleIdentifiers: [canonicalBundle],
                directories: [dir],
                rules: []
            )
        } else {
            let data = (try? Data(contentsOf: canonicalItem, options: .mappedIfSafe)) ?? Data()
            let rule = PatchRule(
                bundleID: canonicalBundle,
                relativePath: canonicalRel,
                replacementFilename: canonicalItem.lastPathComponent,
                replacementData: data
            )
            return PatchProjectDraft(
                name: suggestedName,
                bundleIdentifiers: [canonicalBundle],
                directories: [],
                rules: [rule]
            )
        }
    }

    static func candidates(
        in folder: URL,
        containerRoot: URL
    ) throws -> [PatchDraftCandidate] {
        let canonicalRoot = PatchPathValidator.canonicalFileURL(containerRoot)
        let canonicalFolder = PatchPathValidator.canonicalFileURL(folder)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: canonicalFolder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [PatchDraftCandidate] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let relRaw = fileURL.path.hasPrefix(canonicalRoot.path)
                ? String(fileURL.path.dropFirst(canonicalRoot.path.count))
                : fileURL.lastPathComponent
            let canonicalRel = try PatchPathValidator.canonicalRelativePath(relRaw)
            results.append(PatchDraftCandidate(
                url: fileURL,
                relativePath: canonicalRel,
                byteCount: Int64(values.fileSize ?? 0)
            ))
        }
        return results
    }
}

// MARK: - Library, Transaction & Store

struct PatchTransactionReceipt: Codable, Hashable {
    let id: UUID
    let projectID: UUID
    let bundleIdentifiers: [String]
    let appliedAt: Date
}

struct PatchChangedTarget: Hashable {
    let displayPath: String
}

struct PatchRestoreInspection {
    let changedTargets: [PatchChangedTarget]
}

enum PatchProjectLibrary {
    static func backupRootURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("PatchBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func synchronizeWorkspace(item: PatchLibraryItem) throws -> PatchProject {
        guard let project = item.project else {
            throw PatchPackageError.invalidProject
        }
        try PatchPackageCodec.validate(project)
        return project
    }
}

enum PatchTransaction {
    private static var receiptsByProject: [UUID: PatchTransactionReceipt] = [:]

    static func apply(
        project: PatchProject,
        backupRoot: URL,
        containerResolver: (String) throws -> URL
    ) throws -> PatchTransactionReceipt {
        try PatchPackageCodec.validate(project)
        let bundleIDs = project.allBundleIdentifiers
        for bundleID in bundleIDs {
            _ = try containerResolver(bundleID)
        }
        let receipt = PatchTransactionReceipt(
            id: UUID(),
            projectID: project.id,
            bundleIdentifiers: bundleIDs,
            appliedAt: Date()
        )
        receiptsByProject[project.id] = receipt
        _ = backupRoot
        return receipt
    }

    static func requiredBundleIdentifiers(for receipt: PatchTransactionReceipt) throws -> [String] {
        receipt.bundleIdentifiers
    }

    static func inspectRestore(
        receipt: PatchTransactionReceipt,
        containerResolver: (String) throws -> URL
    ) throws -> PatchRestoreInspection {
        for bundleID in receipt.bundleIdentifiers {
            _ = try containerResolver(bundleID)
        }
        return PatchRestoreInspection(changedTargets: [])
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false,
        containerResolver: (String) throws -> URL
    ) throws {
        _ = allowChangedTargets
        for bundleID in receipt.bundleIdentifiers {
            _ = try containerResolver(bundleID)
        }
        receiptsByProject.removeValue(forKey: receipt.projectID)
    }

    static func resetToAppliedState(
        receipt: PatchTransactionReceipt,
        fallbackProject: PatchProject,
        containerResolver: (String) throws -> URL
    ) throws {
        _ = fallbackProject
        for bundleID in receipt.bundleIdentifiers {
            _ = try containerResolver(bundleID)
        }
    }

    static func latestReceipt(projectID: UUID, backupRoot: URL) -> PatchTransactionReceipt? {
        _ = backupRoot
        return receiptsByProject[projectID]
    }
}

struct PatchDraftRequest: Identifiable {
    let id = UUID()
    let draft: PatchProjectDraft
}

struct PatchExternalImportRequest: Identifiable {
    let id = UUID()
    let source: URL
}

@MainActor
final class PatchDraftCoordinator: ObservableObject {
    @Published var request: PatchDraftRequest?
    @Published var importRequest: PatchExternalImportRequest?

    func present(_ draft: PatchProjectDraft) {
        request = PatchDraftRequest(draft: draft)
    }

    func clear() {
        request = nil
    }

    func enqueueImport(from source: URL) {
        importRequest = PatchExternalImportRequest(source: source)
    }

    func clearImport() {
        importRequest = nil
    }
}

@MainActor
final class PatchProjectStore: ObservableObject {
    @Published var items: [PatchLibraryItem] = []
    @Published var isBusy = false
    @Published var unlockErrorKey: String?

    func reload() {
        objectWillChange.send()
    }

    func create(project: PatchProject, password: String?) {
        _ = password
        let newItem = PatchLibraryItem(
            project: project,
            summary: PatchProjectSummary(
                schemaVersion: 2,
                isPasswordProtected: password != nil
            ),
            canInspectContents: true,
            isAuthorCopy: true
        )
        items.append(newItem)
    }

    func update(project: PatchProject) {
        if let idx = items.firstIndex(where: { $0.id == project.id }) {
            items[idx].project = project
        }
    }

    func importPackage(at url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let project = PatchProject(name: name.isEmpty ? "Imported Patch" : name)
        items.append(PatchLibraryItem(project: project, packageURL: url))
    }

    func importPackage(from url: URL) {
        importPackage(at: url)
    }

    func unlock(password: String) {
        _ = password
        unlockErrorKey = nil
    }

    func clearUnlockError() {
        unlockErrorKey = nil
    }
}
