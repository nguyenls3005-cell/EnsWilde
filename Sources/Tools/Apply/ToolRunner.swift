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
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    func applyAll(isSystemReady: Bool, store: ToolStore, walletStore: AppleWalletStore, themeStore: PasscodeThemeStore, featureFlagsStore: FeatureFlagsStore) async {
        let isAirLiftMode = UserDefaults.standard.bool(forKey: "isAirLiftMode")
        
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
        
        do {
            // KIỂM TRA ĐIỀU KIỆN TIÊN QUYẾT (CHỈ KHI DÙNG AIRLIFT)
            if isAirLiftMode {
                // 1. Check Pairing
                let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
                guard FileManager.default.fileExists(atPath: pairingPath) else {
                    throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Pairing File! Vào Settings để import."])
                }
                await log("✅ Pairing File found.")
                
                // 2. Check Loopback IP
                let targetIP = await getLoopbackIP()
                guard let validIP = targetIP else {
                    throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot connect to LocalDevVPN! Hãy bật VPN."])
                }
                await log("✅ Loopback IP active: \(validIP)")
                _ = al_set_target_host(validIP)
            }

            // CHẠY PASSCODE
            if hasPasscode {
                state = .running(toolName: "Passcode Theme")
                await log("--- Passcode Theme ---")
                if let selectedTheme = themeStore.themes.first(where: { $0.isSelected }) {
                    try await PasscodeThemeViewModel(store: themeStore).applyTheme(selectedTheme, store: store) { logMsg in
                        Task { await self.log(logMsg) }
                    }
                } else {
                    throw NSError(domain: "Passcode", code: -1, userInfo: [NSLocalizedDescriptionKey: "No passcode theme selected in library."])
                }
            }

            // CHẠY WALLET
            if hasWallet {
                state = .running(toolName: "Apple Wallet")
                await log("--- Apple Wallet ---")
                try await AppleWalletTask.run(store: store, walletStore: walletStore) { logMsg in
                    Task { await self.log(logMsg) }
                }
            }

            // CHẠY BAD QUERY (NẾU KHÔNG DÙNG AIRLIFT)
            if !isAirLiftMode {
                if hasMobileGestalt {
                    state = .running(toolName: "MobileGestalt")
                    await log("--- MobileGestalt ---")
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")
                    guard FileManager.default.fileExists(atPath: modMGURL.path) else {
                        throw NSError(domain: "ToolRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist."])
                    }
                    let mgData = try Data(contentsOf: modMGURL)
                    try BadQueryWrapper.writeFile(at: MobileGestaltApplyTask.onDeviceMGPath, data: mgData)
                    await log("✅ MobileGestalt written.")
                }

                if hasConfigTweaks {
                    state = .running(toolName: "Config Tweaks")
                    await log("--- Config Tweaks ---")
                    let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
                    let access = BadQuery().grantAccess(atPath: configDir)
                    guard access.0 else {
                        throw NSError(domain: "ToolRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to grant access."])
                    }
                    await log("✅ Config Tweaks granted.")
                }
            }

            // NẾU MỌI THỨ CHẠY XONG XUÔI SẺ MÀ KHÔNG QUĂNG LỖI -> SUCCESS
            state = .success
            await log("✅ All tweaks applied successfully.")

        } catch {
            // NẾU CÓ BẤT KỲ LỖI NÀO VĂNG RA -> DỪNG LẠI VÀ BÁO ĐỎ
            state = .failed(message: "\(error.localizedDescription)")
            await log("❌ Failed: \(error.localizedDescription)")
        }
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