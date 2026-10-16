import Foundation
import Network
import NetworkExtension

enum NetworkStatus {

    /// Check VPN active via NEVPNManager (accurate, fast)
    static func isVPNActive() -> Bool {
        let manager = NEVPNManager.shared()
        let status = manager.connection.status
        return status == .connected
    }

    /// Async version with completion handler (avoid blocking main)
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

    /// Legacy — keep for compatibility
    static func isVPNTunnelReachable(timeout: TimeInterval = 1.0) -> Bool {
        return isVPNActive()
    }

    /// Legacy — keep for compatibility
    static func isLocalDevVPNActive() -> Bool {
        return isVPNActive()
    }
}