import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI
import Network

@MainActor
class PasscodeThemeViewModel: ObservableObject {
    @Published var isProcessing = false
    private let store: PasscodeThemeStore
    
    init(store: PasscodeThemeStore) { self.store = store }
    
    func importTheme(from sourceURL: URL, name: String) async throws { /* ... giữ nguyên ... */ }
    func processThemeFiles(theme: PasscodeTheme, globalPrefix: PasscodeTheme.PrefixLanguage? = nil) throws -> [(sourceURL: URL, processedData: Data, targetFilename: String)] { /* ... giữ nguyên ... */ }
    
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        let globalTelephony = self.store.globalTelephonyVersion
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: self.store.globalCustomPrefix)
        guard !processedFiles.isEmpty else { throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "No files"]) }
        
        guard NetworkStatus.isVPNTunnelPresent() else { throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN chưa bật."]) }
        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else { throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "No pairing"]) }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftPayload_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        for (_, imageData, targetFilename) in processedFiles { try imageData.write(to: tempDir.appendingPathComponent(targetFilename)) }
        
        let targetPath = globalTelephony.cachePath
        let cleanTargetPath = targetPath.hasSuffix("/") ? String(targetPath.dropLast()) : targetPath
        
        _ = BadQuery().grantAccess(atPath: cleanTargetPath)
        if !FileManager.default.fileExists(atPath: cleanTargetPath) { try? FileManager.default.createDirectory(atPath: cleanTargetPath, withIntermediateDirectories: true) }
        
        guard let _ = await AirliftHostResolver.bestAvailable(log: onLogUpdate) else { throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "No tunnel"]) }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                let res = al_exploit_write_dir(pairingURL.path, tempDir.path, cleanTargetPath, nil, nil, &errPtr)
                
                if res != 0 {
                    let msg = errPtr != nil ? String(cString: errPtr!) : "Airlift Error"
                    if let e = errPtr { al_string_free(e) }
                    continuation.resume(throwing: NSError(domain: "AirLift", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg]))
                } else {
                    continuation.resume()
                }
            }
        }
        onLogUpdate("✅ Passcode applied successfully.")
    }
}