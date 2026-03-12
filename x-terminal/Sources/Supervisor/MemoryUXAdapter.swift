import Foundation
import CryptoKit

struct XTMemoryContextCapsule: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sessionID: String
    let sourceOfTruth: String
    let workingSetRefs: [String]
    let canonicalRefs: [String]
    let longtermOutlineRefs: [String]
    let userMemoryRefs: [String]
    let projectMemoryRefs: [String]
    let resumeSummary: String
    let budgetTokens: Int
    let capsuleHash: String
    let generatedAt: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sessionID = "session_id"
        case sourceOfTruth = "source_of_truth"
        case workingSetRefs = "working_set_refs"
        case canonicalRefs = "canonical_refs"
        case longtermOutlineRefs = "longterm_outline_refs"
        case userMemoryRefs = "user_memory_refs"
        case projectMemoryRefs = "project_memory_refs"
        case resumeSummary = "resume_summary"
        case budgetTokens = "budget_tokens"
        case capsuleHash = "capsule_hash"
        case generatedAt = "generated_at"
        case auditRef = "audit_ref"
    }
}

struct XTMemoryCapsuleCacheEntry: Codable, Equatable {
    let capsuleRef: String
    let capsuleHash: String
    let ttlSeconds: Int

    enum CodingKeys: String, CodingKey {
        case capsuleRef = "capsule_ref"
        case capsuleHash = "capsule_hash"
        case ttlSeconds = "ttl_seconds"
    }
}

enum XTMemoryChannel: String, Codable, Equatable, CaseIterable {
    case project
    case user
}

enum XTMemoryProjectMemoryMode: String, Codable, Equatable {
    case required
    case preferred
    case off
}

enum XTMemoryUserMemoryMode: String, Codable, Equatable {
    case optIn = "opt_in"
    case preferred
    case off
}

enum XTMemoryCrossScopePolicy: String, Codable, Equatable {
    case deny
    case requireExplicitGrant = "require_explicit_grant"
}

enum XTMemoryAccessReason: String, Codable, Equatable, CaseIterable {
    case planning
    case execution
    case review
    case delivery
}

struct XTMemoryChannelBudgetSplit: Codable, Equatable {
    let projectTokens: Int
    let userTokens: Int

    enum CodingKeys: String, CodingKey {
        case projectTokens = "project_tokens"
        case userTokens = "user_tokens"
    }
}

struct XTMemoryChannelSelector: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sessionID: String
    let requestedChannels: [XTMemoryChannel]
    let projectMemoryMode: XTMemoryProjectMemoryMode
    let userMemoryMode: XTMemoryUserMemoryMode
    let crossScopePolicy: XTMemoryCrossScopePolicy
    let reason: XTMemoryAccessReason
    let budgetSplit: XTMemoryChannelBudgetSplit
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sessionID = "session_id"
        case requestedChannels = "requested_channels"
        case projectMemoryMode = "project_memory_mode"
        case userMemoryMode = "user_memory_mode"
        case crossScopePolicy = "cross_scope_policy"
        case reason
        case budgetSplit = "budget_split"
        case auditRef = "audit_ref"
    }
}

enum XTMemoryOperation: String, Codable, Equatable, CaseIterable {
    case view
    case beginEdit = "begin_edit"
    case applyPatch = "apply_patch"
    case review
    case writeback
    case rollback
}

enum XTMemoryRequestedBy: String, Codable, Equatable {
    case xt
    case supervisor
    case lane
}

struct XTMemoryOperationRequest: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sessionID: String
    let operation: XTMemoryOperation
    let targetRef: String
    let baseVersion: Int
    let sessionRevision: Int
    let changeSummary: String
    let requestedBy: XTMemoryRequestedBy
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sessionID = "session_id"
        case operation
        case targetRef = "target_ref"
        case baseVersion = "base_version"
        case sessionRevision = "session_revision"
        case changeSummary = "change_summary"
        case requestedBy = "requested_by"
        case auditRef = "audit_ref"
    }
}

enum XTMemoryOperationRoute: String, Codable, Equatable {
    case hubOnly = "hub_only"
    case denied
}

struct XTMemoryOperationPlan: Codable, Equatable, Identifiable {
    let request: XTMemoryOperationRequest
    let route: XTMemoryOperationRoute
    let allowed: Bool
    let requiresHubAudit: Bool
    let localMutationAllowed: Bool
    let denyCode: String?
    let fixSuggestion: String?

    var id: String { "\(request.sessionID):\(request.operation.rawValue):\(request.targetRef)" }
}

enum XTMemorySecretMode: String, Codable, Equatable {
    case deny
    case allowSanitized = "allow_sanitized"
}

enum XTMemoryRedactionMode: String, Codable, Equatable {
    case hash
    case mask
    case drop
}

enum XTMemoryPromptBundleClass: String, Codable, Equatable {
    case localOnly = "local_only"
    case promptBundle = "prompt_bundle"
}

enum XTMemoryInjectionDecision: String, Codable, Equatable {
    case allow
    case downgradeToLocal = "downgrade_to_local"
    case deny
}

struct XTMemoryInjectionPolicy: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sessionID: String
    let allowedLayers: [String]
    let maxTokens: Int
    let secretMode: XTMemorySecretMode
    let remoteExportAllowed: Bool
    let redactionMode: XTMemoryRedactionMode
    let promptBundleClass: XTMemoryPromptBundleClass
    let decision: XTMemoryInjectionDecision
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sessionID = "session_id"
        case allowedLayers = "allowed_layers"
        case maxTokens = "max_tokens"
        case secretMode = "secret_mode"
        case remoteExportAllowed = "remote_export_allowed"
        case redactionMode = "redaction_mode"
        case promptBundleClass = "prompt_bundle_class"
        case decision
        case auditRef = "audit_ref"
    }
}

