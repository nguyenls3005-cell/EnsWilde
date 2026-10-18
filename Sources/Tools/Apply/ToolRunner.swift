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
        try? await Task.sleep(nanoseconds: 150_000_000) 
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
        await log("Starting Apply process...")
        
        if hasPasscode || hasWallet {
            await log("Checking Pairing File...")
            let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
            if !FileManager.default.fileExists(atPath: pairingPath) {
                state = .failed(message: "Missing Pairing File!")
                await log("❌ Missing Pairing File! Vào Settings để import.")
                return
            }
            await log("✅ Pairing File found.")
        }
        
        // Hàm helper để chạy với Timeout 15s
        func runWithTimeout<T>(_ operation: @escaping () async throws -> T) async throws -> T {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000) // 15s
                    throw NSError(domain: "Timeout", code: -1, userInfo: [NSLocalizedDescriptionKey: "Quá thời gian 15 giây. Vui lòng kiểm tra lại LocalDevVPN."])
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
        
        // ==========================================
        // 1. PASSCODE
        // ==========================================
        if hasPasscode {
            state = .running(toolName: "Passcode Theme")
            await log("--- Passcode Theme (AirLift) ---")
            
            if let selectedTheme = themeStore.themes.first(where: { $0.isSelected }) {
                do {
                    await log("Preparing images...")
                    _ = al_set_target_host("127.0.0.1")
                    
                    let vm = PasscodeThemeViewModel(store: themeStore)
                    try await runWithTimeout {
                        try await vm.applyTheme(selectedTheme, store: store) { msg in
                            Task { await self.log(msg) }
                        }
                    }
                    await log("✅ Passcode applied successfully.")
                } catch {
                    await log("❌ Passcode failed: \(error.localizedDescription)")
                }
            } else {
                await log("⚠️ No passcode theme selected.")
            }
        }

        // ==========================================
        // 2. WALLET
        // ==========================================
        if hasWallet {
            state = .running(toolName: "Apple Wallet")
            await log("--- Apple Wallet (AirLift) ---")
            do {
                await log("Preparing wallet cards...")
                _ = al_set_target_host("127.0.0.1")
                
                try await runWithTimeout {
                    try await AppleWalletTask.run(store: store, walletStore: walletStore) { msg in
                        Task { await self.log(msg) }
                    }
                }
                await log("✅ Wallet applied successfully.")
            } catch {
                await log("❌ Wallet failed: \(error.localizedDescription)")
            }
        }

        // ==========================================
        // 3. MOBILEGESTALT
        // ==========================================
        if hasMobileGestalt {
            state = .running(toolName: "MobileGestalt")
            await log("--- MobileGestalt (Bad Query) ---")
            do {
                await log("Reading ModifiedMobileGestalt.plist...")
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")
                guard FileManager.default.fileExists(atPath: modMGURL.path) else {
                    throw NSError(domain: "ToolRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist."])
                }
                let mgData = try Data(contentsOf: modMGURL)
                
                await log("Writing MobileGestalt...")
                try await runWithTimeout {
                    try BadQueryWrapper.writeFile(at: MobileGestaltApplyTask.onDeviceMGPath, data: mgData)
                }
                await log("✅ MobileGestalt written.")
            } catch {
                await log("❌ MobileGestalt failed: \(error.localizedDescription)")
            }
        }

        // ==========================================
        // 4. CONFIG TWEAKS
        // ==========================================
        if hasConfigTweaks {
            state = .running(toolName: "Config Tweaks")
            await log("--- Config Tweaks (Bad Query) ---")
            do {
                await log("Granting access...")
                try await runWithTimeout {
                    let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
                    let access = BadQuery().grantAccess(atPath: configDir)
                    if !access.0 {
                        throw NSError(domain: "ToolRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to grant access."])
                    }
                }
                await log("✅ Config Tweaks granted.")
            } catch {
                await log("❌ Config Tweaks failed: \(error.localizedDescription)")
            }
        }

        state = .success
        await log("✅ Apply process finished.")
    }
}