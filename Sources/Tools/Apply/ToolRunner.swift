import Foundation
import SwiftUI
import Combine

@MainActor
class ToolRunner: ObservableObject {
    @Published var state: ToolState = .idle

    private let stepDelayNs: UInt64 = 1_000_000_000

    private func paceStep() async {
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: stepDelayNs)
    }

    /// Chuẩn hóa đường dẫn tương đối để loại bỏ lặp thư mục (vd: Library/Cookies/Library/Cookies/...)
    static func normalizeRelativePath(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix("/") {
            cleaned.removeFirst()
        }
        let parts = cleaned.components(separatedBy: "/").filter { !$0.isEmpty }
        var result: [String] = []
        var i = 0
        while i < parts.count {
            // Loại bỏ cặp 2 cấp bị lặp liên tiếp: A/B/A/B -> A/B
            if i + 3 < parts.count,
               parts[i] == parts[i + 2],
               parts[i + 1] == parts[i + 3] {
                result.append(parts[i])
                result.append(parts[i + 1])
                i += 4
            }
            // Loại bỏ 1 cấp bị lặp liên tiếp: A/A -> A
            else if i + 1 < parts.count,
                    parts[i] == parts[i + 1] {
                result.append(parts[i])
                i += 2
            } else {
                result.append(parts[i])
                i += 1
            }
        }
        return result.joined(separator: "/")
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
            onLogUpdate("Chạy không thành công")
            onLogUpdate("Chi tiết lỗi: \(msg)")
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

                // Chuẩn hóa đường dẫn của toàn bộ patch (kể cả patch mới nhập từ .ens) trước khi chạy
                var didFixPath = false
                for idx in zPatch.patches.indices {
                    let fixedRel = Self.normalizeRelativePath(zPatch.patches[idx].relativeDestPath)
                    if fixedRel != zPatch.patches[idx].relativeDestPath {
                        zPatch.patches[idx].relativeDestPath = fixedRel
                        zPatch.patches[idx].cachedDestinationPath = zPatch.patches[idx].fastPreviewPath
                        didFixPath = true
                    }
                }
                if didFixPath {
                    zPatch.savePatches()
                }

                // Bắt trực tiếp từng dòng log được bắn ra đồng bộ từ applyAllUsingWorseQuery
                var capturedErrorLine: String? = nil
                try zPatch.applyAllUsingWorseQuery(onLog: { line in
                    let lower = line.lowercased()
                    if lower.contains("thất bại") ||
                       lower.contains("lỗi") ||
                       lower.contains("doesn’t exist") ||
                       lower.contains("doesn't exist") ||
                       lower.contains("error") ||
                       lower.contains("failed") ||
                       lower.contains("không tìm thấy") {
                        if capturedErrorLine == nil {
                            capturedErrorLine = line
                        }
                    }
                    onLogUpdate(line)
                })

                if let errLine = capturedErrorLine {
                    throw NSError(
                        domain: "zPatchCustom",
                        code: -50,
                        userInfo: [NSLocalizedDescriptionKey: errLine]
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
