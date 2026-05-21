import Foundation

enum HubRemoteHostPolicy {
    static func normalizedNonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedHostToken(_ raw: String?) -> String? {
        guard let value = normalizedNonEmpty(raw)?.lowercased() else { return nil }
        if value.hasSuffix(".") {
            return String(value.dropLast())
        }
        return value
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        guard let normalized = normalizedHostToken(host) else { return false }
        return normalized == "localhost" || normalized == "127.0.0.1"
    }

    static func isIPv4Host(_ host: String) -> Bool {
        guard let normalized = normalizedHostToken(host) else { return false }
        let parts = normalized.split(separator: ".")
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { (0...255).contains($0) }
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        guard let normalized = normalizedHostToken(host) else { return nil }
        let parts = normalized.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return nil }
        guard octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return octets
    }

    static func isPrivateIPv4Host(_ host: String) -> Bool {
        guard let octets = ipv4Octets(host) else { return false }
        let a = octets[0]
        let b = octets[1]
        if a == 10 { return true }
        if a == 127 { return true }
        if a == 169, b == 254 { return true }
        if a == 172, b >= 16, b <= 31 { return true }
        if a == 192, b == 168 { return true }
        return false
    }

    static func isTailscaleIPv4Host(_ host: String) -> Bool {
        guard let octets = ipv4Octets(host) else { return false }
        return octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127
    }

    static func isPublicIPv4Host(_ host: String) -> Bool {
        isIPv4Host(host) && !isPrivateIPv4Host(host) && !isTailscaleIPv4Host(host)
    }

    static func isStableNamedRemoteHost(_ host: String) -> Bool {
        guard let normalized = normalizedHostToken(host) else { return false }
        if isLoopbackHost(normalized) { return false }
        if normalized.hasSuffix(".local") { return false }
        if isIPv4Host(normalized) { return false }
        return true
    }

    static func isFormalRemoteHost(_ host: String) -> Bool {
        isStableNamedRemoteHost(host) || isTailscaleIPv4Host(host)
    }

    static func isDirectInternetRemoteHost(_ host: String) -> Bool {
        isFormalRemoteHost(host) || isPublicIPv4Host(host)
    }

    static func isDirectLocalFallbackHost(_ host: String) -> Bool {
        guard let normalized = normalizedHostToken(host) else { return false }
        if isLoopbackHost(normalized) { return true }
        if normalized.hasSuffix(".local") { return true }
        return isPrivateIPv4Host(normalized)
    }

    static func isReusableConnectCandidate(_ host: String) -> Bool {
        isFormalRemoteHost(host) || isDirectLocalFallbackHost(host)
    }

    static func inferredReusableInternetHost(
        from host: String?,
        hubInstanceID _: String? = nil,
        lanDiscoveryName _: String? = nil
    ) -> String? {
        guard let host = normalizedNonEmpty(host) else { return nil }
        guard isFormalRemoteHost(host) else { return nil }
        return host
    }

    static func shouldTrustPairingInternetHost(
        pairingHost: String?,
        authoritativeHost: String?,
        pairingInternetHost: String?
    ) -> Bool {
        if let pairingInternetHost = normalizedNonEmpty(pairingInternetHost),
           isFormalRemoteHost(pairingInternetHost) {
            return true
        }
        guard let pairing = normalizedHostToken(pairingHost) else { return true }
        guard let authoritative = normalizedHostToken(authoritativeHost) else { return true }
        return pairing == authoritative
    }
}
