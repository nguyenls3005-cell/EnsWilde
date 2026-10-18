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
        // Tăng nhẹ thời gian để log kịp hiển thị lên UI
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
        
        // 1. KHỞI TẠO IP AIRLIFT (NẾU CẦN)
        if hasPasscode || hasWallet {
            await log("Checking Pairing File...")
            let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
            if !FileManager.default.fileExists(atPath: pairingPath) {
                state = .failed(message: "Missing Pairing File!")
                await log("❌ Missing Pairing File! Vào Settings để import.")
                return
            }
            await log("✅ Pairing File found.")
            
            await log("Setting up Loopback IP...")
            _ = al_set_target_host("127.0.0.1")
            await log("✅ Loopback IP set to 127.0.0.1")
        }
        
        // ==========================================
        // 2. PASSCODE THEME (AIRLIFT)
        // ==========================================
        if hasPasscode {
            state = .running(toolName: "Passcode Theme")
            await log("--- Passcode Theme (AirLift) ---")
            
            if let selectedTheme = themeStore.themes.first(where: { $0.isSelected }) {
                do {
                    await log("Preparing images...")
                    let vm = PasscodeThemeViewModel(store: themeStore)
                    
                    // Chạy hàm apply trên background thread để không đơ UI
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        DispatchQueue.global(qos: .userInitiated).async {
                            Task {
                                do {
                                    try await vm.applyTheme(selectedTheme, store: store) { msg in
                                        // Log ra liên tục
                                        Task { await self.log(msg) }
                                    }
                                    continuation.resume()
                                } catch {
                                    continuation.resume(throwing: error)
                                }
                            }
                        }
                    }
                    await log("✅ Passcode applied successfully.")
                } catch {
                    await log("❌ Passcode failed: \(error.localizedDescription)")
                }
            } else {
                await log("⚠️ No passcode theme selected in library.")
            }
        }

        // ==========================================
        // 3. WALLET (AIRLIFT)
        // ==========================================
        if hasWallet {
            state = .running(toolName: "Apple Wallet")
            await log("--- Apple Wallet (AirLift) ---")
            do {
                await log("Preparing wallet cards...")
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        Task {
                            do {
                                try await AppleWalletTask.run(store: store, walletStore: walletStore) { msg in
                                    Task { await self.log(msg) }
                                }
                                continuation.resume()
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
                await log("✅ Wallet applied successfully.")
            } catch {
                await log("❌ Wallet failed: \(error.localizedDescription)")
            }
        }

        // ==========================================
        // 4. MOBILEGESTALT (BAD QUERY)
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
                
                await log("Writing MobileGestalt (Đang xử lý)...")
                // Chạy BadQuery trên background thread
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try BadQueryWrapper.writeFile(at: MobileGestaltApplyTask.onDeviceMGPath, data: mgData)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                await log("✅ MobileGestalt written.")
            } catch {
                await log("❌ MobileGestalt failed: \(error.localizedDescription)")
                await log("⚠️ Lưu ý: Bad Query có thể bị chặn trên iOS 27.")
            }
        }

        // ==========================================
        // 5. CONFIG TWEAKS (BAD QUERY)
        // ==========================================
        if hasConfigTweaks {
            state = .running(toolName: "Config Tweaks")
            await log("--- Config Tweaks (Bad Query) ---")
            do {
                await log("Granting access to Configuration Profiles...")
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
                        let access = BadQuery().grantAccess(atPath: configDir)
                        if access.0 {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: NSError(domain: "ToolRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to grant access."]))
                        }
                    }
                }
                await log("✅ Config Tweaks granted.")
            } catch {
                await log("❌ Config Tweaks failed: \(error.localizedDescription)")
            }
        }

        // KẾT THÚC
        state = .success
        await log("✅ Apply process finished.")
    }
}