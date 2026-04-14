import Foundation

private let hubOperatorChannelLiveTestSupportedProviders: Set<String> = [
    "slack",
    "telegram",
    "feishu",
    "whatsapp_cloud_api",
]

private let hubOperatorChannelLiveTestSchemaVersion = "xt_w3_24_operator_channel_live_test_evidence.v1"

struct HubOperatorChannelLiveTestEvidenceCheck: Codable, Equatable, Sendable {
    var name: String
    var status: String
    var detail: String
    var remediation: String
}

struct HubOperatorChannelLiveTestEvidenceProviderReleaseContext: Codable, Equatable, Sendable {
    var releaseStage: String
    var releaseBlocked: Bool
    var requireRealEvidence: Bool

    enum CodingKeys: String, CodingKey {
        case releaseStage = "release_stage"
        case releaseBlocked = "release_blocked"
        case requireRealEvidence = "require_real_evidence"
    }
}

struct HubOperatorChannelLiveTestEvidenceOnboardingSnapshot: Codable, Equatable, Sendable {
    var ticket: HubOperatorChannelOnboardingTicket?
    var latestDecision: HubOperatorChannelOnboardingApprovalDecision?
    var automationState: HubOperatorChannelOnboardingAutomationState?

    enum CodingKeys: String, CodingKey {
        case ticket
        case latestDecision = "latest_decision"
        case automationState = "automation_state"
    }
}

struct HubOperatorChannelLiveTestEvidenceReport: Codable, Equatable, Sendable {
    var schemaVersion: String
    var generatedAt: String
    var performedAt: String
    var provider: String
    var operatorVerdict: String
    var derivedStatus: String
    var liveTestSuccess: Bool
    var summary: String
    var reportScope: [String]
    var adminBaseURL: String
    var machineReadableEvidencePath: String
    var evidenceRefs: [String]
    var runtimeSnapshot: HubOperatorChannelProviderRuntimeStatus?
    var readinessSnapshot: HubOperatorChannelOnboardingDeliveryReadiness?
    var repairHints: [String]
    var onboardingSnapshot: HubOperatorChannelLiveTestEvidenceOnboardingSnapshot
    var providerReleaseContext: HubOperatorChannelLiveTestEvidenceProviderReleaseContext?
    var checks: [HubOperatorChannelLiveTestEvidenceCheck]
    var requiredNextStep: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case performedAt = "performed_at"
        case provider
        case operatorVerdict = "operator_verdict"
        case derivedStatus = "derived_status"
        case liveTestSuccess = "live_test_success"
        case summary
        case reportScope = "report_scope"
        case adminBaseURL = "admin_base_url"
        case machineReadableEvidencePath = "machine_readable_evidence_path"
        case evidenceRefs = "evidence_refs"
        case runtimeSnapshot = "runtime_snapshot"
        case readinessSnapshot = "readiness_snapshot"
        case repairHints = "repair_hints"
        case onboardingSnapshot = "onboarding_snapshot"
        case providerReleaseContext = "provider_release_context"
        case checks
        case requiredNextStep = "required_next_step"
    }
}

