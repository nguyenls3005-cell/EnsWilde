import Foundation
import CryptoKit

final class MobileGestaltBackupManager {
    static let shared = MobileGestaltBackupManager()

    struct BackupInfo {
        let createdAt: Date
        let byteCount: Int
        let sha256: String
    }

    enum BackupError: LocalizedError {
        case writeFailed, readFailed, noBackup, invalidData
        var errorDescription: String? {
            switch self {
            case .writeFailed: return "Không ghi được file backup."
            case .readFailed: return "Không đọc được file backup."
            case .noBackup: return "Chưa có backup. Bấm Save lần đầu hoặc Apply trước."
            case .invalidData: return "File không phải MobileGestalt plist hợp lệ."
            }
        }
    }

    private let fm = FileManager.default

    private var backupDirectory: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("EnsWilde/Backup", isDirectory: true)
    }

    // Pristine backup (chỉ tạo 1 lần, dùng cho Reset Original)
    private var pristineURL: URL { backupDirectory.appendingPathComponent("MobileGestalt.plist") }
    private var metaURL: URL { backupDirectory.appendingPathComponent("backup.json") }

    var hasBackup: Bool { fm.fileExists(atPath: pristineURL.path) }

    var info: BackupInfo? {
        guard hasBackup else { return nil }
        let attrs = try? fm.attributesOfItem(atPath: pristineURL.path)
        let date = attrs?[.creationDate] as? Date
        let size = attrs?[.size] as? Int ?? 0
        let digest = (try? Data(contentsOf: pristineURL)).map { Self.sha256($0) } ?? ""
        return BackupInfo(createdAt: date ?? Date(), byteCount: size, sha256: digest)
    }

    // PORT GestaltBackupStore.create: tạo file timestamped mỗi lần ghi
    @discardableResult
    func createBackup(from data: Data) throws -> URL {
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let url = backupDirectory
            .appendingPathComponent("MobileGestalt_\(formatter.string(from: Date()))")
            .appendingPathExtension("plist")
        do { try data.write(to: url, options: .atomic) }
        catch { throw BackupError.writeFailed }
        return url
    }

    // Chỉ tạo 1 lần (dùng cho pristine, giữ tương thích cũ)
    @discardableResult
    func ensureBackup(from data: Data) throws -> BackupInfo {
        if hasBackup, let info { return info }
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        guard (try? data.write(to: pristineURL, options: .withoutOverwriting)) != nil else {
            throw BackupError.writeFailed
        }
        let meta: [String: Any] = [
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "byteCount": data.count,
            "sha256": Self.sha256(data)
        ]
        if let metaData = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
            try? metaData.write(to: metaURL)
        }
        return BackupInfo(createdAt: Date(), byteCount: data.count, sha256: Self.sha256(data))
    }

    func importBackup(from data: Data) throws {
        guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil else {
            throw BackupError.invalidData
        }
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        do { try data.write(to: pristineURL, options: .atomic) }
        catch { throw BackupError.writeFailed }
    }

    // Đọc pristine (MobileGestalt.plist cố định)
    func restoreData() throws -> Data {
        guard hasBackup else { throw BackupError.noBackup }
        return try Data(contentsOf: pristineURL)
    }

    func clearBackup() throws {
        if hasBackup { try fm.removeItem(at: pristineURL) }
        if fm.fileExists(atPath: metaURL.path) { try? fm.removeItem(at: metaURL) }
    }

    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}