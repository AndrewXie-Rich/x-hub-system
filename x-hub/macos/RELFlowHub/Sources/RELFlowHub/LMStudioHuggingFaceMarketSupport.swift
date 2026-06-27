import Foundation
import RELFlowHubCore

extension LMStudioMarketBridge {
    static func searchModelsViaURLSession(
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

    static func fetchHuggingFaceRows(
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

    static func fetchHuggingFaceModelDetail(
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

    static func fetchHuggingFaceJSON<T: Decodable>(
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

    static func configuredHuggingFaceBaseURLString() -> String {
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

    static func huggingFaceBaseURLStrings(
        preferred: String? = nil
    ) -> [String] {
        resolvedHuggingFaceBaseURLStrings(
            preferred: preferred,
            configured: configuredHuggingFaceBaseURLString(),
            stored: storedHuggingFaceBaseURLString()
        )
    }

    static func huggingFaceSearchURL(
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

    static func huggingFaceModelInfoURL(
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

    static func huggingFaceToken() -> String? {
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

    static func humanizedHuggingFaceNetworkError(
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

    static func humanizedHuggingFaceStatusError(
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

    static func normalizeCapabilityToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func resolvedDiscoverCategory(for raw: String) -> String? {
        let normalized = normalizeCapabilityToken(raw)
        guard !normalized.isEmpty else { return nil }
        if categoryQueryExpansions[normalized] != nil {
            return normalized
        }
        return categoryQueryAliases[normalized]
    }

    static func uniqueSearchTerms(_ rawTerms: [String]) -> [String] {
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

    static func preparedSortScore(
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

    static func availableRecommendationBuckets(
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

    static func recommendationTargets(
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

    static func primaryFocusTag(for focusCategory: String?) -> String? {
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

    static func recommendationReason(
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

    static func fitAdjustedReason(_ base: String, fit: String) -> String {
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

    static func normalizedRecommendationFit(_ raw: String) -> String {
        normalizeCapabilityToken(raw.replacingOccurrences(of: "_", with: ""))
    }

    static func recommendationScore(
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

    static func fitScore(for raw: String) -> Double {
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

    static func formatScore(
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

    static func familyScore(
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

    static func sizeScore(
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

    static func popularityScore(
        downloads: Int,
        likes: Int
    ) -> Double {
        let downloadScore = min(log10(Double(max(downloads, 0)) + 1.0) * 12.0, 40.0)
        let likeScore = min(log10(Double(max(likes, 0)) + 1.0) * 8.0, 24.0)
        return downloadScore + likeScore
    }

    static func huggingFaceRepoID(for row: HuggingFaceModelRow) -> String {
        stringValue(row.id).isEmpty
            ? (stringValue(row.modelId).isEmpty ? stringValue(row.modelKey) : stringValue(row.modelId))
            : stringValue(row.id)
    }

    static func mergeHuggingFaceRows(
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

    static func preparedSearchResult(
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

    static func shouldSkipHuggingFaceRow(_ row: HuggingFaceModelRow) -> Bool {
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

    static func normalizedTags(for row: HuggingFaceModelRow) -> [String] {
        var tags: [String] = []
        tags.append(contentsOf: row.tags ?? [])
        tags.append(contentsOf: row.cardData?.tags ?? [])
        let pipeline = stringValue(row.pipeline_tag).isEmpty ? stringValue(row.pipelineTag) : stringValue(row.pipeline_tag)
        if !pipeline.isEmpty {
            tags.append(pipeline)
        }
        return Array(NSOrderedSet(array: tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })) as? [String] ?? []
    }

    static func normalizedSiblingNames(for row: HuggingFaceModelRow) -> [String] {
        (row.siblings ?? [])
            .map { siblingName(for: $0) }
            .filter { !$0.isEmpty }
    }

    static func siblingName(for sibling: HuggingFaceModelRow.Sibling) -> String {
        let candidates = [sibling.rfilename, sibling.path, sibling.name]
        for candidate in candidates {
            let trimmed = stringValue(candidate)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    static func siblingSize(for sibling: HuggingFaceModelRow.Sibling) -> Int64 {
        if let size = sibling.size, size > 0 {
            return size
        }
        if let size = sibling.lfs?.size, size > 0 {
            return size
        }
        return 0
    }

    static func detectFormatHint(for row: HuggingFaceModelRow) -> String {
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

    static func capabilityTags(for row: HuggingFaceModelRow) -> [String] {
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

    static func huggingFaceDisplayTitle(for row: HuggingFaceModelRow) -> String {
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

    static func huggingFaceSummary(for row: HuggingFaceModelRow) -> String {
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

    static func selectedDownloadFiles(
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

    static func fileIsAllowed(
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

    static func isLikelyVoiceSidecarBinary(_ loweredName: String) -> Bool {
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

    static func fitEstimation(for bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        guard memoryBytes > 0 else { return "" }
        let ratio = Double(bytes) / Double(memoryBytes)
        if ratio <= 0.18 { return "fullGPUOffload" }
        if ratio <= 0.33 { return "partialGPUOffload" }
        if ratio <= 0.55 { return "fitWithoutGPU" }
        return "willNotFit"
    }

    static func containsAny(_ haystack: String, values: [String]) -> Bool {
        let lowered = haystack.lowercased()
        return values.contains { lowered.contains($0.lowercased()) }
    }

}
