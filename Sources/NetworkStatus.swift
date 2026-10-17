import Foundation
import Network

enum NetworkStatus {

    static func checkVPNStatus(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let active = isLocalDevVPNRunning()
            DispatchQueue.main.async {
                completion(active)
            }
        }
    }

    // Quét IP của tunnel LocalDev (thường là 10.7.0.1) hoặc interface VPN
    static func isLocalDevVPNRunning() -> Bool {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else { return false }
        defer { freeifaddrs(addrs) }
        
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)
            
            // Check IP của LocalDevVPN
            if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                let ip = String(cString: hostname)
                
                // LocalDevVPN dùng IP 10.7.0.1
                if ip.hasPrefix("10.7.0.") {
                    return true
                }
            }
            
            // Fallback check interface VPN nếu không thấy IP
            let isVPNInterface = name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("tap") || name.hasPrefix("ppp")
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            
            if isVPNInterface && isUp && isRunning {
                // Để tránh nhận nhầm mạng Wi-Fi thường, ưu tiên check IP 10.7.0. trước
                // Nếu không thấy IP thì trả về true để báo có VPN đang chạy
                return true
            }
            
            pointer = interface.ifa_next
        }
        
        return false
    }
}