import Foundation
import Network

enum NetworkStatus {

    /// Check VPN tunnel active bằng cách scan network interfaces
    /// Tìm interface có IP `10.7.0.1` hoặc `127.0.0.1` (LocalDevVPN loopback)
    static func checkVPNStatus(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let active = isVPNTunnelPresent()
            DispatchQueue.main.async {
                completion(active)
            }
        }
    }

    /// Sync version — chạy trên background thread
    static func isVPNActive() -> Bool {
        return isVPNTunnelPresent()
    }

    /// Legacy API
    static func isVPNTunnelReachable(timeout: TimeInterval = 1.0) -> Bool {
        return isVPNTunnelPresent()
    }

    /// Legacy API
    static func isLocalDevVPNActive() -> Bool {
        return isVPNTunnelPresent()
    }

    // MARK: - Private

    private static func isVPNTunnelPresent() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }

            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            // Lấy IP address
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let addr = interface.ifa_addr
            let addrLen = socklen_t(interface.ifa_addr.pointee.sa_len)

            let result = getnameinfo(
                addr,
                addrLen,
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let ip = String(cString: hostname)

                // LocalDevVPN thường dùng 10.7.0.1 hoặc 127.0.0.1
                if ip == "10.7.0.1" || ip == "10.7.0.2" || ip == "10.7.0.3" {
                    return true
                }
            }
        }

        return false
    }
}