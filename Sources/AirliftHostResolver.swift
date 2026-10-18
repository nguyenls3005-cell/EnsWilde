import Foundation
import Network
import AirliftFFI

enum AirliftHostResolver {
    static func candidates() -> [String] {
        var out: [String] = []
        if let override = UserDefaults.standard.string(forKey: "TunnelDeviceIP"),
           !override.isEmpty, override != "127.0.0.1", !out.contains(override) {
            out.append(override)
        }
        if let detected = detectFromInterfaces(), !out.contains(detected) {
            out.append(detected)
        }
        for ip in ["10.7.0.1", "10.7.0.2", "10.7.0.3", "198.18.0.1"] where !out.contains(ip) {
            out.append(ip)
        }
        return out
    }
    
    static func detectFromInterfaces() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("10.7.0.") || ip.hasPrefix("198.18.0.") { return ip }
        }
        return nil
    }
    
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        let hosts = candidates()
        log("[Airlift] Probing hosts: \(hosts.joined(separator: ", "))")
        for host in hosts where host != "127.0.0.1" {
            let ok = await canConnect(host: host, port: 49152, timeout: 1.2)
            if ok {
                _ = al_set_target_host(host)
                log("[Airlift] Selected: \(host)")
                return host
            }
            log("[Airlift] \(host) unreachable")
        }
        return nil
    }
    
    private static func canConnect(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { cont.resume(returning: false); return }
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else { cont.resume(returning: false); return }
                defer { close(fd) }
                let flags = fcntl(fd, F_GETFL, 0)
                fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                let rc = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                if rc == 0 { cont.resume(returning: true); return }
                if errno != EINPROGRESS { cont.resume(returning: false); return }
                var wfds = fd_set()
                fdZero(&wfds)
                fdSet(fd, &wfds)
                var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
                let sel = select(fd + 1, nil, &wfds, nil, &tv)
                if sel <= 0 { cont.resume(returning: false); return }
                var soError: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
                cont.resume(returning: soError == 0)
            }
        }
    }
}

private func fdZero(_ set: inout fd_set) {
    withUnsafeMutablePointer(to: &set.fds_bits) { ptr in
        memset(UnsafeMutableRawPointer(ptr), 0, MemoryLayout.size(ofValue: set.fds_bits))
    }
}
private func fdSet(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd / 32)
    let bitOffset = fd % 32
    withUnsafeMutablePointer(to: &set.fds_bits) { ptr in
        ptr.withMemoryRebound(to: Int32.self, capacity: 32) { arr in
            arr[intOffset] |= (1 << bitOffset)
        }
    }
}