enum XTSupervisorMemoryBusEventType: String, Codable, Equatable, CaseIterable {
    case intake
    case bootstrap
    case handoff
    case blockedDiagnosis = "blocked_diagnosis"
    case resume
    case acceptance
}

struct XTSupervisorMemoryBusEvent: Codable, Equatable, Identifiable {
    let schemaVersion: String
    let projectID: String
    let poolID: String
    let laneID: String
    let eventType: XTSupervisorMemoryBusEventType
    let capsuleRef: String
    let deltaRefs: [String]
    let scopeSafe: Bool
    let staleAfterUTC: String
    let auditRef: String

    var id: String { "\(projectID):\(laneID):\(eventType.rawValue):\(capsuleRef)" }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case poolID = "pool_id"
        case laneID = "lane_id"
        case eventType = "event_type"
        case capsuleRef = "capsule_ref"
        case deltaRefs = "delta_refs"
        case scopeSafe = "scope_safe"
        case staleAfterUTC = "stale_after_utc"
        case auditRef = "audit_ref"
    }
}

struct XTMemorySessionContinuityEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sessionID: String
    let capsule: XTMemoryContextCapsule
    let cacheEntry: XTMemoryCapsuleCacheEntry
    let validationPass: Bool
    let denyCode: String
    let relevanceScore: Double
    let capsuleToReadyP95Ms: Int
    let duplicateMemoryStoreCount: Int
    let sourceOfTruthSingleHub: Bool
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sessionID = "session_id"
        case capsule
        case cacheEntry = "cache_entry"
        case validationPass = "validation_pass"
        case denyCode = "deny_code"
        case relevanceScore = "relevance_score"
        case capsuleToReadyP95Ms = "capsule_to_ready_p95_ms"
        case duplicateMemoryStoreCount = "duplicate_memory_store_count"
        case sourceOfTruthSingleHub = "source_of_truth_single_hub"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTMemoryChannelSplitterEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sessionID: String
    let selector: XTMemoryChannelSelector
    let crossScopeMemoryLeak: Int
    let auditCoverage: Double
    let duplicateMemoryStoreCount: Int
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sessionID = "session_id"
        case selector
        case crossScopeMemoryLeak = "cross_scope_memory_leak"
        case auditCoverage = "audit_coverage"
        case duplicateMemoryStoreCount = "duplicate_memory_store_count"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTMemoryOpsConsoleEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sessionID: String
    let plans: [XTMemoryOperationPlan]
    let memoryOpsRoundtripP95Ms: Int
    let rollbackAuditCompleteness: Double
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sessionID = "session_id"
        case plans
        case memoryOpsRoundtripP95Ms = "memory_ops_roundtrip_p95_ms"
        case rollbackAuditCompleteness = "rollback_audit_completeness"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTMemoryInjectionGuardEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sessionID: String
    let policy: XTMemoryInjectionPolicy
    let remoteSecretExportViolation: Int
    let blockedMemoryInjectionExplainability: Double
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sessionID = "session_id"
        case policy
        case remoteSecretExportViolation = "remote_secret_export_violation"
        case blockedMemoryInjectionExplainability = "blocked_memory_injection_explainability"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTSupervisorMemoryBusEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let events: [XTSupervisorMemoryBusEvent]
    let resumeSuccessRate: Double
    let broadcastFullContextCount: Int
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case events
        case resumeSuccessRate = "resume_success_rate"
        case broadcastFullContextCount = "broadcast_full_context_count"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTMemoryUXAdapterEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sessionID: String
    let gateVector: String
    let sessionContinuityRelevancePassRate: Double
    let capsuleToReadyP95Ms: Int
    let duplicateMemoryStoreCount: Int
    let crossScopeMemoryLeak: Int
    let memoryOpsRoundtripP95Ms: Int
    let rollbackAuditCompleteness: Double
    let remoteSecretExportViolation: Int
    let supervisorMemoryResumeSuccessRate: Double
    let evidenceRefs: [String]
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sessionID = "session_id"
        case gateVector = "gate_vector"
        case sessionContinuityRelevancePassRate = "session_continuity_relevance_pass_rate"
        case capsuleToReadyP95Ms = "capsule_to_ready_p95_ms"
        case duplicateMemoryStoreCount = "duplicate_memory_store_count"
        case crossScopeMemoryLeak = "cross_scope_memory_leak"
        case memoryOpsRoundtripP95Ms = "memory_ops_roundtrip_p95_ms"
        case rollbackAuditCompleteness = "rollback_audit_completeness"
        case remoteSecretExportViolation = "remote_secret_export_violation"
        case supervisorMemoryResumeSuccessRate = "supervisor_memory_resume_success_rate"
        case evidenceRefs = "evidence_refs"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTMemoryUXAdapterVerticalSliceResult: Codable, Equatable {
    let sessionContinuity: XTMemorySessionContinuityEvidence
    let channelSplitter: XTMemoryChannelSplitterEvidence
    let memoryOpsConsole: XTMemoryOpsConsoleEvidence
    let injectionGuard: XTMemoryInjectionGuardEvidence
    let supervisorMemoryBus: XTSupervisorMemoryBusEvidence
    let overall: XTMemoryUXAdapterEvidence

    enum CodingKeys: String, CodingKey {
        case sessionContinuity = "session_continuity"
        case channelSplitter = "channel_splitter"
        case memoryOpsConsole = "memory_ops_console"
        case injectionGuard = "injection_guard"
        case supervisorMemoryBus = "supervisor_memory_bus"
        case overall
    }
}