enum HubOperatorChannelLiveTestEvidenceBuilder {
    static func build(
        provider: String,
        verdict: String = "",
        summary: String = "",
        performedAt: Date = Date(),
        evidenceRefs: [String] = [],
        readiness: HubOperatorChannelOnboardingDeliveryReadiness?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus?,
        ticketDetail: HubOperatorChannelOnboardingTicketDetail?,
        adminBaseURL: String = "",
        outputPath: String = "",
        requiredNextStep: String = ""
    ) -> HubOperatorChannelLiveTestEvidenceReport {
        let normalizedProvider = normalizeProvider(provider)
        let checks = evaluateChecks(
            provider: normalizedProvider,
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: ticketDetail
        )
        let derivedStatus = deriveStatus(checks: checks)
        let normalizedVerdict = normalizeVerdict(verdict.isEmpty ? suggestedVerdict(forDerivedStatus: derivedStatus) : verdict)
        let reportRepairHints = combinedRepairHints(
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            automationState: ticketDetail?.automationState
        )

        return HubOperatorChannelLiveTestEvidenceReport(
            schemaVersion: hubOperatorChannelLiveTestSchemaVersion,
            generatedAt: isoString(from: Date()),
            performedAt: isoString(from: performedAt),
            provider: normalizedProvider,
            operatorVerdict: normalizedVerdict,
            derivedStatus: derivedStatus,
            liveTestSuccess: derivedStatus == "pass",
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? suggestedSummary(
                    provider: normalizedProvider,
                    derivedStatus: derivedStatus,
                    ticketDetail: ticketDetail
                )
                : summary.trimmingCharacters(in: .whitespacesAndNewlines),
            reportScope: ["XT-W3-24-S", "operator-channel-live-test"],
            adminBaseURL: adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            machineReadableEvidencePath: outputPath.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceRefs: normalizedEvidenceRefs(evidenceRefs),
            runtimeSnapshot: runtimeStatus,
            readinessSnapshot: readiness,
            repairHints: reportRepairHints,
            onboardingSnapshot: HubOperatorChannelLiveTestEvidenceOnboardingSnapshot(
                ticket: ticketDetail?.ticket,
                latestDecision: ticketDetail?.latestDecision,
                automationState: ticketDetail?.automationState
            ),
            providerReleaseContext: runtimeStatus.map {
                HubOperatorChannelLiveTestEvidenceProviderReleaseContext(
                    releaseStage: $0.releaseStage,
                    releaseBlocked: $0.releaseBlocked,
                    requireRealEvidence: $0.requireRealEvidence
                )
            },
            checks: checks,
            requiredNextStep: requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? defaultNextStep(from: checks)
                : requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func evaluateChecks(
        provider: String,
        readiness: HubOperatorChannelOnboardingDeliveryReadiness?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus?,
        ticketDetail: HubOperatorChannelOnboardingTicketDetail?
    ) -> [HubOperatorChannelLiveTestEvidenceCheck] {
        let strings = HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.self
        let firstSmoke = ticketDetail?.automationState?.firstSmoke
        let automationDeliveryReadiness = ticketDetail?.automationState?.deliveryReadiness
        let outboxPendingCount = ticketDetail?.automationState?.outboxPendingCount ?? 0
        let outboxDeliveredCount = ticketDetail?.automationState?.outboxDeliveredCount ?? 0
        let latestDecision = ticketDetail?.latestDecision?.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let runtimeRemediation = preferredRemediation(
            hintGroups: [runtimeStatus?.repairHints ?? []],
            fallback: provider == "telegram"
                ? strings.telegramRuntimeRemediation
                : strings.runtimeReloadRemediation
        )
        let deliveryRemediation = preferredRemediation(
            hintGroups: [
                automationDeliveryReadiness?.repairHints ?? [],
                readiness?.repairHints ?? [],
                runtimeStatus?.repairHints ?? [],
            ],
            extraHints: [
                automationDeliveryReadiness?.remediationHint ?? "",
                readiness?.remediationHint ?? "",
            ],
            fallback: strings.deliveryReadyRemediation
        )
        let releaseBoundaryRemediation = preferredRemediation(
            hintGroups: [runtimeStatus?.repairHints ?? []],
            fallback: provider == "whatsapp_cloud_api"
                ? strings.whatsAppReleaseBoundaryRemediation
                : strings.releaseBoundaryRemediation
        )
        let firstSmokeRemediation = preferredRemediation(
            hintGroups: [],
            extraHints: [firstSmoke?.remediationHint ?? ""],
            fallback: strings.firstSmokeRemediation
        )
        let outboxRemediation = preferredRemediation(
            hintGroups: [
                automationDeliveryReadiness?.repairHints ?? [],
                readiness?.repairHints ?? [],
                runtimeStatus?.repairHints ?? [],
            ],
            extraHints: [
                automationDeliveryReadiness?.remediationHint ?? "",
                readiness?.remediationHint ?? "",
                firstSmoke?.remediationHint ?? "",
            ],
            fallback: strings.outboxRemediation
        )
        let heartbeatGovernanceSnapshot = parsedHeartbeatGovernanceSnapshot(firstSmoke)

        return [
            makeCheck(
                name: "runtime_command_entry_ready",
                ok: runtimeStatus?.commandEntryReady ?? false,
                pending: runtimeStatus == nil,
                detail: runtimeStatus == nil
                    ? strings.runtimeStatusMissing
                    : strings.runtimeStatusDetail(
                        runtimeState: runtimeStatus?.runtimeState ?? "unknown",
                        commandEntryReady: runtimeStatus?.commandEntryReady ?? false
                    ),
                remediation: runtimeRemediation
            ),
            makeCheck(
                name: "delivery_ready",
                ok: (readiness?.ready ?? false) || (runtimeStatus?.deliveryReady ?? false),
                pending: readiness == nil && runtimeStatus == nil,
                detail: readiness == nil
                    ? (runtimeStatus == nil
                        ? strings.deliveryStatusMissing
                        : strings.deliveryReadyDetail(runtimeStatus?.deliveryReady ?? false))
                    : strings.readinessDetail(
                        ready: readiness?.ready ?? false,
                        replyEnabled: readiness?.replyEnabled ?? false,
                        credentialsConfigured: readiness?.credentialsConfigured ?? false
                    ),
                remediation: deliveryRemediation
            ),
            makeCheck(
                name: "release_ready_boundary",
                ok: runtimeStatus != nil && !(runtimeStatus?.releaseBlocked ?? true) && !(runtimeStatus?.requireRealEvidence ?? true),
                pending: runtimeStatus == nil,
                detail: runtimeStatus == nil
                    ? strings.releaseContextMissing
                    : strings.releaseBoundaryDetail(
                        releaseStage: runtimeStatus?.releaseStage ?? "unknown",
                        releaseBlocked: runtimeStatus?.releaseBlocked ?? false,
                        requireRealEvidence: runtimeStatus?.requireRealEvidence ?? false
                    ),
                remediation: releaseBoundaryRemediation
            ),
            makeCheck(
                name: "quarantine_ticket_recorded",
                ok: ticketDetail?.ticket != nil,
                pending: ticketDetail?.ticket == nil,
                detail: ticketDetail?.ticket == nil
                    ? strings.onboardingTicketMissing
                    : strings.onboardingTicketDetail(
                        ticketID: ticketDetail?.ticket.ticketId ?? "unknown",
                        status: ticketDetail?.ticket.displayStatus ?? "unknown",
                        conversation: ticketDetail?.ticket.conversationId ?? "unknown"
                    ),
                remediation: strings.onboardingTicketRemediation
            ),
            makeCheck(
                name: "approval_recorded",
                ok: latestDecision == "approve",
                pending: ticketDetail?.ticket == nil || ticketDetail?.latestDecision == nil,
                detail: ticketDetail?.latestDecision == nil
                    ? strings.approvalMissing
                    : strings.approvalDetail(
                        decision: ticketDetail?.latestDecision?.decision ?? "unknown",
                        grantProfile: ticketDetail?.latestDecision?.grantProfile ?? "unknown"
                    ),
                remediation: strings.approvalRemediation
            ),
            makeCheck(
                name: "first_smoke_executed",
                ok: firstSmoke?.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "query_executed",
                pending: ticketDetail?.latestDecision == nil || ticketDetail?.automationState == nil || firstSmoke == nil,
                detail: firstSmoke == nil
                    ? strings.firstSmokeMissing
                    : strings.firstSmokeDetail(
                        status: firstSmoke?.status ?? "unknown",
                        action: firstSmoke?.actionName ?? "unknown",
                        routeMode: firstSmoke?.routeMode ?? "unknown"
                    ),
                remediation: firstSmokeRemediation
            ),
            makeCheck(
                name: "heartbeat_governance_visible",
                ok: heartbeatGovernanceVisible(heartbeatGovernanceSnapshot),
                pending: ticketDetail?.automationState == nil || firstSmoke == nil,
                detail: firstSmoke == nil
                    ? strings.firstSmokeMissing
                    : strings.heartbeatGovernanceVisibilityDetail(
                        snapshotPresent: heartbeatGovernanceSnapshot != nil,
                        latestQualityBand: heartbeatGovernanceSnapshot?.latestQualityBand ?? "",
                        nextReviewKind: heartbeatGovernanceSnapshot?.nextReviewDue?.kind ?? ""
                    ),
                remediation: strings.heartbeatGovernanceVisibilityRemediation
            ),
            makeCheck(
                name: "outbox_drained",
                ok: outboxPendingCount == 0 && outboxDeliveredCount > 0,
                pending: ticketDetail?.automationState == nil,
                detail: ticketDetail?.automationState == nil
                    ? strings.automationStateMissing
                    : strings.outboxDetail(pending: outboxPendingCount, delivered: outboxDeliveredCount),
                remediation: outboxRemediation
            ),
        ]
    }

    static func deriveStatus(checks: [HubOperatorChannelLiveTestEvidenceCheck]) -> String {
        if checks.contains(where: { $0.status == "fail" }) { return "attention" }
        if checks.contains(where: { $0.status == "pending" }) { return "pending" }
        return "pass"
    }

    static func suggestedVerdict(forDerivedStatus derivedStatus: String) -> String {
        switch derivedStatus {
        case "pass":
            return "passed"
        case "attention":
            return "partial"
        default:
            return "pending"
        }
    }

    static func defaultFileName(provider: String, ticketId: String = "") -> String {
        let normalizedProvider = sanitizeFileComponent(normalizeProvider(provider))
        let normalizedTicketId = sanitizeFileComponent(ticketId)
        if normalizedTicketId.isEmpty {
            return "xt_w3_24_s_\(normalizedProvider)_live_test_evidence.v1.json"
        }
        return "xt_w3_24_s_\(normalizedProvider)_\(normalizedTicketId)_live_test_evidence.v1.json"
    }

    static func relativePathIfPossible(_ url: URL) -> String {
        guard let repoRoot = detectedRepoRoot() else { return url.path }
        let standardizedPath = url.standardizedFileURL.path
        let rootPath = repoRoot.standardizedFileURL.path
        guard standardizedPath.hasPrefix(rootPath) else { return standardizedPath }
        let relative = String(standardizedPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? "." : relative
    }

    static func suggestedSummary(
        provider: String,
        derivedStatus: String,
        ticketDetail: HubOperatorChannelOnboardingTicketDetail?
    ) -> String {
        let strings = HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.self
        let providerLabel = provider.isEmpty ? strings.unknownProviderLabel : provider.uppercased()
        if derivedStatus == "pass" {
            return strings.passSummary(providerLabel: providerLabel)
        }
        if let ticket = ticketDetail?.ticket, !ticket.conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return strings.conversationSummary(providerLabel: providerLabel, conversationID: ticket.conversationId)
        }
        return strings.localReviewSummary(providerLabel: providerLabel)
    }

    private static func makeCheck(
        name: String,
        ok: Bool,
        pending: Bool,
        detail: String,
        remediation: String
    ) -> HubOperatorChannelLiveTestEvidenceCheck {
        HubOperatorChannelLiveTestEvidenceCheck(
            name: name,
            status: pending ? "pending" : (ok ? "pass" : "fail"),
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            remediation: remediation.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func defaultNextStep(from checks: [HubOperatorChannelLiveTestEvidenceCheck]) -> String {
        checks.first(where: { $0.status != "pass" })?.remediation
            ?? HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.allChecksPassed
    }

    private static func combinedRepairHints(
        readiness: HubOperatorChannelOnboardingDeliveryReadiness?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus?,
        automationState: HubOperatorChannelOnboardingAutomationState?
    ) -> [String] {
        uniqueOrderedStrings(
            (runtimeStatus?.repairHints ?? [])
            + (readiness?.repairHints ?? [])
            + (automationState?.deliveryReadiness?.repairHints ?? [])
        )
    }

    private static func preferredRemediation(
        hintGroups: [[String]],
        extraHints: [String] = [],
        fallback: String
    ) -> String {
        let candidates = uniqueOrderedStrings(hintGroups.flatMap { $0 } + extraHints)
        return candidates.first ?? fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueOrderedStrings(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for raw in values {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard seen.insert(value).inserted else { continue }
            out.append(value)
        }
        return out
    }

    private static func normalizeProvider(_ provider: String) -> String {
        let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return hubOperatorChannelLiveTestSupportedProviders.contains(normalized) ? normalized : normalized
    }

    private static func normalizeVerdict(_ verdict: String) -> String {
        switch verdict.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pass", "passed", "success":
            return "passed"
        case "fail", "failed", "error":
            return "failed"
        case "partial", "warning":
            return "partial"
        default:
            return "pending"
        }
    }

    private static func parsedHeartbeatGovernanceSnapshot(
        _ receipt: HubOperatorChannelOnboardingFirstSmokeReceipt?
    ) -> HubOperatorChannelOnboardingFirstSmokeReceipt.HeartbeatGovernanceSnapshot? {
        if let snapshot = receipt?.heartbeatGovernanceSnapshot {
            return snapshot
        }
        let rawJSON = receipt?.heartbeatGovernanceSnapshotJSON?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawJSON.isEmpty, let data = rawJSON.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(
            HubOperatorChannelOnboardingFirstSmokeReceipt.HeartbeatGovernanceSnapshot.self,
            from: data
        )
    }

    private static func heartbeatGovernanceVisible(
        _ snapshot: HubOperatorChannelOnboardingFirstSmokeReceipt.HeartbeatGovernanceSnapshot?
    ) -> Bool {
        guard let snapshot else { return false }
        return !snapshot.latestQualityBand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(snapshot.nextReviewDue?.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func normalizedEvidenceRefs(_ refs: [String]) -> [String] {
        var seen = Set<String>()
        return refs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func sanitizeFileComponent(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = cleaned.map { char -> Character in
            if char.isLetter || char.isNumber || char == "_" || char == "-" {
                return char
            }
            return "_"
        }
        let collapsed = String(allowed).replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func detectedRepoRoot() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL] = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            Bundle.main.bundleURL.deletingLastPathComponent(),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true),
        ]

        for candidate in candidates {
            for ancestor in ancestorChain(startingAt: candidate) {
                let xTerminal = ancestor.appendingPathComponent("x-terminal", isDirectory: true)
                let xHub = ancestor.appendingPathComponent("x-hub", isDirectory: true)
                if fileManager.fileExists(atPath: xTerminal.path), fileManager.fileExists(atPath: xHub.path) {
                    return ancestor
                }
            }
        }
        return nil
    }

    private static func ancestorChain(startingAt url: URL) -> [URL] {
        var chain: [URL] = []
        var current = url.standardizedFileURL
        while true {
            chain.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return chain
    }
}

enum HubOperatorChannelLiveTestEvidenceExporter {
    static func defaultExportDirectory() -> URL {
        let fileManager = FileManager.default
        let directory: URL
        if let repoRoot = detectedRepoRoot() {
            directory = repoRoot
                .appendingPathComponent("x-terminal", isDirectory: true)
                .appendingPathComponent("build", isDirectory: true)
                .appendingPathComponent("reports", isDirectory: true)
        } else {
            directory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }

    static func write(_ report: HubOperatorChannelLiveTestEvidenceReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: url, options: .atomic)
    }

    private static func detectedRepoRoot() -> URL? {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var cursor = current.standardizedFileURL
        while true {
            let xTerminal = cursor.appendingPathComponent("x-terminal", isDirectory: true)
            let xHub = cursor.appendingPathComponent("x-hub", isDirectory: true)
            if FileManager.default.fileExists(atPath: xTerminal.path),
               FileManager.default.fileExists(atPath: xHub.path) {
                return cursor
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        return nil
    }
}
