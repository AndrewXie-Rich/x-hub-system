import Foundation
import Darwin

@MainActor
extension HubGRPCServerSupport {
    static func currentLANAddresses() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return []
        }
        defer {
            freeifaddrs(ifaddr)
        }

        var out: [String] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }

            let flags = Int32(p.pointee.ifa_flags)
            if (flags & IFF_UP) == 0 { continue }
            if (flags & IFF_LOOPBACK) != 0 { continue }

            guard let addr = p.pointee.ifa_addr else { continue }
            if addr.pointee.sa_family != UInt8(AF_INET) { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var sa = addr.pointee
            let ok = withUnsafePointer(to: &sa) { saPtr -> Int32 in
                let sa2 = UnsafeRawPointer(saPtr).assumingMemoryBound(to: sockaddr.self)
                return getnameinfo(sa2, socklen_t(sa2.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            }
            if ok != 0 { continue }

            let ip = decodeNullTerminatedCString(host)
            if ip == "127.0.0.1" { continue }
            if ip.hasPrefix("169.254.") { continue } // link-local

            let ifname = String(cString: p.pointee.ifa_name)
            out.append("\(ifname): \(ip)")
        }

        // Sort so en0/en1 are near the top.
        out.sort { a, b in
            let pa = a.lowercased()
            let pb = b.lowercased()
            if pa.hasPrefix("en0:") != pb.hasPrefix("en0:") {
                return pa.hasPrefix("en0:")
            }
            return pa < pb
        }
        return out
    }

    static func defaultLANAllowedCidrs() -> [String] {
        var out: [String] = ["private", "loopback"]
        for cidr in currentLANIPv4Cidrs(maxBroadPrefix: 16) {
            if !out.contains(cidr) {
                out.append(cidr)
            }
        }
        // Some corporate networks use globally routable IPv4 ranges (non-RFC1918), and are also
        // segmented into many /24s. In those environments, restricting to the Hub's *exact* interface
        // subnet can incorrectly block legitimate peers (e.g. Hub is 17.81.12.x/24 but a coworker is
        // 17.81.11.x/24).
        //
        // As a pragmatic, defense-in-depth default for pairing + gRPC ports, we also allow a /16
        // "coarse LAN" supernet derived from the Hub's active IPv4 addresses (when not private).
        //
        // Devices can (and should) further restrict their own `allowed_cidrs` in the per-device UI.
        for cidr in currentLANIPv4CoarseCidrs(prefix: 16) {
            if !out.contains(cidr) {
                out.append(cidr)
            }
        }
        return out
    }

    static func defaultFirstPairingLANAllowedCidrs() -> [String] {
        var out: [String] = ["loopback"]
        for cidr in currentLANIPv4Cidrs(maxBroadPrefix: 16, excludingRemoteTunnelInterfaces: true) {
            if !out.contains(cidr) {
                out.append(cidr)
            }
        }
        return out
    }

    private static func currentLANIPv4CoarseCidrs(prefix: Int, excludingRemoteTunnelInterfaces: Bool = false) -> [String] {
        // Derive a coarse supernet CIDR from currently detected LAN IPv4 addresses without relying
        // on ifa_netmask parsing (which can vary between environments).
        //
        // For prefix=16: a.b.c.d -> a.b.0.0/16
        let p = max(0, min(32, prefix))
        guard p == 16 else { return [] }

        func parseIPv4(_ s: String) -> (Int, Int, Int, Int)? {
            let parts = s.split(separator: ".")
            if parts.count != 4 { return nil }
            let nums = parts.compactMap { Int($0) }
            if nums.count != 4 { return nil }
            for n in nums {
                if n < 0 || n > 255 { return nil }
            }
            return (nums[0], nums[1], nums[2], nums[3])
        }

        func isPrivate(_ a: Int, _ b: Int) -> Bool {
            if a == 10 { return true }
            if a == 172, b >= 16, b <= 31 { return true }
            if a == 192, b == 168 { return true }
            return false
        }

        var out: [String] = []
        var seen: Set<String> = []
        for row in currentLANAddresses() {
            guard let parsed = parseInterfaceIPv4Row(row) else { continue }
            if excludingRemoteTunnelInterfaces && isRemoteTunnelInterfaceName(parsed.ifname) {
                continue
            }
            guard let (a, b, _, _) = parseIPv4(parsed.ip) else { continue }
            if a == 127 { continue }
            if a == 169, b == 254 { continue } // link-local
            if isPrivate(a, b) { continue } // already covered by the "private" rule

            let cidr = "\(a).\(b).0.0/16"
            if seen.contains(cidr) { continue }
            seen.insert(cidr)
            out.append(cidr)
        }
        return out
    }

    private static func currentLANIPv4Cidrs(maxBroadPrefix: Int, excludingRemoteTunnelInterfaces: Bool = false) -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return []
        }
        defer {
            freeifaddrs(ifaddr)
        }

        func ipv4HostOrder(_ sa: UnsafeMutablePointer<sockaddr>) -> UInt32? {
            let fam = sa.pointee.sa_family
            guard fam == UInt8(AF_INET) else { return nil }
            let sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            return UInt32(bigEndian: sin.sin_addr.s_addr)
        }

        func ipv4String(hostOrder: UInt32) -> String? {
            var addr = in_addr(s_addr: hostOrder.bigEndian)
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return decodeNullTerminatedCString(buf)
        }

        func prefixLength(mask: UInt32) -> Int? {
            if mask == 0 { return nil }
            var bits = 0
            var m = mask
            while (m & 0x8000_0000) != 0 {
                bits += 1
                m <<= 1
                if bits >= 32 { break }
            }
            if bits <= 0 { return nil }
            let reconstructed: UInt32 = {
                if bits >= 32 { return 0xffff_ffff }
                let allOnes: UInt32 = 0xffff_ffff
                return allOnes << (32 - bits)
            }()
            return reconstructed == mask ? bits : nil
        }

        var rows: [(ifname: String, cidr: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }

            let flags = Int32(p.pointee.ifa_flags)
            if (flags & IFF_UP) == 0 { continue }
            if (flags & IFF_LOOPBACK) != 0 { continue }

            guard let addr = p.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard let netmask = p.pointee.ifa_netmask, netmask.pointee.sa_family == UInt8(AF_INET) else { continue }

            guard let ipH = ipv4HostOrder(addr) else { continue }
            guard let maskH0 = ipv4HostOrder(netmask) else { continue }

            // Skip loopback/link-local and unset addresses.
            if (ipH & 0xff00_0000) == 0x7f00_0000 { continue } // 127.0.0.0/8
            if (ipH & 0xffff_0000) == 0xa9fe_0000 { continue } // 169.254.0.0/16
            if ipH == 0 { continue }

            guard let rawPrefix = prefixLength(mask: maskH0) else { continue }
            let minPrefix = max(0, min(32, maxBroadPrefix))
            let clampedPrefix = max(minPrefix, min(32, rawPrefix))
            let maskH: UInt32 = {
                if clampedPrefix >= 32 { return 0xffff_ffff }
                let allOnes: UInt32 = 0xffff_ffff
                return allOnes << (32 - clampedPrefix)
            }()
            let netH = ipH & maskH
            guard let netS = ipv4String(hostOrder: netH) else { continue }

            let ifname = String(cString: p.pointee.ifa_name)
            if excludingRemoteTunnelInterfaces && isRemoteTunnelInterfaceName(ifname) {
                continue
            }
            rows.append((ifname: ifname, cidr: "\(netS)/\(clampedPrefix)"))
        }

        // Sort so en0/en1 are near the top (matches currentLANAddresses()).
        rows.sort { a, b in
            let pa = "\(a.ifname): \(a.cidr)".lowercased()
            let pb = "\(b.ifname): \(b.cidr)".lowercased()
            if pa.hasPrefix("en0:") != pb.hasPrefix("en0:") {
                return pa.hasPrefix("en0:")
            }
            return pa < pb
        }

        // De-dup by cidr.
        var seen: Set<String> = []
        var out: [String] = []
        for r in rows {
            if seen.contains(r.cidr) { continue }
            seen.insert(r.cidr)
            out.append(r.cidr)
        }
        return out
    }
}