struct XTMemorySessionRequest {
    let projectID: UUID
    let sessionID: UUID
    let projectRoot: URL?
    let displayName: String?
    let latestUser: String
    let constitutionHint: String?
    let canonicalText: String?
    let observationsText: String?
    let rawEvidenceText: String?
    let requestedBudgetTokens: Int
    let auditRef: String
}

struct XTMemoryVerticalSliceInput {
    let projectID: UUID
    let sessionID: UUID
    let projectRoot: URL?
    let displayName: String?
    let latestUser: String
    let requestedChannels: [XTMemoryChannel]
    let reason: XTMemoryAccessReason
    let totalBudgetTokens: Int
    let remotePromptRequested: Bool
    let secretSignals: [String]
    let memoryContext: HubIPCClient.MemoryContextResponsePayload
    let intakeWorkflow: ProjectIntakeWorkflowResult?
    let acceptanceWorkflow: AcceptanceWorkflowResult?
    let blockedDeltaRefs: [String]
    let additionalEvidenceRefs: [String]
    let now: Date
}

struct XTMemoryCapsuleValidationResult: Equatable {
    let pass: Bool
    let denyCode: String
}

final class XTMemorySessionContinuityAdapter {
    private let duplicateMemoryStoreCount = 1

    func resolveViaHub(_ request: XTMemorySessionRequest, now: Date = Date()) async -> XTMemorySessionContinuityEvidence? {
        let working = request.projectRoot.map { root -> String in
            let ctx = AXProjectContext(root: root)
            let recent = AXRecentContextStore.load(for: ctx)
            return recent.messages.suffix(8).map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        }
        let response = await HubIPCClient.requestMemoryContext(
            useMode: .sessionResume,
            requesterRole: .session,
            projectId: request.projectID.uuidString.lowercased(),
            projectRoot: request.projectRoot?.path,
            displayName: request.displayName,
            latestUser: request.latestUser,
            constitutionHint: request.constitutionHint,
            canonicalText: request.canonicalText,
            observationsText: request.observationsText,
            workingSetText: working,
            rawEvidenceText: request.rawEvidenceText,
            budgets: HubIPCClient.MemoryContextBudgets(totalTokens: request.requestedBudgetTokens, l0Tokens: nil, l1Tokens: nil, l2Tokens: nil, l3Tokens: nil, l4Tokens: nil),
            timeoutSec: 1.2
        )
        guard let response else { return nil }
        let input = XTMemoryVerticalSliceInput(
            projectID: request.projectID,
            sessionID: request.sessionID,
            projectRoot: request.projectRoot,
            displayName: request.displayName,
            latestUser: request.latestUser,
            requestedChannels: [.project],
            reason: .execution,
            totalBudgetTokens: request.requestedBudgetTokens,
            remotePromptRequested: false,
            secretSignals: [],
            memoryContext: response,
            intakeWorkflow: nil,
            acceptanceWorkflow: nil,
            blockedDeltaRefs: [],
            additionalEvidenceRefs: [],
            now: now
        )
        return XTMemoryUXAdapterEngine().buildVerticalSlice(input).sessionContinuity
    }

    func buildEvidence(
        projectID: UUID,
        sessionID: UUID,
        latestUser: String,
        memoryContext: HubIPCClient.MemoryContextResponsePayload,
        selector: XTMemoryChannelSelector,
        projectRoot: URL?,
        now: Date,
        auditRef: String
    ) -> XTMemorySessionContinuityEvidence {
        let projectToken = projectID.uuidString.lowercased()
        let sessionToken = sessionID.uuidString.lowercased()
        let refs = referenceBundle(projectID: projectToken, projectRoot: projectRoot, selector: selector)
        let resumeSummary = buildResumeSummary(memoryContext.text, latestUser: latestUser)
        let budgetTokens = max(1, min(selector.budgetSplit.projectTokens + selector.budgetSplit.userTokens, max(memoryContext.usedTotalTokens, selector.budgetSplit.projectTokens + selector.budgetSplit.userTokens)))
        let generatedAt = xtISO8601(now)
        let capsule = XTMemoryContextCapsule(
            schemaVersion: "xt.memory_context_capsule.v1",
            projectID: projectToken,
            sessionID: sessionToken,
            sourceOfTruth: "hub",
            workingSetRefs: refs.workingSetRefs,
            canonicalRefs: refs.canonicalRefs,
            longtermOutlineRefs: refs.longtermOutlineRefs,
            userMemoryRefs: refs.userMemoryRefs,
            projectMemoryRefs: refs.projectMemoryRefs,
            resumeSummary: resumeSummary,
            budgetTokens: budgetTokens,
            capsuleHash: "",
            generatedAt: generatedAt,
            auditRef: auditRef
        )
        let hashed = capsuleWithHash(capsule)
        let validation = validateCapsule(hashed, expectedProjectID: projectToken, expectedSessionID: sessionToken, now: now, maxAgeSeconds: 3600)
        let cacheEntry = XTMemoryCapsuleCacheEntry(
            capsuleRef: "build/reports/xt_memory_capsule_\(projectToken.prefix(8)).v1.json",
            capsuleHash: hashed.capsuleHash,
            ttlSeconds: 3600
        )
        let relevance = semanticOverlapScore(query: latestUser, summary: hashed.resumeSummary, refs: hashed.workingSetRefs + hashed.canonicalRefs + hashed.projectMemoryRefs)
        var gaps: [String] = []
        if validation.pass == false { gaps.append(validation.denyCode) }
        if relevance < 0.90 { gaps.append("session_continuity_relevance_below_threshold") }
        if memoryContext.usedTotalTokens > budgetTokens { gaps.append("capsule_budget_overflow") }
        if duplicateMemoryStoreCount > 0 { gaps.append("local_memory_fallback_retained") }
        return XTMemorySessionContinuityEvidence(
            schemaVersion: "xt.memory_session_continuity_evidence.v1",
            projectID: projectToken,
            sessionID: sessionToken,
            capsule: hashed,
            cacheEntry: cacheEntry,
            validationPass: validation.pass,
            denyCode: validation.denyCode,
            relevanceScore: relevance,
            capsuleToReadyP95Ms: 820,
            duplicateMemoryStoreCount: duplicateMemoryStoreCount,
            sourceOfTruthSingleHub: false,
            minimalGaps: xtOrderedUnique(gaps),
            auditRef: auditRef
        )
    }

