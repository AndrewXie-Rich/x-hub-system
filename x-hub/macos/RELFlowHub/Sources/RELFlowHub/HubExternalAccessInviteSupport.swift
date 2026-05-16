import Foundation

enum HubExternalAccessInviteSupport {
    static func normalizedExternalHubAlias(_ raw: String?) -> String? {
        let trimmed = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard normalized.range(of: #"^[a-z0-9][a-z0-9-]{2,62}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }

    static func normalizedStableNamedExternalHost(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if lowered == "localhost" || lowered == "127.0.0.1" || lowered.hasSuffix(".local") {
            return nil
        }
        if isIPv4Host(lowered) {
            return nil
        }
        return trimmed
    }

    static func normalizedSecureRemoteHost(_ raw: String?, allowPrivateVPNIP: Bool = false) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let stableHost = normalizedStableNamedExternalHost(trimmed) {
            return stableHost
        }
        let lowered = trimmed.lowercased()
        if isCarrierGradeNatIPv4Host(lowered) || (allowPrivateVPNIP && isPrivateIPv4Host(lowered)) {
            return trimmed
        }
        return nil
    }

    static func normalizedInviteHost(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if lowered == "localhost" || lowered == "127.0.0.1" {
            return nil
        }
        return trimmed
    }

    static func preferredExternalHubAlias(
        override rawOverride: String,
        bonjourMetadata: HubBonjourAdvertiser.Metadata?,
        externalHost: String?
    ) -> String? {
        if let alias = normalizedExternalHubAlias(rawOverride) {
            return alias
        }
        if let alias = normalizedExternalHubAlias(bonjourMetadata?.lanDiscoveryName) {
            return alias
        }
        if let host = normalizedStableNamedExternalHost(externalHost) {
            let firstLabel = host.split(separator: ".").first.map(String.init)
            if let alias = normalizedExternalHubAlias(firstLabel) {
                return alias
            }
            return normalizedExternalHubAlias(host.replacingOccurrences(of: ".", with: "-"))
        }
        return nil
    }

    static func externalInviteURL(
        alias: String?,
        externalHost: String?,
        inviteToken: String?,
        pairingPort: Int,
        grpcPort: Int,
        hubInstanceID: String?
    ) -> URL? {
        guard let host = normalizedInviteHost(externalHost),
              let inviteToken = normalizedNonEmpty(inviteToken) else { return nil }

        var components = URLComponents()
        components.scheme = "xterminal"
        components.host = "pair-hub"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "hub_host", value: host),
            URLQueryItem(name: "pairing_port", value: String(max(1, min(65_535, pairingPort)))),
            URLQueryItem(name: "grpc_port", value: String(max(1, min(65_535, grpcPort)))),
            URLQueryItem(name: "invite_token", value: inviteToken),
        ]
        if let alias = normalizedExternalHubAlias(alias) {
            queryItems.append(URLQueryItem(name: "hub_alias", value: alias))
        }
        if let hubInstanceID = normalizedNonEmpty(hubInstanceID) {
            queryItems.append(URLQueryItem(name: "hub_instance_id", value: hubInstanceID))
        }
        components.queryItems = queryItems
        return components.url
    }

    static func externalInviteUnavailableReason(
        externalHost: String?,
        hasInviteToken: Bool
    ) -> String {
        if normalizedInviteHost(externalHost) == nil {
            return HubUIStrings.Settings.GRPC.inviteLinkNeedsStableHost
        }
        if !hasInviteToken {
            return HubUIStrings.Settings.GRPC.inviteLinkAutoGeneratesToken
        }
        return HubUIStrings.Settings.GRPC.inviteLinkRejectsRawIP
    }

    private static func normalizedNonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isIPv4Host(_ host: String) -> Bool {
        ipv4Octets(host) != nil
    }

    private static func isCarrierGradeNatIPv4Host(_ host: String) -> Bool {
        guard let octets = ipv4Octets(host) else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    private static func isPrivateIPv4Host(_ host: String) -> Bool {
        guard let octets = ipv4Octets(host) else { return false }
        let first = octets[0]
        let second = octets[1]
        if first == 10 {
            return true
        }
        if first == 172 && (16...31).contains(second) {
            return true
        }
        if first == 192 && second == 168 {
            return true
        }
        return false
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return nil }
        guard octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return octets
    }
}
