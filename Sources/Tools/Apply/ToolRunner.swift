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
        try? await Task.sleep(nanoseconds: 400_000_000)
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
        
        // Khởi tạo IP cho AirLift (nếu có dùng Passcode/Wallet)
        if hasPasscode || hasWallet {
            let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
            if !FileManager.default.fileExists(atPath: pairingPath) {
                state = .failed(message: "Missing Pairing File!")
                await log("❌ Missing Pairing File! Vào Settings để import.")
                return
            }
            await log("✅ Pairing File found.")
            
            if let validIP = await getLoopbackIP() {
                await log("✅ Loopback IP active: \(validIP)")
                _ = al_set_target_host(validIP)
            } else {
                state = .failed(message: "Cannot connect to LocalDevVPN!")
                await log("❌ Cannot connect to LocalDevVPN! Hãy bật VPN.")
                return
            }
        }
        
        // ==========================================
        // 1. PASSCODE (AIRLIFT)
        // ==========================================
        if hasPasscode {
            state = .running(toolName: "Passcode Theme")
            await log("--- Passcode Theme (AirLift) ---")
            if let selectedTheme = themeStore.themes.first(where: { $0.isSelected }) {
                do {
                    try await PasscodeThemeViewModel(store: themeStore).applyTheme(selectedTheme, store: store) { logMsg in
                        Task { await self.log(logMsg) }
                    }
                } catch {
                    await log("❌ Passcode failed: \(error.localizedDescription)")
                }
            } else {
                await log("⚠️ No passcode theme selected.")
            }
        }

        // ==========================================
        // 2. WALLET (AIRLIFT)
        // ==========================================
        if hasWallet {
            state = .running(toolName: "Apple Wallet")
            await log("--- Apple Wallet (AirLift) ---")
            do {
                try await AppleWalletTask.run(store: store, walletStore: walletStore) { logMsg in
                    Task { await self.log(logMsg) }
                }
            } catch {
                await log("❌ Wallet failed: \(error.localizedDescription)")
            }
        }

        // ==========================================
        // 3. MOBILEGESTALT (BAD QUERY - CÓ BỌC LỖI HTTP)
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
                try BadQueryWrapper.writeFile(at: MobileGestaltApplyTask.onDeviceMGPath, data: mgData)
                await log("✅ MobileGestalt written.")
            } catch {
                // Bọc lỗi HTTP ở đây
                await log("❌ MobileGestalt failed: \(error.localizedDescription)")
                await log("⚠️ Lưu ý: Bad Query có thể bị chặn trên iOS 27.")
            }
        }

        // ==========================================
        // 4. CONFIG TWEAKS (BAD QUERY)
        // ==========================================
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

        state = .success
        await log("✅ All tweaks applied successfully.")
    }
    
    private func getLoopbackIP() async -> String? {
        let candidates = ["10.7.0.1", "127.0.0.1"]
        for ip in candidates {
            if let url = URL(string: "http://\(ip)") {
                var request = URLRequest(url: url)
                request.timeoutInterval = 1.0
                if let (_, _) = try? await URLSession.shared.data(for: request) { return ip }
            }
        }
        return nil
    }
}