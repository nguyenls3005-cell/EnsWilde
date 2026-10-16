import Foundation
import SwiftUI

@MainActor
final class ToolRunner: ObservableObject {

    @Published var state: ToolRunState = .idle
    @Published var logs: [ToolRunLogLine] = []

    func resetLogs() {
        logs.removeAll()
    }

    func log(_ s: String) {
        logs.append(.init(text: s))
        print("[APPLY] \(s)")
    }

    func applyAll(store: ToolStore, themeStore: PasscodeThemeStore) async {
        resetLogs()

        let hasMobileGestalt = store.replaceMobileGestaltEnabled
        let hasRecordSound = store.disableSoundEnabled
        let hasWallet = store.walletEnabled

        if !hasMobileGestalt && !hasRecordSound && !hasWallet {
            state = .failed(message: "No tweaks enabled.")
            log("Nothing to apply.")
            return
        }

        var names: [String] = []
        if hasMobileGestalt { names.append("MobileGestalt") }
        if hasRecordSound { names.append("Record Sound") }
        if hasWallet { names.append("Apple Wallet") }
        log("Apply started. Enabled: \(names.joined(separator: ", "))")

        // Check unsupported tweaks first
        var unsupported: [String] = []
        if hasRecordSound { unsupported.append("Record Sound") }
        if hasWallet { unsupported.append("Apple Wallet") }

        if !unsupported.isEmpty {
            state = .failed(message: "Chưa hỗ trợ exploit cho: \(unsupported.joined(separator: ", ")). Cần Airlift (Mac paired).")
            log("⚠ Chưa hỗ trợ: \(unsupported.joined(separator: ", "))")
            return
        }

        do {
            if hasMobileGestalt {
                state = .running(toolName: "MobileGestalt")
                log("Reading ModifiedMobileGestalt.plist...")

                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")

                guard FileManager.default.fileExists(atPath: modMGURL.path) else {
                    throw NSError(
                        domain: "ToolRunner", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist. Save it first in MobileGestalt tool."]
                    )
                }

                let mgData = try Data(contentsOf: modMGURL)
                let targetPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

                log("Writing via bad_query...")
                try BadQueryWrapper.writeFile(at: targetPath, data: mgData)
                log("✓ MobileGestalt written.")
            }

            state = .success
            log("✓ Apply completed.")
        } catch {
            state = .failed(message: "\(error)")
            log("✗ Failed: \(error.localizedDescription)")
        }
    }
}