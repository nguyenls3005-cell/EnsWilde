import Foundation
import CryptoKit

final class MobileGestaltBackupManager {
    static let shared = MobileGestaltBackupManager()

    struct BackupRecord {
        let id: UUID
        let url: URL
        let sha256: String
        let byteCount: Int
        let date: Date
    }

    private let fm = FileManager.default
    private var backupDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnsWilde/Backups", isDirectory: true)
    }

    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func createBackup(from data: Data, reason: String = "Before applying") throws -> BackupRecord {
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let id = UUID()
        let url = backupDir.appendingPathComponent("\(id.uuidString).plist")
        try data.write(to: url, options: .atomic)
        
        let hash = Self.sha256(data)
        let meta = ["id": id.uuidString, "sha256": hash, "byteCount": "\(data.count)", "reason": reason]
        let metaURL = backupDir.appendingPathComponent("\(id.uuidString).json")
        try JSONSerialization.data(withJSONObject: meta).write(to: metaURL)
        
        return BackupRecord(id: id, url: url, sha256: hash, byteCount: data.count, date: Date())
    }

    func backupData(_ record: BackupRecord) throws -> Data {
        let data = try Data(contentsOf: record.url)
        guard data.count == record.byteCount, Self.sha256(data) == record.sha256 else {
            throw NSError(domain: "Backup", code: -1, userInfo: [NSLocalizedDescriptionKey: "Backup bị hỏng (SHA256 không khớp)."])
        }
        return data
    }

    func latestBackup() -> BackupRecord? {
        guard let files = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return nil }
        let plists = files.filter { $0.pathExtension == "plist" }
        guard let latest = plists.max(by: { url1, url2 in
            let d1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let d2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return d1 < d2
        }) else { return nil }
        
        guard let id = UUID(uuidString: latest.deletingPathExtension().lastPathComponent),
              let metaData = try? Data(contentsOf: backupDir.appendingPathComponent("\(id.uuidString).json")),
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: String],
              let hash = meta["sha256"], let countStr = meta["byteCount"], let count = Int(countStr) else { return nil }
        
        return BackupRecord(id: id, url: latest, sha256: hash, byteCount: count, date: Date())
    }
}