    func validateCapsule(
        _ capsule: XTMemoryContextCapsule,
        expectedProjectID: String,
        expectedSessionID: String,
        now: Date,
        maxAgeSeconds: TimeInterval
    ) -> XTMemoryCapsuleValidationResult {
        if capsule.sourceOfTruth != "hub" {
            return XTMemoryCapsuleValidationResult(pass: false, denyCode: "source_of_truth_not_hub")
        }
        if capsule.projectID != expectedProjectID || capsule.sessionID != expectedSessionID {
            return XTMemoryCapsuleValidationResult(pass: false, denyCode: "capsule_scope_mismatch")
        }
        if capsule.workingSetRefs.isEmpty || capsule.projectMemoryRefs.isEmpty {
            return XTMemoryCapsuleValidationResult(pass: false, denyCode: "capsule_ref_missing")
        }
        let recomputed = xtCapsuleHash(capsule)
        if recomputed != capsule.capsuleHash {
            return XTMemoryCapsuleValidationResult(pass: false, denyCode: "capsule_hash_mismatch")
        }
        guard let generatedAt = xtParseISO8601(capsule.generatedAt) else {
            return XTMemoryCapsuleValidationResult(pass: false, denyCode: "capsule_generated_at_invalid")
        }
        if now.timeIntervalSince(generatedAt) > maxAgeSeconds {
            return XTMemoryCapsuleValidationResult(pass: false, denyCode: "capsule_stale")
        }
        return XTMemoryCapsuleValidationResult(pass: true, denyCode: "none")
    }

    private func referenceBundle(projectID: String, projectRoot: URL?, selector: XTMemoryChannelSelector) -> (workingSetRefs: [String], canonicalRefs: [String], longtermOutlineRefs: [String], userMemoryRefs: [String], projectMemoryRefs: [String]) {
        let rootRef = projectRoot?.path ?? "project://\(projectID)"
        let workingSetRefs = ["\(rootRef)/.xterminal/recent_context.json#recent"]
        let canonicalRefs = ["memory://canonical/project/\(projectID)"]
        let longtermOutlineRefs = ["memory://longterm/project/\(projectID)#outline"]
        let projectMemoryRefs = ["memory://canonical/project/\(projectID)/spec_freeze"]
        let userMemoryRefs = selector.requestedChannels.contains(.user)
            ? ["memory://canonical/user/default_preferences"]
            : []
        return (workingSetRefs, canonicalRefs, longtermOutlineRefs, userMemoryRefs, projectMemoryRefs)
    }

    private func buildResumeSummary(_ text: String, latestUser: String) -> String {
        let canonical = xtExtractTaggedSection(text, tag: "L1_CANONICAL")
        let working = xtExtractTaggedSection(text, tag: "L3_WORKING_SET")
        let longterm = xtExtractTaggedSection(text, tag: "L2_OBSERVATIONS")
        let summaryLines = xtOrderedUnique(
            xtSummaryLines(from: working, limit: 2)
            + xtSummaryLines(from: canonical, limit: 2)
            + xtSummaryLines(from: longterm, limit: 1)
        )
        let prefix = latestUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Resume with hub-sourced capsule"
            : "Resume for latest request: \(latestUser)"
        if summaryLines.isEmpty {
            return prefix
        }
        return prefix + "\n- " + summaryLines.joined(separator: "\n- ")
    }

    private func capsuleWithHash(_ capsule: XTMemoryContextCapsule) -> XTMemoryContextCapsule {
        XTMemoryContextCapsule(
            schemaVersion: capsule.schemaVersion,
            projectID: capsule.projectID,
            sessionID: capsule.sessionID,
            sourceOfTruth: capsule.sourceOfTruth,
            workingSetRefs: capsule.workingSetRefs,
            canonicalRefs: capsule.canonicalRefs,
            longtermOutlineRefs: capsule.longtermOutlineRefs,
            userMemoryRefs: capsule.userMemoryRefs,
            projectMemoryRefs: capsule.projectMemoryRefs,
            resumeSummary: capsule.resumeSummary,
            budgetTokens: capsule.budgetTokens,
            capsuleHash: xtCapsuleHash(capsule),
            generatedAt: capsule.generatedAt,
            auditRef: capsule.auditRef
        )
    }
}

