import Foundation
import SwiftUI
import Combine

@MainActor
class ToolRunner: ObservableObject {
    @Published var state: ToolState = .idle

    /// Nhịp trễ ~1 giây giữa các bước để dễ quan sát tiến trình.
    private let stepDelayNs: UInt64 = 1_000_000_000

    private func paceStep() async {
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: stepDelayNs)
    }

    func applyAll(
        isSystemReady: Bool,
        store: ToolStore,
        walletStore: AppleWalletStore,
        themeStore: PasscodeThemeStore,
        featureFlagsStore: FeatureFlagsStore,
        onLogUpdate: @escaping (String) -> Void
    ) async {
        GLOBAL_LOG.beginNewSession(header: "=== Phiên chạy mới: \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)) ===")

        guard isSystemReady else {
            let msg = "System not ready. Check Pairing & VPN."
            state = .failed(msg)
            onLogUpdate("Chạy không thành công: \(msg)")
            return
        }

        state = .running
        onLogUpdate("Starting tweaks...")
        await paceStep()

        do {
            if store.replaceMobileGestaltEnabled {
                onLogUpdate(">> Applying MobileGestalt...")
                try await MobileGestaltApplyTask.applyGestalt(store: GestaltStore.shared, onLogUpdate: onLogUpdate)
                onLogUpdate(">> MobileGestalt Done.")
                await paceStep()
            }

            if themeStore.passcodeThemeEnabled {
                onLogUpdate(">> Applying Passcode Theme...")
                let selectedTheme = themeStore.getSelectedTheme() ?? PasscodeTheme(name: "Default")
                let vm = PasscodeThemeViewModel(store: themeStore)
                try await vm.applyTheme(selectedTheme, store: store, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Passcode Theme Done.")
                await paceStep()
            }

            if walletStore.appleWalletEnabled {
                onLogUpdate(">> Applying Apple Wallet...")
                try await AppleWalletTask.run(store: store, walletStore: walletStore, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Wallet Done.")
                await paceStep()
            }

            if store.configTweaksEnabled {
                onLogUpdate(">> Applying Config Tweaks...")
                try await ConfigTweaksApplyTask.apply(store: store, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Config Tweaks Done.")
                await paceStep()
            }

            if store.disableCallRecordingSoundEnabled {
                onLogUpdate(">> Applying Disable Call Recording Sound...")
                let vm = DisableCallRecordingSoundViewModel()
                try await vm.apply(store: store, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Disable Call Recording Sound Done.")
                await paceStep()
            }

            let zPatch = zPatchStore.shared
            if zPatch.isTweakEnabled || zPatch.pendingApply || zPatch.patches.contains(where: { $0.pendingRevert }) {
                onLogUpdate(">> Applying zPatch Custom...")
                let beforeCount = GLOBAL_LOG.text.components(separatedBy: "\n").count
                try zPatch.applyAllUsingWorseQuery(onLog: onLogUpdate)

                // Kiểm tra nếu log zPatch báo "Ghi đè thất bại" hoặc "doesn't exist" thì coi là lỗi thực thi
                let recentLines = GLOBAL_LOG.text.components(separatedBy: "\n").dropFirst(max(0, beforeCount - 1))
                if let failedLine = recentLines.first(where: {
                    $0.localizedCaseInsensitiveContains("ghi đè thất bại") ||
                    $0.localizedCaseInsensitiveContains("doesn’t exist") ||
                    $0.localizedCaseInsensitiveContains("doesn't exist") ||
                    $0.localizedCaseInsensitiveContains("failed")
                }) {
                    throw NSError(
                        domain: "zPatchCustom",
                        code: -50,
                        userInfo: [NSLocalizedDescriptionKey: failedLine]
                    )
                }

                onLogUpdate(">> zPatch Custom Done.")
                await paceStep()
            }

            state = .success
            onLogUpdate("All tweaks applied successfully.")

        } catch {
            let reason = error.localizedDescription.isEmpty ? "Lỗi không xác định" : error.localizedDescription
            state = .failed(reason)
            onLogUpdate("Chạy không thành công")
            onLogUpdate("Chi tiết lỗi: \(reason)")
        }
    }
}

enum ToolState: Equatable {
    case idle
    case running
    case success
    case failed(String)
}
