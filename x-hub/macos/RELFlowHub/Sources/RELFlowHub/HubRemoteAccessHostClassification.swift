import Foundation

struct HubRemoteAccessHostClassification: Equatable {
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
    }

    let rawHost: String?
    let normalizedHost: String?
    let kind: Kind

    static func classify(_ raw: String?) -> HubRemoteAccessHostClassification {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return HubRemoteAccessHostClassification(rawHost: nil, normalizedHost: nil, kind: .missing)
        }

        let lowered = trimmed.lowercased()
        if lowered == "localhost" || lowered.hasSuffix(".local") {
            return HubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .lanOnly)
        }
        if let scope = classifyIPv4Scope(lowered) {
            return HubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .rawIP(scope: scope))
        }
        if let stable = HubExternalAccessInviteSupport.normalizedStableNamedExternalHost(trimmed) {
            return HubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: stable, kind: .stableNamed)
        }
        return HubRemoteAccessHostClassification(rawHost: trimmed, normalizedHost: trimmed, kind: .lanOnly)
    }

    var displayHost: String? {
        let normalized = normalizedHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalized.isEmpty { return normalized }
        let raw = rawHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    static func classifyIPAddressScope(_ raw: String) -> IPScope {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scope = classifyIPv4Scope(lowered) {
            return scope
        }
        if lowered == "::1" {
            return .loopback
        }
        if lowered.hasPrefix("fe80:") {
            return .linkLocal
        }
        if lowered.hasPrefix("fc") || lowered.hasPrefix("fd") {
            return .privateLAN
        }
        if lowered.contains(":") {
            return .publicInternet
        }
        return .unknown
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
