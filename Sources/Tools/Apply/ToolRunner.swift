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
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    func applyAll(isSystemReady: Bool, store: ToolStore, walletStore: AppleWalletStore, themeStore: PasscodeThemeStore, featureFlagsStore: FeatureFlagsStore) async {
        let hasMobileGestalt = store.replaceMobileGestaltEnabled
        let hasConfigTweaks = store.configTweaksEnabled
        let hasPasscode = themeStore.passcodeThemeEnabled
        let hasWallet = walletStore.appleWalletEnabled

        if !hasMobileGestalt && !hasConfigTweaks && !hasPasscode && !hasWallet {
            state = .failed(message: "No tweaks enabled.")
            await log("No tweaks enabled.")
            return
        }

        resetLogs()
        state = .running(toolName: "Initializing")
        await log("Starting Apply process...")
        
        if hasPasscode || hasWallet {
            let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
            if !FileManager.default.fileExists(atPath: pairingPath) {
                state = .failed(message: "Missing Pairing File!")
                await log("Missing Pairing File!")
                return
            }
            await log("Pairing File found.")
            _ = al_set_target_host("10.7.0.1") // Set cứng IP
        }
        
        if hasPasscode {
            state = .running(toolName: "Passcode Theme")
            await log("--- Passcode Theme (AirLift) ---")
            if let selectedTheme = themeStore.themes.first(where: { $0.isSelected }) {
                do {
                    // Bọc trong Task với Timeout 10 giây
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await PasscodeThemeViewModel(store: themeStore).applyTheme(selectedTheme, store: store) { logMsg in
                                Task { await self.log(logMsg) }
                            }
                        }
                        group.addTask {
                            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 giây
                            throw NSError(domain: "AirLift", code: -4, userInfo: [NSLocalizedDescriptionKey: "Timeout: AirLift không phản hồi sau 10 giây."])
                        }
                        try await group.next()
                        group.cancelAll()
                    }
                } catch {
                    await log("Passcode failed: \(error.localizedDescription)")
                }
            } else {
                await log("No passcode theme selected.")
            }
        }

        if hasWallet {
            state = .running(toolName: "Apple Wallet")
            await log("--- Apple Wallet (AirLift) ---")
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await AppleWalletTask.run(store: store, walletStore: walletStore) { logMsg in
                            Task { await self.log(logMsg) }
                        }
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 10_000_000_000)
                        throw NSError(domain: "AirLift", code: -4, userInfo: [NSLocalizedDescriptionKey: "Timeout: Wallet không phản hồi sau 10 giây."])
                    }
                    try await group.next()
                    group.cancelAll()
                }
            } catch {
                await log("Wallet failed: \(error.localizedDescription)")
            }
        }

        if hasMobileGestalt {
            // ... (Code Bad Query cũ giữ nguyên)
        }

        if hasConfigTweaks {
            // ... (Code Bad Query cũ giữ nguyên)
        }

        state = .success
        await log("All tweaks applied successfully.")
    }
}