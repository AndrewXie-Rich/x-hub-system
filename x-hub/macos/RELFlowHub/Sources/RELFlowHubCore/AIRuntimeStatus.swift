import Foundation

public struct AIRuntimeStatus: Codable, Sendable, Equatable {
    public var pid: Int
    public var updatedAt: Double
    public var mlxOk: Bool
    public var runtimeVersion: String?
    public var importError: String?
    // MLX memory (bytes). More accurate than RSS for capacity.
    public var activeMemoryBytes: Int64?
    public var peakMemoryBytes: Int64?
    public var loadedModelCount: Int?

    public init(
        pid: Int,
        updatedAt: Double,
        mlxOk: Bool,
        runtimeVersion: String? = nil,
        importError: String? = nil,
        activeMemoryBytes: Int64? = nil,
        peakMemoryBytes: Int64? = nil,
        loadedModelCount: Int? = nil
    ) {
        self.pid = pid
        self.updatedAt = updatedAt
        self.mlxOk = mlxOk
        self.runtimeVersion = runtimeVersion
        self.importError = importError
        self.activeMemoryBytes = activeMemoryBytes
        self.peakMemoryBytes = peakMemoryBytes
        self.loadedModelCount = loadedModelCount
    }

    enum CodingKeys: String, CodingKey {
        case pid
        case updatedAt
        case mlxOk
        case runtimeVersion
        case importError
        case activeMemoryBytes
        case peakMemoryBytes
        case loadedModelCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pid = (try? c.decode(Int.self, forKey: .pid)) ?? 0
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        mlxOk = (try? c.decode(Bool.self, forKey: .mlxOk)) ?? false
        runtimeVersion = try? c.decodeIfPresent(String.self, forKey: .runtimeVersion)
        importError = try? c.decodeIfPresent(String.self, forKey: .importError)
        activeMemoryBytes = try? c.decodeIfPresent(Int64.self, forKey: .activeMemoryBytes)
        peakMemoryBytes = try? c.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes)
        loadedModelCount = try? c.decodeIfPresent(Int.self, forKey: .loadedModelCount)
    }

    public func isAlive(ttl: Double = 3.0) -> Bool {
        (Date().timeIntervalSince1970 - updatedAt) < ttl
    }
}

public enum AIRuntimeStatusStorage {
    public static let fileName = "ai_runtime_status.json"

    public static func url() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> AIRuntimeStatus? {
        let url = url()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AIRuntimeStatus.self, from: data)
    }
}
