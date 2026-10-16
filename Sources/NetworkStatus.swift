import Foundation
import Network

enum NetworkStatus {
    /// Check if LocalDevVPN loopback is active (10.7.0.1 or 127.0.0.1)
    static func isLocalDevVPNActive() -> Bool {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var isSatisfied = false

        monitor.pathUpdateHandler = { path in
            isSatisfied = (path.status == .satisfied)
            semaphore.signal()
        }

        let queue = DispatchQueue(label: "NetworkStatusCheck")
        monitor.start(queue: queue)

        _ = semaphore.wait(timeout: .now() + 1.0)
        monitor.cancel()

        return isSatisfied
    }

    /// Check VPN tunnel active via simple TCP connect to 10.7.0.1
    static func isVPNTunnelReachable(timeout: TimeInterval = 1.0) -> Bool {
        let host = "10.7.0.1"
        let port: UInt16 = 80

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Non-blocking connect
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result == 0 { return true }

        // Wait for connect
        var writefds = fd_set()
        writefds.fd = sock
        let selectResult = select(sock + 1, nil, &writefds, nil, &tv)

        if selectResult > 0 {
            var so_error: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(sock, SOL_SOCKET, SO_ERROR, &so_error, &len)
            return so_error == 0
        }

        result = errno
        _ = result
        return false
    }
}