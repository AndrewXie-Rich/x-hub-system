import AppKit
import SwiftUI
import RELFlowHubCore

enum MarketDiscoverCategory: String, CaseIterable, Identifiable {
    case recommended
    case chat
    case coding
    case voice
    case vision
    case ocr
    case embedding
    case speech

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended:
            return HubUIStrings.Models.Discover.Category.recommended
        case .chat:
            return HubUIStrings.Models.Discover.Category.chat
        case .coding:
            return HubUIStrings.Models.Discover.Category.coding
        case .voice:
            return HubUIStrings.Models.Discover.Category.voice
        case .vision:
            return HubUIStrings.Models.Discover.Category.vision
        case .ocr:
            return HubUIStrings.Models.Discover.Category.ocr
        case .embedding:
            return HubUIStrings.Models.Discover.Category.embedding
        case .speech:
            return HubUIStrings.Models.Discover.Category.speech
        }
    }

    var bridgeCategory: String {
        switch self {
        case .recommended:
            return ""
        default:
            return rawValue
        }
    }

    var capabilityTag: String? {
        switch self {
        case .recommended:
            return nil
        case .chat:
            return "Text"
        case .coding:
            return "Coding"
        case .voice:
            return "Voice"
        case .vision:
            return "Vision"
        case .ocr:
            return "OCR"
        case .embedding:
            return "Embedding"
        case .speech:
            return "Speech"
        }
    }
}

struct DiscoverModelMarketSection: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemName: String
    var results: [LMStudioMarketResult]
}

enum DiscoverModelMarketSectionPlanner {
    private struct SectionDefinition {
        var id: String
        var title: String
        var subtitle: String
        var systemName: String
    }

    private static let sectionDefinitions: [SectionDefinition] = [
        SectionDefinition(
            id: "text",
            title: HubUIStrings.Models.Discover.Section.textTitle,
            subtitle: HubUIStrings.Models.Discover.Section.textSubtitle,
            systemName: "text.bubble"
        ),
        SectionDefinition(
            id: "coding",
            title: HubUIStrings.Models.Discover.Section.codingTitle,
            subtitle: HubUIStrings.Models.Discover.Section.codingSubtitle,
            systemName: "curlybraces"
        ),
        SectionDefinition(
            id: "embedding",
            title: HubUIStrings.Models.Discover.Section.embeddingTitle,
            subtitle: HubUIStrings.Models.Discover.Section.embeddingSubtitle,
            systemName: "point.3.connected.trianglepath.dotted"
        ),
        SectionDefinition(
            id: "voice",
            title: HubUIStrings.Models.Discover.Section.voiceTitle,
            subtitle: HubUIStrings.Models.Discover.Section.voiceSubtitle,
            systemName: "speaker.wave.2.fill"
        ),
        SectionDefinition(
            id: "vision",
            title: HubUIStrings.Models.Discover.Section.visionTitle,
            subtitle: HubUIStrings.Models.Discover.Section.visionSubtitle,
            systemName: "photo.on.rectangle"
        ),
        SectionDefinition(
            id: "ocr",
            title: HubUIStrings.Models.Discover.Section.ocrTitle,
            subtitle: HubUIStrings.Models.Discover.Section.ocrSubtitle,
            systemName: "doc.text.viewfinder"
        ),
        SectionDefinition(
            id: "speech",
            title: HubUIStrings.Models.Discover.Section.speechTitle,
            subtitle: HubUIStrings.Models.Discover.Section.speechSubtitle,
            systemName: "waveform"
        ),
        SectionDefinition(
            id: "other",
            title: HubUIStrings.Models.Discover.Section.otherTitle,
            subtitle: HubUIStrings.Models.Discover.Section.otherSubtitle,
            systemName: "square.stack.3d.up"
        ),
    ]

    static func recommendedSections(from results: [LMStudioMarketResult]) -> [DiscoverModelMarketSection] {
        guard !results.isEmpty else { return [] }

        var groupedResults: [String: [LMStudioMarketResult]] = [:]
        for result in results {
            groupedResults[sectionID(for: result), default: []].append(result)
        }

        return sectionDefinitions.compactMap { definition in
            guard let sectionResults = groupedResults[definition.id], !sectionResults.isEmpty else {
                return nil
            }
            return DiscoverModelMarketSection(
                id: definition.id,
                title: definition.title,
                subtitle: definition.subtitle,
                systemName: definition.systemName,
                results: sectionResults
            )
        }
    }

