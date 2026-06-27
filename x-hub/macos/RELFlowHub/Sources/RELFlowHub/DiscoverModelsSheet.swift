import AppKit
import SwiftUI
import RELFlowHubCore

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
                    } else if let modelID = lifecycleStatus.matchingModelID,
                              shouldShowLifecycleVerifyAction(lifecycleStatus) {
                        Button(HubUIStrings.Models.Discover.Lifecycle.verifyAction) {
                            hubStore.scanLocalModelHealth(for: [modelID])
                        }
                        .disabled(
                            hubStore.localModelHealthScanInFlight
                                || hubStore.isLocalModelHealthScanInProgress(for: modelID)
                        )
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
                    HubUIStrings.Models.Discover.Lifecycle.pendingVerification,
                    active: status.verificationStage == .pendingVerification,
                    tint: .secondary
                )
                marketLifecycleChip(
                    HubUIStrings.Models.Discover.Lifecycle.needsReview,
                    active: status.verificationStage == .needsReview,
                    tint: .yellow
                )
            }
            HStack(spacing: 6) {
                marketLifecycleChip(
                    HubUIStrings.Models.Discover.Lifecycle.runtimeUnavailable,
                    active: status.verificationStage == .runtimeUnavailable,
                    tint: .orange
                )
                marketLifecycleChip(
                    HubUIStrings.Models.Discover.Lifecycle.ready,
                    active: status.verificationStage == .ready,
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
        let pendingVerificationCount = lifecycleStatuses.filter { $0.verificationStage == .pendingVerification }.count
        let reviewCount = lifecycleStatuses.filter { $0.verificationStage == .needsReview }.count
        let runtimeUnavailableCount = lifecycleStatuses.filter { $0.verificationStage == .runtimeUnavailable }.count
        let readyCount = lifecycleStatuses.filter { $0.verificationStage == .ready }.count
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
        if pendingVerificationCount > 0 {
            items.append((HubUIStrings.Models.Discover.Lifecycle.pendingVerification, "hourglass", pendingVerificationCount, .secondary))
        }
        if reviewCount > 0 {
            items.append((HubUIStrings.Models.Discover.Lifecycle.needsReview, "arrow.triangle.2.circlepath", reviewCount, .yellow))
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
        let health = matchingModel.flatMap { hubStore.localModelHealth(for: $0.id) }
        let isHealthScanning = matchingModel.map { hubStore.isLocalModelHealthScanInProgress(for: $0.id) } ?? false
        return DiscoverModelMarketLifecyclePlanner.status(
            for: result,
            matchingModel: matchingModel,
            health: health,
            isHealthScanning: isHealthScanning,
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

        switch status.verificationStage {
        case .pendingVerification?:
            return status.isHealthScanning
                ? HubUIStrings.Models.Discover.Lifecycle.importedVerificationScanning
                : HubUIStrings.Models.Discover.Lifecycle.importedVerificationPending
        case .needsReview?:
            let detail = LocalLibraryRuntimeReadinessResolver.collapsedDetail(status.health?.detail ?? "")
            if detail.isEmpty {
                return HubUIStrings.Models.Discover.Lifecycle.importedNeedsReviewNoDetail
            }
            return HubUIStrings.Models.Discover.Lifecycle.importedNeedsReview(detail)
        case .ready?:
            return HubUIStrings.Models.Discover.Lifecycle.importedReady(status.runtimeReadiness?.detail ?? "")
        case .runtimeUnavailable?:
            let detail = LocalLibraryRuntimeReadinessResolver.collapsedDetail(
                status.runtimeReadiness?.detail ?? status.health?.detail ?? ""
            )
            if detail.isEmpty {
                return HubUIStrings.Models.Discover.Lifecycle.importedRuntimeUnavailableNoDetail
            }
            return HubUIStrings.Models.Discover.Lifecycle.importedRuntimeUnavailable(detail)
        case nil:
            return HubUIStrings.Models.Discover.Lifecycle.importedVerificationPending
        }
    }

    private func shouldShowLifecycleVerifyAction(_ status: DiscoverModelMarketLifecycleStatus) -> Bool {
        guard status.isImported, !status.isHealthScanning else { return false }
        switch status.verificationStage {
        case .pendingVerification?, .needsReview?, .runtimeUnavailable?:
            return true
        case .ready?, nil:
            return false
        }
    }
}
