import Foundation
import AppKit
import CoreImage

@MainActor
extension HubGRPCServerSupport {
    private static let qrContext = CIContext(options: nil)

    private static func firstNonLoopbackIPv4(from rows: [String]) -> String? {
        preferredXTTerminalInternetHost(override: "", interfaceRows: rows)
    }

    static func preferredXTTerminalInternetHost(
        override rawOverride: String,
        interfaceRows rows: [String]
    ) -> String? {
        let trimmedOverride = rawOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOverride.isEmpty {
            return trimmedOverride
        }

        let parsed = rows
            .compactMap(parseInterfaceIPv4Row(_:))
            .filter { isAdvertisableRemoteInterfaceCandidate($0) }
        guard !parsed.isEmpty else { return nil }
        return parsed.min { lhs, rhs in
            preferredXTTerminalInternetHostScore(lhs) < preferredXTTerminalInternetHostScore(rhs)
        }?.ip
    }

    static func preferredNoDomainPrivateRemoteHost(interfaceRows rows: [String]) -> String? {
        let candidates = rows.compactMap(parseInterfaceIPv4Row(_:))
        guard !candidates.isEmpty else { return nil }

        return candidates
            .filter { candidate in
                isCarrierGradeNatIPv4(candidate.ip)
            }
            .min { lhs, rhs in
                noDomainRemoteHostScore(lhs) < noDomainRemoteHostScore(rhs)
            }?.ip
    }

    private static func noDomainRemoteHostScore(_ candidate: (ifname: String, ip: String)) -> Int {
        if isCarrierGradeNatIPv4(candidate.ip) {
            return 0
        }
        return 1
    }

    private static func isAdvertisableRemoteInterfaceCandidate(_ candidate: (ifname: String, ip: String)) -> Bool {
        isCarrierGradeNatIPv4(candidate.ip)
    }

    private static func preferredXTTerminalInternetHostScore(_ candidate: (ifname: String, ip: String)) -> Int {
        let ifname = candidate.ifname.lowercased()
        if isCarrierGradeNatIPv4(candidate.ip) {
            return 0
        }
        if isPubliclyRoutedIPv4(candidate.ip) {
            return 1
        }
        if ifname.hasPrefix("en0") {
            return 2
        }
        if ifname.hasPrefix("en1") {
            return 3
        }
        if ifname.hasPrefix("en") {
            return 4
        }
        if isRemoteTunnelInterfaceName(ifname) {
            return 5
        }
        return 6
    }

    static func parseInterfaceIPv4Row(_ row: String) -> (ifname: String, ip: String)? {
        guard let idx = row.firstIndex(of: ":") else { return nil }
        let ifname = row[..<idx].trimmingCharacters(in: .whitespacesAndNewlines)
        let ip = row[row.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ifname.isEmpty, !ip.isEmpty else { return nil }
        return (ifname: String(ifname), ip: String(ip))
    }

    static func interfaceRowsContainRemoteTunnelIP(_ ip: String, rows: [String]) -> Bool {
        rows.compactMap(parseInterfaceIPv4Row(_:)).contains { candidate in
            candidate.ip == ip
                && isCarrierGradeNatIPv4(candidate.ip)
                && isRemoteTunnelInterfaceName(candidate.ifname)
        }
    }

    static func isRemoteTunnelInterfaceName(_ rawIfname: String) -> Bool {
        let ifname = rawIfname.lowercased()
        return ifname.hasPrefix("utun")
            || ifname.hasPrefix("tun")
            || ifname.hasPrefix("tap")
            || ifname.hasPrefix("wg")
    }

    static func isCarrierGradeNatIPv4(_ ip: String) -> Bool {
        guard let (a, b, _, _) = parseIPv4Octets(ip) else { return false }
        return a == 100 && b >= 64 && b <= 127
    }

    private static func isPubliclyRoutedIPv4(_ ip: String) -> Bool {
        guard let (a, b, _, _) = parseIPv4Octets(ip) else { return false }
        if a == 10 { return false }
        if a == 127 { return false }
        if a == 169 && b == 254 { return false }
        if a == 172 && b >= 16 && b <= 31 { return false }
        if a == 192 && b == 168 { return false }
        if isCarrierGradeNatIPv4(ip) { return false }
        return true
    }

    private static func isPrivateIPv4(_ ip: String) -> Bool {
        guard let (a, b, _, _) = parseIPv4Octets(ip) else { return false }
        if a == 10 { return true }
        if a == 172 && b >= 16 && b <= 31 { return true }
        if a == 192 && b == 168 { return true }
        return false
    }

    private static func parseIPv4Octets(_ raw: String) -> (Int, Int, Int, Int)? {
        let parts = raw.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return nil }
        for value in octets where value < 0 || value > 255 {
            return nil
        }
        return (octets[0], octets[1], octets[2], octets[3])
    }

    static func qrCodeImage(for text: String, side: CGFloat) -> NSImage? {
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.integral
        let scale = max(1, floor(side / max(extent.width, extent.height)))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = qrContext.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: scaled.extent.width, height: scaled.extent.height)
        )
    }
}
