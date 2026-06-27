import Foundation
import Darwin
import RELFlowHubCore

struct LMStudioMarketResult: Identifiable, Equatable {
    var modelKey: String
    var title: String
    var summary: String
    var formatHint: String
    var capabilityTags: [String]
    var staffPick: Bool
    var recommendationReason: String
    var recommendedForThisMac: Bool
    var recommendedFitEstimation: String
    var recommendedSizeBytes: Int64
    var downloadIdentifier: String
    var downloaded: Bool
    var inLibrary: Bool

    var id: String { modelKey }
}

extension LMStudioMarketResult {
    func hasCapabilityTag(_ tag: String) -> Bool {
        capabilityTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    var recommendationHaystack: String {
        [
            modelKey,
            title,
            summary,
            capabilityTags.joined(separator: " "),
            formatHint,
        ]
            .joined(separator: " ")
            .lowercased()
    }
}

struct LMStudioDownloadedModelDescriptor: Identifiable, Equatable {
    var indexedModelIdentifier: String
    var displayName: String
    var defaultIdentifier: String
    var user: String
    var model: String
    var file: String
    var format: String
    var quantLabel: String
    var domain: String
    var contextLength: Int
    var directoryPath: String
    var entryPointPath: String
    var sourceDirectoryType: String
    var paramsB: Double

    var id: String {
        let preferred = indexedModelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty {
            return preferred
        }
        return [user, model, file].joined(separator: "/")
    }

    var modelPath: String {
        let directory = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !directory.isEmpty {
            return directory
        }
        return entryPointPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBundled: Bool {
        sourceDirectoryType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "bundled"
    }

    var isDirectoryModel: Bool {
        let path = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDirectory: ObjCBool = false
        return !path.isEmpty
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func matchesMarketKey(_ marketKey: String) -> Bool {
        LMStudioMarketBridge.marketKeyMatchesDescriptor(marketKey, descriptor: self)
    }
}

enum LMStudioMarketBridgeError: LocalizedError {
    case helperBinaryMissing
    case searchFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperBinaryMissing:
            return HubUIStrings.Models.MarketBridge.helperBinaryMissing
        case .searchFailed(let detail):
            return HubUIStrings.Models.MarketBridge.searchFailed(detail)
        case .downloadFailed(let detail):
            return HubUIStrings.Models.MarketBridge.downloadFailed(detail)
        }
    }
}

struct LMStudioCLIProcessResult {
    var stdout: String
    var stderr: String
    var timedOut: Bool
    var terminatedByCallback: Bool
    var terminationStatus: Int32

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct LMStudioSDKSearchEnvelope: Decodable {
    var results: [LMStudioSDKSearchResult]
}

struct LMStudioSDKSearchResult: Decodable {
    var modelKey: String
    var title: String
    var summary: String
    var formatHint: String
    var capabilityTags: [String]
    var staffPick: Bool?
    var recommendationReason: String?
    var recommendedForThisMac: Bool?
    var recommendedFitEstimation: String?
    var recommendedSizeBytes: Int64?
    var downloadIdentifier: String?
}

struct HuggingFaceModelRow: Decodable, Sendable {
    struct CardData: Decodable, Sendable {
        var tags: [String]?
        var model_name: String?
        var title: String?
        var summary: String?
        var description: String?
    }

    struct LFSInfo: Decodable, Sendable {
        var size: Int64?
    }

    struct Sibling: Decodable, Sendable {
        var rfilename: String?
        var path: String?
        var name: String?
        var size: Int64?
        var lfs: LFSInfo?
    }

    var id: String?
    var modelId: String?
    var modelKey: String?
    var name: String?
    var description: String?
    var downloads: Int?
    var likes: Int?
    var tags: [String]?
    var siblings: [Sibling]?
    var pipeline_tag: String?
    var pipelineTag: String?
    var cardData: CardData?
    var `private`: Bool?
    var gated: Bool?
}

struct HuggingFacePreparedSearchResult: Sendable {
    var result: LMStudioMarketResult
    var downloads: Int
    var likes: Int
}

struct MarketRecommendationBucket {
    var tag: String
    var weight: Int
}

struct LMStudioSDKHelperEvent: Decodable {
    var type: String
    var message: String?
    var defaultIdentifier: String?
}

struct LMStudioNodeLaunchConfig: Equatable {
    var executablePath: String
    var argumentsPrefix: [String]
}

final class LMStudioCLIOutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private(set) var terminatedByCallback = false

    func append(_ data: Data, toStdout: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        if toStdout {
            stdoutData.append(data)
        } else {
            stderrData.append(data)
        }
        return combinedOutputLocked()
    }

    func setTerminatedByCallback() {
        lock.lock()
        terminatedByCallback = true
        lock.unlock()
    }

    func stdoutString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stdoutData, encoding: .utf8) ?? ""
    }

    func stderrString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stderrData, encoding: .utf8) ?? ""
    }

    private func combinedOutputLocked() -> String {
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

final class LMStudioProcessBox: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }
}
