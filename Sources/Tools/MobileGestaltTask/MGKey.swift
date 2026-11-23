import Foundation

enum MGKey {
    static let regionCode      = "h63QSdBCiT/z0WU6rdQv6Q"
    static let regionInfo      = "zHeENZu+wbg7PUprwNwBWg"
    static let regionSysconfig = "yK+xavymRGZ3xWc1tb8XDg"
    static let regModelNumber  = "97JDvERpVwO+GHtthIh7hA"
    static let prodType        = "h9jDsbgj7xIVeIQ8S3/X3Q"
    static let artwork         = "oPeik/9e8lQWMszEjbPzng"
    static let modelNameOuter1 = "ArtworkDeviceProductDescription"
    static let modelNameOuter2 = "Z/dqyWS6OZTRy10UcmUAhw"

    static let intInstall = "EqrsVvjcYDdxHBiQmGhAWw"
    static let intBuild   = "LBJfwOEzExRxzlAnSuI7eg"
    static let srd        = "XYlJKKkj2hztRP1NWWnhlw"

    static let appIntell            = MGCacheDataLayout.appIntellKey
    static let photosCleanUp        = MGCacheDataLayout.photosCleanUpKey
    static let handwritingSynth     = MGCacheDataLayout.handwritingSynthKey
    static let audioIntell          = MGCacheDataLayout.audioIntellKey
    static let personalTranslator   = MGCacheDataLayout.personalTranslatorKey
    static let audioMix             = MGCacheDataLayout.audioMixKey
    static let spatialAudioRec      = MGCacheDataLayout.spatialAudioRecKey
    static let spatialFaceTimeAudio = MGCacheDataLayout.spatialFaceTimeAudioKey
    static let responsiveShutter    = MGCacheDataLayout.responsiveShutterKey
    static let hypertensionNotif    = MGCacheDataLayout.hypertensionNotifKey
    static let liquidGlassLowPower  = MGCacheDataLayout.liquidGlassLowPowerKey
    static let island               = MGCacheDataLayout.islandKey
    static let AOD                  = MGCacheDataLayout.aodKey
    static let AOTime               = MGCacheDataLayout.aoTimeKey
    static let AODVibrancy          = MGCacheDataLayout.aodVibrancyKey
    static let chargeLim            = MGCacheDataLayout.chargeLimKey
    static let bootChime            = MGCacheDataLayout.bootChimeKey
    static let crashDet             = MGCacheDataLayout.crashDetKey
    static let pwm                  = MGCacheDataLayout.pwmKey
    static let appPencil            = MGCacheDataLayout.appPencilKey
    static let camButton            = MGCacheDataLayout.camButtonKey
    static let actButton            = MGCacheDataLayout.actButtonKey
    static let tapToWake            = MGCacheDataLayout.tapToWakeKey
    static let stageMgr             = MGCacheDataLayout.stageMgrKey
    static let grapPefr             = "H9f+2vhlgQyV7rGz3pJIhg"

    static let shutterRelaxation           = MGCacheDataLayout.shutterRelaxationKey
    static let shutterKeyboardMutePreserve = MGCacheDataLayout.shutterKeyboardMutePreserveKey
    static let shutterLegacyMutePreserve   = MGCacheDataLayout.shutterLegacyMutePreserveKey
    static let concurrentHPLPMics          = MGCacheDataLayout.concurrentHPLPMicsKey
    static let photosLocalLight            = MGCacheDataLayout.photosLocalLightKey
    static let toneMapping                 = MGCacheDataLayout.toneMappingKey
    static let hdrDeferredProcessing       = MGCacheDataLayout.hdrDeferredProcessingKey
    static let spatialOverCapture          = MGCacheDataLayout.spatialOverCaptureKey
    static let stereoAudioRec              = MGCacheDataLayout.stereoAudioRecKey
    static let p3VideoRec                  = MGCacheDataLayout.p3VideoRecKey
    static let touchSensitiveCamControl    = MGCacheDataLayout.touchSensitiveCamControlKey
    static let hardwareDetents             = MGCacheDataLayout.hardwareDetentsKey
    static let cameraHaptics               = MGCacheDataLayout.cameraHapticsKey
    static let legacyBatteryInfo           = MGCacheDataLayout.legacyBatteryInfoKey
    static let legacyDynamicEndOfCharge    = MGCacheDataLayout.legacyDynamicEndOfChargeKey
    static let highLuminanceAOD            = MGCacheDataLayout.highLuminanceAODKey
    static let aodFlipbook                 = MGCacheDataLayout.aodFlipbookKey
    static let carPlay2                    = MGCacheDataLayout.carPlay2Key
    static let touchDelivery120Hz          = MGCacheDataLayout.touchDelivery120HzKey
    static let hearingAidEQ                = MGCacheDataLayout.hearingAidEQKey
    static let hearingAidLE                = MGCacheDataLayout.hearingAidLEKey
    static let hearingAidPowerRed          = MGCacheDataLayout.hearingAidPowerRedKey
    static let breathingDisturbances       = MGCacheDataLayout.breathingDisturbancesKey
    static let usBloodOxygen               = MGCacheDataLayout.usBloodOxygenKey
    static let workoutUltra                = MGCacheDataLayout.workoutUltraKey
    static let timeInDaylight              = MGCacheDataLayout.timeInDaylightKey
    static let siriHub                     = MGCacheDataLayout.siriHubKey
    static let onDeviceSiri                = MGCacheDataLayout.onDeviceSiriKey
    static let modelPruning                = MGCacheDataLayout.modelPruningKey

    static let advAppIntellKeys: [String] = [personalTranslator, audioIntell]
    static let advAppIntellRules: String  = personalTranslator
}
