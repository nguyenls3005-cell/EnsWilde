import Foundation
import SwiftUI
import AirliftFFI

@MainActor
final class ToolRunner: ObservableObject {
    @Published var state: ToolRunState = .idle
    @Published var logs: [ToolRunLogLine] = []

    func resetLogs() { logs.removeAll() }

    // Hàm log đồng bộ, đảm bảo UI cập nhật ngay lập tức
    func log(_ s: String) {
        logs.append(.init(text: s))
        print("[APPLY] \(s)")
    }

    func applyAll(isSystemReady: Bool, store: ToolStore, walletStore: AppleWalletStore, themeStore: PasscodeThemeStore, featureFlagsStore: FeatureFlagsStore) async {
        let hasMobileGestalt = UserDefaults.standard.bool(forKey: "ReplaceMobileGestaltEnabled")
        let hasConfigTweaks = UserDefaults.standard.bool(forKey: "ConfigTweaksEnabled")
        let hasPasscode = UserDefaults.standard.bool(forKey: "PasscodeThemeEnabled")
        let hasWallet = UserDefaults.standard.bool(forKey: "AppleWalletEnabled")

        if !hasMobileGestalt && !hasConfigTweaks && !hasPasscode && !hasWallet {
            state = .failed(message: "No tweaks enabled.")
            log("❌ No tweaks enabled.")
            return
        }

        resetLogs()
        state = .running(toolName: "Initializing")
        log("Starting Apply Process...")
        
        if hasPasscode || hasWallet {
            let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
            if !FileManager.default.fileExists(atPath: pairingPath) {
                state = .failed(message: "Missing Pairing File!")
                log("❌ Missing Pairing File! Import pairingFile.plist vào Documents.")
                return
            }
            if !NetworkStatus.isVPNTunnelPresent() {
                state = .failed(message: "VPN tunnel not active.")
                log("❌ Không phát hiện VPN tunnel. Bật LocalDevVPN hoặc StikDebug.")
                return
            }
            log("✅ Pairing & VPN OK.")
        }

        if hasMobileGestalt {
            state = .running(toolName: "MobileGestalt")
            log("--- MobileGestalt (Bad Query) ---")
            do {
                try BadQueryManager.ensureMobileGestaltAccess()
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")
                guard FileManager.default.fileExists(atPath: modMGURL.path) else { throw NSError(domain: "ToolRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist."]) }
                let mgData = try Data(contentsOf: modMGURL)
                try BadQueryWrapper.writeFile(at: MobileGestaltApplyTask.onDeviceMGPath, data: mgData)
                log("✅ MobileGestalt written.")
            } catch {
                log("❌ MobileGestalt failed: \(error.localizedDescription)")
            }
        }

        if hasConfigTweaks {
            state = .running(toolName: "Config Tweaks")
            log("--- Config Tweaks (Bad Query) ---")
            do {
                let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
                let access = BadQuery().grantAccess(atPath: configDir)
                guard access.0 else { throw NSError(domain: "ToolRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to grant access."]) }
                log("✅ Config Tweaks granted.")
            } catch {
                log("❌ Config Tweaks failed: \(error.localizedDescription)")
            }
        }

        if hasPasscode {
            state = .running(toolName: "Passcode (Airlift)")
            if let selectedTheme = themeStore.themes.first(where: { $0.isSelected }) {
                do {
                    // Truyền thẳng hàm log đồng bộ vào
                    try await PasscodeThemeViewModel(store: themeStore).applyTheme(selectedTheme, store: store) { msg in 
                        self.log(msg) 
                    }
                    log("✅ Passcode applied.")
                } catch {
                    // BẮT BUỘC PHẢI HIỆN LỖI RA MÀN HÌNH
                    log("❌ LỖI AIRLIFT PASSCODE: \(error.localizedDescription)")
                }
            } else {
                log("⚠️ No passcode theme selected.")
            }
        }

        if hasWallet {
            state = .running(toolName: "Wallet (Airlift)")
            do {
                try await AppleWalletTask.run(store: store, walletStore: walletStore) { msg in 
                    self.log(msg) 
                }
                log("✅ Wallet applied.")
            } catch {
                log("❌ LỖI AIRLIFT WALLET: \(error.localizedDescription)")
            }
        }

        state = .success
        log("✅ All done.")
    }
}