import Foundation

enum MGURL {
    /// Path thật trên iOS 26/27 — SystemGroup container.
    static let fsGestaltURL = URL(fileURLWithPath:
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist")

    static let savedGestaltURL       = URL.documentsDirectory.appendingPathComponent("OriginalGestalt.plist")
    static let savedGestaltSHA256URL = URL.documentsDirectory.appendingPathComponent("OriginalGestalt.sha256")
    static let systemVaultGestaltURL = URL(fileURLWithPath:
        "/var/mobile/Library/Preferences/com.yangjiii.EnsWilde.MGOriginalVault.plist")
    static let systemVaultSHA256URL  = URL(fileURLWithPath:
        "/var/mobile/Library/Preferences/com.yangjiii.EnsWilde.MGOriginalVault.sha256")
    static let preApplyGestaltURL    = URL.documentsDirectory.appendingPathComponent("PreApplyGestalt.plist")
}
