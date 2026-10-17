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

    // Check chuẩn xác xem app LocalDevVPN có đang chạy không thay vì quét interface chung chung
    static func isLocalDevVPNRunning() -> Bool {
        // 1. Check xem tiến trình LocalDevVPN có đang chạy không
        let runningApps = LSApplicationWorkspaceDefaultWorkspace().allInstalledApplications()
        if let localDevApp = runningApps.first(where: { $0.bundleIdentifier == "com.LocalDev.VPN" || $0.localizedName?.contains("LocalDevVPN") == true }) {
            if localDevApp.isRunning() {
                return true
            }
        }
        
        // 2. Check IP của tunnel LocalDev (thường là 10.7.0.1)
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else { return false }
        defer { freeifaddrs(addrs) }
        
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            let interface = current.pointee
            if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                let ip = String(cString: hostname)
                
                // IP của LocalDevVPN thường là 10.7.0.1 hoặc 10.7.0.2
                if ip.hasPrefix("10.7.0.") {
                    return true
                }
            }
            pointer = interface.ifa_next
        }
        
        return false
    }
}