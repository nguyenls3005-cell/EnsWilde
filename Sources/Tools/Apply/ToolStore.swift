import Foundation
import SwiftUI

/// Central place for enable flags + shared prefs.
/// Keep using AppStorage so settings persist.
final class ToolStore: ObservableObject {

    // Disable Sound
    @AppStorage("DisableDisclosureSoundEnabled") var disableSoundEnabled: Bool = false
    @AppStorage("SoundRespringEnabled") var soundRespringEnabled: Bool = true
    @AppStorage("BookassetdContainerUUID") var bookassetdUUID: String?

    // MobileGestalt
    @AppStorage("ReplaceMobileGestaltEnabled") var replaceMobileGestaltEnabled: Bool = false
    
    // Themes UI
    @AppStorage("ThemesUIEnabled") var themesUIEnabled: Bool = false
    
    // zPatch Custom
    @AppStorage("zPatchCustomEnabled") var zPatchCustomEnabled: Bool = false
    @AppStorage("zPatchUnlocked") var zPatchUnlocked: Bool = false

    // DisableSound delays
    @AppStorage("SoundDelayAfterStartSeconds") var soundDelayAfterStart: Double = 3.0
    @AppStorage("SoundDelayAfterStopSeconds") var soundDelayAfterStop: Double = 3.0

    // Other / legacy
    @AppStorage("DeviceUDID") var deviceUDID: String = ""
    @AppStorage("ToolAEnabled") var toolAEnabled: Bool = false
    @AppStorage("ToolBEnabled") var toolBEnabled: Bool = false
}