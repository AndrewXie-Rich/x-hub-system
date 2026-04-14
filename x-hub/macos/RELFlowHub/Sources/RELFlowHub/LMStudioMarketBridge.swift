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

private extension LMStudioMarketResult {
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
        return !path.isEmpty && FileManager.default.directoryExists(atPath: path)
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

private struct LMStudioCLIProcessResult {
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

private struct LMStudioSDKSearchEnvelope: Decodable {
    var results: [LMStudioSDKSearchResult]
}

private struct LMStudioSDKSearchResult: Decodable {
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

private struct HuggingFaceModelRow: Decodable, Sendable {
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

private struct HuggingFacePreparedSearchResult: Sendable {
    var result: LMStudioMarketResult
    var downloads: Int
    var likes: Int
}

private struct MarketRecommendationBucket {
    var tag: String
    var weight: Int
}

private struct LMStudioSDKHelperEvent: Decodable {
    var type: String
    var message: String?
    var defaultIdentifier: String?
}

private struct LMStudioNodeLaunchConfig: Equatable {
    var executablePath: String
    var argumentsPrefix: [String]
}

private final class LMStudioCLIOutputAccumulator: @unchecked Sendable {
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

private final class LMStudioProcessBox: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }
}

enum LMStudioMarketBridge {
    private static let huggingFaceBaseURL = "https://huggingface.co"
    private static let huggingFaceFallbackBaseURLs = ["https://hf-mirror.com"]
    private static let huggingFaceBasePreferenceFileName = "huggingface_base_preference.json"
    private static let defaultDiscoverQueries = ["vision", "coder", "embedding", "voice", "qwen", "llama", "glm"]
    private static let categoryQueryExpansions: [String: [String]] = [
        "chat": ["chat", "instruct", "assistant", "qwen", "llama", "glm"],
        "vision": ["vision", "vl", "llava", "glm-4.6v", "qwen2-vl", "qwen3-vl", "florence", "ocr", "image"],
        "ocr": ["ocr", "document", "trocr", "donut", "florence"],
        "coding": ["coder", "coding", "code", "qwen-coder", "deepseek-coder"],
        "embedding": ["embedding", "embed", "bge", "gte", "qwen-embedding"],
        "voice": ["tts", "voice", "text-to-speech", "kokoro", "melo", "parler", "bark", "speecht5", "f5-tts", "cosyvoice"],
        "speech": ["speech", "audio", "asr", "whisper"],
    ]
    private static let categoryQueryAliases: [String: String] = [
        "assistant": "chat",
        "chat": "chat",
        "general": "chat",
        "instruct": "chat",
        "llm": "chat",
        "text": "chat",
        "asr": "speech",
        "audio": "speech",
        "speech": "speech",
        "tts": "voice",
        "text-to-speech": "voice",
        "speech-synthesis": "voice",
        "speechsynthesis": "voice",
        "transcribe": "speech",
        "transcription": "speech",
        "voice": "voice",
        "kokoro": "voice",
        "melo": "voice",
        "parler": "voice",
        "parler-tts": "voice",
        "bark": "voice",
        "speecht5": "voice",
        "f5-tts": "voice",
        "f5tts": "voice",
        "cosyvoice": "voice",
        "chattts": "voice",
        "whisper": "speech",
        "code": "coding",
        "coder": "coding",
        "coding": "coding",
        "dev": "coding",
        "programming": "coding",
        "document": "ocr",
        "doc": "ocr",
        "ocr": "ocr",
        "pdf": "ocr",
        "scan": "ocr",
        "embed": "embedding",
        "embedding": "embedding",
        "embeddings": "embedding",
        "rerank": "embedding",
        "retrieval": "embedding",
        "vector": "embedding",
        "image": "vision",
        "images": "vision",
        "multimodal": "vision",
        "photo": "vision",
        "vision": "vision",
        "vl": "vision",
        "vlm": "vision",
    ]
    private static let categoryTagFilters: [String: Set<String>] = [
        "chat": ["Text"],
        "vision": ["Vision", "OCR"],
        "ocr": ["OCR"],
        "coding": ["Coding"],
        "embedding": ["Embedding"],
        "voice": ["Voice"],
        "speech": ["Speech"],
    ]
    private static let curatedRecommendationBucketsBase: [MarketRecommendationBucket] = [
        MarketRecommendationBucket(tag: "Text", weight: 6),
        MarketRecommendationBucket(tag: "Coding", weight: 4),
        MarketRecommendationBucket(tag: "Embedding", weight: 4),
    ]
    private static let curatedRecommendationBucketsHelper: [MarketRecommendationBucket] = [
        MarketRecommendationBucket(tag: "Vision", weight: 4),
        MarketRecommendationBucket(tag: "Voice", weight: 3),
        MarketRecommendationBucket(tag: "OCR", weight: 2),
    ]
    private static let repoExcludeTags: Set<String> = ["gguf", "onnx", "diffusers"]
    private static let discoveryTimeout: TimeInterval = 8.0
    private static let terminalEscapeRegex = try? NSRegularExpression(
        pattern: #"\u{001B}\[[0-?]*[ -/]*[@-~]"#,
        options: []
    )
    private static let nonPrintableControlRegex = try? NSRegularExpression(
        pattern: #"[\u{0000}-\u{0008}\u{000B}\u{000C}\u{000E}-\u{001F}\u{007F}]"#,
        options: []
    )
    private static let modelKeySearchRegex = try? NSRegularExpression(
        pattern: #"([A-Za-z0-9._-]+/[A-Za-z0-9._:+-]+)"#,
        options: []
    )
    private static let matchingStopWords: Set<String> = [
        "mlx",
        "gguf",
        "model",
        "models",
        "local",
        "hub",
        "4bit",
        "8bit",
        "bf16",
        "fp16",
        "fp32",
        "q4",
        "q8",
    ]

    static func helperBinaryPath() -> String {
        LocalHelperBridgeDiscovery.discoverHelperBinary()
    }

    static func lmStudioHomeDirectory(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default
    ) -> URL {
        let pointerURL = homeDirectory.appendingPathComponent(".lmstudio-home-pointer")
        if let rawPointer = try? String(contentsOf: pointerURL, encoding: .utf8) {
            let pointedPath = rawPointer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pointedPath.isEmpty {
                let pointedURL = URL(fileURLWithPath: pointedPath, isDirectory: true).standardizedFileURL
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: pointedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return pointedURL
                }
            }
        }
        return homeDirectory
            .appendingPathComponent(".lmstudio", isDirectory: true)
            .standardizedFileURL
    }

    static func legacyDownloadedModelsDirectory(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default
    ) -> URL {
        lmStudioHomeDirectory(homeDirectory: homeDirectory, fileManager: fileManager)
            .appendingPathComponent("models", isDirectory: true)
    }

    static func marketDownloadedModelsDirectory(
        baseDir: URL = SharedPaths.ensureHubDirectory()
    ) -> URL {
        LocalModelManagedStorage.managedModelsDirectory(baseDir: baseDir)
            .appendingPathComponent("_market", isDirectory: true)
    }

    static func downloadedModelsDisplayPath(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) -> String {
        let homePath = homeDirectory.standardizedFileURL.path
        let downloadsPath = marketDownloadedModelsDirectory(baseDir: baseDir).standardizedFileURL.path
        guard downloadsPath.hasPrefix(homePath) else { return downloadsPath }
        let suffix = String(downloadsPath.dropFirst(homePath.count))
        return "~" + suffix
    }

    static func searchModels(
        query: String,
        category: String = "",
        limit: Int = 12
    ) async throws -> [LMStudioMarketResult] {
        do {
            return try searchModelsViaSDKHelper(query: query, category: category, limit: limit)
        } catch let helperError {
            do {
                return try await searchModelsViaURLSession(query: query, category: category, limit: limit)
            } catch let fallbackError {
                let helperMessage = helperError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackMessage = fallbackError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallbackMessage.isEmpty, helperMessage != fallbackMessage {
                    throw LMStudioMarketBridgeError.searchFailed(
                        HubUIStrings.Models.MarketBridge.helperFallbackDetail(
                            fallback: fallbackMessage,
                            helper: helperMessage
                        )
                    )
                }
                throw fallbackError
            }
        }
    }

    static func downloadRecommended(
        modelKey: String,
        downloadIdentifier: String? = nil,
        progress: @escaping @Sendable (String) -> Void
    ) throws {
        let key = modelKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw LMStudioMarketBridgeError.downloadFailed(HubUIStrings.Models.MarketBridge.missingModelKey)
        }
        try downloadRecommendedViaSDKHelper(
            modelKey: key,
            downloadIdentifier: downloadIdentifier,
            progress: progress
        )
    }

