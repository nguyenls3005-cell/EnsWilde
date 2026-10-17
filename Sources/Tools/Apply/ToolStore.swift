import Foundation
import SwiftUI

final class ToolStore: ObservableObject {

    @AppStorage("DisableDisclosureSoundEnabled") var disableSoundEnabled: Bool = false
    @AppStorage("SoundRespringEnabled") var soundRespringEnabled: Bool = true
    @AppStorage("BookassetdContainerUUID") var bookassetdUUID: String?

    @AppStorage("ReplaceMobileGestaltEnabled") var replaceMobileGestaltEnabled: Bool = false
    @AppStorage("ThemesUIEnabled") var themesUIEnabled: Bool = false
    @AppStorage("zPatchCustomEnabled") var zPatchCustomEnabled: Bool = false
    @AppStorage("zPatchUnlocked") var zPatchUnlocked: Bool = false
    @AppStorage("SoundDelayAfterStartSeconds") var soundDelayAfterStart: Double = 3.0
    @AppStorage("SoundDelayAfterStopSeconds") var soundDelayAfterStop: Double = 3.0
    @AppStorage("DeviceUDID") var deviceUDID: String = ""
    @AppStorage("ToolAEnabled") var toolAEnabled: Bool = false
    @AppStorage("ToolBEnabled") var toolBEnabled: Bool = false

    // Thêm 2 biến này để ConfigView hoạt động
    @AppStorage("ConfigTweaksEnabled") var configTweaksEnabled: Bool = false
    @AppStorage("ConfigFootnoteText") var configFootnoteText: String = ""
}