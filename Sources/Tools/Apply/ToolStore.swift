import Foundation
import SwiftUI

final class ToolStore: ObservableObject {

    // Disable Sound (Record Sound)
    @AppStorage("DisableDisclosureSoundEnabled") var disableSoundEnabled: Bool = false
    @AppStorage("SoundRespringEnabled") var soundRespringEnabled: Bool = true
    @AppStorage("BookassetdContainerUUID") var bookassetdUUID: String?

    // MobileGestalt
    @AppStorage("ReplaceMobileGestaltEnabled") var replaceMobileGestaltEnabled: Bool = false

    // Apple Wallet
    @AppStorage("AppleWalletEnabled") var walletEnabled: Bool = false

    // Themes UI (không dùng)
    @AppStorage("ThemesUIEnabled") var themesUIEnabled: Bool = false

    // zPatch (không dùng)
    @AppStorage("zPatchCustomEnabled") var zPatchCustomEnabled: Bool = false
    @AppStorage("zPatchUnlocked") var zPatchUnlocked: Bool = false

    // DisableSound delays (không dùng)
    @AppStorage("SoundDelayAfterStartSeconds") var soundDelayAfterStart: Double = 3.0
    @AppStorage("SoundDelayAfterStopSeconds") var soundDelayAfterStop: Double = 3.0

    // Other / legacy
    @AppStorage("DeviceUDID") var deviceUDID: String = ""
    @AppStorage("ToolAEnabled") var toolAEnabled: Bool = false
    @AppStorage("ToolBEnabled") var toolBEnabled: Bool = false
}