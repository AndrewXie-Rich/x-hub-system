import Foundation

enum RELFlowHubActionURLBuilder {
    static func providerKeysSettingsURL(sourceRef: String? = nil) -> URL? {
        let normalizedSourceRef = normalized(sourceRef)

        var components = URLComponents()
        components.scheme = "relflowhub"
        components.host = "settings"
        components.path = "/provider-keys"

        if let normalizedSourceRef {
            components.queryItems = [
                URLQueryItem(name: "source_ref", value: normalizedSourceRef)
            ]
        } else {
            components.queryItems = nil
        }

        return components.url
    }

    private static func normalized(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
