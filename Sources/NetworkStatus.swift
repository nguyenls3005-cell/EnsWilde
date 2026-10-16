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

    /// Kiểm tra xem có VPN tunnel interface nào đang active không
    static func isVPNTunnelPresent() -> Bool {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            return false
        }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)

            // utun*, ipsec*, ppp* là các interface VPN phổ biến
            let isVPNInterface = name.hasPrefix("utun")
                || name.hasPrefix("ipsec")
                || name.hasPrefix("ppp")
                || name.hasPrefix("tun")
                || name.hasPrefix("tap")

            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING

            if isVPNInterface && isUp && isRunning {
                return true
            }

            pointer = interface.ifa_next
        }
        return false
    }
}