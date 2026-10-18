import Foundation
import SwiftUI
import AirliftFFI

@MainActor
final class ToolRunner: ObservableObject {

    @Published var state: ToolRunState = .idle
    @Published var logs: [ToolRunLogLine] = []

    func resetLogs() { logs.removeAll() }

    func log(_ s: String) async {
        logs.append(.init(text: s))
        print("[APPLY] \(s)")
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func applyAll(isSystemReady: Bool, store: ToolStore, walletStore: AppleWalletStore, themeStore: PasscodeThemeStore, featureFlagsStore: FeatureFlagsStore) async {
        let hasMobileGestalt = store.replaceMobileGestaltEnabled
        let hasConfigTweaks = store.configTweaksEnabled
        let hasPasscode = themeStore.passcodeThemeEnabled
        let hasWallet = walletStore.appleWalletEnabled

        if !hasMobileGestalt && !hasConfigTweaks && !hasPasscode && !hasWallet {
            state = .failed(message: "No tweaks enabled.")
            await log("❌ No tweaks enabled.")
            return
        }

        resetLogs()
        state = .running(toolName: "Initializing")
        await log("Starting Apply Process...")
        
        // 1. KIỂM TRA ĐIỀU KIỆN CHUNG CHO AIRLIFT
        if hasPasscode || hasWallet {
            let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
            if !FileManager.default.fileExists(atPath: pairingPath) {
                state = .failed(message: "Missing Pairing File!")
                await log("❌ Missing Pairing File! Import pairingFile.plist vào Documents.")
                return
            }
            if !NetworkStatus.isVPNTunnelPresent() {
                state = .failed(message: "VPN tunnel not active.")
                await log("❌ Không phát hiện VPN tunnel. Bật LocalDevVPN hoặc StikDebug.")
                return
            }
            await log("✅ Pairing & VPN OK.")
        }

        // 2. CHẠY MOBILEGESTALT (BAD QUERY) TRƯỚC
        if hasMobileGestalt {
            state = .running(toolName: "MobileGestalt")
            await log("--- MobileGestalt (Bad Query) ---")
            do {
                try BadQueryManager.ensureMobileGestaltAccess()
                await log("✅ Granted BadQuery access.")
                
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")
                guard FileManager.default.fileExists(atPath: modMGURL.path) else {
                    throw NSError(domain: "ToolRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist."])
                }
                let mgData = try Data(contentsOf: modMGURL)
                try BadQueryWrapper.writeFile(at: MobileGestaltApplyTask.onDeviceMGPath, data: mgData)
                await log("✅ MobileGestalt written.")
            } catch {
                await log("❌ MobileGestalt failed: \(error.localizedDescription)")
            }
        }

        // 3. CHẠY CONFIG TWEAKS (BAD QUERY)
        if hasConfigTweaks {
            state = .running(toolName: "Config Tweaks")
            await log("--- Config Tweaks (Bad Query) ---")
            do {
                let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
                let access = BadQuery().grantAccess(atPath: configDir)
                guard access.0 else {
                    throw NSError(domain: "ToolRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to grant access."])
                }
                await log("✅ Config Tweaks granted.")
            } catch {
                await log("❌ Config Tweaks failed: \(error.localizedDescription)")
            }
        }

        // 4. CHẠY PASSCODE (AIRLIFT) SAU CÙNG
        if hasPasscode {
            state = .running(toolName: "Passcode (Airlift)")
            if let selectedTheme = themeStore.themes.first(where: { $0.isSelected }) {
                do {
                    try await PasscodeThemeViewModel(store: themeStore).applyTheme(selectedTheme, store: store) { msg in
                        Task { await self.log(msg) }
                    }
                    await log("✅ Passcode applied.")
                } catch {
                    await log("❌ Passcode failed: \(error.localizedDescription)")
                }
            } else {
                await log("⚠️ No passcode theme selected.")
            }
        }

        // 5. CHẠY WALLET (AIRLIFT) SAU CÙNG
        if hasWallet {
            state = .running(toolName: "Wallet (Airlift)")
            do {
                try await AppleWalletTask.run(store: store, walletStore: walletStore) { msg in
                    Task { await self.log(msg) }
                }
                await log("✅ Wallet applied.")
            } catch {
                await log("❌ Wallet failed: \(error.localizedDescription)")
            }
        }

        state = .success
        await log("✅ All done.")
    }
}