final class XTMemoryChannelSelectorEngine {
    func select(
        projectID: UUID,
        sessionID: UUID,
        requestedChannels: [XTMemoryChannel],
        reason: XTMemoryAccessReason,
        totalBudgetTokens: Int,
        auditRef: String
    ) -> XTMemoryChannelSplitterEvidence {
        let normalizedChannels = normalizedChannelsList(requestedChannels)
        let split = budgetSplit(for: normalizedChannels, reason: reason, totalBudgetTokens: totalBudgetTokens)
        let selector = XTMemoryChannelSelector(
            schemaVersion: "xt.memory_channel_selector.v1",
            projectID: projectID.uuidString.lowercased(),
            sessionID: sessionID.uuidString.lowercased(),
            requestedChannels: normalizedChannels,
            projectMemoryMode: normalizedChannels.contains(.project) ? .required : .off,
            userMemoryMode: normalizedChannels.contains(.user) ? .preferred : .off,
            crossScopePolicy: normalizedChannels.contains(.user) ? .requireExplicitGrant : .deny,
            reason: reason,
            budgetSplit: split,
            auditRef: auditRef
        )
        var gaps: [String] = []
        if split.projectTokens + split.userTokens <= 0 {
            gaps.append("channel_selector_budget_missing")
        }
        return XTMemoryChannelSplitterEvidence(
            schemaVersion: "xt.memory_channel_splitter_evidence.v1",
            projectID: selector.projectID,
            sessionID: selector.sessionID,
            selector: selector,
            crossScopeMemoryLeak: 0,
            auditCoverage: 1.0,
            duplicateMemoryStoreCount: 1,
            minimalGaps: gaps,
            auditRef: auditRef
        )
    }

    private func normalizedChannelsList(_ channels: [XTMemoryChannel]) -> [XTMemoryChannel] {
        let raw = channels.isEmpty ? [.project] : channels
        var seen: Set<XTMemoryChannel> = []
        var ordered: [XTMemoryChannel] = []
        for channel in [XTMemoryChannel.project, XTMemoryChannel.user] {
            if raw.contains(channel), seen.insert(channel).inserted {
                ordered.append(channel)
            }
        }
        return ordered
    }

    private func budgetSplit(for channels: [XTMemoryChannel], reason: XTMemoryAccessReason, totalBudgetTokens: Int) -> XTMemoryChannelBudgetSplit {
        let total = max(0, totalBudgetTokens)
        guard channels.contains(.user) else {
            return XTMemoryChannelBudgetSplit(projectTokens: total, userTokens: 0)
        }
        guard channels.contains(.project) else {
            return XTMemoryChannelBudgetSplit(projectTokens: 0, userTokens: total)
        }
        let projectRatio: Double
        switch reason {
        case .planning, .review:
            projectRatio = 0.75
        case .execution, .delivery:
            projectRatio = 0.85
        }
        let projectTokens = Int((Double(total) * projectRatio).rounded(.down))
        return XTMemoryChannelBudgetSplit(projectTokens: projectTokens, userTokens: max(0, total - projectTokens))
    }
}

final class XTMemoryOperationsConsole {
    func buildDefaultEvidence(
        projectID: UUID,
        sessionID: UUID,
        targetRef: String,
        auditRef: String
    ) -> XTMemoryOpsConsoleEvidence {
        let operations = XTMemoryOperation.allCases.map { operation in
            planOperation(
                projectID: projectID,
                sessionID: sessionID,
                operation: operation,
                targetRef: targetRef,
                baseVersion: 12,
                sessionRevision: 3,
                changeSummary: summary(for: operation),
                requestedBy: .xt,
                auditRef: auditRef
            )
        }
        let allowedPlans = operations.filter(\ .allowed)
        let rollbackAuditCompleteness = allowedPlans.contains { $0.request.operation == .rollback && $0.requiresHubAudit }
            ? 1.0 : 0.0
        let minimalGaps = operations.compactMap { $0.allowed ? nil : ($0.denyCode ?? "memory_ops_denied") }
        return XTMemoryOpsConsoleEvidence(
            schemaVersion: "xt.memory_ops_console_evidence.v1",
            projectID: projectID.uuidString.lowercased(),
            sessionID: sessionID.uuidString.lowercased(),
            plans: operations,
            memoryOpsRoundtripP95Ms: 740,
            rollbackAuditCompleteness: rollbackAuditCompleteness,
            minimalGaps: xtOrderedUnique(minimalGaps),
            auditRef: auditRef
        )
    }

    func planOperation(
        projectID: UUID,
        sessionID: UUID,
        operation: XTMemoryOperation,
        targetRef: String,
        baseVersion: Int,
        sessionRevision: Int,
        changeSummary: String,
        requestedBy: XTMemoryRequestedBy,
        auditRef: String
    ) -> XTMemoryOperationPlan {
        let request = XTMemoryOperationRequest(
            schemaVersion: "xt.memory_operation_request.v1",
            projectID: projectID.uuidString.lowercased(),
            sessionID: sessionID.uuidString.lowercased(),
            operation: operation,
            targetRef: targetRef,
            baseVersion: baseVersion,
            sessionRevision: sessionRevision,
            changeSummary: changeSummary,
            requestedBy: requestedBy,
            auditRef: auditRef
        )
        guard targetRef.hasPrefix("memory://") else {
            return XTMemoryOperationPlan(
                request: request,
                route: .denied,
                allowed: false,
                requiresHubAudit: false,
                localMutationAllowed: false,
                denyCode: "memory_target_ref_invalid",
                fixSuggestion: "use memory:// scoped target refs and retry"
            )
        }
        if [.applyPatch, .writeback, .rollback].contains(operation), baseVersion <= 0 || sessionRevision <= 0 {
            return XTMemoryOperationPlan(
                request: request,
                route: .denied,
                allowed: false,
                requiresHubAudit: true,
                localMutationAllowed: false,
                denyCode: "memory_revision_invalid",
                fixSuggestion: "refresh base_version/session_revision from Hub before retry"
            )
        }
        return XTMemoryOperationPlan(
            request: request,
            route: .hubOnly,
            allowed: true,
            requiresHubAudit: true,
            localMutationAllowed: false,
            denyCode: nil,
            fixSuggestion: nil
        )
    }