    static func loadDownloadedModels(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) -> [LMStudioDownloadedModelDescriptor] {
        var descriptors: [LMStudioDownloadedModelDescriptor] = []
        descriptors.append(
            contentsOf: fallbackDownloadedDescriptorsFromManagedMarket(
                baseDir: baseDir,
                fileManager: fileManager
            )
        )
        let cacheURL = lmStudioHomeDirectory(
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
            .appendingPathComponent(".internal", isDirectory: true)
            .appendingPathComponent("model-index-cache.json")
        if let data = try? Data(contentsOf: cacheURL),
           let payload = try? JSONSerialization.jsonObject(with: data, options: []),
           let root = payload as? [String: Any],
           let rows = root["models"] as? [[String: Any]] {
            descriptors.append(contentsOf: rows.compactMap(downloadedDescriptor(from:)))
        }

        descriptors.append(
            contentsOf: fallbackDownloadedDescriptorsFromFilesystem(
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        )

        return mergedDownloadedDescriptors(descriptors)
            .sorted { lhs, rhs in
                if lhs.isBundled != rhs.isBundled {
                    return !lhs.isBundled
                }
                if lhs.displayName != rhs.displayName {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }

    static func catalogEntries(
        from downloadedModels: [LMStudioDownloadedModelDescriptor],
        helperBinaryPath: String = helperBinaryPath()
    ) -> [ModelCatalogEntry] {
        downloadedModels.compactMap { descriptor in
            catalogEntry(from: descriptor, helperBinaryPath: helperBinaryPath)
        }
    }

    private static func searchModelsViaURLSession(
        query: String,
        category: String,
        limit: Int
    ) async throws -> [LMStudioMarketResult] {
        let requestedLimit = max(1, min(25, limit))
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = normalizeCapabilityToken(category)
        let searchTerms = expandedSearchTerms(for: trimmedQuery, category: normalizedCategory)
        let categoryTagFilter = categoryTagFilter(for: trimmedQuery, category: normalizedCategory)
        let perQueryLimit = trimmedQuery.isEmpty
            ? max(4, min(10, requestedLimit))
            : max(6, min(12, requestedLimit * 2))

        let searchResponses = await withTaskGroup(of: Result<[HuggingFaceModelRow], Error>.self) { group in
            for term in searchTerms {
                group.addTask {
                    do {
                        return .success(try await fetchHuggingFaceRows(for: term, limit: perQueryLimit))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var responses: [Result<[HuggingFaceModelRow], Error>] = []
            for await result in group {
                responses.append(result)
            }
            return responses
        }

        var rawCandidates: [HuggingFaceModelRow] = []
        var firstError: Error?
        for response in searchResponses {
            switch response {
            case .success(let rows):
                rawCandidates.append(contentsOf: rows)
            case .failure(let error):
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if rawCandidates.isEmpty {
            throw firstError ?? LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.huggingFaceCatalogUnavailable)
        }

        var deduped: [HuggingFaceModelRow] = []
        var seen = Set<String>()
        for candidate in rawCandidates {
            let repoID = huggingFaceRepoID(for: candidate)
            guard !repoID.isEmpty, !seen.contains(repoID) else { continue }
            seen.insert(repoID)
            deduped.append(candidate)
        }

        let maxCandidates = min(deduped.count, max(requestedLimit * 3, requestedLimit + 8))
        let candidates = Array(deduped.prefix(maxCandidates))
        let detailResponses = await withTaskGroup(of: (Int, HuggingFaceModelRow).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let detailed = (try? await fetchHuggingFaceModelDetail(for: candidate)) ?? candidate
                    return (index, detailed)
                }
            }

            var rows = Array(repeating: HuggingFaceModelRow(), count: candidates.count)
            for await (index, row) in group {
                rows[index] = row
            }
            return rows
        }

        let focusCategory = resolvedDiscoverCategory(for: normalizedCategory.isEmpty ? trimmedQuery : normalizedCategory)
        let prepared = zip(candidates, detailResponses).compactMap { candidate, detailed -> HuggingFacePreparedSearchResult? in
            preparedSearchResult(from: mergeHuggingFaceRows(base: candidate, detailed: detailed))
        }
            .filter { prepared in
                guard let categoryTagFilter else { return true }
                return prepared.result.capabilityTags.contains(where: categoryTagFilter.contains)
            }
            .sorted { lhs, rhs in
                let lhsScore = preparedSortScore(lhs, focusCategory: focusCategory)
                let rhsScore = preparedSortScore(rhs, focusCategory: focusCategory)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.result.title.localizedCaseInsensitiveCompare(rhs.result.title) == .orderedAscending
            }

        let sortedResults = prepared.map(\.result)
        if trimmedQuery.isEmpty, focusCategory == nil {
            return curatedRecommendedResults(from: sortedResults, limit: requestedLimit)
        }
        return Array(sortedResults.prefix(requestedLimit))
    }

    private static func fetchHuggingFaceRows(
        for term: String,
        limit: Int
    ) async throws -> [HuggingFaceModelRow] {
        var lastError: Error?
        for baseURLString in huggingFaceBaseURLStrings() {
            guard let url = huggingFaceSearchURL(baseURLString: baseURLString, for: term, limit: limit) else {
                continue
            }
            do {
                let rows = try await fetchHuggingFaceJSON([HuggingFaceModelRow].self, from: url)
                persistStoredHuggingFaceBaseURLString(baseURLString)
                return rows
            } catch {
                lastError = error
            }
        }
        throw lastError ?? LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.huggingFaceRequestBuildFailed)
    }

    private static func fetchHuggingFaceModelDetail(
        for row: HuggingFaceModelRow
    ) async throws -> HuggingFaceModelRow {
        if let siblings = row.siblings, !siblings.isEmpty {
            return row
        }
        let repoID = huggingFaceRepoID(for: row)
        guard !repoID.isEmpty else {
            return row
        }
        var lastError: Error?
        for baseURLString in huggingFaceBaseURLStrings() {
            guard let url = huggingFaceModelInfoURL(baseURLString: baseURLString, repoID: repoID) else {
                continue
            }
            do {
                let detail = try await fetchHuggingFaceJSON(HuggingFaceModelRow.self, from: url)
                persistStoredHuggingFaceBaseURLString(baseURLString)
                return detail
            } catch {
                lastError = error
            }
        }
        if let lastError {
            throw lastError
        }
        return row
    }

    private static func fetchHuggingFaceJSON<T: Decodable>(
        _ type: T.Type,
        from url: URL
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = discoveryTimeout
        request.setValue("X-Hub/1.0 (local-model-market)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = huggingFaceToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(configuration: .ephemeral)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw humanizedHuggingFaceNetworkError(error, host: url.host ?? "huggingface.co")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.invalidHuggingFaceResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw humanizedHuggingFaceStatusError(
                statusCode: httpResponse.statusCode,
                data: data,
                host: url.host ?? "huggingface.co"
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.invalidHuggingFacePayload)
        }
    }

    private static func configuredHuggingFaceBaseURLString() -> String {
        let environment = ProcessInfo.processInfo.environment
        let configured = (
            environment["XHUB_HF_BASE_URL"]
            ?? environment["HF_ENDPOINT"]
            ?? environment["HUGGINGFACE_HUB_ENDPOINT"]
            ?? ""
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
    }

    static func storedHuggingFaceBaseURLString(
        baseDir: URL = SharedPaths.ensureHubDirectory()
    ) -> String {
        let url = baseDir.appendingPathComponent(huggingFaceBasePreferenceFileName)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let payload = object as? [String: Any] else {
            return ""
        }
        let preferred = (payload["preferredBaseURL"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preferred.isEmpty else { return "" }
        return preferred.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
    }

    @discardableResult
    static func persistStoredHuggingFaceBaseURLString(
        _ rawValue: String,
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) -> String {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        let url = baseDir.appendingPathComponent(huggingFaceBasePreferenceFileName)
        if normalized.isEmpty {
            try? fileManager.removeItem(at: url)
            return ""
        }

        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "preferredBaseURL": normalized,
            "updatedAt": Date().timeIntervalSince1970,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: url, options: [.atomic])
        }
        return normalized
    }

    static func resolvedHuggingFaceBaseURLStrings(
        preferred: String? = nil,
        configured: String? = nil,
        stored: String? = nil
    ) -> [String] {
        let candidates = [
            preferred?.trimmingCharacters(in: .whitespacesAndNewlines),
            configured?.trimmingCharacters(in: .whitespacesAndNewlines),
            stored?.trimmingCharacters(in: .whitespacesAndNewlines),
            huggingFaceBaseURL,
        ] + huggingFaceFallbackBaseURLs

        var ordered: [String] = []
        for candidate in candidates {
            let normalized = (candidate ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
            guard !normalized.isEmpty else { continue }
            if !ordered.contains(normalized) {
                ordered.append(normalized)
            }
        }
        return ordered
    }

    private static func huggingFaceBaseURLStrings(
        preferred: String? = nil
    ) -> [String] {
        resolvedHuggingFaceBaseURLStrings(
            preferred: preferred,
            configured: configuredHuggingFaceBaseURLString(),
            stored: storedHuggingFaceBaseURLString()
        )
    }

    private static func huggingFaceSearchURL(
        baseURLString: String,
        for term: String,
        limit: Int
    ) -> URL? {
        guard let baseURL = URL(string: baseURLString) else { return nil }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "api", "models"].filter { !$0.isEmpty }).joined(separator: "/")
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "sort", value: "downloads"),
            .init(name: "direction", value: "-1"),
        ]
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(.init(name: "search", value: trimmed))
        }
        components.queryItems = items
        return components.url
    }

    private static func huggingFaceModelInfoURL(
        baseURLString: String,
        repoID: String
    ) -> URL? {
        guard let baseURL = URL(string: baseURLString),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let encoded = repoID
            .split(separator: "/")
            .map { part in
                String(part).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(part)
            }
            .joined(separator: "/")
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "api", "models", encoded].filter { !$0.isEmpty }).joined(separator: "/")
        components.queryItems = [
            .init(name: "blobs", value: "true")
        ]
        return components.url
    }