    private static func sectionID(for result: LMStudioMarketResult) -> String {
        let tags = Set(
            result.capabilityTags.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )

        if tags.contains("coding") {
            return "coding"
        }
        if tags.contains("embedding") {
            return "embedding"
        }
        if tags.contains("voice") {
            return "voice"
        }
        if tags.contains("ocr") {
            return "ocr"
        }
        if tags.contains("vision") {
            return "vision"
        }
        if tags.contains("speech") {
            return "speech"
        }
        if tags.contains("text") {
            return "text"
        }
        return "other"
    }
}

struct DiscoverModelMarketLifecycleStatus: Equatable {
    enum VerificationStage: Equatable {
        case pendingVerification
        case needsReview
        case runtimeUnavailable
        case ready
    }

    var isDownloaded: Bool
    var isImported: Bool
    var runtimeReadiness: LocalLibraryRuntimeReadiness?
    var health: LocalModelHealthRecord?
    var isHealthScanning: Bool
    var verificationStage: VerificationStage?
    var matchingModelID: String?

    static let notDownloaded = DiscoverModelMarketLifecycleStatus(
        isDownloaded: false,
        isImported: false,
        runtimeReadiness: nil,
        health: nil,
        isHealthScanning: false,
        verificationStage: nil,
        matchingModelID: nil
    )
}

enum DiscoverModelMarketLifecyclePlanner {
    static func status(
        for result: LMStudioMarketResult,
        matchingModel: HubModel?,
        health: LocalModelHealthRecord? = nil,
        isHealthScanning: Bool = false,
        runtimeReadinessEvaluator: (HubModel) -> LocalLibraryRuntimeReadiness
    ) -> DiscoverModelMarketLifecycleStatus {
        guard result.downloaded else {
            return .notDownloaded
        }

        let isImported = result.inLibrary || matchingModel != nil
        guard isImported else {
            return DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: false,
                runtimeReadiness: nil,
                health: nil,
                isHealthScanning: false,
                verificationStage: nil,
                matchingModelID: nil
            )
        }

        guard let matchingModel else {
            return DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: nil,
                health: nil,
                isHealthScanning: false,
                verificationStage: .pendingVerification,
                matchingModelID: nil
            )
        }

        if isHealthScanning {
            return DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: nil,
                health: health,
                isHealthScanning: true,
                verificationStage: .pendingVerification,
                matchingModelID: matchingModel.id
            )
        }

        switch LocalModelHealthSupport.effectiveState(for: health) {
        case .healthy?:
            let readiness = runtimeReadinessEvaluator(matchingModel)
            return DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: readiness,
                health: health,
                isHealthScanning: false,
                verificationStage: readiness.state == .ready ? .ready : .runtimeUnavailable,
                matchingModelID: matchingModel.id
            )
        case .degraded?, .unknownStale?:
            return DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: nil,
                health: health,
                isHealthScanning: false,
                verificationStage: .needsReview,
                matchingModelID: matchingModel.id
            )
        case .blockedReadiness?, .blockedRuntime?:
            return DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: .unavailable(health?.detail ?? ""),
                health: health,
                isHealthScanning: false,
                verificationStage: .runtimeUnavailable,
                matchingModelID: matchingModel.id
            )
        case nil:
            return DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: nil,
                health: nil,
                isHealthScanning: false,
                verificationStage: .pendingVerification,
                matchingModelID: matchingModel.id
            )
        }
    }
}

@MainActor
final class LocalModelMarketStore: ObservableObject {
    private struct CachedSearchResults {
        var results: [LMStudioMarketResult]
        var cachedAt: TimeInterval
    }

    static let pageSize: Int = 24
    private static let cacheTTLSeconds: TimeInterval = 300
    private static var cachedResultsByRequest: [String: CachedSearchResults] = [:]
    private static var optimisticDownloadedMarketKeys: Set<String> = []
    private static var optimisticLibraryMarketKeys: Set<String> = []

    @Published private(set) var results: [LMStudioMarketResult] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var isSyncingLibrary: Bool = false
    @Published private(set) var statusText: String = ""
    @Published private(set) var errorText: String = ""
    @Published private(set) var downloadStatusByModelKey: [String: String] = [:]
    @Published private(set) var downloadedImportableCount: Int = 0

