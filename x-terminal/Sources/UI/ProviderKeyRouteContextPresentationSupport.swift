import Foundation

struct XTProviderKeyRouteContext: Codable, Equatable, Sendable {
    var pool: HubProviderKeysClient.ProviderPool?
    var decision: ProviderKeySelectionDecision?
    var modelId: String?
    var importContextLines: [String]
    var importIssues: [XTProviderKeyImportIssueContext]

    static let empty = XTProviderKeyRouteContext(
        pool: nil,
        decision: nil,
        modelId: nil,
        importContextLines: [],
        importIssues: []
    )

    var primaryImportIssue: XTProviderKeyImportIssueContext? {
        importIssues.first
    }

    var hasSignal: Bool {
        pool != nil
            || decision != nil
            || modelId != nil
            || !importContextLines.isEmpty
            || !importIssues.isEmpty
    }
}

enum XTProviderKeyRouteContextPresentation {
    static func context(section: XTUnifiedDoctorSection?) -> XTProviderKeyRouteContext {
        guard let section else { return .empty }
        let projected = section.providerKeyRouteContextProjection
        let fallback = context(
            fromDoctorDetailLines: section.detailLines,
            pool: projected?.pool,
            decision: projected?.decision ?? section.providerKeySelectionProjection,
            modelId: projected?.modelId
        )
        return XTProviderKeyRouteContext(
            pool: projected?.pool ?? fallback.pool,
            decision: projected?.decision ?? section.providerKeySelectionProjection ?? fallback.decision,
            modelId: normalized(projected?.modelId)
                ?? normalized(section.providerKeySelectionProjection?.requestedModelId)
                ?? fallback.modelId,
            importContextLines: providerKeyRouteOrderedUnique(
                (projected?.importContextLines ?? []) + fallback.importContextLines
            ),
            importIssues: {
                if let projected, !projected.importIssues.isEmpty {
                    return projected.importIssues
                }
                return fallback.importIssues
            }()
        )
    }

