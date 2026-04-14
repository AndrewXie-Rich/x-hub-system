import Foundation

struct XTHubRemoteAccessHostClassification: Equatable {
    enum Kind: Equatable {
        case missing
        case lanOnly
        case rawIP(scope: IPScope)
        case stableNamed
    }

    enum IPScope: String, Equatable {
        case loopback
        case privateLAN
        case carrierGradeNat
        case linkLocal
        case publicInternet
        case unknown

        var doctorLabel: String {
            switch self {
            case .loopback:
                return "回环地址"
            case .privateLAN:
                return "私有局域网 IP"
            case .carrierGradeNat:
                return "运营商 NAT IP"
            case .linkLocal:
                return "链路本地地址"
            case .publicInternet:
                return "公网 IP"
            case .unknown:
                return "未识别地址"
            }
        }
    }

    let rawHost: String?
    let normalizedHost: String?
    let kind: Kind

    static func classify(_ raw: String?) -> XTHubRemoteAccessHostClassification {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return XTHubRemoteAccessHostClassification(rawHost: nil, normalizedHost: nil, kind: .missing)
        }

        let lowered = trimmed.lowercased()
        if lowered == "localhost" || lowered.hasSuffix(".local") {
            return XTHubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .lanOnly)
        }
        if let scope = classifyIPv4Scope(lowered) {
            return XTHubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .rawIP(scope: scope))
        }
        if lowered == "::1" {
            return XTHubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .rawIP(scope: .loopback))
        }
        if lowered.hasPrefix("fe80:") {
            return XTHubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .rawIP(scope: .linkLocal))
        }
        if lowered.hasPrefix("fc") || lowered.hasPrefix("fd") {
            return XTHubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .rawIP(scope: .privateLAN))
        }
        if lowered.contains(":") {
            return XTHubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .rawIP(scope: .publicInternet))
        }
        if looksLikeStableNamedHost(trimmed) {
            return XTHubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .stableNamed)
        }
        return XTHubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .lanOnly)
    }

    var displayHost: String? {
        let normalized = normalizedHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalized.isEmpty { return normalized }
        let raw = rawHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    var kindCode: String {
        switch kind {
        case .missing:
            return "missing"
        case .lanOnly:
            return "lan_only"
        case .rawIP:
            return "raw_ip"
        case .stableNamed:
            return "stable_named"
        }
    }

    var ipScope: IPScope? {
        switch kind {
        case .rawIP(let scope):
            return scope
        case .missing, .lanOnly, .stableNamed:
            return nil
        }
    }

    private static func looksLikeStableNamedHost(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.contains(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func classifyIPv4Scope(_ host: String) -> IPScope? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return nil }
        guard octets.allSatisfy({ (0...255).contains($0) }) else { return nil }

        let a = octets[0]
        let b = octets[1]

        if a == 127 {
            return .loopback
        }
        if a == 169 && b == 254 {
            return .linkLocal
        }
        if a == 10 {
            return .privateLAN
        }
        if a == 172 && b >= 16 && b <= 31 {
            return .privateLAN
        }
        if a == 192 && b == 168 {
            return .privateLAN
        }
        if a == 100 && b >= 64 && b <= 127 {
            return .carrierGradeNat
        }
        return .publicInternet
    }
}