    private var currentSearchTask: Task<Void, Never>?
    private var downloadTasksByModelKey: [String: Task<Void, Never>] = [:]
    private let downloadsPath = LMStudioMarketBridge.downloadedModelsDisplayPath()

    func loadRecommended(limit: Int = pageSize) {
        search(query: "", category: .recommended, limit: limit, forceRefresh: false)
        syncDownloadedLibrary(autoBenchNewModels: false, allowPrompt: false)
    }

    func search(
        query: String,
        category: MarketDiscoverCategory,
        limit: Int,
        forceRefresh: Bool = false
    ) {
        currentSearchTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestKey = Self.requestKey(query: trimmedQuery, category: category, limit: limit)
        if !forceRefresh,
           let cached = Self.cachedResults(for: requestKey) {
            isSearching = false
            errorText = ""
            results = annotatedResults(from: cached)
            statusText = searchStatusText(
                query: trimmedQuery,
                category: category,
                count: results.count,
                limit: limit
            )
            return
        }
        isSearching = true
        errorText = ""
        statusText = searchInFlightStatusText(query: trimmedQuery, category: category)

        currentSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rawResults = try await Task.detached(priority: .userInitiated) {
                    try await LMStudioMarketBridge.searchModels(
                        query: trimmedQuery,
                        category: category.bridgeCategory,
                        limit: limit
                    )
                }.value
                if Task.isCancelled { return }
                let filteredResults = self.filteredResults(rawResults, category: category)
                Self.storeCachedResults(filteredResults, for: requestKey)
                self.results = self.annotatedResults(from: filteredResults)
                if self.results.isEmpty {
                    self.statusText = emptyResultsStatusText(query: trimmedQuery, category: category)
                } else {
                    self.statusText = self.searchStatusText(
                        query: trimmedQuery,
                        category: category,
                        count: self.results.count,
                        limit: limit
                    )
                }
            } catch {
                if Task.isCancelled { return }
                self.errorText = error.localizedDescription
                if let cached = Self.cachedResults(for: requestKey), !cached.isEmpty {
                    self.results = self.annotatedResults(from: cached)
                    self.statusText = HubUIStrings.Models.Discover.Summary.cachedRefreshFailure
                } else if !self.results.isEmpty {
                    self.results = self.annotatedResults(from: self.results)
                    self.statusText = HubUIStrings.Models.Discover.Summary.preservePreviousFailure
                } else {
                    self.statusText = ""
                }
            }
            self.isSearching = false
        }
    }

    func syncDownloadedLibrary(autoBenchNewModels: Bool, allowPrompt: Bool = true) {
        guard !isSyncingLibrary else { return }
        isSyncingLibrary = true

        Task { [weak self] in
            guard let self else { return }
            guard self.ensureDownloadedModelsAccess(allowPrompt: allowPrompt) else {
                self.isSyncingLibrary = false
                return
            }
            let helperBinary = LMStudioMarketBridge.helperBinaryPath()
            let descriptors = await Task.detached(priority: .utility) {
                LMStudioMarketBridge.loadDownloadedModels()
            }.value
            let entries = await Task.detached(priority: .utility) {
                LMStudioMarketBridge.catalogEntries(
                    from: descriptors,
                    helperBinaryPath: helperBinary
                )
            }.value
            let importedModelIDs = await ModelStore.shared.importCatalogEntries(
                entries,
                autoBenchNewModels: autoBenchNewModels
            )
            self.downloadedImportableCount = descriptors.filter { !$0.isBundled }.count
            self.recordOptimisticStates(from: descriptors)
            if !importedModelIDs.isEmpty {
                self.recordOptimisticLibraryStates(importedModelIDs: importedModelIDs)
            }
            self.results = self.annotatedResults(from: self.results)
            if importedModelIDs.isEmpty {
                self.statusText = self.downloadedImportableCount == 0
                    ? HubUIStrings.Models.Discover.Summary.emptyDownloadedModels(in: self.downloadsPath)
                    : HubUIStrings.Models.Discover.Summary.syncedExistingDownloads(in: self.downloadsPath)
            } else {
                self.statusText = HubUIStrings.Models.Discover.Summary.importedToLibrary(importedModelIDs.count)
            }
            self.isSyncingLibrary = false
        }
    }

    func downloadRecommended(_ result: LMStudioMarketResult) {
        guard downloadTasksByModelKey[result.modelKey] == nil else { return }
        errorText = ""
        downloadStatusByModelKey[result.modelKey] = HubUIStrings.Models.Discover.Summary.preparingDownload

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try LMStudioMarketBridge.downloadRecommended(
                        modelKey: result.modelKey,
                        downloadIdentifier: result.downloadIdentifier
                    ) { status in
                        Task { @MainActor [weak self] in
                            self?.downloadStatusByModelKey[result.modelKey] = status
                        }
                    }
                }.value

                self.markDownloaded(marketKey: result.modelKey)
                self.downloadStatusByModelKey[result.modelKey] = HubUIStrings.Models.Discover.Summary.finalizingImport
                let importedModelIDs = await self.waitForDownloadedModelImport(
                    marketKey: result.modelKey,
                    autoBenchNewModels: true
                )
                if !importedModelIDs.isEmpty {
                    self.markInLibrary(marketKey: result.modelKey)
                    self.recordOptimisticLibraryStates(importedModelIDs: importedModelIDs)
                }
                self.results = self.annotatedResults(from: self.results)
                if importedModelIDs.isEmpty {
                    self.statusText = HubUIStrings.Models.Discover.Summary.downloadedPendingLibrary(in: self.downloadsPath)
                } else {
                    self.statusText = HubUIStrings.Models.Discover.Summary.downloadedAndBenched(importedModelIDs.count)
                }
            } catch {
                self.errorText = error.localizedDescription
            }
            self.downloadStatusByModelKey.removeValue(forKey: result.modelKey)
            self.downloadTasksByModelKey.removeValue(forKey: result.modelKey)
        }

        downloadTasksByModelKey[result.modelKey] = task
    }

    func importDownloadedModel(_ result: LMStudioMarketResult) {
        guard downloadTasksByModelKey[result.modelKey] == nil else { return }
        errorText = ""
        downloadStatusByModelKey[result.modelKey] = HubUIStrings.Models.Discover.Summary.importingLibrary

        let task = Task { [weak self] in
            guard let self else { return }
            let importedModelIDs = await self.waitForDownloadedModelImport(
                marketKey: result.modelKey,
                autoBenchNewModels: true
            )
            self.markDownloaded(marketKey: result.modelKey)
            if !importedModelIDs.isEmpty {
                self.markInLibrary(marketKey: result.modelKey)
                self.recordOptimisticLibraryStates(importedModelIDs: importedModelIDs)
            }
            self.results = self.annotatedResults(from: self.results)
            if importedModelIDs.isEmpty {
                self.statusText = HubUIStrings.Models.Discover.Summary.importPendingIndex(in: self.downloadsPath)
            } else {
                self.statusText = HubUIStrings.Models.Discover.Summary.importedAndBenched(importedModelIDs.count)
            }
            self.downloadStatusByModelKey.removeValue(forKey: result.modelKey)
            self.downloadTasksByModelKey.removeValue(forKey: result.modelKey)
        }

        downloadTasksByModelKey[result.modelKey] = task
    }

    func downloadStatus(for modelKey: String) -> String? {
        downloadStatusByModelKey[modelKey]
    }

    private func filteredResults(
        _ rawResults: [LMStudioMarketResult],
        category: MarketDiscoverCategory
    ) -> [LMStudioMarketResult] {
        guard let capabilityTag = category.capabilityTag else { return rawResults }
        return rawResults.filter { result in
            result.capabilityTags.contains(where: { $0.caseInsensitiveCompare(capabilityTag) == .orderedSame })
        }
    }

    private func waitForDownloadedModelImport(
        marketKey: String,
        autoBenchNewModels: Bool
    ) async -> [String] {
        guard ensureDownloadedModelsAccess(allowPrompt: true) else {
            return []
        }
        let helperBinary = LMStudioMarketBridge.helperBinaryPath()
        for _ in 0..<10 {
            let descriptors = await Task.detached(priority: .utility) {
                LMStudioMarketBridge.loadDownloadedModels()
            }.value
            let matching = descriptors.filter { $0.matchesMarketKey(marketKey) }
            let entries = await Task.detached(priority: .utility) {
                LMStudioMarketBridge.catalogEntries(
                    from: matching.isEmpty ? descriptors : matching,
                    helperBinaryPath: helperBinary
                )
            }.value
            let importedModelIDs = await ModelStore.shared.importCatalogEntries(
                entries,
                autoBenchNewModels: autoBenchNewModels
            )
            if !matching.isEmpty || !importedModelIDs.isEmpty {
                return importedModelIDs
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return []
    }

    private func ensureDownloadedModelsAccess(allowPrompt: Bool) -> Bool {
        guard SharedPaths.isSandboxedProcess() else {
            return true
        }

        let downloadsURL = LMStudioMarketBridge.legacyDownloadedModelsDirectory(
            homeDirectory: SharedPaths.realHomeDirectory(),
            fileManager: .default
        ).standardizedFileURL
        if LocalModelAccessBookmarkStore.resolvedBookmarkURL(for: downloadsURL) != nil {
            return true
        }
        guard allowPrompt else {
            return false
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = downloadsURL.deletingLastPathComponent()
        panel.prompt = HubUIStrings.Models.AddLocal.choosePrompt
        panel.message = HubUIStrings.Models.Discover.Summary.downloadsAccessRequired(in: downloadsPath)
        guard panel.runModal() == .OK, let selectedURL = panel.url?.standardizedFileURL else {
            statusText = HubUIStrings.Models.Discover.Summary.downloadsAccessGrantFailed(in: downloadsPath)
            return false
        }
        guard downloadsRootIsCovered(downloadsURL: downloadsURL, selectedURL: selectedURL) else {
            statusText = HubUIStrings.Models.Discover.Summary.downloadsAccessInvalidSelection(in: downloadsPath)
            return false
        }

        let baseDir = SharedPaths.ensureHubDirectory()
        LocalModelAccessBookmarkStore.persistBookmarkIfPossible(
            for: selectedURL,
            baseDir: baseDir
        )
        if downloadsURL.path != selectedURL.path,
           downloadsURL.path.hasPrefix(selectedURL.path + "/") {
            do {
                try LocalModelAccessBookmarkStore.withScopedAccess(
                    to: selectedURL,
                    baseDir: baseDir
                ) {
                    LocalModelAccessBookmarkStore.persistBookmarkIfPossible(
                        for: downloadsURL,
                        baseDir: baseDir
                    )
                }
            } catch {
                statusText = HubUIStrings.Models.Discover.Summary.downloadsAccessGrantFailed(in: downloadsPath)
                return false
            }
        }

        let granted = LocalModelAccessBookmarkStore.resolvedBookmarkURL(
            for: downloadsURL,
            baseDir: baseDir
        ) != nil
        if !granted {
            statusText = HubUIStrings.Models.Discover.Summary.downloadsAccessGrantFailed(in: downloadsPath)
        }
        return granted
    }

    private func downloadsRootIsCovered(downloadsURL: URL, selectedURL: URL) -> Bool {
        let downloadsPath = downloadsURL.standardizedFileURL.path
        let selectedPath = selectedURL.standardizedFileURL.path
        guard !downloadsPath.isEmpty, !selectedPath.isEmpty else {
            return false
        }
        if downloadsPath == selectedPath {
            return true
        }
        return downloadsPath.hasPrefix(selectedPath + "/")
    }

    private func annotatedResults(from rawResults: [LMStudioMarketResult]) -> [LMStudioMarketResult] {
        let downloaded = LMStudioMarketBridge.loadDownloadedModels()
        downloadedImportableCount = downloaded.filter { !$0.isBundled }.count
        let libraryModels = ModelStore.shared.snapshot.models
        recordOptimisticStates(from: downloaded)
        return rawResults.map { raw in
            var updated = raw
            let normalizedKey = Self.normalizedMarketKey(raw.modelKey)
            let actualDownloaded = downloaded.contains { $0.matchesMarketKey(raw.modelKey) }
            let actualInLibrary = libraryModels.contains {
                LMStudioMarketBridge.marketKeyMatchesModel(raw.modelKey, model: $0)
            }
            updated.downloaded = actualDownloaded || Self.optimisticDownloadedMarketKeys.contains(normalizedKey)
            updated.inLibrary = actualInLibrary || Self.optimisticLibraryMarketKeys.contains(normalizedKey)
            return updated
        }
    }

    private func recordOptimisticStates(from descriptors: [LMStudioDownloadedModelDescriptor]) {
        for descriptor in descriptors {
            let key = Self.normalizedMarketKey("\(descriptor.user)/\(descriptor.model)")
            guard !key.isEmpty else { continue }
            Self.optimisticDownloadedMarketKeys.insert(key)
        }
    }

    private func recordOptimisticLibraryStates(importedModelIDs: [String]) {
        let libraryModels = ModelStore.shared.snapshot.models.filter { importedModelIDs.contains($0.id) }
        for model in libraryModels {
            for result in results where LMStudioMarketBridge.marketKeyMatchesModel(result.modelKey, model: model) {
                markDownloaded(marketKey: result.modelKey)
                markInLibrary(marketKey: result.modelKey)
            }
        }
    }

    private func markDownloaded(marketKey: String) {
        let normalizedKey = Self.normalizedMarketKey(marketKey)
        guard !normalizedKey.isEmpty else { return }
        Self.optimisticDownloadedMarketKeys.insert(normalizedKey)
    }

    private func markInLibrary(marketKey: String) {
        let normalizedKey = Self.normalizedMarketKey(marketKey)
        guard !normalizedKey.isEmpty else { return }
        Self.optimisticDownloadedMarketKeys.insert(normalizedKey)
        Self.optimisticLibraryMarketKeys.insert(normalizedKey)
    }

    private static func cachedResults(for query: String) -> [LMStudioMarketResult]? {
        guard let cached = cachedResultsByRequest[query] else { return nil }
        guard Date().timeIntervalSince1970 - cached.cachedAt <= cacheTTLSeconds else {
            cachedResultsByRequest.removeValue(forKey: query)
            return nil
        }
        return cached.results
    }

    private static func storeCachedResults(_ results: [LMStudioMarketResult], for query: String) {
        let normalizedResults = results.map { result in
            LMStudioMarketResult(
                modelKey: result.modelKey,
                title: result.title,
                summary: result.summary,
                formatHint: result.formatHint,
                capabilityTags: result.capabilityTags,
                staffPick: result.staffPick,
                recommendationReason: result.recommendationReason,
                recommendedForThisMac: result.recommendedForThisMac,
                recommendedFitEstimation: result.recommendedFitEstimation,
                recommendedSizeBytes: result.recommendedSizeBytes,
                downloadIdentifier: result.downloadIdentifier,
                downloaded: false,
                inLibrary: false
            )
        }
        cachedResultsByRequest[query] = CachedSearchResults(
            results: normalizedResults,
            cachedAt: Date().timeIntervalSince1970
        )
    }

    private static func normalizedMarketKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func requestKey(
        query: String,
        category: MarketDiscoverCategory,
        limit: Int
    ) -> String {
        [
            category.rawValue,
            normalizedMarketKey(query),
            String(max(1, limit))
        ].joined(separator: "::")
    }

    private func searchInFlightStatusText(
        query: String,
        category: MarketDiscoverCategory
    ) -> String {
        if !query.isEmpty {
            return HubUIStrings.Models.Discover.Summary.searchInFlight(category.title)
        }
        if category == .recommended {
            return HubUIStrings.Models.Discover.Summary.loadingRecommended
        }
        return HubUIStrings.Models.Discover.Summary.loadingCategory(category.title)
    }

    private func searchStatusText(
        query: String,
        category: MarketDiscoverCategory,
        count: Int,
        limit: Int
    ) -> String {
        if count == 0 {
            return emptyResultsStatusText(query: query, category: category)
        }
        let categoryPrefix = category == .recommended ? HubUIStrings.Models.Discover.Summary.marketCategoryPrefix : category.title
        let suffix = count >= limit ? HubUIStrings.Models.Discover.Summary.limitedSuffix(count) : ""
        if query.isEmpty {
            return HubUIStrings.Models.Discover.Summary.readyCategoryModels(count, categoryPrefix: categoryPrefix, suffix: suffix)
        }
        return HubUIStrings.Models.Discover.Summary.foundCategoryModels(count, categoryPrefix: categoryPrefix, suffix: suffix)
    }

    private func emptyResultsStatusText(
        query: String,
        category: MarketDiscoverCategory
    ) -> String {
        if query.isEmpty {
            return category == .recommended
                ? HubUIStrings.Models.Discover.Summary.noRecommendedModels()
                : HubUIStrings.Models.Discover.Summary.noAvailableCategory(category.title)
        }
        return HubUIStrings.Models.Discover.Summary.noMatchingCategory(category.title)
    }
}
