import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI
import Network

@MainActor
class PasscodeThemeViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var isApplying = false // Xoay xoay khi apply
    @Published var errorMessage: String?
    
    private let store: PasscodeThemeStore
    
    init(store: PasscodeThemeStore) {
        self.store = store
    }
    
    func importTheme(from sourceURL: URL, name: String) async throws {
        // Code cũ của bạn giữ nguyên...
        isProcessing = true; defer { isProcessing = false }
        // ...
    }
    
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isApplying = true
        defer { isApplying = false }
        
        let globalPrefix = self.store.globalCustomPrefix
        let globalTelephony = self.store.globalTelephonyVersion
        
        onLogUpdate("Preparing Passcode Theme...")
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: globalPrefix)
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }
        
        let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
        guard FileManager.default.fileExists(atPath: pairingPath) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftDialer_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        for (_, imageData, targetFilename) in processedFiles {
            try imageData.write(to: tempDir.appendingPathComponent(targetFilename))
        }
        
        _ = al_set_target_host("127.0.0.1")
        onLogUpdate("Đang ghi file qua AirTraffic...")
        
        // Bọc Background Task để icon Status Bar xoay xoay và không bị kill
        let bgTask = await UIApplication.shared.beginBackgroundTask(withName: "AirliftApplyPasscode") {
            onLogUpdate("⚠️ Hết thời gian chạy ngầm, nhưng có thể vẫn đang ghi.")
        }
        defer { UIApplication.shared.endBackgroundTask(bgTask) }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorCString: UnsafeMutablePointer<CChar>? = nil
                let targetPath = globalTelephony.cachePath
                let cleanTargetPath = targetPath.hasSuffix("/") ? String(targetPath.dropLast()) : targetPath
                
                let result = al_exploit_write_dir(
                    pairingPath, tempDir.path, cleanTargetPath,
                    { _, msg in
                        guard let msg = msg else { return }
                        let line = String(cString: msg)
                        DispatchQueue.main.async { onLogUpdate(line) }
                    },
                    nil, &errorCString
                )
                
                if result != 0 {
                    let errorMsg = errorCString != nil ? String(cString: errorCString!) : "Unknown AirLift Error"
                    if let err = errorCString { al_string_free(err) }
                    continuation.resume(throwing: NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "AirLift Error: \(errorMsg)"]))
                } else {
                    continuation.resume()
                }
            }
        }
        onLogUpdate("✅ Passcode applied successfully.")
    }
    
    // Các hàm phụ giữ nguyên...
    private func processThemeFiles(theme: PasscodeTheme, globalPrefix: PasscodeTheme.PrefixLanguage?) throws -> [(URL, Data, String)] { return [] }
    enum PasscodeThemeError: LocalizedError { case noImagesProcessed }
}