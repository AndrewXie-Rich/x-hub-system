import Foundation

enum XTCoreProjectionEnvelopeError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedProtocol(String)
    case payloadMustBeObject
    case authorityMustBeObject

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocol(let value):
            return "Unsupported XT core projection protocol: \(value)"
        case .payloadMustBeObject:
            return "XT core projection payload must be a JSON object."
        case .authorityMustBeObject:
            return "XT core projection authority metadata must be a JSON object."
        }
    }
}

enum XTCoreProjectionSurface: String, Codable, Equatable, Sendable {
    case projectSidebar = "project_sidebar"
    case settingsDiagnostics = "settings_diagnostics"
}

struct XTCoreProjectionEnvelope: Decodable, Equatable, Sendable {
    static let supportedProtocol = "xt-core-projection.v1"

    var protocolVersion: String
    var surface: XTCoreProjectionSurface
    var revision: Int
    var generatedAtMs: Int64
    var source: String
    var authority: [String: JSONValue]
    var payload: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case surface
        case revision
        case generatedAtMs = "generated_at_ms"
        case source
        case authority
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        protocolVersion = try container.decode(String.self, forKey: .protocolVersion)
        guard protocolVersion == Self.supportedProtocol else {
            throw XTCoreProjectionEnvelopeError.unsupportedProtocol(protocolVersion)
        }

        surface = try container.decode(XTCoreProjectionSurface.self, forKey: .surface)
        revision = try container.decode(Int.self, forKey: .revision)
        generatedAtMs = try container.decode(Int64.self, forKey: .generatedAtMs)
        source = (try? container.decode(String.self, forKey: .source)) ?? ""

        let authorityValue = (try? container.decode(JSONValue.self, forKey: .authority)) ?? .object([:])
        guard let authorityObject = authorityValue.objectValue else {
            throw XTCoreProjectionEnvelopeError.authorityMustBeObject
        }
        authority = authorityObject

        let payloadValue = try container.decode(JSONValue.self, forKey: .payload)
        guard let payloadObject = payloadValue.objectValue else {
            throw XTCoreProjectionEnvelopeError.payloadMustBeObject
        }
        payload = payloadObject
    }

    func decodePayload<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let data = try JSONEncoder().encode(JSONValue.object(payload))
        return try decoder.decode(type, from: data)
    }
}
