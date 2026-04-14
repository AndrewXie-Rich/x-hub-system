import SwiftUI
import RELFlowHubCore

private enum MarketDiscoverCategory: String, CaseIterable, Identifiable {
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
    var isDownloaded: Bool
    var isImported: Bool
    var runtimeReadiness: LocalLibraryRuntimeReadiness?

    static let notDownloaded = DiscoverModelMarketLifecycleStatus(
        isDownloaded: false,
        isImported: false,
        runtimeReadiness: nil
    )
}

enum DiscoverModelMarketLifecyclePlanner {
    static func status(
        for result: LMStudioMarketResult,
        matchingModel: HubModel?,
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
                runtimeReadiness: nil
            )
        }

        guard let matchingModel else {
            return DiscoverModelMarketLifecycleStatus(
                isDownloaded: true,
                isImported: true,
                runtimeReadiness: nil
            )
        }

        return DiscoverModelMarketLifecycleStatus(
            isDownloaded: true,
            isImported: true,
            runtimeReadiness: runtimeReadinessEvaluator(matchingModel)
        )
    }
}

@MainActor
private final class LocalModelMarketStore: ObservableObject {
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
        syncDownloadedLibrary(autoBenchNewModels: false)
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

    func syncDownloadedLibrary(autoBenchNewModels: Bool) {
        guard !isSyncingLibrary else { return }
        isSyncingLibrary = true

        Task { [weak self] in
            guard let self else { return }
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

struct DiscoverModelsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var marketStore = LocalModelMarketStore()
    @ObservedObject private var modelStore: ModelStore = .shared
    @ObservedObject private var hubStore: HubStore = .shared
    @State private var searchText: String = ""
    @State private var selectedCategory: MarketDiscoverCategory = .recommended
    @State private var displayLimit: Int = LocalModelMarketStore.pageSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            searchCard

            if !marketStore.errorText.isEmpty {
                banner(marketStore.errorText, tint: .red)
            }

            if !marketStore.statusText.isEmpty {
                banner(marketStore.statusText, tint: .blue)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if marketStore.isSearching || marketStore.isSyncingLibrary {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(progressText())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                    }

                    if marketStore.results.isEmpty, !(marketStore.isSearching || marketStore.isSyncingLibrary) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(HubUIStrings.Models.Discover.Summary.noResultsTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(HubUIStrings.Models.Discover.Summary.noResultsDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                    } else {
                        marketResultsHeader
                        marketSummaryChips
                        if selectedCategory == .recommended {
                            ForEach(recommendedSections) { section in
                                recommendedSection(section)
                            }
                        } else {
                            ForEach(marketStore.results) { result in
                                resultCard(result)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            HStack(spacing: 10) {
                Button(HubUIStrings.Models.Discover.Summary.refresh) {
                    runSearch(forceRefresh: true, resetLimit: false)
                }
                Button(HubUIStrings.Models.Discover.Summary.syncToLibrary) {
                    marketStore.syncDownloadedLibrary(autoBenchNewModels: false)
                }
                .disabled(marketStore.isSearching || marketStore.isSyncingLibrary || marketStore.downloadedImportableCount == 0)
                if canLoadMore {
                    Button(HubUIStrings.Models.Discover.Summary.showMore) {
                        displayLimit += LocalModelMarketStore.pageSize
                        runSearch(forceRefresh: false, resetLimit: false)
                    }
                    .disabled(marketStore.isSearching || marketStore.isSyncingLibrary)
                }
                Spacer()
                if marketStore.downloadedImportableCount == 0 {
                    Text(HubUIStrings.Models.Discover.Summary.noDownloadedModels)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(HubUIStrings.Models.Discover.Summary.downloadingCount(marketStore.downloadedImportableCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(HubUIStrings.Models.Discover.Summary.close) {
                    dismiss()
                }
            }
        }
        .padding(18)
        .frame(width: 760, height: 720)
        .onAppear {
            marketStore.loadRecommended(limit: displayLimit)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(HubUIStrings.Models.Discover.Summary.title)
                    .font(.headline)
                Text(HubUIStrings.Models.Discover.Summary.subtitle(LMStudioMarketBridge.downloadedModelsDisplayPath()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(HubUIStrings.Models.Discover.Summary.searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        runSearch(forceRefresh: false, resetLimit: true)
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        runSearch(forceRefresh: false, resetLimit: true)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button(HubUIStrings.Models.Discover.Summary.search) {
                    runSearch(forceRefresh: false, resetLimit: true)
                }
                .disabled(marketStore.isSearching)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MarketDiscoverCategory.allCases) { category in
                        suggestionChip(category.title, isSelected: selectedCategory == category) {
                            selectedCategory = category
                            runSearch(forceRefresh: false, resetLimit: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func suggestionChip(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue.opacity(0.22) : Color.white.opacity(0.06))
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.blue.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private var recommendedSections: [DiscoverModelMarketSection] {
        DiscoverModelMarketSectionPlanner.recommendedSections(from: marketStore.results)
    }

    private var marketResultsHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(marketResultsTitle())
                .font(.subheadline.weight(.semibold))
            Text(marketResultsSubtitle())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private var marketSummaryChips: some View {
        let items = marketSummaryItems()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.title) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.systemName)
                            .imageScale(.small)
                        Text(item.title)
                        Text(HubUIStrings.Models.Library.countBadge(item.count))
                            .font(.caption2.monospaced())
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(item.tint.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func recommendedSection(_ section: DiscoverModelMarketSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: section.systemName)
                    .imageScale(.small)
                    .foregroundStyle(recommendedSectionTint(section))
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                Text(HubUIStrings.Models.Library.countBadge(section.results.count))
                    .font(.caption2.monospaced())
                    .foregroundStyle(recommendedSectionTint(section))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(recommendedSectionTint(section).opacity(0.12))
                    .clipShape(Capsule())
            }
            Text(section.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(section.results) { result in
                resultCard(result)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func resultCard(_ result: LMStudioMarketResult) -> some View {
        let lifecycleStatus = lifecycleStatus(for: result)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconTint(for: result).opacity(0.18))
                    Image(systemName: iconName(for: result))
                        .foregroundStyle(iconTint(for: result))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 6) {
                    let metaLine = resultMetaLine(for: result)
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                    Text(result.modelKey)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if !metaLine.isEmpty {
                        Text(metaLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !result.recommendationReason.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: result.staffPick ? "star.fill" : "sparkles")
                                .font(.caption2)
                                .foregroundStyle(result.staffPick ? .yellow : .blue)
                            Text(result.recommendationReason)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.primary.opacity(0.88))
                                .lineLimit(2)
                        }
                    }
                    if !result.summary.isEmpty {
                        Text(result.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    HStack(spacing: 6) {
                        ForEach(result.capabilityTags, id: \.self) { tag in
                            Text(ModelCapabilityPresentation.localizedTitle(for: tag))
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        Text(formatChipTitle(for: result))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(formatChipTint(for: result).opacity(0.18))
                            .clipShape(Capsule())
                        if result.staffPick {
                            Text(HubUIStrings.Models.Discover.Lifecycle.featured)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        if result.recommendedForThisMac {
                            Text(HubUIStrings.Models.Discover.Lifecycle.recommendedForMac)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    if let downloadStatus = marketStore.downloadStatus(for: result.modelKey) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(downloadStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } else if lifecycleStatus.isDownloaded && !lifecycleStatus.isImported {
                        Button(HubUIStrings.Models.Discover.Lifecycle.importToLibrary) {
                            marketStore.importDownloadedModel(result)
                        }
                        .disabled(marketStore.isSearching || marketStore.isSyncingLibrary)
                    } else if !lifecycleStatus.isDownloaded {
                        Button(HubUIStrings.Models.Discover.Lifecycle.download) {
                            marketStore.downloadRecommended(result)
                        }
                        .disabled(marketStore.isSearching)
                    }

                    marketLifecycleStage(lifecycleStatus)

                    Text(lifecycleDescription(for: result, status: lifecycleStatus))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 220)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func marketLifecycleStage(_ status: DiscoverModelMarketLifecycleStatus) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                marketLifecycleChip(HubUIStrings.Models.Discover.Lifecycle.downloaded, active: status.isDownloaded, tint: .blue)
                marketLifecycleChip(HubUIStrings.Models.Discover.Lifecycle.imported, active: status.isImported, tint: .green)
            }
            HStack(spacing: 6) {
                marketLifecycleChip(
                    HubUIStrings.Models.Discover.Lifecycle.runtimeUnavailable,
                    active: status.runtimeReadiness?.state == .unavailable,
                    tint: .orange
                )
                marketLifecycleChip(
                    HubUIStrings.Models.Discover.Lifecycle.ready,
                    active: status.runtimeReadiness?.state == .ready,
                    tint: .mint
                )
            }
        }
    }

    private func marketLifecycleChip(
        _ title: String,
        active: Bool,
        tint: Color
    ) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(active ? tint : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? tint.opacity(0.16) : Color.white.opacity(0.04))
            .overlay(
                Capsule()
                    .stroke(active ? tint.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private func progressText() -> String {
        if marketStore.isSearching {
            return HubUIStrings.Models.Discover.Summary.refreshingResults(selectedCategory.title)
        }
        return HubUIStrings.Models.Discover.Summary.syncingDownloadedModels
    }

    private func banner(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func iconName(for result: LMStudioMarketResult) -> String {
        let tags = Set(result.capabilityTags.map { $0.lowercased() })
        if tags.contains("vision") || tags.contains("ocr") {
            return "photo.on.rectangle.angled"
        }
        if tags.contains("embedding") {
            return "point.3.connected.trianglepath.dotted"
        }
        if tags.contains("voice") {
            return "speaker.wave.2.fill"
        }
        if tags.contains("coding") {
            return "curlybraces"
        }
        return "sparkles"
    }

    private func iconTint(for result: LMStudioMarketResult) -> Color {
        let tags = Set(result.capabilityTags.map { $0.lowercased() })
        if tags.contains("vision") || tags.contains("ocr") {
            return .orange
        }
        if tags.contains("embedding") {
            return .green
        }
        if tags.contains("voice") {
            return .mint
        }
        if tags.contains("coding") {
            return .blue
        }
        return .accentColor
    }

    private func recommendedSectionTint(_ section: DiscoverModelMarketSection) -> Color {
        switch section.id {
        case "coding":
            return .blue
        case "embedding":
            return .green
        case "voice":
            return .mint
        case "vision", "ocr":
            return .orange
        case "speech":
            return .pink
        case "text":
            return .secondary
        default:
            return .secondary
        }
    }

    private func formatChipTitle(for result: LMStudioMarketResult) -> String {
        switch result.formatHint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mlx":
            return HubUIStrings.Models.AddLocal.backendTitle("mlx")
        case "transformers":
            return HubUIStrings.Models.AddLocal.backendTitle("transformers")
        default:
            return result.formatHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? HubUIStrings.Models.Discover.Lifecycle.localFormat
                : result.formatHint.capitalized
        }
    }

    private func formatChipTint(for result: LMStudioMarketResult) -> Color {
        switch result.formatHint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mlx":
            return .green
        case "transformers":
            return .blue
        default:
            return .secondary
        }
    }

    private func downloadHelpText(for result: LMStudioMarketResult) -> String {
        let fit = normalizedFitEstimation(result.recommendedFitEstimation)
        if fit == "willnotfit" {
            return HubUIStrings.Models.Discover.Fit.manualVariantWarning
        }
        if result.recommendedForThisMac {
            return HubUIStrings.Models.Discover.Fit.recommendedDownloadHelp
        }
        return HubUIStrings.Models.Discover.Fit.genericDownloadHelp
    }

    private func resultMetaLine(for result: LMStudioMarketResult) -> String {
        var parts: [String] = []
        if result.recommendedSizeBytes > 0 {
            parts.append(formatBytes(result.recommendedSizeBytes))
        }

        switch normalizedFitEstimation(result.recommendedFitEstimation) {
        case "fullgpuoffload":
            parts.append(HubUIStrings.Models.Discover.Fit.fullGPU)
        case "partialgpuoffload":
            parts.append(HubUIStrings.Models.Discover.Fit.partialGPU)
        case "fitwithoutgpu":
            parts.append(HubUIStrings.Models.Discover.Fit.cpu)
        case "willnotfit":
            parts.append(HubUIStrings.Models.Discover.Fit.willNotFit)
        default:
            break
        }

        return HubUIStrings.Formatting.middleDotSeparated(parts)
    }

    private func normalizedFitEstimation(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    private func marketResultsTitle() -> String {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            if selectedCategory == .recommended {
                return HubUIStrings.Models.Discover.Summary.availableMarketModels
            }
            return HubUIStrings.Models.Discover.Summary.categoryTitle(selectedCategory.title)
        }
        if selectedCategory == .recommended {
            return HubUIStrings.Models.Discover.Summary.searchResults
        }
        return HubUIStrings.Models.Discover.Summary.categorySearchResults(selectedCategory.title)
    }

    private func marketResultsSubtitle() -> String {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = marketStore.results.count
        if trimmedQuery.isEmpty {
            if selectedCategory == .recommended {
                return HubUIStrings.Models.Discover.Summary.recommendedSubtitle(count)
            }
            return HubUIStrings.Models.Discover.Summary.categorySubtitle(count, category: selectedCategory.title)
        }
        if selectedCategory == .recommended {
            return HubUIStrings.Models.Discover.Summary.groupedSearchResults(count, query: trimmedQuery)
        }
        return HubUIStrings.Models.Discover.Summary.categorySearchResultsSubtitle(count, query: trimmedQuery, category: selectedCategory.title)
    }

    private func marketSummaryItems() -> [(title: String, systemName: String, count: Int, tint: Color)] {
        guard !marketStore.results.isEmpty else { return [] }

        let lifecycleStatuses = marketStore.results.map(lifecycleStatus(for:))
        let downloadedCount = lifecycleStatuses.filter(\.isDownloaded).count
        let importedCount = lifecycleStatuses.filter(\.isImported).count
        let runtimeUnavailableCount = lifecycleStatuses.filter { $0.runtimeReadiness?.state == .unavailable }.count
        let readyCount = lifecycleStatuses.filter { $0.runtimeReadiness?.state == .ready }.count
        let recommendedCount = marketStore.results.filter(\.recommendedForThisMac).count
        let largerCount = max(0, marketStore.results.count - recommendedCount)
        let capabilityDefinitions: [(title: String, systemName: String, tag: String, tint: Color)] = [
            (HubUIStrings.Models.Discover.Section.textTitle, "text.bubble", "Text", .secondary),
            (HubUIStrings.Models.Discover.Section.codingTitle, "curlybraces", "Coding", .blue),
            (HubUIStrings.Models.Discover.Section.voiceTitle, "speaker.wave.2.fill", "Voice", .mint),
            (HubUIStrings.Models.Discover.Section.visionTitle, "photo.on.rectangle", "Vision", .orange),
            (HubUIStrings.Models.Discover.Section.ocrTitle, "doc.text.viewfinder", "OCR", .orange),
            (HubUIStrings.Models.Discover.Section.embeddingTitle, "point.3.connected.trianglepath.dotted", "Embedding", .green),
            (HubUIStrings.Models.Discover.Section.speechTitle, "waveform", "Speech", .pink),
        ]

        var items: [(title: String, systemName: String, count: Int, tint: Color)] = []
        if downloadedCount > 0 {
            items.append((HubUIStrings.Models.Discover.Lifecycle.downloaded, "arrow.down.circle.fill", downloadedCount, .blue))
        }
        if importedCount > 0 {
            items.append((HubUIStrings.Models.Discover.Lifecycle.imported, "shippingbox.fill", importedCount, .green))
        }
        if runtimeUnavailableCount > 0 {
            items.append((HubUIStrings.Models.Discover.Lifecycle.runtimeUnavailable, "exclamationmark.triangle.fill", runtimeUnavailableCount, .orange))
        }
        if readyCount > 0 {
            items.append((HubUIStrings.Models.Discover.Lifecycle.ready, "checkmark.circle.fill", readyCount, .mint))
        }
        if recommendedCount > 0 {
            items.append((HubUIStrings.Models.Discover.Summary.recommendedChip, "checkmark.seal.fill", recommendedCount, .blue))
        }
        if largerCount > 0 {
            items.append((HubUIStrings.Models.Discover.Summary.largerModelsChip, "externaldrive.fill.badge.exclamationmark", largerCount, .orange))
        }

        for definition in capabilityDefinitions {
            let count = marketStore.results.filter { result in
                result.capabilityTags.contains(where: { $0.caseInsensitiveCompare(definition.tag) == .orderedSame })
            }.count
            if count > 0 {
                items.append((definition.title, definition.systemName, count, definition.tint))
            }
        }
        return items
    }

    private var canLoadMore: Bool {
        !marketStore.isSearching && marketStore.results.count >= displayLimit
    }

    private func runSearch(forceRefresh: Bool, resetLimit: Bool) {
        if resetLimit {
            displayLimit = LocalModelMarketStore.pageSize
        }
        marketStore.search(
            query: searchText,
            category: selectedCategory,
            limit: displayLimit,
            forceRefresh: forceRefresh
        )
    }

    private func lifecycleStatus(for result: LMStudioMarketResult) -> DiscoverModelMarketLifecycleStatus {
        let matchingModel = modelStore.snapshot.models.first { model in
            LMStudioMarketBridge.marketKeyMatchesModel(result.modelKey, model: model)
        }
        return DiscoverModelMarketLifecyclePlanner.status(
            for: result,
            matchingModel: matchingModel,
            runtimeReadinessEvaluator: runtimeReadiness(for:)
        )
    }

    private func runtimeReadiness(for model: HubModel) -> LocalLibraryRuntimeReadiness {
        LocalLibraryRuntimeReadinessResolver.readiness(for: model)
    }

    private func lifecycleDescription(
        for result: LMStudioMarketResult,
        status: DiscoverModelMarketLifecycleStatus
    ) -> String {
        guard status.isDownloaded else {
            return downloadHelpText(for: result)
        }
        guard status.isImported else {
            return HubUIStrings.Models.Discover.Lifecycle.downloadedCacheOnly
        }
        guard let runtimeReadiness = status.runtimeReadiness else {
            return HubUIStrings.Models.Discover.Lifecycle.importedCheckingRuntime
        }

        switch runtimeReadiness.state {
        case .ready:
            return HubUIStrings.Models.Discover.Lifecycle.importedReady(runtimeReadiness.detail)
        case .unavailable:
            let detail = LocalLibraryRuntimeReadinessResolver.collapsedDetail(runtimeReadiness.detail)
            if detail.isEmpty {
                return HubUIStrings.Models.Discover.Lifecycle.importedRuntimeUnavailableNoDetail
            }
            return HubUIStrings.Models.Discover.Lifecycle.importedRuntimeUnavailable(detail)
        }
    }
}
