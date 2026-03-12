import Foundation

struct AIRuntimeStatus: Codable, Equatable {
    var pid: Int
    var updatedAt: Double
    var mlxOk: Bool
    var runtimeVersion: String?
    var importError: String?
    var activeMemoryBytes: Int64?
    var peakMemoryBytes: Int64?
    var loadedModelCount: Int?

    func isAlive(ttl: Double = 3.0) -> Bool {
        (Date().timeIntervalSince1970 - updatedAt) < ttl
    }
}

enum HubModelState: String, Codable {
    case loaded
    case available
    case sleeping
}

struct HubModel: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var backend: String
    var quant: String
    var contextLength: Int
    var paramsB: Double
    var roles: [String]?
    var state: HubModelState
    var memoryBytes: Int64?
    var tokensPerSec: Double?
    var modelPath: String?
    var note: String?
}

struct ModelStateSnapshot: Codable, Equatable {
    var models: [HubModel]
    var updatedAt: Double

    static func empty() -> ModelStateSnapshot {
        ModelStateSnapshot(models: [], updatedAt: Date().timeIntervalSince1970)
    }
}

struct HubAIRequest: Codable {
    var type: String = "generate"
    var req_id: String
    var app_id: String
    var task_type: String
    var preferred_model_id: String?
    var model_id: String?
    var prompt: String
    var max_tokens: Int
    var temperature: Double
    var top_p: Double
    var created_at: Double
    var auto_load: Bool
}

struct HubAIResponseEvent: Codable {
    var type: String
    var req_id: String
    var ok: Bool?
    var reason: String?
    var text: String?
    var seq: Int?
    var model_id: String?
    var task_type: String?
    var promptTokens: Int?
    var generationTokens: Int?
    var generationTPS: Double?

    // Future-proof: keep any extra fields.
    var raw: [String: JSONValue]?

    init(
        type: String,
        req_id: String,
        ok: Bool? = nil,
        reason: String? = nil,
        text: String? = nil,
        seq: Int? = nil,
        model_id: String? = nil,
        task_type: String? = nil,
        promptTokens: Int? = nil,
        generationTokens: Int? = nil,
        generationTPS: Double? = nil,
        raw: [String: JSONValue]? = nil
    ) {
        self.type = type
        self.req_id = req_id
        self.ok = ok
        self.reason = reason
        self.text = text
        self.seq = seq
        self.model_id = model_id
        self.task_type = task_type
        self.promptTokens = promptTokens
        self.generationTokens = generationTokens
        self.generationTPS = generationTPS
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        req_id = (try? c.decode(String.self, forKey: .req_id)) ?? ""
        ok = try? c.decodeIfPresent(Bool.self, forKey: .ok)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        seq = try? c.decodeIfPresent(Int.self, forKey: .seq)
        model_id = try? c.decodeIfPresent(String.self, forKey: .model_id)
        task_type = try? c.decodeIfPresent(String.self, forKey: .task_type)
        promptTokens = try? c.decodeIfPresent(Int.self, forKey: .promptTokens)
        generationTokens = try? c.decodeIfPresent(Int.self, forKey: .generationTokens)
        generationTPS = try? c.decodeIfPresent(Double.self, forKey: .generationTPS)

        // Decode full payload as a dictionary of JSONValue.
        let any = try decoder.singleValueContainer()
        raw = (try? any.decode([String: JSONValue].self))
    }

    enum CodingKeys: String, CodingKey {
        case type
        case req_id
        case ok
        case reason
        case text
        case seq
        case model_id
        case task_type
        case promptTokens
        case generationTokens
        case generationTPS
    }

    var requestedModelIdFromMetadata: String? {
        metadataString("requested_model_id")
            ?? metadataString("preferred_model_id")
            ?? metadataString("requestedModelId")
    }

    var actualModelIdFromMetadata: String? {
        metadataString("actual_model_id")
            ?? metadataString("resolved_model_id")
            ?? metadataString("actualModelId")
            ?? model_id
    }

    var runtimeProviderFromMetadata: String? {
        metadataString("runtime_provider")
            ?? metadataString("provider")
    }

    var executionPathFromMetadata: String? {
        metadataString("execution_path")
    }

    var fallbackReasonCodeFromMetadata: String? {
        metadataString("fallback_reason_code")
            ?? metadataString("failure_reason_code")
    }

    private func metadataString(_ key: String) -> String? {
        raw?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HubAIUsage: Equatable {
    var promptTokens: Int
    var generationTokens: Int
    var generationTPS: Double
    var requestedModelId: String?
    var actualModelId: String?
    var runtimeProvider: String?
    var executionPath: String?
    var fallbackReasonCode: String?
}

// Minimal JSON representation to preserve unknown fields.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var obj: [String: JSONValue] = [:]
            for k in c.allKeys {
                obj[k.stringValue] = (try? c.decode(JSONValue.self, forKey: k)) ?? .null
            }
            self = .object(obj)
            return
        }
        if var a = try? decoder.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !a.isAtEnd {
                arr.append((try? a.decode(JSONValue.self)) ?? .null)
            }
            self = .array(arr)
            return
        }
        let s = try decoder.singleValueContainer()
        if s.decodeNil() { self = .null; return }
        if let b = try? s.decode(Bool.self) { self = .bool(b); return }
        if let n = try? s.decode(Double.self) { self = .number(n); return }
        if let str = try? s.decode(String.self) { self = .string(str); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .number(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .bool(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .object(let o):
            var c = encoder.container(keyedBy: DynamicCodingKey.self)
            for (k, v) in o {
                try c.encode(v, forKey: DynamicCodingKey(k))
            }
        case .array(let a):
            var c = encoder.unkeyedContainer()
            for v in a { try c.encode(v) }
        case .null:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        }
    }

    struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? = nil
        init(_ s: String) { self.stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

extension JSONValue {
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }
}
