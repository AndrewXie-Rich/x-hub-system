import Foundation

public struct ModelBenchResult: Codable, Sendable, Equatable {
    public var modelId: String
    public var measuredAt: Double
    public var promptTokens: Int
    public var generationTokens: Int
    public var promptTPS: Double
    public var generationTPS: Double
    public var peakMemoryBytes: Int64
    public var runtimeVersion: String?

    public init(
        modelId: String,
        measuredAt: Double,
        promptTokens: Int,
        generationTokens: Int,
        promptTPS: Double,
        generationTPS: Double,
        peakMemoryBytes: Int64,
        runtimeVersion: String? = nil
    ) {
        self.modelId = modelId
        self.measuredAt = measuredAt
        self.promptTokens = promptTokens
        self.generationTokens = generationTokens
        self.promptTPS = promptTPS
        self.generationTPS = generationTPS
        self.peakMemoryBytes = peakMemoryBytes
        self.runtimeVersion = runtimeVersion
    }
}

public struct ModelsBenchSnapshot: Codable, Sendable, Equatable {
    public var results: [ModelBenchResult]
    public var updatedAt: Double

    public init(results: [ModelBenchResult], updatedAt: Double) {
        self.results = results
        self.updatedAt = updatedAt
    }

    public static func empty() -> ModelsBenchSnapshot {
        ModelsBenchSnapshot(results: [], updatedAt: Date().timeIntervalSince1970)
    }
}

public enum ModelBenchStorage {
    public static let fileName = "models_bench.json"

    public static func url() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> ModelsBenchSnapshot {
        let url = url()
        guard let data = try? Data(contentsOf: url) else {
            return .empty()
        }
        // Support both {results:[...]} and legacy list format.
        if let obj = try? JSONDecoder().decode(ModelsBenchSnapshot.self, from: data) {
            return obj
        }
        if let arr = try? JSONDecoder().decode([ModelBenchResult].self, from: data) {
            return ModelsBenchSnapshot(results: arr, updatedAt: Date().timeIntervalSince1970)
        }
        return .empty()
    }
}

