import Foundation
import Darwin

@MainActor
extension HubGRPCServerSupport {
    static func pairingPort(grpcPort: Int) -> Int {
        max(1, min(65535, grpcPort + 1))
    }

    static func isTCPPortInUse(_ port: Int) -> Bool {
        let p = max(1, min(65535, port))
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }
        defer { close(sock) }

        var yes: Int32 = 1
        _ = setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(p).bigEndian
        addr.sin_addr = in_addr(s_addr: in_addr_t(0)) // INADDR_ANY

        let bindRes: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindRes == 0 {
            return false
        }
        if errno == EADDRINUSE {
            return true
        }
        return false
    }

    static func diagnosticsFindAvailablePort(startingAt: Int, maxTries: Int = 32) -> Int? {
        // Ensure pairing port (grpc+1) stays valid.
        let start = max(1024, min(65534, startingAt))
        let cap = max(1, maxTries)
        for delta in 0..<cap {
            let p = start + delta
            if p > 65534 { break }
            if isTCPPortInUse(p) { continue }
            if isTCPPortInUse(pairingPort(grpcPort: p)) { continue }
            return p
        }
        return nil
    }

    static func detectNearbyLocalHubGRPCPort(configuredPort: Int, maxDistance: Int = 6) -> Int? {
        let current = max(1024, min(65534, configuredPort))
        let span = max(1, min(12, maxDistance))
        var candidates: [Int] = []
        var seen = Set<Int>()

        func append(_ grpcPort: Int) {
            let p = max(1024, min(65534, grpcPort))
            if seen.contains(p) { return }
            seen.insert(p)
            candidates.append(p)
        }

        append(current)
        for delta in 1...span {
            append(current - delta)
            append(current + delta)
        }
        append(defaultPort)
        append(defaultPort + 1)

        for grpcPort in candidates {
            if probeLocalPairingHealth(pairingPort: pairingPort(grpcPort: grpcPort), timeoutUsec: 80_000) {
                return grpcPort
            }
        }
        return nil
    }

    static func probeLocalPairingHealth(pairingPort: Int, timeoutUsec: Int = 200_000) -> Bool {
        let p = max(1, min(65535, pairingPort))
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }
        defer { close(sock) }

        // Ensure the probe never stalls the UI thread.
        var tv = timeval(tv_sec: 0, tv_usec: __darwin_suseconds_t(max(10_000, min(1_000_000, timeoutUsec))))
        _ = setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(p).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connRes: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connRes != 0 {
            return false
        }

        // Minimal HTTP probe: if the embedded pairing server is up, it responds with JSON
        // containing `"service":"pairing"`.
        let req = "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        _ = req.withCString { cstr in
            Darwin.send(sock, cstr, strlen(cstr), 0)
        }

        var buf = [UInt8](repeating: 0, count: 1024)
        let n = Darwin.recv(sock, &buf, buf.count, 0)
        if n <= 0 { return false }
        let data = Data(buf.prefix(Int(n)))
        let s = String(data: data, encoding: .utf8) ?? ""
        return s.contains("\"service\":\"pairing\"")
    }
}