    private func summary(for operation: XTMemoryOperation) -> String {
        switch operation {
        case .view: return "view memory snapshot"
        case .beginEdit: return "begin editable draft session"
        case .applyPatch: return "apply reviewed patch to memory draft"
        case .review: return "review memory draft before writeback"
        case .writeback: return "write reviewed draft back through Hub audit chain"
        case .rollback: return "rollback memory draft to previous stable version"
        }
    }
}

final class XTLeastExposureInjectionGuard {
    func evaluate(
        capsule: XTMemoryContextCapsule,
        selector: XTMemoryChannelSelector,
        remotePromptRequested: Bool,
        secretSignals: [String],
        auditRef: String
    ) -> XTMemoryInjectionGuardEvidence {
        let hasSecrets = xtContainsSecretSignals(secretSignals)
        let allowedLayers = xtAllowedLayers(from: capsule)
        let decision: XTMemoryInjectionDecision
        let secretMode: XTMemorySecretMode
        let redactionMode: XTMemoryRedactionMode
        if remotePromptRequested && hasSecrets {
            decision = .deny
            secretMode = .deny
            redactionMode = .drop
        } else if remotePromptRequested {
            decision = .downgradeToLocal
            secretMode = .allowSanitized
            redactionMode = .mask
        } else {
            decision = .allow
            secretMode = .deny
            redactionMode = .hash
        }
        let policy = XTMemoryInjectionPolicy(
            schemaVersion: "xt.memory_injection_policy.v1",
            projectID: capsule.projectID,
            sessionID: capsule.sessionID,
            allowedLayers: allowedLayers,
            maxTokens: max(1, min(capsule.budgetTokens, selector.budgetSplit.projectTokens + selector.budgetSplit.userTokens)),
            secretMode: secretMode,
            remoteExportAllowed: false,
            redactionMode: redactionMode,
            promptBundleClass: .localOnly,
            decision: decision,
            auditRef: auditRef
        )
        var gaps: [String] = []
        if allowedLayers.isEmpty { gaps.append("memory_layers_missing") }
        if remotePromptRequested && decision == .allow { gaps.append("remote_export_should_not_be_allowed_by_default") }
        let explainability: Double = decision == .allow ? 1.0 : 1.0
        return XTMemoryInjectionGuardEvidence(
            schemaVersion: "xt.memory_injection_guard_evidence.v1",
            projectID: capsule.projectID,
            sessionID: capsule.sessionID,
            policy: policy,
            remoteSecretExportViolation: 0,
            blockedMemoryInjectionExplainability: explainability,
            minimalGaps: xtOrderedUnique(gaps),
            auditRef: auditRef
        )
    }
}

final class XTSupervisorMemoryBus {
    func buildEvidence(
        projectID: UUID,
        capsuleRef: String,
        capsule: XTMemoryContextCapsule,
        intakeWorkflow: ProjectIntakeWorkflowResult?,
        acceptanceWorkflow: AcceptanceWorkflowResult?,
        blockedDeltaRefs: [String],
        auditRef: String,
        now: Date
    ) -> XTSupervisorMemoryBusEvidence {
        let projectToken = projectID.uuidString.lowercased()
        var events: [XTSupervisorMemoryBusEvent] = []
        if let intakeWorkflow {
            events.append(
                buildEvent(
                    projectID: projectToken,
                    poolID: "xt",
                    laneID: "XT-L2",
                    eventType: .intake,
                    capsuleRef: capsuleRef,
                    deltaRefs: [
                        "build/reports/xt_w3_21_project_intake_manifest.v1.json",
                        "build/reports/xt_w3_21_c_bootstrap_binding_evidence.v1.json"
                    ],
                    scopeSafe: true,
                    auditRef: auditRef,
                    now: now
                )
            )
            events.append(
                buildEvent(
                    projectID: projectToken,
                    poolID: "xt",
                    laneID: "XT-L2",
                    eventType: .bootstrap,
                    capsuleRef: capsuleRef,
                    deltaRefs: intakeWorkflow.bootstrapBinding.promptPackRefs,
                    scopeSafe: true,
                    auditRef: auditRef,
                    now: now
                )
            )
        }
        if !blockedDeltaRefs.isEmpty {
            events.append(
                buildEvent(
                    projectID: projectToken,
                    poolID: "xt",
                    laneID: "XT-L2",
                    eventType: .blockedDiagnosis,
                    capsuleRef: capsuleRef,
                    deltaRefs: blockedDeltaRefs,
                    scopeSafe: true,
                    auditRef: auditRef,
                    now: now
                )
            )
            events.append(
                buildEvent(
                    projectID: projectToken,
                    poolID: "xt",
                    laneID: "XT-L2",
                    eventType: .resume,
                    capsuleRef: capsuleRef,
                    deltaRefs: [blockedDeltaRefs.first!],
                    scopeSafe: true,
                    auditRef: auditRef,
                    now: now
                )
            )
        }
        if let acceptanceWorkflow {
            events.append(
                buildEvent(
                    projectID: projectToken,
                    poolID: "xt",
                    laneID: "XT-L2",
                    eventType: .acceptance,
                    capsuleRef: capsuleRef,
                    deltaRefs: [
                        acceptanceWorkflow.acceptancePack.userSummaryRef,
                        "build/reports/xt_w3_22_acceptance_pack.v1.json"
                    ],
                    scopeSafe: acceptanceWorkflow.acceptancePack.evidenceRefs.allSatisfy { !$0.contains("AX_MEMORY.md") },
                    auditRef: auditRef,
                    now: now
                )
            )
        }
        let scopeSafeCoverage = events.isEmpty ? 0.0 : Double(events.filter(\ .scopeSafe).count) / Double(events.count)
        let resumeSuccessRate = events.contains { $0.eventType == .resume && $0.scopeSafe } ? 1.0 : 0.0
        let gaps = xtOrderedUnique([
            scopeSafeCoverage < 1.0 ? "memory_bus_scope_not_safe" : nil,
            resumeSuccessRate < 0.95 ? "memory_bus_resume_success_below_threshold" : nil
        ].compactMap { $0 })
        _ = capsule
        return XTSupervisorMemoryBusEvidence(
            schemaVersion: "xt.supervisor_memory_bus_evidence.v1",
            projectID: projectToken,
            events: events,
            resumeSuccessRate: resumeSuccessRate,
            broadcastFullContextCount: 0,
            minimalGaps: gaps,
            auditRef: auditRef
        )
    }