    static func context(
        importSnapshot: HubProviderKeyImportSnapshot?,
        doctorSection: XTUnifiedDoctorSection? = nil,
        decision: ProviderKeySelectionDecision?,
        modelId: String?,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> XTProviderKeyRouteContext {
        let doctorContext = context(section: doctorSection)
        if let importSnapshot {
            let resolvedDecision = decision ?? doctorContext.decision
            return XTProviderKeyRouteContext(
                pool: doctorContext.pool,
                decision: resolvedDecision,
                modelId: normalized(modelId)
                    ?? doctorContext.modelId
                    ?? normalized(resolvedDecision?.requestedModelId),
                importContextLines: XTProviderKeyImportSourcePresentation.contextLines(
                    snapshot: importSnapshot,
                    decision: resolvedDecision,
                    language: language,
                    now: now
                ),
                importIssues: XTProviderKeyImportSourcePresentation.issues(
                    snapshot: importSnapshot,
                    decision: resolvedDecision,
                    language: language,
                    now: now
                )
            )
        }
        return XTProviderKeyRouteContext(
            pool: doctorContext.pool,
            decision: decision ?? doctorContext.decision,
            modelId: normalized(modelId)
                ?? doctorContext.modelId
                ?? normalized(decision?.requestedModelId),
            importContextLines: doctorContext.importContextLines,
            importIssues: doctorContext.importIssues
        )
    }

    static func context(
        pool: HubProviderKeysClient.ProviderPool? = nil,
        decision: ProviderKeySelectionDecision?,
        modelId: String?,
        importContextLines: [String] = [],
        importIssues: [XTProviderKeyImportIssueContext] = []
    ) -> XTProviderKeyRouteContext {
        XTProviderKeyRouteContext(
            pool: pool,
            decision: decision,
            modelId: normalized(modelId) ?? normalized(decision?.requestedModelId),
            importContextLines: providerKeyRouteOrderedUnique(importContextLines.compactMap(normalized)),
            importIssues: importIssues
        )
    }

    static func context(
        fromDoctorDetailLines detailLines: [String],
        pool: HubProviderKeysClient.ProviderPool? = nil,
        decision: ProviderKeySelectionDecision? = nil,
        modelId: String? = nil
    ) -> XTProviderKeyRouteContext {
        let resolvedPool = pool
            ?? XTProviderKeySelectionPresentation.pool(fromDoctorDetailLines: detailLines)
        let resolvedDecision = decision
            ?? XTProviderKeySelectionPresentation.decision(fromDoctorDetailLines: detailLines)
        let resolvedModelId = normalized(modelId)
            ?? normalized(resolvedDecision?.requestedModelId)
            ?? normalized(resolvedPool?.modelID)
            ?? normalized(
                XTProviderKeySelectionPresentation.requestedModelID(
                    fromDoctorDetailLines: detailLines
                )
            )
        return context(
            pool: resolvedPool,
            decision: resolvedDecision,
            modelId: resolvedModelId,
            importContextLines: XTProviderKeyImportSourcePresentation.contextLines(
                fromDoctorDetailLines: detailLines
            ),
            importIssues: XTProviderKeyImportSourcePresentation.issues(
                fromDoctorDetailLines: detailLines
            )
        )
    }

    static func summary(
        for context: XTProviderKeyRouteContext,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> XTDoctorProjectionSummary? {
        let resolvedModelId = context.modelId ?? normalized(context.decision?.requestedModelId)
        let selectionSummary = resolvedModelId.flatMap {
            XTProviderKeySelectionPresentation.summary(
                pool: context.pool,
                decision: context.decision,
                modelId: $0,
                language: language,
                now: now
            )
        }

        guard let primaryIssue = context.primaryImportIssue else {
            return selectionSummary
        }

        let lines = providerKeyRouteOrderedUnique(
            [
                providerKeyRouteContextSummaryLine(
                    XTL10n.text(language, zhHans: "当前阻塞", en: "Current Blocker"),
                    XTProviderKeyImportSourcePresentation.repairSummaryText(
                        for: primaryIssue,
                        language: language
                    )
                ),
                providerKeyRouteContextSummaryLine(
                    XTL10n.text(language, zhHans: "优先修复", en: "Repair Surface"),
                    providerKeyImportRepairTargetText(primaryIssue, language: language)
                )
            ] + (selectionSummary?.lines ?? [])
        )

        guard !lines.isEmpty else { return nil }
        return XTDoctorProjectionSummary(
            title: XTL10n.text(
                language,
                zhHans: "远端 Key 调度与导入源",
                en: "Remote Key Routing & Import Sources"
            ),
            lines: lines
        )
    }

    static func summary(
        decision: ProviderKeySelectionDecision?,
        modelId: String?,
        importSnapshot: HubProviderKeyImportSnapshot?,
        doctorSection: XTUnifiedDoctorSection? = nil,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> XTDoctorProjectionSummary? {
        summary(
            for: context(
                importSnapshot: importSnapshot,
                doctorSection: doctorSection,
                decision: decision,
                modelId: modelId,
                language: language,
                now: now
            ),
            language: language,
            now: now
        )
    }

    static func narrativeSummaryText(
        for context: XTProviderKeyRouteContext,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> String? {
        let resolvedModelId = context.modelId ?? normalized(context.decision?.requestedModelId)
        let evidence = resolvedModelId.flatMap {
            XTProviderKeySelectionPresentation.evidenceSummaryText(
                pool: context.pool,
                decision: context.decision,
                modelId: $0,
                language: language,
                now: now
            )
        }

        guard let primaryIssue = context.primaryImportIssue else {
            return evidence
        }

        return providerKeyRouteOrderedUnique(
            [
                XTProviderKeyImportSourcePresentation.repairSummaryText(
                    for: primaryIssue,
                    language: language
                ),
                evidence
            ]
                .compactMap(normalized)
        )
            .joined(separator: " ")
    }

    static func narrativeNextStepText(
        for context: XTProviderKeyRouteContext,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> String? {
        if let primaryIssue = context.primaryImportIssue {
            return XTProviderKeyImportSourcePresentation.repairInstructionText(
                for: primaryIssue,
                language: language
            )
        }

        guard let resolvedModelId = context.modelId ?? normalized(context.decision?.requestedModelId) else {
            return nil
        }
        return XTProviderKeySelectionPresentation.retryGuidanceText(
            pool: context.pool,
            decision: context.decision,
            modelId: resolvedModelId,
            language: language,
            now: now
        )
    }

    static func contextLines(
        for issue: UITroubleshootIssue,
        context: XTProviderKeyRouteContext,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> [String] {
        guard [.modelNotReady, .connectorScopeBlocked, .paidModelAccessBlocked].contains(issue) else {
            return []
        }

        let resolvedModelId = context.modelId ?? normalized(context.decision?.requestedModelId)
        let evidenceSummary = resolvedModelId.flatMap {
            XTProviderKeySelectionPresentation.evidenceSummaryText(
                pool: context.pool,
                decision: context.decision,
                modelId: $0,
                language: language,
                now: now
            )
        }
        let evidenceLines = resolvedModelId.map {
            XTProviderKeySelectionPresentation.compactEvidenceLines(
                pool: context.pool,
                decision: context.decision,
                modelId: $0,
                language: language,
                now: now
            )
        } ?? []

        var lines: [String] = []
        if issue == .modelNotReady,
           let primaryIssue = context.primaryImportIssue {
            lines.append(
                XTProviderKeyImportSourcePresentation.repairSummaryText(
                    for: primaryIssue,
                    language: language
                )
            )
        }
        lines.append(contentsOf: [evidenceSummary].compactMap(normalized))
        lines.append(contentsOf: evidenceLines)
        lines.append(contentsOf: context.importContextLines)
        return providerKeyRouteOrderedUnique(lines.compactMap(normalized))
    }

    static func guideOverride(
        for issue: UITroubleshootIssue,
        context: XTProviderKeyRouteContext,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> UITroubleshootGuide? {
        guard issue == .modelNotReady,
              let primaryIssue = context.primaryImportIssue else {
            return nil
        }

        return UITroubleshootGuide(
            issue: issue,
            summary: "\(XTProviderKeyImportSourcePresentation.repairSummaryText(for: primaryIssue, language: language)) 先把这条 Provider Key 导入链修好，再回来看模型路由是否仍然缺模型或缺 provider。",
            steps: [
                UITroubleshootStep(
                    index: 1,
                    instruction: "先在 Supervisor 控制中心 → AI 模型确认这次要命中的 model_id 没填错；否则会把导入源问题和目标模型写错混在一起。",
                    destination: .xtChooseModel
                ),
                UITroubleshootStep(
                    index: 2,
                    instruction: XTProviderKeyImportSourcePresentation.repairInstructionText(
                        for: primaryIssue,
                        language: language
                    ),
                    destination: .hubProviderKeys
                ),
                UITroubleshootStep(
                    index: 3,
                    instruction: "修复后回 XT 设置 → 诊断与核对 或运行 `/route diagnose` 重跑一次；只有导入源恢复后仍报 `model_not_found` / `provider_not_ready`，才继续追模型或 provider 本体。",
                    destination: .xtDiagnostics
                ),
            ]
        )
    }

    private static func providerKeyImportRepairTargetText(
        _ issue: XTProviderKeyImportIssueContext,
        language: XTInterfaceLanguage
    ) -> String {
        let sourceLabel = normalized(issue.sourceName) ?? issue.sourceRef
        let surface = XTL10n.text(
            language,
            zhHans: "X-Hub → 设置 → Provider Key 管理",
            en: "X-Hub -> Settings -> Provider Key Management"
        )
        guard let sourceLabel = normalized(sourceLabel) else {
            return surface
        }
        return "\(surface) · \(sourceLabel)"
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func providerKeyRouteContextSummaryLine(
        _ label: String,
        _ value: String
    ) -> String {
        "\(label)：\(value)"
    }
}

private func providerKeyRouteOrderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
        ordered.append(trimmed)
    }
    return ordered
}
