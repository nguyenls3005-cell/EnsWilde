import Foundation
import SwiftUI

@MainActor
final class ToolRunner: ObservableObject {
    @Published var state: ToolRunState = .idle
    @Published var logs: [ToolRunLogLine] = []

    func resetLogs() { logs.removeAll() }

    func log(_ s: String) {
        logs.append(.init(text: s))
        print("[APPLY] \(s)")
    }

    func applyAll(store: ToolStore, themeStore: PasscodeThemeStore) async {
        resetLogs()

        let hasMobileGestalt = store.replaceMobileGestaltEnabled

        if !hasMobileGestalt {
            state = .failed(message: "No tweaks enabled.")
            log("Nothing to apply.")
            return
        }

        log("Apply started.")

        do {
            if hasMobileGestalt {
                state = .running(toolName: "MobileGestalt")
                log("Reading ModifiedMobileGestalt.plist...")

                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")

                guard FileManager.default.fileExists(atPath: modMGURL.path) else {
                    throw NSError(domain: "ToolRunner", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist. Save it first in MobileGestalt tool."])
                }

                let mgData = try Data(contentsOf: modMGURL)
                let targetPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

                log("Writing via bad_query to \(targetPath)...")
                try BadQueryWrapper.writeFile(at: targetPath, data: mgData)
                log("MobileGestalt written successfully.")
            }

            state = .success
            log("Apply completed.")
        } catch {
            state = .failed(message: "\(error)")
            log("Failed: \(error.localizedDescription)")
        }
    }
}