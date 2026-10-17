import Foundation
import SwiftUI

@MainActor
final class ToolRunner: ObservableObject {

    @Published var state: ToolRunState = .idle
    @Published var logs: [ToolRunLogLine] = []

    func resetLogs() { logs.removeAll() }

    func log(_ s: String) async {
        logs.append(.init(text: s))
        print("[APPLY] \(s)")
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 giây
    }

    func applyAll(isSystemReady: Bool, store: ToolStore, walletStore: AppleWalletStore, themeStore: PasscodeThemeStore, featureFlagsStore: FeatureFlagsStore) async {
        let hasMobileGestalt = store.replaceMobileGestaltEnabled
        let hasConfigTweaks = store.configTweaksEnabled

        if !hasMobileGestalt && !hasConfigTweaks {
            state = .failed(message: "No tweaks enabled.")
            return
        }

        resetLogs()
        state = .running(toolName: "Initializing")
        
        await log("Initializing Bad_Query exploit...")
        await log("Checking system permissions...")
        
        do {
            if hasMobileGestalt {
                state = .running(toolName: "MobileGestalt")
                await log("Locating ModifiedMobileGestalt.plist...")
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")
                guard FileManager.default.fileExists(atPath: modMGURL.path) else {
                    throw NSError(domain: "ToolRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist."])
                }
                await log("Reading plist data...")
                let mgData = try Data(contentsOf: modMGURL)
                let targetPath = MobileGestaltApplyTask.onDeviceMGPath
                await log("Writing MobileGestalt via bad_query...")
                try BadQueryWrapper.writeFile(at: targetPath, data: mgData)
                await log("✓ MobileGestalt written.")
            }

            if hasConfigTweaks {
                state = .running(toolName: "Config Tweaks")
                await log("Preparing Config Tweaks...")
                let footnote = store.configFootnoteText
                let supervised = UserDefaults.standard.bool(forKey: "ConfigSupervised")
                let orgName = UserDefaults.standard.string(forKey: "ConfigOrgName") ?? ""
                let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
                let sharedDevConfigPath = "\(configDir)/SharedDeviceConfiguration.plist"
                let cloudConfigPath = "\(configDir)/CloudConfigurationDetails.plist"

                await log("Granting access...")
                let access = bq.grantAccess(atPath: configDir)
                guard access.0 else {
                    throw NSError(domain: "ToolRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to grant access."])
                }

                let ftDict: [String: Any] = ["LockScreenFootnote": footnote]
                let ftData = try PropertyListSerialization.data(fromPropertyList: ftDict, format: .binary, options: 0)
                await log("Writing SharedDeviceConfiguration.plist...")
                try ftData.write(to: URL(fileURLWithPath: sharedDevConfigPath))

                var ccDict: NSMutableDictionary = [:]
                if let existing = NSMutableDictionary(contentsOfFile: cloudConfigPath) { ccDict = existing }
                ccDict["IsSupervised"] = supervised
                if supervised && !orgName.isEmpty { ccDict["OrganizationName"] = orgName }
                else { ccDict.removeObject(forKey: "OrganizationName") }
                
                await log("Writing CloudConfigurationDetails.plist...")
                let ccData = try PropertyListSerialization.data(fromPropertyList: ccDict, format: .binary, options: 0)
                try ccData.write(to: URL(fileURLWithPath: cloudConfigPath))
                await log("✓ Config Tweaks applied.")
            }

            state = .success
            await log("✓ All tweaks applied successfully.")
        } catch {
            state = .failed(message: "\(error)")
            await log("✗ Failed: \(error.localizedDescription)")
        }
    }
}