    private static func huggingFaceToken() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let envCandidates = [
            environment["HF_TOKEN"],
            environment["HUGGING_FACE_HUB_TOKEN"],
            environment["XHUB_HF_TOKEN"],
        ]
        for candidate in envCandidates {
            let token = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                return token
            }
        }

        let home = SharedPaths.realHomeDirectory()
        let fileCandidates = [
            home.appendingPathComponent(".cache/huggingface/token"),
            home.appendingPathComponent(".huggingface/token"),
        ]
        for candidate in fileCandidates {
            if let token = try? String(contentsOf: candidate, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !token.isEmpty {
                return token
            }
        }
        return nil
    }

    private static func humanizedHuggingFaceNetworkError(
        _ error: Error,
        host: String
    ) -> Error {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return LMStudioMarketBridgeError.searchFailed(
                    HubUIStrings.Models.MarketBridge.huggingFaceTimedOut(host)
                )
            case .cannotFindHost, .dnsLookupFailed:
                return LMStudioMarketBridgeError.searchFailed(
                    HubUIStrings.Models.MarketBridge.huggingFaceDNS(host)
                )
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return LMStudioMarketBridgeError.searchFailed(
                    HubUIStrings.Models.MarketBridge.huggingFaceConnection(host)
                )
            default:
                break
            }
        }
        return LMStudioMarketBridgeError.searchFailed(error.localizedDescription)
    }

    private static func humanizedHuggingFaceStatusError(
        statusCode: Int,
        data: Data,
        host: String
    ) -> Error {
        var parsedMessage = ""
        if let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = object as? [String: Any] {
            parsedMessage = stringValue(dict["error"]).isEmpty
                ? stringValue(dict["message"])
                : stringValue(dict["error"])
        }

        switch statusCode {
        case 401, 403:
            return LMStudioMarketBridgeError.searchFailed(
                parsedMessage.isEmpty
                    ? HubUIStrings.Models.MarketBridge.huggingFaceAuthRequired
                    : parsedMessage
            )
        case 429:
            return LMStudioMarketBridgeError.searchFailed(
                parsedMessage.isEmpty
                    ? HubUIStrings.Models.MarketBridge.huggingFaceRateLimited
                    : parsedMessage
            )
        default:
            let message = parsedMessage.isEmpty
                ? HubUIStrings.Models.MarketBridge.huggingFaceStatus(statusCode: statusCode, host: host)
                : parsedMessage
            return LMStudioMarketBridgeError.searchFailed(message)
        }
    }

    static func expandedSearchTerms(
        for query: String,
        category: String
    ) -> [String] {
        let normalizedQuery = normalizeCapabilityToken(query)
        if !normalizedQuery.isEmpty {
            if let resolvedCategory = resolvedDiscoverCategory(for: normalizedQuery),
               let queries = categoryQueryExpansions[resolvedCategory],
               !queries.isEmpty {
                return uniqueSearchTerms([query] + queries)
            }
            return [query]
        }
        if let resolvedCategory = resolvedDiscoverCategory(for: category),
           let categoryQueries = categoryQueryExpansions[resolvedCategory],
           !categoryQueries.isEmpty {
            return categoryQueries
        }
        return defaultDiscoverQueries
    }

    static func categoryTagFilter(
        for query: String,
        category: String
    ) -> Set<String>? {
        if let resolvedCategory = resolvedDiscoverCategory(for: category),
           let filter = categoryTagFilters[resolvedCategory] {
            return filter
        }
        if let resolvedQuery = resolvedDiscoverCategory(for: query) {
            return categoryTagFilters[resolvedQuery]
        }
        let normalized = normalizeCapabilityToken(query)
        return categoryTagFilters[normalized]
    }

    private static func normalizeCapabilityToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func resolvedDiscoverCategory(for raw: String) -> String? {
        let normalized = normalizeCapabilityToken(raw)
        guard !normalized.isEmpty else { return nil }
        if categoryQueryExpansions[normalized] != nil {
            return normalized
        }
        return categoryQueryAliases[normalized]
    }

    private static func uniqueSearchTerms(_ rawTerms: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in rawTerms {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    static func curatedRecommendedResults(
        from rawResults: [LMStudioMarketResult],
        limit: Int
    ) -> [LMStudioMarketResult] {
        let normalizedLimit = max(1, limit)
        guard !rawResults.isEmpty else { return [] }

        let buckets = availableRecommendationBuckets(in: rawResults)
        guard !buckets.isEmpty else {
            return Array(
                rawResults
                    .sorted {
                        let lhsScore = recommendationScore(for: $0, focusTag: nil)
                        let rhsScore = recommendationScore(for: $1, focusTag: nil)
                        if lhsScore != rhsScore {
                            return lhsScore > rhsScore
                        }
                        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                    .prefix(normalizedLimit)
            )
            .enumerated()
            .map { index, candidate in
                var updated = candidate
                updated.recommendationReason = recommendationReason(
                    for: updated,
                    focusTag: nil,
                    rank: index,
                    fallbackOnly: true
                )
                return updated
            }
        }

        let targets = recommendationTargets(for: buckets, limit: normalizedLimit)
        var selected: [LMStudioMarketResult] = []
        var selectedKeys = Set<String>()

        for bucket in buckets {
            let candidates = rawResults
                .filter { result in
                    result.hasCapabilityTag(bucket.tag)
                        && !selectedKeys.contains(normalizedMarketKey(result.modelKey))
                }
                .sorted {
                    let lhsScore = recommendationScore(for: $0, focusTag: bucket.tag)
                    let rhsScore = recommendationScore(for: $1, focusTag: bucket.tag)
                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            let targetCount = min(targets[bucket.tag] ?? 0, candidates.count)
            for (index, candidate) in candidates.prefix(targetCount).enumerated() {
                var updated = candidate
                if index == 0 {
                    updated.staffPick = true
                }
                updated.recommendationReason = recommendationReason(
                    for: updated,
                    focusTag: bucket.tag,
                    rank: index,
                    fallbackOnly: false
                )
                selected.append(updated)
                selectedKeys.insert(normalizedMarketKey(updated.modelKey))
            }
        }

        if selected.count < normalizedLimit {
            let fallback = rawResults
                .filter { !selectedKeys.contains(normalizedMarketKey($0.modelKey)) }
                .sorted {
                    let lhsScore = recommendationScore(for: $0, focusTag: nil)
                    let rhsScore = recommendationScore(for: $1, focusTag: nil)
                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }
                        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            for (index, candidate) in fallback.prefix(normalizedLimit - selected.count).enumerated() {
                var updated = candidate
                updated.recommendationReason = recommendationReason(
                    for: updated,
                    focusTag: nil,
                    rank: index,
                    fallbackOnly: true
                )
                selected.append(updated)
            }
        }

        return Array(selected.prefix(normalizedLimit))
    }

    private static func preparedSortScore(
        _ prepared: HuggingFacePreparedSearchResult,
        focusCategory: String?
    ) -> Double {
        recommendationScore(
            for: prepared.result,
            focusTag: primaryFocusTag(for: focusCategory),
            downloads: prepared.downloads,
            likes: prepared.likes
        )
    }

    private static func availableRecommendationBuckets(
        in results: [LMStudioMarketResult],
        fileManager: FileManager = .default
    ) -> [MarketRecommendationBucket] {
        var buckets = curatedRecommendationBucketsBase
        let helperPath = helperBinaryPath().trimmingCharacters(in: .whitespacesAndNewlines)
        if !helperPath.isEmpty, fileManager.isExecutableFile(atPath: helperPath) {
            buckets.append(contentsOf: curatedRecommendationBucketsHelper)
        }
        return buckets.filter { bucket in
            results.contains { $0.hasCapabilityTag(bucket.tag) }
        }
    }

    private static func recommendationTargets(
        for buckets: [MarketRecommendationBucket],
        limit: Int
    ) -> [String: Int] {
        guard limit > 0, !buckets.isEmpty else { return [:] }
        if limit <= buckets.count {
            return Dictionary(
                uniqueKeysWithValues: buckets.prefix(limit).map { ($0.tag, 1) }
            )
        }

        let totalWeight = max(1, buckets.reduce(0) { $0 + max(1, $1.weight) })
        var targets = Dictionary(uniqueKeysWithValues: buckets.map { ($0.tag, 1) })
        var allocated = buckets.count

        for bucket in buckets {
            let proportional = Int(
                (Double(limit) * Double(max(1, bucket.weight)) / Double(totalWeight)).rounded(.toNearestOrAwayFromZero)
            )
            let desired = max(1, proportional)
            targets[bucket.tag] = desired
            allocated += desired - 1
        }

        while allocated > limit {
            guard let candidate = buckets
                .sorted(by: { lhs, rhs in
                    let lhsTarget = targets[lhs.tag] ?? 0
                    let rhsTarget = targets[rhs.tag] ?? 0
                    if lhsTarget != rhsTarget {
                        return lhsTarget > rhsTarget
                    }
                    return lhs.weight > rhs.weight
                })
                .first(where: { (targets[$0.tag] ?? 0) > 1 }) else {
                break
            }
            targets[candidate.tag, default: 1] -= 1
            allocated -= 1
        }

        while allocated < limit {
            guard let candidate = buckets.max(by: { lhs, rhs in
                let lhsTarget = targets[lhs.tag] ?? 0
                let rhsTarget = targets[rhs.tag] ?? 0
                if lhs.weight != rhs.weight {
                    return lhs.weight < rhs.weight
                }
                return lhsTarget > rhsTarget
            }) else {
                break
            }
            targets[candidate.tag, default: 0] += 1
            allocated += 1
        }

        return targets
    }

    private static func primaryFocusTag(for focusCategory: String?) -> String? {
        switch normalizeCapabilityToken(focusCategory ?? "") {
        case "chat":
            return "Text"
        case "coding":
            return "Coding"
        case "embedding":
            return "Embedding"
        case "voice":
            return "Voice"
        case "vision":
            return "Vision"
        case "ocr":
            return "OCR"
        case "speech":
            return "Speech"
        default:
            return nil
        }
    }

    private static func recommendationReason(
        for result: LMStudioMarketResult,
        focusTag: String?,
        rank: Int,
        fallbackOnly: Bool
    ) -> String {
        let fit = normalizedRecommendationFit(result.recommendedFitEstimation)
        let isPrimaryPick = rank == 0

        switch focusTag {
        case "Text":
            return fitAdjustedReason(
                isPrimaryPick ? "Best everyday text starter" : "Higher-headroom text option",
                fit: fit
            )
        case "Coding":
            return fitAdjustedReason(
                isPrimaryPick ? "Best coding starter" : "Higher-headroom coding option",
                fit: fit
            )
        case "Embedding":
            return isPrimaryPick
                ? "Best embedding starter for local retrieval"
                : "Higher-capacity embedding option for local retrieval"
        case "Voice":
            return fitAdjustedReason(
                isPrimaryPick ? "Best Supervisor voice starter" : "Alternative local voice option",
                fit: fit
            )
        case "Vision":
            return fitAdjustedReason(
                isPrimaryPick ? "Best vision starter" : "Alternative vision option",
                fit: fit
            )
        case "OCR":
            return fitAdjustedReason(
                isPrimaryPick
                    ? "Best OCR starter for docs and screenshots"
                    : "Alternative OCR option for docs and screenshots",
                fit: fit
            )
        case "Speech":
            return fitAdjustedReason(
                isPrimaryPick ? "Best speech starter" : "Alternative speech option",
                fit: fit
            )
        default:
            if fallbackOnly {
                return fitAdjustedReason(
                    isPrimaryPick ? "Balanced local model pick" : "Alternative local model pick",
                    fit: fit
                )
            }
            return ""
        }
    }

    private static func fitAdjustedReason(_ base: String, fit: String) -> String {
        switch fit {
        case "fullgpuoffload", "partialgpuoffload":
            return "\(base) for this Mac"
        case "fitwithoutgpu":
            return "\(base) that can stay CPU-friendly"
        case "willnotfit":
            return "\(base) if you want to push this Mac"
        default:
            return base
        }
    }

    private static func normalizedRecommendationFit(_ raw: String) -> String {
        normalizeCapabilityToken(raw.replacingOccurrences(of: "_", with: ""))
    }

    private static func recommendationScore(
        for result: LMStudioMarketResult,
        focusTag: String?,
        downloads: Int = 0,
        likes: Int = 0
    ) -> Double {
        var score = fitScore(for: result.recommendedFitEstimation)
        score += formatScore(for: result, focusTag: focusTag)
        score += familyScore(for: result, focusTag: focusTag)
        score += sizeScore(for: result.recommendedSizeBytes, focusTag: focusTag)
        score += popularityScore(downloads: downloads, likes: likes)
        score += Double(result.capabilityTags.count) * 6.0

        if let focusTag {
            if result.hasCapabilityTag(focusTag) {
                score += 120.0
            } else if focusTag == "Vision", result.hasCapabilityTag("OCR") {
                score += 45.0
            } else if focusTag == "Text", result.hasCapabilityTag("Coding") {
                score += 20.0
            }
        } else if result.recommendedForThisMac {
            score += 20.0
        }

        if result.staffPick {
            score += 12.0
        }
        return score
    }

    private static func fitScore(for raw: String) -> Double {
        switch normalizeCapabilityToken(raw.replacingOccurrences(of: "_", with: "")) {
        case "fullgpuoffload":
            return 240.0
        case "partialgpuoffload":
            return 190.0
        case "fitwithoutgpu":
            return 150.0
        case "willnotfit":
            return 40.0
        default:
            return 110.0
        }
    }

    private static func formatScore(
        for result: LMStudioMarketResult,
        focusTag: String?
    ) -> Double {
        let normalizedFormat = normalizeCapabilityToken(result.formatHint)
        switch normalizedFormat {
        case "mlx":
            switch focusTag {
            case "Text", "Coding", "Embedding":
                return 42.0
            case "Vision", "OCR":
                return 12.0
            default:
                return 18.0
            }
        case "transformers":
            switch focusTag {
            case "Vision", "OCR":
                return 34.0
            case "Speech", "Voice":
                return 26.0
            default:
                return 18.0
            }
        default:
            return 0.0
        }
    }

    private static func familyScore(
        for result: LMStudioMarketResult,
        focusTag: String?
    ) -> Double {
        let haystack = result.recommendationHaystack
        let genericSignals: [(String, Double)] = [
            ("qwen", 18.0),
            ("llama", 16.0),
            ("gemma", 15.0),
            ("phi", 14.0),
            ("mistral", 14.0),
            ("deepseek", 14.0),
            ("glm", 12.0),
            ("bge", 14.0),
            ("gte", 12.0),
            ("whisper", 14.0),
            ("florence", 16.0),
        ]
        let focusedSignals: [String: [(String, Double)]] = [
            "Text": [
                ("qwen3", 28.0),
                ("llama-3", 24.0),
                ("gemma-3", 22.0),
                ("phi-3", 20.0),
            ],
            "Coding": [
                ("qwen-coder", 34.0),
                ("codestral", 32.0),
                ("deepseek-coder", 32.0),
                ("starcoder", 28.0),
                ("codegemma", 26.0),
                ("codellama", 24.0),
                ("devstral", 22.0),
            ],
            "Vision": [
                ("qwen2-vl", 34.0),
                ("qwen3-vl", 34.0),
                ("glm-4.6v", 36.0),
                ("glm4v", 34.0),
                ("florence", 30.0),
                ("llava", 24.0),
                ("smolvlm", 18.0),
            ],
            "OCR": [
                ("florence", 34.0),
                ("trocr", 30.0),
                ("donut", 24.0),
                ("ocr", 18.0),
            ],
            "Embedding": [
                ("qwen3-embedding", 36.0),
                ("bge", 30.0),
                ("gte", 28.0),
                ("nomic-embed", 26.0),
                ("mxbai", 24.0),
                ("e5", 22.0),
            ],
            "Voice": [
                ("kokoro", 34.0),
                ("melo", 30.0),
                ("parler", 30.0),
                ("bark", 28.0),
                ("speecht5", 28.0),
                ("f5-tts", 28.0),
                ("cosyvoice", 26.0),
            ],
            "Speech": [
                ("whisper-large-v3", 34.0),
                ("whisper", 28.0),
                ("parakeet", 20.0),
            ],
        ]

        var score = 0.0
        for (signal, bonus) in genericSignals where haystack.contains(signal) {
            score += bonus
        }
        if let focusSignals = focusedSignals[focusTag ?? ""] {
            for (signal, bonus) in focusSignals where haystack.contains(signal) {
                score += bonus
            }
        }
        return score
    }

    private static func sizeScore(
        for bytes: Int64,
        focusTag: String?
    ) -> Double {
        guard bytes > 0 else { return 0.0 }
        let gb = Double(bytes) / 1_000_000_000.0
        switch focusTag {
        case "Embedding":
            switch gb {
            case ..<1.5: return 26.0
            case ..<4.0: return 20.0
            case ..<8.0: return 8.0
            default: return -12.0
            }
        case "Vision", "OCR":
            switch gb {
            case ..<3.0: return 10.0
            case ..<8.0: return 18.0
            case ..<14.0: return 12.0
            default: return -8.0
            }
        default:
            switch gb {
            case ..<3.0: return 24.0
            case ..<6.0: return 18.0
            case ..<10.0: return 8.0
            case ..<18.0: return 0.0
            default: return -16.0
            }
        }
    }

    private static func popularityScore(
        downloads: Int,
        likes: Int
    ) -> Double {
        let downloadScore = min(log10(Double(max(downloads, 0)) + 1.0) * 12.0, 40.0)
        let likeScore = min(log10(Double(max(likes, 0)) + 1.0) * 8.0, 24.0)
        return downloadScore + likeScore
    }

    private static func huggingFaceRepoID(for row: HuggingFaceModelRow) -> String {
        stringValue(row.id).isEmpty
            ? (stringValue(row.modelId).isEmpty ? stringValue(row.modelKey) : stringValue(row.modelId))
            : stringValue(row.id)
    }

    private static func mergeHuggingFaceRows(
        base: HuggingFaceModelRow,
        detailed: HuggingFaceModelRow
    ) -> HuggingFaceModelRow {
        HuggingFaceModelRow(
            id: stringValue(detailed.id).isEmpty ? base.id : detailed.id,
            modelId: stringValue(detailed.modelId).isEmpty ? base.modelId : detailed.modelId,
            modelKey: stringValue(detailed.modelKey).isEmpty ? base.modelKey : detailed.modelKey,
            name: stringValue(detailed.name).isEmpty ? base.name : detailed.name,
            description: stringValue(detailed.description).isEmpty ? base.description : detailed.description,
            downloads: detailed.downloads ?? base.downloads,
            likes: detailed.likes ?? base.likes,
            tags: (detailed.tags?.isEmpty == false ? detailed.tags : base.tags),
            siblings: (detailed.siblings?.isEmpty == false ? detailed.siblings : base.siblings),
            pipeline_tag: stringValue(detailed.pipeline_tag).isEmpty ? base.pipeline_tag : detailed.pipeline_tag,
            pipelineTag: stringValue(detailed.pipelineTag).isEmpty ? base.pipelineTag : detailed.pipelineTag,
            cardData: detailed.cardData ?? base.cardData,
            private: detailed.private ?? base.private,
            gated: detailed.gated ?? base.gated
        )
    }

    private static func preparedSearchResult(
        from row: HuggingFaceModelRow
    ) -> HuggingFacePreparedSearchResult? {
        let repoID = huggingFaceRepoID(for: row)
        guard !repoID.isEmpty else { return nil }
        guard !shouldSkipHuggingFaceRow(row) else { return nil }
        let files = selectedDownloadFiles(from: row)
        guard !files.isEmpty else { return nil }

        let sizeBytes = files.reduce(Int64(0)) { partial, item in
            partial + item.size
        }
        let formatHint = detectFormatHint(for: row)
        let title = huggingFaceDisplayTitle(for: row)
        let summary = huggingFaceSummary(for: row)
        let result = LMStudioMarketResult(
            modelKey: repoID,
            title: title,
            summary: summary,
            formatHint: formatHint,
            capabilityTags: capabilityTags(for: row),
            staffPick: false,
            recommendationReason: "",
            recommendedForThisMac: fitEstimation(for: sizeBytes) != "willNotFit",
            recommendedFitEstimation: fitEstimation(for: sizeBytes),
            recommendedSizeBytes: sizeBytes,
            downloadIdentifier: repoID,
            downloaded: false,
            inLibrary: false
        )
        return HuggingFacePreparedSearchResult(
            result: result,
            downloads: row.downloads ?? 0,
            likes: row.likes ?? 0
        )
    }

    private static func shouldSkipHuggingFaceRow(_ row: HuggingFaceModelRow) -> Bool {
        if (row.private ?? false) || (row.gated ?? false) {
            return true
        }
        let repoID = huggingFaceRepoID(for: row)
        guard !repoID.isEmpty else { return true }
        let tags = normalizedTags(for: row)
        if tags.contains(where: { repoExcludeTags.contains(normalizeCapabilityToken($0)) }) {
            return true
        }
        return detectFormatHint(for: row).isEmpty
    }

    private static func normalizedTags(for row: HuggingFaceModelRow) -> [String] {
        var tags: [String] = []
        tags.append(contentsOf: row.tags ?? [])
        tags.append(contentsOf: row.cardData?.tags ?? [])
        let pipeline = stringValue(row.pipeline_tag).isEmpty ? stringValue(row.pipelineTag) : stringValue(row.pipeline_tag)
        if !pipeline.isEmpty {
            tags.append(pipeline)
        }
        return Array(NSOrderedSet(array: tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })) as? [String] ?? []
    }

    private static func normalizedSiblingNames(for row: HuggingFaceModelRow) -> [String] {
        (row.siblings ?? [])
            .map { siblingName(for: $0) }
            .filter { !$0.isEmpty }
    }

    private static func siblingName(for sibling: HuggingFaceModelRow.Sibling) -> String {
        let candidates = [sibling.rfilename, sibling.path, sibling.name]
        for candidate in candidates {
            let trimmed = stringValue(candidate)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func siblingSize(for sibling: HuggingFaceModelRow.Sibling) -> Int64 {
        if let size = sibling.size, size > 0 {
            return size
        }
        if let size = sibling.lfs?.size, size > 0 {
            return size
        }
        return 0
    }

    private static func detectFormatHint(for row: HuggingFaceModelRow) -> String {
        let repoID = huggingFaceRepoID(for: row)
        let owner = repoID.split(separator: "/").first.map(String.init) ?? ""
        let tags = normalizedTags(for: row).map(normalizeCapabilityToken)
        let siblingNames = normalizedSiblingNames(for: row).map { $0.lowercased() }
        let hasConfig = siblingNames.contains("config.json") || siblingNames.contains("xhub_model_manifest.json")
        let hasSFT = siblingNames.contains(where: { $0.hasSuffix(".safetensors") || $0.hasSuffix(".safetensors.index.json") })
        let hasNPZ = siblingNames.contains("weights.npz") || siblingNames.contains(where: { $0.hasSuffix(".npz") })

        if (owner == "mlx-community" || tags.contains("mlx")) && (hasNPZ || hasSFT || hasConfig) {
            return "mlx"
        }
        if hasConfig && (hasSFT || hasNPZ) {
            return "transformers"
        }
        return ""
    }

    private static func capabilityTags(for row: HuggingFaceModelRow) -> [String] {
        let repoID = huggingFaceRepoID(for: row)
        let title = huggingFaceDisplayTitle(for: row)
        let summary = huggingFaceSummary(for: row)
        let pipeline = normalizeCapabilityToken(
            stringValue(row.pipeline_tag).isEmpty ? stringValue(row.pipelineTag) : stringValue(row.pipeline_tag)
        )
        let tags = normalizedTags(for: row).map(normalizeCapabilityToken)
        let haystack = "\(repoID) \(title) \(summary) \(pipeline) \(tags.joined(separator: " "))".lowercased()
        var out: [String] = []
        let voiceSignals = ["text-to-speech", "tts", "voice", "kokoro", "melo", "parler", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"]

        if ["image-text-to-text", "image-to-text", "visual-question-answering", "document-question-answering"].contains(pipeline)
            || containsAny(haystack, values: ["vision", "vl", "llava", "glm4v", "glm-4.6v", "qwen2-vl", "qwen3-vl", "florence", "image"]) {
            out.append("Vision")
        }
        if containsAny(haystack, values: ["ocr", "document"]) {
            out.append("OCR")
        }
        if pipeline == "feature-extraction"
            || containsAny(haystack, values: ["embedding", "embed", "bge", "gte"]) {
            out.append("Embedding")
        }
        if containsAny(haystack, values: ["coder", "coding", "code"]) {
            out.append("Coding")
        }
        if pipeline == "text-to-speech"
            || pipeline == "text-to-audio"
            || containsAny(haystack, values: voiceSignals) {
            out.append("Voice")
        }
        if pipeline == "automatic-speech-recognition"
            || (containsAny(haystack, values: ["whisper", "speech", "audio", "asr"])
                && !containsAny(haystack, values: voiceSignals)) {
            out.append("Speech")
        }
        if out.isEmpty {
            out.append("Text")
        }
        return Array(NSOrderedSet(array: out)) as? [String] ?? out
    }

    private static func huggingFaceDisplayTitle(for row: HuggingFaceModelRow) -> String {
        let explicit = [
            row.cardData?.model_name,
            row.cardData?.title,
            row.name,
        ]
            .compactMap { value -> String? in
                let trimmed = stringValue(value)
                return trimmed.isEmpty ? nil : trimmed
            }
            .first
        if let explicit, !explicit.isEmpty {
            return explicit
        }
        return displayTitle(for: huggingFaceRepoID(for: row))
    }

    private static func huggingFaceSummary(for row: HuggingFaceModelRow) -> String {
        let raw = [
            row.cardData?.summary,
            row.cardData?.description,
            row.description,
        ]
            .compactMap { value -> String? in
                let trimmed = stringValue(value)
                return trimmed.isEmpty ? nil : trimmed
            }
            .first ?? ""
        return raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func selectedDownloadFiles(
        from row: HuggingFaceModelRow
    ) -> [(name: String, size: Int64)] {
        let formatHint = detectFormatHint(for: row)
        guard !formatHint.isEmpty else { return [] }
        let siblingNames = normalizedSiblingNames(for: row).map { $0.lowercased() }
        let selected = (row.siblings ?? []).compactMap { sibling -> (String, Int64)? in
            let name = siblingName(for: sibling)
            guard fileIsAllowed(name: name, formatHint: formatHint, siblingNames: siblingNames) else { return nil }
            return (name, siblingSize(for: sibling))
        }

        let hasWeights = selected.contains { item in
            let name = item.0.lowercased()
            return name.hasSuffix(".safetensors") || name.hasSuffix(".npz") || name.hasSuffix(".bin")
        }
        let hasConfig = selected.contains { $0.0.lowercased() == "config.json" }
        guard hasWeights, hasConfig else { return [] }
        return selected.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    static func isAllowedMarketDownloadFile(
        name: String,
        formatHint: String,
        siblingNames: [String]
    ) -> Bool {
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty, !lowered.hasSuffix("/") else { return false }

        let blockedExtensions = [".gguf", ".onnx", ".ot", ".ckpt", ".h5", ".pth", ".pt", ".msgpack", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".mp4"]
        if blockedExtensions.contains(where: lowered.hasSuffix) {
            return false
        }
        let allowedTextExtensions = [".json", ".txt", ".model", ".tiktoken", ".jinja", ".sentencepiece", ".bpe", ".py"]
        if allowedTextExtensions.contains(where: lowered.hasSuffix) {
            return true
        }
        if lowered.hasSuffix(".npz") || lowered.hasSuffix(".safetensors") || lowered.hasSuffix(".safetensors.index.json") {
            return true
        }
        if lowered.hasSuffix(".bin") {
            let hasSafeTensors = siblingNames.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".safetensors.index.json") }
            if formatHint != "transformers" {
                return false
            }
            if isLikelyVoiceSidecarBinary(lowered) {
                return true
            }
            return !hasSafeTensors
        }
        return false
    }

    private static func fileIsAllowed(
        name: String,
        formatHint: String,
        siblingNames: [String]
    ) -> Bool {
        isAllowedMarketDownloadFile(
            name: name,
            formatHint: formatHint,
            siblingNames: siblingNames
        )
    }

    private static func isLikelyVoiceSidecarBinary(_ loweredName: String) -> Bool {
        containsAny(
            loweredName,
            values: [
                "voice",
                "voices",
                "speaker",
                "speakers",
                "spk",
                "style",
                "phoneme",
                "g2p",
                "lexicon",
                "espeak",
            ]
        )
    }

    private static func fitEstimation(for bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        guard memoryBytes > 0 else { return "" }
        let ratio = Double(bytes) / Double(memoryBytes)
        if ratio <= 0.18 { return "fullGPUOffload" }
        if ratio <= 0.33 { return "partialGPUOffload" }
        if ratio <= 0.55 { return "fitWithoutGPU" }
        return "willNotFit"
    }

    private static func containsAny(_ haystack: String, values: [String]) -> Bool {
        let lowered = haystack.lowercased()
        return values.contains { lowered.contains($0.lowercased()) }
    }

    private static func searchModelsViaSDKHelper(
        query: String,
        category: String,
        limit: Int
    ) throws -> [LMStudioMarketResult] {
        let result = try runSDKHelperCommand(
            command: "search",
            arguments: [
                query.trimmingCharacters(in: .whitespacesAndNewlines),
                String(max(1, min(25, limit))),
                category.trimmingCharacters(in: .whitespacesAndNewlines),
            ],
            timeoutSec: 60.0
        )
        guard result.terminationStatus == 0 else {
            throw LMStudioMarketBridgeError.searchFailed(cleanedProcessFailureDetail(result))
        }
        return try decodeSDKSearchResults(from: result.stdout)
    }

    private static func downloadRecommendedViaSDKHelper(
        modelKey: String,
        downloadIdentifier: String?,
        progress: @escaping @Sendable (String) -> Void
    ) throws {
        let result = try runSDKHelperCommand(
            command: "download",
            arguments: [
                modelKey,
                downloadIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            ],
            timeoutSec: 3600.0,
            onOutputUpdate: { output in
                let status = lastSDKHelperMessage(from: output)
                if !status.isEmpty {
                    progress(status)
                }
            }
        )
        let events = helperEvents(from: result.stdout)
        let succeeded = events.contains { $0.type == "success" }
        guard result.terminationStatus == 0 || succeeded else {
            throw LMStudioMarketBridgeError.downloadFailed(cleanedProcessFailureDetail(result))
        }
    }

    static func decodeSDKSearchResults(from rawOutput: String) throws -> [LMStudioMarketResult] {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8) else {
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.invalidModelDiscoveryOutput)
        }
        let envelope: LMStudioSDKSearchEnvelope
        do {
            envelope = try JSONDecoder().decode(LMStudioSDKSearchEnvelope.self, from: data)
        } catch {
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.unreadableModelDiscoveryResult)
        }

        return envelope.results.map { item in
            LMStudioMarketResult(
                modelKey: item.modelKey,
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? displayTitle(for: item.modelKey)
                    : item.title,
                summary: item.summary,
                formatHint: item.formatHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "transformers"
                    : item.formatHint,
                capabilityTags: item.capabilityTags.isEmpty
                    ? capabilityTags(for: item.modelKey, summary: item.summary)
                    : item.capabilityTags,
                staffPick: item.staffPick ?? false,
                recommendationReason: item.recommendationReason ?? "",
                recommendedForThisMac: item.recommendedForThisMac ?? false,
                recommendedFitEstimation: item.recommendedFitEstimation ?? "",
                recommendedSizeBytes: item.recommendedSizeBytes ?? 0,
                downloadIdentifier: item.downloadIdentifier ?? "",
                downloaded: false,
                inLibrary: false
            )
        }
    }

    private static func helperEvents(from rawOutput: String) -> [LMStudioSDKHelperEvent] {
        sanitizedTerminalOutput(rawOutput)
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
                guard let data = trimmed.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(LMStudioSDKHelperEvent.self, from: data)
            }
    }

    private static func lastSDKHelperMessage(from rawOutput: String) -> String {
        for event in helperEvents(from: rawOutput).reversed() {
            let message = event.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty && event.type != "success" {
                return message
            }
        }
        return ""
    }

    static func parseSearchResultsFromTerminalOutput(_ rawOutput: String) -> [LMStudioMarketResult] {
        let sanitized = sanitizedTerminalOutput(rawOutput)
        let lines = sanitized.components(separatedBy: .newlines)
        var results: [LMStudioMarketResult] = []
        var seen: Set<String> = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("?") || line.contains("navigate") || line.contains("select") {
                continue
            }
            if line.hasPrefix("Searching for models") || line.hasPrefix("No exact match found") {
                continue
            }

            let normalized = line.hasPrefix("❯")
                ? String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                : line

            guard let parsed = parseSearchLine(normalized),
                  seen.insert(parsed.modelKey).inserted else {
                continue
            }

            results.append(
                LMStudioMarketResult(
                    modelKey: parsed.modelKey,
                    title: displayTitle(for: parsed.modelKey),
                    summary: parsed.summary,
                    formatHint: "mlx",
                    capabilityTags: capabilityTags(for: parsed.modelKey, summary: parsed.summary),
                    staffPick: false,
                    recommendationReason: "",
                    recommendedForThisMac: false,
                    recommendedFitEstimation: "",
                    recommendedSizeBytes: 0,
                    downloadIdentifier: "",
                    downloaded: false,
                    inLibrary: false
                )
            )
        }

        return results
    }

    static func marketKeyMatchesDescriptor(
        _ marketKey: String,
        descriptor: LMStudioDownloadedModelDescriptor
    ) -> Bool {
        let keyParts = normalizedMarketKeyParts(marketKey)
        guard keyParts.count == 2 else { return false }

        let requestedUser = keyParts[0]
        let requestedTokens = matchingTokens(from: keyParts[1])
        guard !requestedTokens.isEmpty else { return false }

        let descriptorUser = descriptor.user.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !descriptorUser.isEmpty && descriptorUser != requestedUser {
            return false
        }

        let candidateTokens = descriptorMatchingTokens(descriptor)
        return requestedTokens.isSubset(of: candidateTokens)
    }

    static func marketKeyMatchesModel(
        _ marketKey: String,
        model: HubModel
    ) -> Bool {
        let keyParts = normalizedMarketKeyParts(marketKey)
        guard keyParts.count == 2 else { return false }

        if let exactKey = extractedMarketKey(fromModelPath: model.modelPath ?? ""),
           exactKey == normalizedMarketKey(marketKey) {
            return true
        }

        let requestedTokens = matchingTokens(from: keyParts[1])
        guard !requestedTokens.isEmpty else { return false }

        let haystacks = [
            model.id,
            model.name,
            model.modelPath ?? "",
            model.note ?? "",
        ]
        let modelTokens = Set(haystacks.flatMap { matchingTokens(from: $0) })
        return requestedTokens.isSubset(of: modelTokens)
    }

    private static func catalogEntry(
        from descriptor: LMStudioDownloadedModelDescriptor,
        helperBinaryPath: String
    ) -> ModelCatalogEntry? {
        guard !descriptor.isBundled else { return nil }
        guard descriptor.isDirectoryModel else { return nil }
        let path = descriptor.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        guard LocalModelFolderIntegrityPolicy.issue(modelPath: path) == nil else { return nil }

        let modelURL = URL(fileURLWithPath: path, isDirectory: true)
        let manifest = XHubLocalModelManifestLoader.load(from: modelURL)
        let config = readConfigJSON(in: modelURL)
        let backendDetection = LocalModelImportDetector.detectBackend(
            for: modelURL,
            manifest: manifest,
            config: config
        )
        let backend = backendDetection.backend
        guard backend == "mlx" || backend == "transformers" || backend == "llama.cpp" else { return nil }

        let inferredCapabilities = LocalModelImportDetector.detectCapabilities(
            for: modelURL,
            backend: backend,
            manifest: manifest,
            config: config
        )
        let taskKinds = inferredCapabilities?.taskKinds ?? taskKinds(
            forDomain: descriptor.domain,
            modelName: descriptor.model
        )
        guard !taskKinds.isEmpty else { return nil }

        let modelFormat = inferredCapabilities?.modelFormat
            ?? manifest?.modelFormat
            ?? defaultModelFormat(forBackend: backend, descriptor: descriptor)
        let maxContextLength = max(
            512,
            descriptor.contextLength > 0 ? descriptor.contextLength : detectContextLength(config)
        )
        let quant = normalizedQuantLabel(descriptor.quantLabel, fileName: descriptor.file)
        let paramsB = descriptor.paramsB
        let resourceProfile = manifest?.resourceProfile ?? LocalModelCapabilityDefaults.defaultResourceProfile(
            backend: backend,
            quant: quant,
            paramsB: paramsB
        )
        let trustProfile = manifest?.trustProfile ?? LocalModelCapabilityDefaults.defaultTrustProfile()
        let processorRequirements = inferredCapabilities?.processorRequirements
            ?? manifest?.processorRequirements
            ?? LocalModelCapabilityDefaults.defaultProcessorRequirements(
                backend: backend,
                modelFormat: modelFormat,
                taskKinds: taskKinds
            )
        let runtimeProviderID = LocalModelExecutionProviderResolver.suggestedRuntimeProviderID(
            backend: backend,
            modelPath: path,
            taskKinds: taskKinds,
            helperBinaryPath: helperBinaryPath
        )
        let defaultLoadProfile = (manifest?.defaultLoadProfile ?? LocalModelLoadProfile(contextLength: maxContextLength))
            .normalized(maxContextLength: maxContextLength)
        let modelID = stableCatalogModelID(for: descriptor)
        let name = descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? displayTitle(for: "\(descriptor.user)/\(descriptor.model)")
            : descriptor.displayName
        let note = marketManagedNote(for: descriptor)
        let outputModalities = inferredCapabilities?.outputModalities
            ?? manifest?.outputModalities
            ?? LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds)

        let entry = ModelCatalogEntry(
            id: modelID,
            name: name,
            backend: backend,
            runtimeProviderID: runtimeProviderID,
            quant: quant,
            contextLength: maxContextLength,
            maxContextLength: maxContextLength,
            paramsB: paramsB,
            modelPath: path,
            roles: nil,
            note: note,
            modelFormat: modelFormat,
            defaultLoadProfile: defaultLoadProfile,
            taskKinds: taskKinds,
            inputModalities: inferredCapabilities?.inputModalities
                ?? manifest?.inputModalities
                ?? LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds),
            outputModalities: outputModalities,
            offlineReady: manifest?.offlineReady ?? true,
            voiceProfile: LocalModelCapabilityDefaults.defaultVoiceProfile(
                modelID: modelID,
                name: name,
                note: note,
                taskKinds: taskKinds,
                outputModalities: outputModalities
            ),
            resourceProfile: resourceProfile,
            trustProfile: trustProfile,
            processorRequirements: processorRequirements
        )
        return LocalModelExecutionProviderResolver.backfilled(
            entry,
            helperBinaryPath: helperBinaryPath
        )
    }

    private static func marketManagedNote(
        for descriptor: LMStudioDownloadedModelDescriptor
    ) -> String {
        let source = descriptor.sourceDirectoryType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source == "xhub_market" {
            return "market_managed"
        }
        return "lmstudio_managed"
    }

    private static func readConfigJSON(in directory: URL) -> [String: Any]? {
        let configURL = directory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any] else {
            return nil
        }
        return dict
    }

    private static func mergedDownloadedDescriptors(
        _ descriptors: [LMStudioDownloadedModelDescriptor]
    ) -> [LMStudioDownloadedModelDescriptor] {
        var merged: [LMStudioDownloadedModelDescriptor] = []
        var seenPaths = Set<String>()
        var seenMarketKeys = Set<String>()

        for descriptor in descriptors {
            let pathKey = standardizedDescriptorPath(descriptor)
            let marketKey = normalizedDescriptorMarketKey(descriptor)
            if !pathKey.isEmpty, seenPaths.contains(pathKey) {
                continue
            }
            if !marketKey.isEmpty, seenMarketKeys.contains(marketKey) {
                continue
            }
            if !pathKey.isEmpty {
                seenPaths.insert(pathKey)
            }
            if !marketKey.isEmpty {
                seenMarketKeys.insert(marketKey)
            }
            merged.append(descriptor)
        }

        return merged
    }

    private static func standardizedDescriptorPath(
        _ descriptor: LMStudioDownloadedModelDescriptor
    ) -> String {
        let path = descriptor.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
    }

    private static func normalizedDescriptorMarketKey(
        _ descriptor: LMStudioDownloadedModelDescriptor
    ) -> String {
        let user = descriptor.user.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let model = descriptor.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !user.isEmpty, !model.isEmpty else { return "" }
        return "\(user)/\(model)"
    }

    private static func fallbackDownloadedDescriptorsFromFilesystem(
        homeDirectory: URL,
        fileManager: FileManager
    ) -> [LMStudioDownloadedModelDescriptor] {
        let root = legacyDownloadedModelsDirectory(homeDirectory: homeDirectory, fileManager: fileManager)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        guard let ownerDirectories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var descriptors: [LMStudioDownloadedModelDescriptor] = []
        for ownerDirectory in ownerDirectories {
            guard fileManager.directoryExists(atPath: ownerDirectory.path) else { continue }
            let owner = ownerDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !owner.isEmpty else { continue }
            guard let modelDirectories = try? fileManager.contentsOfDirectory(
                at: ownerDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for modelDirectory in modelDirectories where fileManager.directoryExists(atPath: modelDirectory.path) {
                let model = modelDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty else { continue }
                guard let descriptor = fallbackDownloadedDescriptor(
                    owner: owner,
                    model: model,
                    directoryURL: modelDirectory,
                    sourceDirectoryType: "downloaded",
                    fileManager: fileManager
                ) else {
                    continue
                }
                descriptors.append(descriptor)
            }
        }
        return descriptors
    }

    private static func fallbackDownloadedDescriptorsFromManagedMarket(
        baseDir: URL,
        fileManager: FileManager
    ) -> [LMStudioDownloadedModelDescriptor] {
        let root = marketDownloadedModelsDirectory(baseDir: baseDir)
        guard fileManager.directoryExists(atPath: root.path) else { return [] }
        guard let ownerDirectories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var descriptors: [LMStudioDownloadedModelDescriptor] = []
        for ownerDirectory in ownerDirectories where fileManager.directoryExists(atPath: ownerDirectory.path) {
            let owner = ownerDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !owner.isEmpty else { continue }
            guard let modelDirectories = try? fileManager.contentsOfDirectory(
                at: ownerDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for modelDirectory in modelDirectories where fileManager.directoryExists(atPath: modelDirectory.path) {
                let model = modelDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty else { continue }
                guard let descriptor = fallbackDownloadedDescriptor(
                    owner: owner,
                    model: model,
                    directoryURL: modelDirectory,
                    sourceDirectoryType: "xhub_market",
                    fileManager: fileManager
                ) else {
                    continue
                }
                descriptors.append(descriptor)
            }
        }
        return descriptors
    }

    private static func fallbackDownloadedDescriptor(
        owner: String,
        model: String,
        directoryURL: URL,
        sourceDirectoryType: String,
        fileManager: FileManager
    ) -> LMStudioDownloadedModelDescriptor? {
        guard fileManager.directoryExists(atPath: directoryURL.path) else { return nil }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let fileNames = entries.map(\.lastPathComponent)
        guard directoryLooksLikeDownloadedModel(fileNames: fileNames) else {
            return nil
        }

        let marketKey = "\(owner)/\(model)"
        let preferredEntry = preferredModelEntryPoint(in: directoryURL, fileNames: fileNames)
        let preferredFile = preferredEntry?.lastPathComponent ?? ""

        return LMStudioDownloadedModelDescriptor(
            indexedModelIdentifier: marketKey,
            displayName: displayTitle(for: marketKey),
            defaultIdentifier: fallbackDefaultIdentifier(for: model),
            user: owner,
            model: model,
            file: preferredFile,
            format: fallbackFormat(fileNames: fileNames),
            quantLabel: fallbackQuantLabel(modelName: model),
            domain: fallbackDomain(modelName: model),
            contextLength: 0,
            directoryPath: directoryURL.path,
            entryPointPath: preferredEntry?.path ?? directoryURL.path,
            sourceDirectoryType: sourceDirectoryType,
            paramsB: 0.0
        )
    }

    private static func directoryLooksLikeDownloadedModel(fileNames: [String]) -> Bool {
        let lowered = Set(fileNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let markerFiles: Set<String> = [
            "config.json",
            "xhub_model_manifest.json",
            "model.safetensors.index.json",
            "consolidated.safetensors.index.json",
            "weights.npz",
            "processor_config.json",
            "preprocessor_config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "generation_config.json",
        ]
        if !lowered.isDisjoint(with: markerFiles) {
            return true
        }
        return lowered.contains(where: { name in
            name.hasSuffix(".gguf") || name.hasSuffix(".safetensors")
        })
    }

    private static func preferredModelEntryPoint(
        in directoryURL: URL,
        fileNames: [String]
    ) -> URL? {
        let preferredNames = [
            "model.safetensors.index.json",
            "consolidated.safetensors.index.json",
            "weights.npz",
            "model.safetensors",
            "config.json",
        ]
        let byLoweredName = Dictionary(uniqueKeysWithValues: fileNames.map {
            ($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0)
        })
        for preferredName in preferredNames {
            if let match = byLoweredName[preferredName] {
                return directoryURL.appendingPathComponent(match)
            }
        }
        if let gguf = fileNames.first(where: { $0.lowercased().hasSuffix(".gguf") }) {
            return directoryURL.appendingPathComponent(gguf)
        }
        if let safetensors = fileNames.first(where: { $0.lowercased().hasSuffix(".safetensors") }) {
            return directoryURL.appendingPathComponent(safetensors)
        }
        return nil
    }

    private static func fallbackDefaultIdentifier(for model: String) -> String {
        sanitizedIdentifier(model)
    }

    private static func fallbackFormat(fileNames: [String]) -> String {
        let lowered = fileNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if lowered.contains(where: { $0.hasSuffix(".gguf") }) {
            return "gguf"
        }
        if lowered.contains("weights.npz") {
            return "mlx"
        }
        if lowered.contains(where: { $0.hasSuffix(".safetensors") || $0.hasSuffix(".safetensors.index.json") }) {
            return "safetensors"
        }
        return "safetensors"
    }

    private static func fallbackQuantLabel(modelName: String) -> String {
        let lowered = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for token in ["2bit", "3bit", "4bit", "5bit", "6bit", "8bit", "bf16", "fp16", "fp32", "q4", "q8"] {
            if lowered.contains(token) {
                return token
            }
        }
        return ""
    }

    private static func fallbackDomain(modelName: String) -> String {
        let lowered = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.contains("embed") {
            return "embedding"
        }
        if containsAny(lowered, values: ["text-to-speech", "text_to_speech", "tts", "voice", "kokoro", "melo", "parler", "vits", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"]) {
            return "voice"
        }
        if lowered.contains("vision")
            || lowered.contains("ocr")
            || lowered.contains("-vl")
            || lowered.contains("glm4v")
            || lowered.contains("glm-4.6v")
            || lowered.contains("qwen2-vl")
            || lowered.contains("qwen3-vl")
            || lowered.contains("florence") {
            return "vision"
        }
        if lowered.contains("audio")
            || lowered.contains("whisper")
            || lowered.contains("asr")
            || lowered.contains("speech") {
            return "audio"
        }
        return "llm"
    }

    private static func detectContextLength(_ config: [String: Any]?) -> Int {
        guard let config else { return 8192 }
        for key in ["max_position_embeddings", "context_length", "n_ctx", "max_seq_len", "seq_length"] {
            if let value = config[key] as? Int, value > 0 {
                return value
            }
            if let value = config[key] as? NSNumber, value.intValue > 0 {
                return value.intValue
            }
        }
        return 8192
    }

    private static func defaultModelFormat(
        forBackend backend: String,
        descriptor: LMStudioDownloadedModelDescriptor
    ) -> String {
        let normalizedFormat = descriptor.format.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedFormat == "gguf" {
            return "gguf"
        }
        return LocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
    }

    private static func taskKinds(
        forDomain domain: String,
        modelName: String
    ) -> [String] {
        let normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedDomain == "embedding" || normalizedName.contains("embed") {
            return ["embedding"]
        }
        if normalizedDomain == "voice"
            || containsAny(normalizedName, values: ["text-to-speech", "text_to_speech", "tts", "voice", "kokoro", "melo", "parler", "vits", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"]) {
            return ["text_to_speech"]
        }
        if normalizedDomain.contains("speech") || normalizedDomain.contains("audio") {
            if containsAny(normalizedName, values: ["text-to-speech", "text_to_speech", "tts", "voice", "kokoro", "melo", "parler", "vits", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"]) {
                return ["text_to_speech"]
            }
            if containsAny(normalizedName, values: ["whisper", "asr", "wav2vec", "hubert", "ctc"]) {
                return ["speech_to_text"]
            }
            return ["speech_to_text"]
        }
        if normalizedDomain.contains("vision")
            || normalizedDomain.contains("image")
            || normalizedName.contains("vision")
            || normalizedName.contains("llava")
            || normalizedName.contains("glm4v")
            || normalizedName.contains("glm-4.6v")
            || normalizedName.contains("qwen2-vl")
            || normalizedName.contains("qwen3-vl")
            || normalizedName.contains("florence")
            || normalizedName.contains("ocr") {
            if normalizedName.contains("ocr") {
                return ["vision_understand", "ocr"]
            }
            return ["vision_understand"]
        }
        return ["text_generate"]
    }

    private static func stableCatalogModelID(for descriptor: LMStudioDownloadedModelDescriptor) -> String {
        let parts = [
            descriptor.defaultIdentifier,
            descriptor.quantLabel,
            descriptor.file.replacingOccurrences(of: ".", with: "-"),
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let seed = parts.isEmpty ? descriptor.id : parts.joined(separator: "-")
        return sanitizedIdentifier(seed)
    }

    private static func sanitizedIdentifier(_ raw: String) -> String {
        let lower = raw.lowercased()
        let replaced = lower.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        )
        let collapsed = replaced.replacingOccurrences(
            of: #"-+"#,
            with: "-",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? UUID().uuidString.lowercased() : trimmed
    }

    private static func downloadedDescriptor(from row: [String: Any]) -> LMStudioDownloadedModelDescriptor? {
        let indexedModelIdentifier = stringValue(row["indexedModelIdentifier"])
        let displayName = stringValue(row["displayName"])
        let defaultIdentifier = stringValue(row["defaultIdentifier"])
        let user = stringValue(row["user"])
        let model = stringValue(row["model"])
        let file = stringValue(row["file"])
        let format = stringValue(row["format"])
        let domain = stringValue(row["domain"])
        let contextLength = intValue(row["contextLength"])
        let sourceDirectoryType = stringValue(row["sourceDirectoryType"])
        let paramsB = paramsValue(row["params"])
        let quantLabel: String = {
            if let quant = row["quant"] as? [String: Any] {
                return stringValue(quant["name"])
            }
            return ""
        }()
        let entryPoint = row["entryPoint"] as? [String: Any] ?? [:]
        let entryPointPath = stringValue(entryPoint["absPath"])
        let directoryPath = stringValue(row["concreteModelDirAbsolutePath"])

        let hasIdentity = !indexedModelIdentifier.isEmpty || (!user.isEmpty && !model.isEmpty)
        guard hasIdentity else { return nil }

        return LMStudioDownloadedModelDescriptor(
            indexedModelIdentifier: indexedModelIdentifier,
            displayName: displayName,
            defaultIdentifier: defaultIdentifier,
            user: user,
            model: model,
            file: file,
            format: format,
            quantLabel: quantLabel,
            domain: domain,
            contextLength: contextLength,
            directoryPath: directoryPath,
            entryPointPath: entryPointPath,
            sourceDirectoryType: sourceDirectoryType,
            paramsB: paramsB
        )
    }

    private static func paramsValue(_ raw: Any?) -> Double {
        if let number = raw as? NSNumber {
            return number.doubleValue
        }
        let text = stringValue(raw)
        guard !text.isEmpty else { return 0.0 }
        let normalized = text.lowercased()
        let multiplier: Double
        if normalized.contains("b") {
            multiplier = 1.0
        } else if normalized.contains("m") {
            multiplier = 0.001
        } else {
            multiplier = 1.0
        }
        let digits = normalized.replacingOccurrences(
            of: #"[^0-9.]"#,
            with: "",
            options: .regularExpression
        )
        if let value = Double(digits) {
            return value * multiplier
        }
        return 0.0
    }

    private static func normalizedQuantLabel(_ quant: String, fileName: String) -> String {
        let quantToken = quant.trimmingCharacters(in: .whitespacesAndNewlines)
        if !quantToken.isEmpty {
            return quantToken.lowercased()
        }
        let lower = fileName.lowercased()
        if lower.contains("4bit") { return "4bit" }
        if lower.contains("8bit") { return "8bit" }
        if lower.contains("bf16") { return "bf16" }
        if lower.contains("fp16") { return "fp16" }
        return ""
    }

    private static func capabilityTags(for modelKey: String, summary: String) -> [String] {
        let haystack = "\(modelKey) \(summary)".lowercased()
        var out: [String] = []
        let voiceSignals = ["text-to-speech", "text_to_speech", "tts", "voice", "kokoro", "melo", "parler", "vits", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"]
        if haystack.contains("vision")
            || haystack.contains("vlm")
            || haystack.contains("llava")
            || haystack.contains("glm-4.6v")
            || haystack.contains("glm4v")
            || haystack.contains("qwen2-vl")
            || haystack.contains("qwen3-vl")
            || haystack.contains("florence")
            || haystack.contains("image") {
            out.append("Vision")
        }
        if haystack.contains("ocr") {
            out.append("OCR")
        }
        if haystack.contains("embed") {
            out.append("Embedding")
        }
        if haystack.contains("coder") || haystack.contains("coding") || haystack.contains("code") {
            out.append("Coding")
        }
        if containsAny(haystack, values: voiceSignals) {
            out.append("Voice")
        }
        if out.isEmpty {
            out.append("Text")
        }
        return Array(out.prefix(3))
    }

    private static func displayTitle(for modelKey: String) -> String {
        let base = modelKey.split(separator: "/").last.map(String.init) ?? modelKey
        let words = base
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { token -> String in
                let raw = String(token)
                if raw.uppercased() == raw {
                    return raw
                }
                if raw.count <= 3 {
                    return raw.uppercased()
                }
                return String(raw.prefix(1)).uppercased() + String(raw.dropFirst())
            }
        return words.joined(separator: " ")
    }

    private static func parseSearchLine(_ line: String) -> (modelKey: String, summary: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("/") else { return nil }

        guard let regex = modelKeySearchRegex else { return nil }
        let nsrange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: nsrange),
              let keyRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }
        let modelKey = String(trimmed[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelKey.contains("/") else { return nil }

        let summary: String
        if let dashRange = trimmed.range(of: " — ") {
            summary = String(trimmed[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            summary = ""
        }
        return (modelKey, summary)
    }

    private static func runSDKHelperCommand(
        command: String,
        arguments: [String],
        timeoutSec: TimeInterval,
        onOutputUpdate: (@Sendable (String) -> Void)? = nil
    ) throws -> LMStudioCLIProcessResult {
        guard let scriptPath = marketHelperScriptPath() else {
            if command == "download" {
                throw LMStudioMarketBridgeError.downloadFailed(HubUIStrings.Models.MarketBridge.missingBundledBridge)
            }
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.missingBundledBridge)
        }
        guard let nodeLaunch = nodeLaunchConfig() else {
            if command == "download" {
                throw LMStudioMarketBridgeError.downloadFailed(HubUIStrings.Models.MarketBridge.missingNodeRuntime)
            }
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.missingNodeRuntime)
        }
        let realHome = SharedPaths.realHomeDirectory()
        let hubDirectory = SharedPaths.ensureHubDirectory()
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = realHome.path
        environment["PWD"] = realHome.path
        environment["XHUB_REAL_HOME"] = realHome.path
        environment["XHUB_HUB_DIR"] = hubDirectory.path
        environment["XHUB_MARKET_DIR"] = marketDownloadedModelsDirectory(baseDir: hubDirectory).path

        return runProcessCommand(
            executablePath: nodeLaunch.executablePath,
            arguments: nodeLaunch.argumentsPrefix + [scriptPath, command] + arguments,
            currentDirectoryURL: realHome,
            environment: environment,
            timeoutSec: timeoutSec,
            onOutputUpdate: onOutputUpdate
        )
    }

    private static func marketHelperScriptPath() -> String? {
        if let resourceURL = Bundle.main.resourceURL {
            let candidates = [
                resourceURL.appendingPathComponent("lmstudio_market_bridge.cjs"),
                resourceURL
                    .appendingPathComponent("RELFlowHub_RELFlowHub.bundle", isDirectory: true)
                    .appendingPathComponent("lmstudio_market_bridge.cjs"),
                resourceURL
                    .appendingPathComponent("RELFlowHub_RELFlowHub.bundle", isDirectory: true)
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("lmstudio_market_bridge.cjs"),
            ]
            if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })?.path {
                return path
            }
        }

        let sourceCandidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("lmstudio_market_bridge.cjs")
        if FileManager.default.fileExists(atPath: sourceCandidate.path) {
            return sourceCandidate.path
        }

        return nil
    }

    private static func nodeLaunchConfig() -> LMStudioNodeLaunchConfig? {
        let fileManager = FileManager.default

        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "relflowhub_node")?.path,
           fileManager.isExecutableFile(atPath: bundled) {
            return LMStudioNodeLaunchConfig(executablePath: bundled, argumentsPrefix: [])
        }
        if let bundledResource = Bundle.main.resourceURL?.appendingPathComponent("relflowhub_node").path,
           fileManager.isExecutableFile(atPath: bundledResource) {
            return LMStudioNodeLaunchConfig(executablePath: bundledResource, argumentsPrefix: [])
        }

        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] {
            if fileManager.isExecutableFile(atPath: candidate) {
                return LMStudioNodeLaunchConfig(executablePath: candidate, argumentsPrefix: [])
            }
        }

        if fileManager.isExecutableFile(atPath: "/usr/bin/env") {
            let probe = runProcessCommand(
                executablePath: "/usr/bin/env",
                arguments: ["node", "--version"],
                timeoutSec: 3.0
            )
            if probe.terminationStatus == 0 {
                return LMStudioNodeLaunchConfig(executablePath: "/usr/bin/env", argumentsPrefix: ["node"])
            }
        }

        return nil
    }

    private static func runCLICommand(
        helperBinaryPath: String,
        arguments: [String],
        timeoutSec: TimeInterval,
        stopWhen: (@Sendable (String) -> Bool)? = nil,
        onOutputUpdate: (@Sendable (String) -> Void)? = nil
    ) -> LMStudioCLIProcessResult {
        let realHome = SharedPaths.realHomeDirectory()
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = realHome.path
        environment["PWD"] = realHome.path
        return runProcessCommand(
            executablePath: helperBinaryPath,
            arguments: arguments,
            currentDirectoryURL: realHome,
            environment: environment,
            timeoutSec: timeoutSec,
            stopWhen: stopWhen,
            onOutputUpdate: onOutputUpdate
        )
    }

    private static func runProcessCommand(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL = SharedPaths.realHomeDirectory(),
        environment: [String: String]? = nil,
        timeoutSec: TimeInterval,
        stopWhen: (@Sendable (String) -> Bool)? = nil,
        onOutputUpdate: (@Sendable (String) -> Void)? = nil
    ) -> LMStudioCLIProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let accumulator = LMStudioCLIOutputAccumulator()
        let processBox = LMStudioProcessBox(process)
        let semaphore = DispatchSemaphore(value: 0)

        let append: @Sendable (Data, Bool) -> Void = { data, toStdout in
            guard !data.isEmpty else { return }
            let combined = accumulator.append(data, toStdout: toStdout)

            onOutputUpdate?(combined)
            if stopWhen?(combined) == true, processBox.process.isRunning {
                accumulator.setTerminatedByCallback()
                processBox.process.terminate()
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            append(data, true)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            append(data, false)
        }
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return LMStudioCLIProcessResult(
                stdout: "",
                stderr: "ProcessError: \(error.localizedDescription)",
                timedOut: false,
                terminatedByCallback: false,
                terminationStatus: -1
            )
        }

        var timedOut = false
        let waitResult = semaphore.wait(timeout: .now() + timeoutSec)
        if waitResult == .timedOut {
            timedOut = true
            if process.isRunning {
                process.terminate()
            }
            if semaphore.wait(timeout: .now() + 2.0) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = semaphore.wait(timeout: .now() + 1.0)
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let trailingStdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let trailingStderr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        append(trailingStdout, true)
        append(trailingStderr, false)

        let stdout = accumulator.stdoutString()
        let stderr = accumulator.stderrString()
        return LMStudioCLIProcessResult(
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut,
            terminatedByCallback: accumulator.terminatedByCallback,
            terminationStatus: process.terminationStatus
        )
    }

    static func helperFailureDetail(
        from rawOutput: String,
        timedOut: Bool,
        terminationStatus: Int32
    ) -> String {
        for event in helperEvents(from: rawOutput).reversed() {
            guard event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "error" else {
                continue
            }
            let message = event.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                return message
            }
        }

        let output = sanitizedTerminalOutput(rawOutput)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                !(line.hasPrefix("{") && line.hasSuffix("}"))
            }
            .suffix(4)
            .joined(separator: " ")
        if !output.isEmpty {
            return output
        }
        if timedOut {
            return HubUIStrings.Models.MarketBridge.helperTimedOut
        }
        return HubUIStrings.Models.MarketBridge.helperExitStatus(terminationStatus)
    }

    private static func cleanedProcessFailureDetail(_ result: LMStudioCLIProcessResult) -> String {
        helperFailureDetail(
            from: result.combinedOutput,
            timedOut: result.timedOut,
            terminationStatus: result.terminationStatus
        )
    }

    private static func lastMeaningfulOutputLine(_ rawOutput: String) -> String {
        let lines = sanitizedTerminalOutput(rawOutput)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                !line.hasPrefix("?")
                    && !line.contains("navigate")
                    && !line.contains("select")
            }
        return lines.last ?? ""
    }

    private static func sanitizedTerminalOutput(_ rawOutput: String) -> String {
        var text = applyBackspaces(rawOutput)
        if let regex = terminalEscapeRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        text = text.replacingOccurrences(of: "\r", with: "\n")
        if let regex = nonPrintableControlRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        return text
    }

    private static func applyBackspaces(_ rawOutput: String) -> String {
        var buffer: [Character] = []
        buffer.reserveCapacity(rawOutput.count)
        for character in rawOutput {
            if character == "\u{8}" {
                if !buffer.isEmpty {
                    buffer.removeLast()
                }
                continue
            }
            buffer.append(character)
        }
        return String(buffer)
    }

    private static func descriptorMatchingTokens(_ descriptor: LMStudioDownloadedModelDescriptor) -> Set<String> {
        let rawValues = [
            descriptor.model,
            descriptor.displayName,
            descriptor.defaultIdentifier,
            descriptor.file,
            descriptor.indexedModelIdentifier,
        ]
        return Set(rawValues.flatMap { matchingTokens(from: $0) })
    }

    private static func normalizedMarketKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedMarketKeyParts(_ raw: String) -> [String] {
        normalizedMarketKey(raw)
            .split(separator: "/", maxSplits: 1)
            .map(String.init)
    }

    private static func extractedMarketKey(fromModelPath rawPath: String) -> String? {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let standardized = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
        let components = standardized
            .split(separator: "/")
            .map { String($0).lowercased() }

        if let marketIndex = components.firstIndex(of: "_market"),
           components.count > marketIndex + 2 {
            return "\(components[marketIndex + 1])/\(components[marketIndex + 2])"
        }

        if let lmstudioIndex = components.firstIndex(of: ".lmstudio"),
           let modelsIndex = components[(lmstudioIndex + 1)...].firstIndex(of: "models"),
           components.count > modelsIndex + 2 {
            return "\(components[modelsIndex + 1])/\(components[modelsIndex + 2])"
        }

        return nil
    }

    private static func matchingTokens(from raw: String) -> Set<String> {
        let lower = raw.lowercased()
        let components = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(
            components.filter { token in
                token.count >= 2 && !matchingStopWords.contains(token)
            }
        )
    }

    private static func stringValue(_ raw: Any?) -> String {
        (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let number = raw as? NSNumber {
            return number.intValue
        }
        if let value = raw as? Int {
            return value
        }
        if let text = raw as? String, let value = Int(text) {
            return value
        }
        return 0
    }
}

private extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }
}
