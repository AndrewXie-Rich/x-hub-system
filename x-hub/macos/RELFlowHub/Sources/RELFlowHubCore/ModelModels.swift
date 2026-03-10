import Foundation

public enum HubModelState: String, Codable, Sendable {
    case loaded
    case available
    case sleeping
}

public struct HubModel: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var backend: String
    public var quant: String
    public var contextLength: Int
    public var paramsB: Double
    // Optional routing hints (e.g. ["translate"], ["general"]).
    public var roles: [String]?
    public var state: HubModelState
    public var memoryBytes: Int64?
    public var tokensPerSec: Double?
    // Optional local model directory (for runtime workers). Kept optional for backward compatibility.
    public var modelPath: String?
    public var note: String?

    public init(
        id: String,
        name: String,
        backend: String,
        quant: String,
        contextLength: Int,
        paramsB: Double,
        roles: [String]? = nil,
        state: HubModelState,
        memoryBytes: Int64? = nil,
        tokensPerSec: Double? = nil,
        modelPath: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.quant = quant
        self.contextLength = contextLength
        self.paramsB = paramsB
        self.roles = roles
        self.state = state
        self.memoryBytes = memoryBytes
        self.tokensPerSec = tokensPerSec
        self.modelPath = modelPath
        self.note = note
    }
}

public struct ModelCatalogEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var backend: String
    public var quant: String
    public var contextLength: Int
    public var paramsB: Double
    public var modelPath: String
    public var roles: [String]?
    public var note: String?

    public init(
        id: String,
        name: String,
        backend: String = "mlx",
        quant: String = "bf16",
        contextLength: Int = 8192,
        paramsB: Double = 0.0,
        modelPath: String,
        roles: [String]? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.quant = quant
        self.contextLength = contextLength
        self.paramsB = paramsB
        self.modelPath = modelPath
        self.roles = roles
        self.note = note
    }
}

public struct ModelCatalogSnapshot: Codable, Sendable, Equatable {
    public var models: [ModelCatalogEntry]
    public var updatedAt: Double

    public init(models: [ModelCatalogEntry], updatedAt: Double) {
        self.models = models
        self.updatedAt = updatedAt
    }

    public static func empty() -> ModelCatalogSnapshot {
        ModelCatalogSnapshot(models: [], updatedAt: Date().timeIntervalSince1970)
    }
}

public enum ModelCatalogStorage {
    public static let fileName = "models_catalog.json"

    public static func url() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> ModelCatalogSnapshot {
        let url = url()
        if let data = try? Data(contentsOf: url) {
            // Support both {models: [...]} and legacy list format.
            if let obj = try? JSONDecoder().decode(ModelCatalogSnapshot.self, from: data) {
                return obj
            }
            if let arr = try? JSONDecoder().decode([ModelCatalogEntry].self, from: data) {
                return ModelCatalogSnapshot(models: arr, updatedAt: Date().timeIntervalSince1970)
            }
        }
        return .empty()
    }

    public static func save(_ snap: ModelCatalogSnapshot) {
        var cur = snap
        cur.updatedAt = Date().timeIntervalSince1970
        let url = url()
        if let data = try? JSONEncoder().encode(cur) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

public struct ModelStateSnapshot: Codable, Sendable, Equatable {
    public var models: [HubModel]
    public var updatedAt: Double

    public init(models: [HubModel], updatedAt: Double) {
        self.models = models
        self.updatedAt = updatedAt
    }

    public static func empty() -> ModelStateSnapshot {
        ModelStateSnapshot(models: [], updatedAt: Date().timeIntervalSince1970)
    }
}

public enum ModelStateStorage {
    public static let fileName = "models_state.json"

    public static func url() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> ModelStateSnapshot {
        let url = url()
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) {
            return obj
        }
        return .empty()
    }

    public static func save(_ state: ModelStateSnapshot) {
        let url = url()
        if let data = try? JSONEncoder().encode(state) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