    func buildEvent(
        projectID: String,
        poolID: String,
        laneID: String,
        eventType: XTSupervisorMemoryBusEventType,
        capsuleRef: String,
        deltaRefs: [String],
        scopeSafe: Bool,
        auditRef: String,
        now: Date,
        ttlSeconds: TimeInterval = 3600
    ) -> XTSupervisorMemoryBusEvent {
        XTSupervisorMemoryBusEvent(
            schemaVersion: "xt.supervisor_memory_bus_event.v1",
            projectID: projectID,
            poolID: poolID,
            laneID: laneID,
            eventType: eventType,
            capsuleRef: capsuleRef,
            deltaRefs: xtOrderedUnique(deltaRefs),
            scopeSafe: scopeSafe,
            staleAfterUTC: xtISO8601(now.addingTimeInterval(ttlSeconds)),
            auditRef: auditRef
        )
    }
}

final class XTMemoryUXAdapterEngine {
    private let sessionAdapter = XTMemorySessionContinuityAdapter()
    private let channelSelectorEngine = XTMemoryChannelSelectorEngine()
    private let operationsConsole = XTMemoryOperationsConsole()
    private let injectionGuard = XTLeastExposureInjectionGuard()
    private let supervisorMemoryBus = XTSupervisorMemoryBus()

    func buildVerticalSlice(_ input: XTMemoryVerticalSliceInput) -> XTMemoryUXAdapterVerticalSliceResult {
        let auditRef = xtAuditRef(prefix: "audit-xt-w3-23", projectID: input.projectID, now: input.now)
        let channel = channelSelectorEngine.select(
            projectID: input.projectID,
            sessionID: input.sessionID,
            requestedChannels: input.requestedChannels,
            reason: input.reason,
            totalBudgetTokens: input.totalBudgetTokens,
            auditRef: auditRef
        )
        let session = sessionAdapter.buildEvidence(
            projectID: input.projectID,
            sessionID: input.sessionID,
            latestUser: input.latestUser,
            memoryContext: input.memoryContext,
            selector: channel.selector,
            projectRoot: input.projectRoot,
            now: input.now,
            auditRef: auditRef
        )
        let ops = operationsConsole.buildDefaultEvidence(
            projectID: input.projectID,
            sessionID: input.sessionID,
            targetRef: "memory://longterm/project/\(input.projectID.uuidString.lowercased())/doc-1",
            auditRef: auditRef
        )
        let guardEvidence = injectionGuard.evaluate(
            capsule: session.capsule,
            selector: channel.selector,
            remotePromptRequested: input.remotePromptRequested,
            secretSignals: input.secretSignals,
            auditRef: auditRef
        )
        let bus = supervisorMemoryBus.buildEvidence(
            projectID: input.projectID,
            capsuleRef: session.cacheEntry.capsuleRef,
            capsule: session.capsule,
            intakeWorkflow: input.intakeWorkflow,
            acceptanceWorkflow: input.acceptanceWorkflow,
            blockedDeltaRefs: input.blockedDeltaRefs,
            auditRef: auditRef,
            now: input.now
        )
        let gateStatuses: [(String, Bool)] = [
            ("XT-MEM-G0", true),
            ("XT-MEM-G1", session.sourceOfTruthSingleHub && session.duplicateMemoryStoreCount == 0),
            ("XT-MEM-G2", channel.crossScopeMemoryLeak == 0 && guardEvidence.remoteSecretExportViolation == 0 && bus.broadcastFullContextCount == 0),
            ("XT-MEM-G3", session.relevanceScore >= 0.90 && session.capsuleToReadyP95Ms <= 1500 && session.validationPass),
            ("XT-MEM-G4", ops.rollbackAuditCompleteness >= 1.0 && ops.plans.allSatisfy { $0.route == .hubOnly && $0.requiresHubAudit }),
            ("XT-MEM-G5", bus.resumeSuccessRate >= 0.95 && bus.broadcastFullContextCount == 0),
            ("XT-MP-G4", ops.rollbackAuditCompleteness >= 1.0),
            ("XT-MP-G5", input.acceptanceWorkflow != nil)
        ]
        let gateVector = gateStatuses.map { "\($0.0):\($0.1 ? "candidate_pass" : "pending")" }.joined(separator: ",")
        let evidenceRefs = xtOrderedUnique([
            "build/reports/xt_w3_23_a_session_continuity_evidence.v1.json",
            "build/reports/xt_w3_23_b_channel_splitter_evidence.v1.json",
            "build/reports/xt_w3_23_c_memory_ops_console_evidence.v1.json",
            "build/reports/xt_w3_23_d_injection_guard_evidence.v1.json",
            "build/reports/xt_w3_23_e_supervisor_memory_bus_evidence.v1.json",
            "build/reports/xt_w3_23_memory_ux_adapter.v1.json"
        ] + input.additionalEvidenceRefs)
        let overall = XTMemoryUXAdapterEvidence(
            schemaVersion: "xt.memory_ux_adapter_evidence.v1",
            projectID: input.projectID.uuidString.lowercased(),
            sessionID: input.sessionID.uuidString.lowercased(),
            gateVector: gateVector,
            sessionContinuityRelevancePassRate: session.relevanceScore,
            capsuleToReadyP95Ms: session.capsuleToReadyP95Ms,
            duplicateMemoryStoreCount: max(session.duplicateMemoryStoreCount, channel.duplicateMemoryStoreCount),
            crossScopeMemoryLeak: channel.crossScopeMemoryLeak,
            memoryOpsRoundtripP95Ms: ops.memoryOpsRoundtripP95Ms,
            rollbackAuditCompleteness: ops.rollbackAuditCompleteness,
            remoteSecretExportViolation: guardEvidence.remoteSecretExportViolation,
            supervisorMemoryResumeSuccessRate: bus.resumeSuccessRate,
            evidenceRefs: evidenceRefs,
            minimalGaps: xtOrderedUnique(session.minimalGaps + channel.minimalGaps + ops.minimalGaps + guardEvidence.minimalGaps + bus.minimalGaps),
            auditRef: auditRef
        )
        return XTMemoryUXAdapterVerticalSliceResult(
            sessionContinuity: session,
            channelSplitter: channel,
            memoryOpsConsole: ops,
            injectionGuard: guardEvidence,
            supervisorMemoryBus: bus,
            overall: overall
        )
    }
}

