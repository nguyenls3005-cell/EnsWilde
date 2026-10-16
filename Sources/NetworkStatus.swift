import Foundation
import Network

enum NetworkStatus {

    /// Check VPN tunnel active bằng getifaddrs
    static func checkVPNStatus(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let active = isVPNTunnelPresent()
            DispatchQueue.main.async {
                completion(active)
            }
        }
    }

    static