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

    func applyAll(isSystemReady: Bool, store: ToolStore, walletStore: AppleWalletStore, themeStore: PasscodeThemeStore, featureFlagsStore: FeatureFlagsStore) async {
        guard isSystemReady else {
            state = .failed(message: "System not ready.")
            return
        }

        let hasMobileGestalt = store.replaceMobileGestaltEnabled
        let hasConfigTweaks = store.configTweaksEnabled

        if !hasMobileGestalt && !hasConfigTweaks {
            state = .failed(message: "No tweaks enabled.")
            return
        }

        resetLogs()
        var names: [String] = []
        if hasMobileGestalt { names.append("MobileGestalt") }
        if hasConfigTweaks { names.append("Config Tweaks") }
        log("Apply started. Enabled: \(names.joined(separator: ", "))")

        do {
            if hasMobileGestalt {
                state = .running(toolName: "MobileGestalt")
                log("Reading ModifiedMobileGestalt.plist...")
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")
                guard FileManager.default.fileExists(atPath: modMGURL.path) else {
                    throw NSError(domain: "ToolRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist."])
                }
                let mgData = try Data(contentsOf: modMGURL)
                let targetPath = MobileGestaltApplyTask.onDeviceMGPath
                log("Writing MobileGestalt via bad_query...")
                try BadQueryWrapper.writeFile(at: targetPath, data: mgData)
                log("✓ MobileGestalt written.")
            }

            if hasConfigTweaks {
                state = .running(toolName: "Config Tweaks")
                let footnote = store.configFootnoteText
                let supervised = UserDefaults.standard.bool(forKey: "ConfigSupervised")
                let orgName = UserDefaults.standard.string(forKey: "ConfigOrgName") ?? ""
                let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
                let sharedDevConfigPath = "\(configDir)/SharedDeviceConfiguration.plist"
                let cloudConfigPath = "\(configDir)/CloudConfigurationDetails.plist"

                log("Granting access...")
                let access = bq.grantAccess(atPath: configDir)
                guard access.0 else {
                    throw NSError(domain: "ToolRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to grant access."])
                }

                let ftDict: [String: Any] = ["LockScreenFootnote": footnote]
                let ftData = try PropertyListSerialization.data(fromPropertyList: ftDict, format: .binary, options: 0)
                try ftData.write(to: URL(fileURLWithPath: sharedDevConfigPath))

                var ccDict: NSMutableDictionary = [:]
                if let existing = NSMutableDictionary(contentsOfFile: cloudConfigPath) { ccDict = existing }
                ccDict["IsSupervised"] = supervised
                if supervised && !orgName.isEmpty { ccDict["OrganizationName"] = orgName }
                else { ccDict.removeObject(forKey: "OrganizationName") }
                let ccData = try PropertyListSerialization.data(fromPropertyList: ccDict, format: .binary, options: 0)
                try ccData.write(to: URL(fileURLWithPath: cloudConfigPath))
                log("✓ Config Tweaks applied.")
            }

            state = .success
            log("✓ Apply completed.")
        } catch {
            state = .failed(message: "\(error)")
            log("✗ Failed: \(error.localizedDescription)")
        }
    }
}