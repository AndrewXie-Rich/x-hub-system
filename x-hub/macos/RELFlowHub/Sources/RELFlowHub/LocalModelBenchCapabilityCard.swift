import Foundation
import RELFlowHubCore

struct LocalModelBenchCapabilityCard: Equatable {
    enum Tone: String, Equatable {
        case neutral
        case success
        case caution
        case warning
    }

    struct Badge: Equatable, Identifiable {
        var title: String
        var tone: Tone

        var id: String { "\(tone.rawValue):\(title)" }
    }

    struct Insight: Equatable, Identifiable {
        var label: String
        var value: String

        var id: String { label }
    }

    var headline: String
    var summary: String
    var tone: Tone
    var badges: [Badge]
    var insights: [Insight]
    var notes: [String]
}

enum LocalModelBenchCapabilityCardBuilder {
    static func build(
        model: HubModel,
        taskKind: String,
        requestContext: LocalModelRuntimeRequestContext?,
        benchResult: ModelBenchResult?,
        explanation: LocalModelBenchMonitorExplanation?,
        runtimeStatus: AIRuntimeStatus?
    ) -> LocalModelBenchCapabilityCard {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedTaskKind = normalizedTaskKind.isEmpty
            ? benchResult?.taskKind ?? ""
            : normalizedTaskKind
        let taskTitle = LocalTaskRoutingCatalog.title(for: resolvedTaskKind)
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let providerMonitor = runtimeStatus?.monitorSnapshot?.providers.first(where: { $0.provider == providerID })

        let benchFailed = benchResult.map { !$0.ok } ?? false
        let verdict = (benchResult?.verdict ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackMode = (benchResult?.fallbackMode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackUsed = benchResult?.fallbackUsed == true || !fallbackMode.isEmpty
        let previewOnly = isPreviewOnlyVerdict(verdict)
        let cpuFallback = fallbackMode.localizedCaseInsensitiveContains("cpu")
        let queueActive = (providerMonitor?.queuedTaskCount ?? 0) > 0
        let needsWarmup = requiresWarmup(explanation: explanation)
        let residentReady = isResidentReady(requestContext: requestContext, explanation: explanation)

        let tone: LocalModelBenchCapabilityCard.Tone = {
            if benchFailed { return .warning }
            if cpuFallback || previewOnly || fallbackUsed || queueActive || needsWarmup { return .caution }
            switch explanation?.severity {
            case .warning:
                return .warning
            case .info:
                return .caution
            case .neutral, .none:
                return .success
            }
        }()

        let headline: String = {
            if benchFailed { return HubUIStrings.Models.Review.CapabilityCard.benchFailedHeadline }
            if cpuFallback { return HubUIStrings.Models.Review.CapabilityCard.cpuFallbackHeadline }
            if previewOnly { return HubUIStrings.Models.Review.Bench.previewOnly }
            if !verdict.isEmpty { return HubUIStrings.Models.Review.Bench.localizedVerdict(verdict) }
            let explanationHeadline = explanation?.headline.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !explanationHeadline.isEmpty { return explanationHeadline }
            return HubUIStrings.Models.Review.CapabilityCard.waitingBenchResult
        }()

        let summary: String = {
            if let benchResult, benchFailed {
                let reason = LocalModelRuntimeErrorPresentation.humanized(benchResult.reasonCode)
                return reason.isEmpty ? HubUIStrings.Models.Review.CapabilityCard.benchFailedSummary : reason
            }
            if !fallbackMode.isEmpty {
                return HubUIStrings.Models.Review.CapabilityCard.fallbackSummary(fallbackMode)
            }
            if let explanation, !explanation.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explanation.headline
            }
            if !verdict.isEmpty {
                return HubUIStrings.Models.Review.CapabilityCard.verdictSummary(
                    taskTitle: taskTitle,
                    verdict: HubUIStrings.Models.Review.Bench.localizedVerdict(verdict)
                )
            }
            return HubUIStrings.Models.Review.CapabilityCard.defaultSummary
        }()

        var badges: [LocalModelBenchCapabilityCard.Badge] = []
        if benchFailed {
            badges.append(.init(title: HubUIStrings.Models.Review.CapabilityCard.badgeFailed, tone: .warning))
        } else if !verdict.isEmpty {
            badges.append(.init(title: HubUIStrings.Models.Review.Bench.localizedVerdict(verdict), tone: previewOnly ? .caution : tone))
        }
        if cpuFallback {
            badges.append(.init(title: HubUIStrings.Models.Review.CapabilityCard.cpuFallbackHeadline, tone: .warning))
        } else if fallbackUsed {
            badges.append(.init(title: HubUIStrings.Models.Review.CapabilityCard.badgeFallbackUsed, tone: .caution))
        }
        if needsWarmup {
            badges.append(.init(title: HubUIStrings.Models.Review.CapabilityCard.badgeNeedsWarmup, tone: .caution))
        } else if residentReady {
            badges.append(.init(title: HubUIStrings.Models.Review.CapabilityCard.badgeResidentReady, tone: .success))
        }
        if queueActive, let providerMonitor {
            badges.append(.init(title: HubUIStrings.Models.Review.CapabilityCard.badgeQueued(providerMonitor.queuedTaskCount), tone: .caution))
        }
        badges = uniqueBadges(badges)

        var insights: [LocalModelBenchCapabilityCard.Insight] = [
            .init(label: HubUIStrings.Models.Review.CapabilityCard.insightSuitable, value: bestForText(taskKind: resolvedTaskKind, verdict: verdict, previewOnly: previewOnly)),
            .init(label: HubUIStrings.Models.Review.CapabilityCard.insightWarmup, value: warmupText(needsWarmup: needsWarmup, residentReady: residentReady)),
            .init(label: HubUIStrings.Models.Review.CapabilityCard.insightRuntime, value: runtimeText(
                providerID: providerID,
                providerMonitor: providerMonitor,
                benchResult: benchResult,
                fallbackMode: fallbackMode
            )),
            .init(label: HubUIStrings.Models.Review.CapabilityCard.insightScope, value: scopeText(
                taskTitle: taskTitle,
                requestContext: requestContext,
                benchResult: benchResult
            )),
        ]

        if let avoidFor = avoidForText(
            taskTitle: taskTitle,
            benchResult: benchResult,
            explanation: explanation,
            queueActive: queueActive,
            previewOnly: previewOnly,
            fallbackUsed: fallbackUsed
        ) {
            insights.insert(.init(label: HubUIStrings.Models.Review.CapabilityCard.insightAvoid, value: avoidFor), at: 1)
        }

        let notes = buildNotes(
            explanation: explanation,
            benchResult: benchResult,
            providerMonitor: providerMonitor
        )

        return LocalModelBenchCapabilityCard(
            headline: headline,
            summary: summary,
            tone: tone,
            badges: badges,
            insights: insights,
            notes: notes
        )
    }

    private static func bestForText(taskKind: String, verdict: String, previewOnly: Bool) -> String {
        if previewOnly {
            return HubUIStrings.Models.Review.CapabilityCard.bestForPreview
        }
        switch taskKind {
        case "text_generate":
            switch verdict.lowercased() {
            case "fast":
                return HubUIStrings.Models.Review.CapabilityCard.textFast
            case "balanced":
                return HubUIStrings.Models.Review.CapabilityCard.textBalanced
            case "heavy":
                return HubUIStrings.Models.Review.CapabilityCard.textHeavy
            default:
                return HubUIStrings.Models.Review.CapabilityCard.textDefault
            }
        case "embedding":
            return HubUIStrings.Models.Review.CapabilityCard.embedding
        case "speech_to_text":
            return HubUIStrings.Models.Review.CapabilityCard.speechToText
        case "text_to_speech":
            return HubUIStrings.Models.Review.CapabilityCard.textToSpeech
        case "vision_understand":
            return HubUIStrings.Models.Review.CapabilityCard.visionUnderstand
        case "ocr":
            return HubUIStrings.Models.Review.CapabilityCard.ocr
        case "classify":
            return HubUIStrings.Models.Review.CapabilityCard.classify
        case "rerank":
            return HubUIStrings.Models.Review.CapabilityCard.rerank
        default:
            return HubUIStrings.Models.Review.CapabilityCard.taskWorkflow(LocalTaskRoutingCatalog.title(for: taskKind))
        }
    }

    private static func avoidForText(
        taskTitle: String,
        benchResult: ModelBenchResult?,
        explanation: LocalModelBenchMonitorExplanation?,
        queueActive: Bool,
        previewOnly: Bool,
        fallbackUsed: Bool
    ) -> String? {
        if let benchResult, !benchResult.ok {
            let reason = LocalModelRuntimeErrorPresentation.humanized(benchResult.reasonCode)
            return reason.isEmpty ? HubUIStrings.Models.Review.CapabilityCard.avoidBeforeFix : reason
        }
        if previewOnly {
            return HubUIStrings.Models.Review.CapabilityCard.avoidPreview(taskTitle: taskTitle)
        }
        if fallbackUsed {
            return HubUIStrings.Models.Review.CapabilityCard.avoidBeforeNativeReady
        }
        if queueActive {
            return HubUIStrings.Models.Review.CapabilityCard.avoidQueueBurst
        }
        let monitorStrings = HubUIStrings.Models.Review.MonitorExplanation.self
        if let explanation,
           (explanation.headline.localizedCaseInsensitiveContains("unavailable")
            || explanation.headline.contains(monitorStrings.unsupportedKeyword)) {
            return explanation.headline
        }
        return nil
    }

    private static func warmupText(needsWarmup: Bool, residentReady: Bool) -> String {
        if needsWarmup {
            return HubUIStrings.Models.Review.CapabilityCard.warmupNeeded
        }
        if residentReady {
            return HubUIStrings.Models.Review.CapabilityCard.warmupNotNeeded
        }
        return HubUIStrings.Models.Review.CapabilityCard.warmupUnknown
    }

    private static func runtimeText(
        providerID: String,
        providerMonitor: AIRuntimeMonitorProvider?,
        benchResult: ModelBenchResult?,
        fallbackMode: String
    ) -> String {
        var parts: [String] = [HubUIStrings.Models.Review.CapabilityCard.runtimeProvider(providerID)]
        let source = (benchResult?.runtimeSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !source.isEmpty {
            parts.append(HubUIStrings.Models.Review.CapabilityCard.runtimeSource(source))
        }
        let resolution = (benchResult?.runtimeResolutionState ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolution.isEmpty {
            parts.append(HubUIStrings.Models.Review.CapabilityCard.runtimeResolution(resolution))
        }
        if let providerMonitor {
            parts.append(HubUIStrings.Models.Review.CapabilityCard.runtimeQueueActive(
                active: providerMonitor.activeTaskCount,
                limit: providerMonitor.concurrencyLimit
            ))
            if providerMonitor.queuedTaskCount > 0 {
                parts.append(HubUIStrings.Models.Review.CapabilityCard.badgeQueued(providerMonitor.queuedTaskCount))
            }
            if !providerMonitor.deviceBackend.isEmpty {
                parts.append(providerMonitor.deviceBackend)
            }
        }
        if !fallbackMode.isEmpty {
            parts.append(fallbackMode)
        }
        return HubUIStrings.Formatting.middleDotSeparated(parts)
    }

    private static func scopeText(
        taskTitle: String,
        requestContext: LocalModelRuntimeRequestContext?,
        benchResult: ModelBenchResult?
    ) -> String {
        var parts: [String] = [taskTitle]
        if let fixtureTitle = benchResult?.fixtureTitle.trimmingCharacters(in: .whitespacesAndNewlines), !fixtureTitle.isEmpty {
            parts.append(fixtureTitle)
        } else if let fixtureProfile = benchResult?.fixtureProfile.trimmingCharacters(in: .whitespacesAndNewlines), !fixtureProfile.isEmpty {
            parts.append(fixtureProfile)
        }
        if let requestContext {
            if requestContext.effectiveContextLength > 0 {
                parts.append(HubUIStrings.Models.Review.CapabilityCard.scopeContext(requestContext.effectiveContextLength))
            }
            parts.append(requestContext.shortSourceLabel)
        } else if let effectiveContextLength = benchResult?.effectiveContextLength, effectiveContextLength > 0 {
            parts.append(HubUIStrings.Models.Review.CapabilityCard.scopeContext(effectiveContextLength))
        }
        return HubUIStrings.Formatting.middleDotSeparated(parts)
    }

    private static func buildNotes(
        explanation: LocalModelBenchMonitorExplanation?,
        benchResult: ModelBenchResult?,
        providerMonitor: AIRuntimeMonitorProvider?
    ) -> [String] {
        var notes: [String] = []
        if let runtimeHint = benchResult?.runtimeHint.trimmingCharacters(in: .whitespacesAndNewlines), !runtimeHint.isEmpty {
            notes.append(runtimeHint)
        }
        if let providerMonitor, providerMonitor.oldestWaiterAgeMs > 0 {
            notes.append(HubUIStrings.Models.Review.CapabilityCard.oldestWait(providerMonitor.oldestWaiterAgeMs))
        }
        if let explanation {
            notes.append(contentsOf: explanation.detailLines)
        }
        return uniqueStrings(notes, limit: 3)
    }

    private static func requiresWarmup(explanation: LocalModelBenchMonitorExplanation?) -> Bool {
        guard let explanation else { return false }
        let monitorStrings = HubUIStrings.Models.Review.MonitorExplanation.self
        if explanation.headline.localizedCaseInsensitiveContains("cold start")
            || explanation.headline.contains(monitorStrings.coldStartKeyword) {
            return true
        }
        return explanation.detailLines.contains { line in
            line.localizedCaseInsensitiveContains("cold start")
                || line.localizedCaseInsensitiveContains("no matching loaded instance")
                || line.contains(monitorStrings.coldStartKeyword)
                || line.contains(monitorStrings.residentNoMatchingLoadedInstance)
        }
    }

    private static func isResidentReady(
        requestContext: LocalModelRuntimeRequestContext?,
        explanation: LocalModelBenchMonitorExplanation?
    ) -> Bool {
        if requestContext?.instanceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }
        guard let explanation else { return false }
        let monitorStrings = HubUIStrings.Models.Review.MonitorExplanation.self
        return explanation.detailLines.contains { line in
            line.localizedCaseInsensitiveContains("target resident: instance")
                || line.localizedCaseInsensitiveContains("matching load profile is already loaded")
                || line.contains(monitorStrings.residentInstancePrefix)
                || line.contains(monitorStrings.residentLoadConfigKeyword)
        }
    }

    private static func isPreviewOnlyVerdict(_ verdict: String) -> Bool {
        let normalized = verdict.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "preview only" || verdict == HubUIStrings.Models.Review.Bench.previewOnly
    }

    private static func uniqueBadges(
        _ values: [LocalModelBenchCapabilityCard.Badge]
    ) -> [LocalModelBenchCapabilityCard.Badge] {
        var out: [LocalModelBenchCapabilityCard.Badge] = []
        var seen: Set<String> = []
        for value in values {
            guard seen.insert(value.id).inserted else { continue }
            out.append(value)
        }
        return out
    }

    private static func uniqueStrings(_ values: [String], limit: Int) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for raw in values {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            out.append(token)
            if out.count >= limit {
                break
            }
        }
        return out
    }
}
