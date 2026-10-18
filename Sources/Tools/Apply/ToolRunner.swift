import Foundation
import SwiftUI
import AirliftFFI

@MainActor
final class ToolRunner: ObservableObject {

    @Published var state: ToolRunState = .idle
    @Published var logs: [ToolRunLogLine] = []

    func resetLogs() { logs.removeAll() }

    // Bỏ Task.sleep, chỉ log ra cho nhanh
    func log(_ s: String) async {
        logs.append(.init(text: s))
        print("[APPLY] \(s)")
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
            let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
            if !FileManager.default.fileExists(atPath: pairingPath) {
                state = .failed(message: "Missing Pairing File!")
                await log("❌ Missing Pairing File!")
                return
            }
            await log("✅ Pairing File found.")
        }
        
        // Helper chạy ngầm kèm Timeout 20s
        func runBackgroundWithTimeout<T>(_ operation: @escaping () async throws -> T) async throws -> T {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 20_000_000_000) // 20s
                    throw NSError(domain: "Timeout", code: -1, userInfo: [NSLocalizedDescriptionKey: "Quá 20 giây không phản hồi. Kiểm tra lại VPN."])
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
                    // Ép cứng IP
                    _ = al_set_target_host("127.0.0.1")
                    
                    // Chạy TOÀN BỘ quá trình trên Background Thread
                    try await runBackgroundWithTimeout {
                        try await Task.detached(priority: .high) {
                            let vm = PasscodeThemeViewModel(store: themeStore)
                            try await vm.applyTheme(selectedTheme, store: store) { msg in
                                Task { await self.log(msg) }
                            }
                        }.value
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
                _ = al_set_target_host("127.0.0.1")
                
                try await runBackgroundWithTimeout {
                    try await Task.detached(priority: .high) {
                        try await AppleWalletTask.run(store: store, walletStore: walletStore) { msg in
                            Task { await self.log(msg) }
                        }
                    }.value
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
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")
                guard FileManager.default.fileExists(atPath: modMGURL.path) else {
                    throw NSError(domain: "ToolRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist."])
                }
                let mgData = try Data(contentsOf: modMGURL)
                
                try await runBackgroundWithTimeout {
                    try await Task.detached(priority: .high) {
                        try BadQueryWrapper.writeFile(at: MobileGestaltApplyTask.onDeviceMGPath, data: mgData)
                    }.value
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
                try await runBackgroundWithTimeout {
                    try await Task.detached(priority: .high) {
                        let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
                        let access = BadQuery().grantAccess(atPath: configDir)
                        if !access.0 {
                            throw NSError(domain: "ToolRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to grant access."])
                        }
                    }.value
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