import Foundation
import Network
import NetworkExtension

enum NetworkStatus {

    /// Async VPN check via NEVPNManager (không block main thread)
    static func checkVPNStatus(completion: @escaping (Bool) -> Void) {
        NEVPNManager.shared().loadFromPreferences { error in
            if let error = error {
                print("[VPN] Load error: \(error)")
                DispatchQueue.main.async { completion(false) }
                return
            }
            let isConnected = NEVPNManager.shared().connection.status == .connected
            DispatchQueue.main.async { completion(isConnected) }
        }
    }

    /// Sync check
    static func isVPNActive() -> Bool {
        return NEVPNManager.shared().connection.status == .connected
    }

    /// Legacy — giữ để tương thích
    static func isVPNTunnelReachable(timeout: TimeInterval = 1.0) -> Bool {
        return isVPNActive()
    }

    /// Legacy — giữ để tương thích
    static func isLocalDevVPNActive() -> Bool {
        return isVPNActive()
    }
}