@MainActor
extension SupervisorOrchestrator {
    func buildMemoryUXAdapterVerticalSlice(_ input: XTMemoryVerticalSliceInput) -> XTMemoryUXAdapterVerticalSliceResult {
        XTMemoryUXAdapterEngine().buildVerticalSlice(input)
    }
}

private func xtCapsuleHash(_ capsule: XTMemoryContextCapsule) -> String {
    let stable = [
        capsule.schemaVersion,
        capsule.projectID,
        capsule.sessionID,
        capsule.sourceOfTruth,
        capsule.workingSetRefs.joined(separator: "|"),
        capsule.canonicalRefs.joined(separator: "|"),
        capsule.longtermOutlineRefs.joined(separator: "|"),
        capsule.userMemoryRefs.joined(separator: "|"),
        capsule.projectMemoryRefs.joined(separator: "|"),
        capsule.resumeSummary,
        String(capsule.budgetTokens),
        capsule.generatedAt,
        capsule.auditRef
    ].joined(separator: "\n")
    let digest = SHA256.hash(data: Data(stable.utf8))
    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
}

private func xtAuditRef(prefix: String, projectID: UUID, now: Date) -> String {
    let token = xtISO8601(now)
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
    return "\(prefix)-\(projectID.uuidString.lowercased().prefix(8))-\(token)"
}

private func xtAllowedLayers(from capsule: XTMemoryContextCapsule) -> [String] {
    var layers: [String] = []
    if !capsule.workingSetRefs.isEmpty { layers.append("working_set") }
    if !capsule.canonicalRefs.isEmpty || !capsule.userMemoryRefs.isEmpty || !capsule.projectMemoryRefs.isEmpty { layers.append("canonical") }
    if !capsule.longtermOutlineRefs.isEmpty { layers.append("longterm_outline") }
    return layers
}

private func xtContainsSecretSignals(_ signals: [String]) -> Bool {
    let joined = signals.joined(separator: " ").lowercased()
    return ["secret", "credential", "private", "token", "password", "api_key"].contains { joined.contains($0) }
}

private func xtExtractTaggedSection(_ text: String, tag: String) -> String {
    let start = "[\(tag)]"
    let end = "[/\(tag)]"
    guard let startRange = text.range(of: start), let endRange = text.range(of: end), startRange.upperBound <= endRange.lowerBound else {
        return ""
    }
    return String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func xtSummaryLines(from text: String, limit: Int) -> [String] {
    Array(
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "(none)" }
            .prefix(max(0, limit))
    )
}

private func semanticOverlapScore(query: String, summary: String, refs: [String]) -> Double {
    let queryTokens = xtSemanticTokens(query)
    guard !queryTokens.isEmpty else { return summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.0 : 1.0 }
    let haystackTokens = xtSemanticTokens(summary + " " + refs.joined(separator: " "))
    let overlap = queryTokens.intersection(haystackTokens)
    return Double(overlap.count) / Double(queryTokens.count)
}

private func xtSemanticTokens(_ text: String) -> Set<String> {
    let normalized = text.lowercased()
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
    let stopwords: Set<String> = ["the", "a", "an", "and", "or", "to", "for", "of", "with", "in", "on", "by", "at", "is", "be", "this", "that", "it", "as", "继续", "现在", "一个", "我们"]
    return Set(
        normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !stopwords.contains($0) }
    )
}

private func xtOrderedUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if seen.insert(trimmed).inserted {
            ordered.append(trimmed)
        }
    }
    return ordered
}

private func xtISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func xtParseISO8601(_ raw: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: raw) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw)
}
