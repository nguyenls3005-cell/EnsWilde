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

    /// Check VPN tunnel active via NWConnection to 10.7.0.1
    static func isVPNTunnelReachable(timeout: TimeInterval = 1.0) -> Bool {
        let host = NWEndpoint.Host("10.7.0.1")
        let port = NWEndpoint.Port(rawValue: 80)!

        let connection = NWConnection(host: host, port: port, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        var isReady = false

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                isReady = true
                semaphore.signal()
                connection.cancel()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }

        let queue = DispatchQueue(label: "VPNTunnelCheck")
        connection.start(queue: queue)

        _ = semaphore.wait(timeout: .now() + timeout)
        connection.cancel()

        return isReady
    }
}