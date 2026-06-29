import Foundation

extension SupervisorManager {
    struct SupervisorPendingGrant: Identifiable, Equatable {
        var id: String
        var dedupeKey: String
        var grantRequestId: String
        var requestId: String
        var projectId: String
        var projectName: String
        var capability: String
        var modelId: String
        var reason: String
        var requestedTtlSec: Int
        var requestedTokenCap: Int
        var createdAt: TimeInterval?
        var actionURL: String?
        var priorityRank: Int
        var priorityReason: String
        var nextAction: String
    }

    struct SupervisorAutoGrantResolution {
        var ok: Bool
        var reasonCode: String
        var grantRequestId: String?
    }

    struct SupervisorPendingSkillApproval: Identifiable, Equatable {
        var id: String
        var requestId: String
        var projectId: String
        var projectName: String
        var jobId: String
        var planId: String
        var stepId: String
        var skillId: String
        var requestedSkillId: String? = nil
        var toolName: String
        var tool: ToolName?
        var toolSummary: String
        var reason: String
        var createdAt: TimeInterval?
        var actionURL: String?
        var routingReasonCode: String? = nil
        var routingExplanation: String? = nil
        var deltaApproval: XTSkillProfileDeltaApproval? = nil
        var readiness: XTSkillExecutionReadiness? = nil

        var requestedSkillIdText: String {
            requestedSkillId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    struct SupervisorRecentSkillActivity: Identifiable, Equatable {
        struct GovernanceEvidence: Equatable {
            var policyReason: String = ""
            var governanceReason: String = ""
            var blockedSummary: String = ""
            var governanceTruth: String = ""
            var repairAction: String = ""

            var hasAnyValue: Bool {
                !policyReason.isEmpty
                    || !governanceReason.isEmpty
                    || !blockedSummary.isEmpty
                    || !governanceTruth.isEmpty
                    || !repairAction.isEmpty
            }
        }

        struct GovernanceSummary: Equatable {
            var latestReviewId: String = ""
            var latestReviewVerdict: SupervisorReviewVerdict? = nil
            var latestReviewLevel: SupervisorReviewLevel? = nil
            var configuredExecutionTier: AXProjectExecutionTier? = nil
            var effectiveExecutionTier: AXProjectExecutionTier? = nil
            var configuredSupervisorTier: AXProjectSupervisorInterventionTier? = nil
            var effectiveSupervisorTier: AXProjectSupervisorInterventionTier? = nil
            var reviewPolicyMode: AXProjectReviewPolicyMode? = nil
            var progressHeartbeatSeconds: Int? = nil
            var reviewPulseSeconds: Int? = nil
            var brainstormReviewSeconds: Int? = nil
            var compatSource: AXProjectGovernanceCompatSource? = nil
            var effectiveWorkOrderDepth: AXProjectSupervisorWorkOrderDepth? = nil
            var followUpRhythmSummary: String = ""
            var workOrderRef: String = ""
            var latestGuidanceId: String = ""
            var latestGuidanceDeliveryMode: SupervisorGuidanceDeliveryMode? = nil
            var latestGuidanceSummary: String = ""
            var pendingGuidanceId: String = ""
            var pendingGuidanceAckStatus: SupervisorGuidanceAckStatus? = nil
            var pendingGuidanceRequired: Bool = false
            var pendingGuidanceSummary: String = ""
            var guidanceContract: SupervisorGuidanceContractSummary? = nil

            var activeGuidanceSummary: String {
                if let summary = normalizedGuidanceSummary(pendingGuidanceSummary) {
                    return summary
                }
                if let summary = normalizedGuidanceSummary(latestGuidanceSummary) {
                    return summary
                }
                guard let guidanceContract else { return "" }
                return normalizedGuidanceSummary(guidanceContract.summaryText) ?? ""
            }

            private func normalizedGuidanceSummary(_ value: String?) -> String? {
                let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "(none)" else { return nil }
                return trimmed
            }
        }

        var projectId: String
        var projectName: String
        var record: SupervisorSkillCallRecord
        var tool: ToolName?
        var toolCall: ToolCall?
        var toolSummary: String
        var actionURL: String?
        var governanceEvidence: GovernanceEvidence? = nil
        var governance: GovernanceSummary? = nil

        var id: String { "skill:\(projectId):\(record.requestId)" }
        var requestId: String { record.requestId }
        var skillId: String { record.skillId }
        var requestedSkillId: String {
            record.requestedSkillId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var toolName: String { record.toolName }
        var status: String { record.status.rawValue }
        var requiredCapability: String {
            record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var resultSummary: String { record.resultSummary }
        var denyCode: String { record.denyCode }
        var policySource: String {
            record.policySource?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var policyReason: String {
            let persisted = governanceEvidence?.policyReason.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !persisted.isEmpty {
                return persisted
            }
            return record.policyReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var governanceReason: String {
            governanceEvidence?.governanceReason.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var blockedSummary: String {
            governanceEvidence?.blockedSummary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var governanceTruth: String {
            governanceEvidence?.governanceTruth.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var repairAction: String {
            governanceEvidence?.repairAction.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var createdAt: TimeInterval? {
            record.createdAtMs > 0 ? Double(record.createdAtMs) / 1000.0 : nil
        }
        var updatedAt: TimeInterval? {
            record.updatedAtMs > 0 ? Double(record.updatedAtMs) / 1000.0 : nil
        }
        var grantRequestId: String {
            record.grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var grantId: String {
            record.grantId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var resultEvidenceRef: String {
            record.resultEvidenceRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    struct XTReadyIncidentEventsExportResult {
        var ok: Bool
        var outputPath: String
        var exportedEventCount: Int
        var missingIncidentCodes: [String]
        var reason: String
    }

    struct XTFreshPairReconnectSmokeDiagnosisSnapshot: Codable, Equatable, Sendable {
        var source: String
        var status: String
        var route: String
        var triggeredAtMs: Int64
        var completedAtMs: Int64
        var reasonCode: String?
        var summary: String

        init(
            source: String,
            status: String,
            route: String,
            triggeredAtMs: Int64,
            completedAtMs: Int64,
            reasonCode: String?,
            summary: String
        ) {
            self.source = source
            self.status = status
            self.route = route
            self.triggeredAtMs = triggeredAtMs
            self.completedAtMs = completedAtMs
            self.reasonCode = reasonCode
            self.summary = summary
        }

        enum CodingKeys: String, CodingKey {
            case source
            case status
            case route
            case triggeredAtMs = "triggered_at_ms"
            case completedAtMs = "completed_at_ms"
            case reasonCode = "reason_code"
            case summary
        }

        init(_ snapshot: XTFreshPairReconnectSmokeSnapshot) {
            self.source = snapshot.source.rawValue
            self.status = snapshot.status.rawValue
            self.route = snapshot.route.rawValue
            self.triggeredAtMs = snapshot.triggeredAtMs
            self.completedAtMs = snapshot.completedAtMs
            self.reasonCode = snapshot.reasonCode
            self.summary = snapshot.summary
        }

        init(_ snapshot: XHubDoctorOutputFreshPairReconnectSmokeSnapshot) {
            self.source = snapshot.source
            self.status = snapshot.status
            self.route = snapshot.route
            self.triggeredAtMs = snapshot.triggeredAtMs
            self.completedAtMs = snapshot.completedAtMs
            self.reasonCode = snapshot.reasonCode
            self.summary = snapshot.summary
        }
    }

    struct XTFirstPairCompletionProofDiagnosisSnapshot: Codable, Equatable, Sendable {
        var readiness: String
        var sameLanVerified: Bool
        var ownerLocalApprovalVerified: Bool
        var pairingMaterialIssued: Bool
        var cachedReconnectSmokePassed: Bool
        var stableRemoteRoutePresent: Bool
        var remoteShadowSmokePassed: Bool
        var remoteShadowSmokeStatus: String
        var remoteShadowSmokeSource: String? = nil
        var remoteShadowTriggeredAtMs: Int64? = nil
        var remoteShadowCompletedAtMs: Int64? = nil
        var remoteShadowRoute: String? = nil
        var remoteShadowReasonCode: String? = nil
        var remoteShadowSummary: String? = nil
        var summaryLine: String
        var generatedAtMs: Int64

        enum CodingKeys: String, CodingKey {
            case readiness
            case sameLanVerified = "same_lan_verified"
            case ownerLocalApprovalVerified = "owner_local_approval_verified"
            case pairingMaterialIssued = "pairing_material_issued"
            case cachedReconnectSmokePassed = "cached_reconnect_smoke_passed"
            case stableRemoteRoutePresent = "stable_remote_route_present"
            case remoteShadowSmokePassed = "remote_shadow_smoke_passed"
            case remoteShadowSmokeStatus = "remote_shadow_smoke_status"
            case remoteShadowSmokeSource = "remote_shadow_smoke_source"
            case remoteShadowTriggeredAtMs = "remote_shadow_triggered_at_ms"
            case remoteShadowCompletedAtMs = "remote_shadow_completed_at_ms"
            case remoteShadowRoute = "remote_shadow_route"
            case remoteShadowReasonCode = "remote_shadow_reason_code"
            case remoteShadowSummary = "remote_shadow_summary"
            case summaryLine = "summary_line"
            case generatedAtMs = "generated_at_ms"
        }

        init(
            readiness: String,
            sameLanVerified: Bool,
            ownerLocalApprovalVerified: Bool,
            pairingMaterialIssued: Bool,
            cachedReconnectSmokePassed: Bool,
            stableRemoteRoutePresent: Bool,
            remoteShadowSmokePassed: Bool,
            remoteShadowSmokeStatus: String,
            remoteShadowSmokeSource: String? = nil,
            remoteShadowTriggeredAtMs: Int64? = nil,
            remoteShadowCompletedAtMs: Int64? = nil,
            remoteShadowRoute: String? = nil,
            remoteShadowReasonCode: String? = nil,
            remoteShadowSummary: String? = nil,
            summaryLine: String,
            generatedAtMs: Int64
        ) {
            self.readiness = readiness
            self.sameLanVerified = sameLanVerified
            self.ownerLocalApprovalVerified = ownerLocalApprovalVerified
            self.pairingMaterialIssued = pairingMaterialIssued
            self.cachedReconnectSmokePassed = cachedReconnectSmokePassed
            self.stableRemoteRoutePresent = stableRemoteRoutePresent
            self.remoteShadowSmokePassed = remoteShadowSmokePassed
            self.remoteShadowSmokeStatus = remoteShadowSmokeStatus
            self.remoteShadowSmokeSource = remoteShadowSmokeSource
            self.remoteShadowTriggeredAtMs = remoteShadowTriggeredAtMs
            self.remoteShadowCompletedAtMs = remoteShadowCompletedAtMs
            self.remoteShadowRoute = remoteShadowRoute
            self.remoteShadowReasonCode = remoteShadowReasonCode
            self.remoteShadowSummary = remoteShadowSummary
            self.summaryLine = summaryLine
            self.generatedAtMs = generatedAtMs
        }

        init(_ snapshot: XTFirstPairCompletionProofSnapshot) {
            self.readiness = snapshot.readiness.rawValue
            self.sameLanVerified = snapshot.sameLanVerified
            self.ownerLocalApprovalVerified = snapshot.ownerLocalApprovalVerified
            self.pairingMaterialIssued = snapshot.pairingMaterialIssued
            self.cachedReconnectSmokePassed = snapshot.cachedReconnectSmokePassed
            self.stableRemoteRoutePresent = snapshot.stableRemoteRoutePresent
            self.remoteShadowSmokePassed = snapshot.remoteShadowSmokePassed
            self.remoteShadowSmokeStatus = snapshot.remoteShadowSmokeStatus.rawValue
            self.remoteShadowSmokeSource = snapshot.remoteShadowSmokeSource?.rawValue
            self.remoteShadowTriggeredAtMs = snapshot.remoteShadowTriggeredAtMs
            self.remoteShadowCompletedAtMs = snapshot.remoteShadowCompletedAtMs
            self.remoteShadowRoute = snapshot.remoteShadowRoute?.rawValue
            self.remoteShadowReasonCode = snapshot.remoteShadowReasonCode
            self.remoteShadowSummary = snapshot.remoteShadowSummary
            self.summaryLine = snapshot.summaryLine
            self.generatedAtMs = snapshot.generatedAtMs
        }

        init(_ snapshot: XHubDoctorOutputFirstPairCompletionProofSnapshot) {
            self.readiness = snapshot.readiness
            self.sameLanVerified = snapshot.sameLanVerified
            self.ownerLocalApprovalVerified = snapshot.ownerLocalApprovalVerified
            self.pairingMaterialIssued = snapshot.pairingMaterialIssued
            self.cachedReconnectSmokePassed = snapshot.cachedReconnectSmokePassed
            self.stableRemoteRoutePresent = snapshot.stableRemoteRoutePresent
            self.remoteShadowSmokePassed = snapshot.remoteShadowSmokePassed
            self.remoteShadowSmokeStatus = snapshot.remoteShadowSmokeStatus
            self.remoteShadowSmokeSource = snapshot.remoteShadowSmokeSource
            self.remoteShadowTriggeredAtMs = snapshot.remoteShadowTriggeredAtMs
            self.remoteShadowCompletedAtMs = snapshot.remoteShadowCompletedAtMs
            self.remoteShadowRoute = snapshot.remoteShadowRoute
            self.remoteShadowReasonCode = snapshot.remoteShadowReasonCode
            self.remoteShadowSummary = snapshot.remoteShadowSummary
            self.summaryLine = snapshot.summaryLine
            self.generatedAtMs = snapshot.generatedAtMs
        }
    }

    struct XTHubRuntimeDiagnosisSnapshot {
        var overallState: String
        var readyForFirstTask: Bool
        var failureCode: String
        var headline: String
        var detailLines: [String]
        var nextStep: String
        var actionCategory: String = ""
        var installHint: String = ""
        var recommendedAction: String = ""
        var supportFAQSummary: String = ""
        var loadConfigSummaryLine: String = ""
        var repairDestinationRef: String = ""
        var generatedAtMs: Int64 = 0

        var strictIssueCode: String? {
            guard overallState == XHubDoctorOverallState.blocked.rawValue else { return nil }
            let trimmedCode = failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCode.isEmpty ? "hub_blocked" : trimmedCode
        }

        func renderableDetailLines(limit: Int = 2) -> [String] {
            let trimmedLoadConfig = loadConfigSummaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = detailLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && (trimmedLoadConfig.isEmpty || $0 != trimmedLoadConfig) }
            return Array(normalized.prefix(max(0, limit)))
        }
    }

    struct XTSupervisorVoiceDiagnosisSnapshot {
        static let staleAfterMs: Int64 = 15 * 60 * 1000

        var status: String
        var headline: String
        var message: String
        var detailLines: [String]
        var nextStep: String
        var repairDestinationRef: String
        var actionURL: String? = nil
        var generatedAtMs: Int64 = 0

        func renderableDetailLines(limit: Int = 2) -> [String] {
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = detailLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != trimmedMessage }
            return Array(normalized.prefix(max(0, limit)))
        }

        func isStale(nowMs: Int64 = Int64((Date().timeIntervalSince1970 * 1000).rounded())) -> Bool {
            guard generatedAtMs > 0 else { return true }
            return nowMs - generatedAtMs > Self.staleAfterMs
        }

        func ageSummary(nowMs: Int64 = Int64((Date().timeIntervalSince1970 * 1000).rounded())) -> String {
            guard generatedAtMs > 0 else { return "时间未知" }
            let deltaMs = max(Int64(0), nowMs - generatedAtMs)
            let deltaSec = deltaMs / 1000
            if deltaSec < 60 {
                return "刚刚"
            }
            let deltaMin = deltaSec / 60
            if deltaMin < 60 {
                return "\(deltaMin) 分钟前"
            }
            let deltaHours = deltaMin / 60
            if deltaHours < 24 {
                return "\(deltaHours) 小时前"
            }
            let deltaDays = deltaHours / 24
            return "\(deltaDays) 天前"
        }

        func freshnessSummary(nowMs: Int64 = Int64((Date().timeIntervalSince1970 * 1000).rounded())) -> String {
            let age = ageSummary(nowMs: nowMs)
            if isStale(nowMs: nowMs) {
                return "最近一次语音自检已过期（\(age)）"
            }
            return "最近一次语音自检：\(age)"
        }
    }

    struct XTReadyIncidentExportSnapshot {
        var autoExportEnabled: Bool
        var ledgerIncidentCount: Int
        var requiredIncidentEventCount: Int
        var missingIncidentCodes: [String]
        var memoryAssemblyReady: Bool
        var memoryAssemblyIssues: [String]
        var memoryAssemblyDetailLines: [String] = []
        var memoryAssemblyStatusLine: String
        var durableCandidateMirrorStatus: SupervisorDurableCandidateMirrorStatus = .notNeeded
        var durableCandidateMirrorTarget: String? = nil
        var durableCandidateMirrorAttempted: Bool = false
        var durableCandidateMirrorErrorCode: String? = nil
        var durableCandidateLocalStoreRole: String = XTSupervisorDurableCandidateMirror.localStoreRole
        var strictE2EReady: Bool
        var strictE2EIssues: [String]
        var pairedRouteSetSnapshot: XHubDoctorOutputPairedRouteSetSnapshot? = nil
        var pairedRouteSnapshot: XHubDoctorOutputRouteSnapshot? = nil
        var connectivityIncidentSnapshot: XHubDoctorOutputConnectivityIncidentSnapshot? = nil
        var connectivityIncidentHistory: XHubDoctorOutputConnectivityIncidentHistoryReport? = nil
        var connectivityRepairLedger: XTConnectivityRepairLedgerSnapshot? = nil
        var hubRuntimeDiagnosis: XTHubRuntimeDiagnosisSnapshot? = nil
        var freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeDiagnosisSnapshot? = nil
        var firstPairCompletionProofSnapshot: XTFirstPairCompletionProofDiagnosisSnapshot? = nil
        var supervisorVoiceDiagnosis: XTSupervisorVoiceDiagnosisSnapshot? = nil
        var status: String
        var reportPath: String
    }

    struct XTReadyIncidentReadiness {
        var ready: Bool
        var issues: [String]
    }

    struct XTReadyIncidentEventsPayload: Codable {
        var runId: String
        var schemaVersion: String
        var generatedAtMs: Int64
        var source: String
        var summary: XTReadyIncidentSummary
        var events: [XTReadyIncidentEvent]

        enum CodingKeys: String, CodingKey {
            case runId = "run_id"
            case schemaVersion = "schema_version"
            case generatedAtMs = "generated_at_ms"
            case source
            case summary
            case events
        }
    }

    struct XTReadyIncidentSummary: Codable {
        var highRiskLaneWithoutGrant: Int
        var unauditedAutoResolution: Int
        var highRiskBypassCount: Int
        var blockedEventMissRate: Double
        var nonMessageIngressPolicyCoverage: Int
        var memoryAssemblyReady: Bool
        var memoryAssemblyIssueCount: Int
        var memoryAssemblyRequestedProfile: String
        var memoryAssemblyResolvedProfile: String
        var memoryAssemblyTruncatedLayerCount: Int
        var durableCandidateMirrorStatus: String
        var durableCandidateMirrorTarget: String?
        var durableCandidateMirrorAttempted: Bool
        var durableCandidateMirrorErrorCode: String?
        var durableCandidateLocalStoreRole: String
        var pairedRouteSetSnapshot: XHubDoctorOutputPairedRouteSetSnapshot?
        var pairedRouteSnapshot: XHubDoctorOutputRouteSnapshot?
        var connectivityIncident: XHubDoctorOutputConnectivityIncidentSnapshot?
        var connectivityIncidentHistory: XHubDoctorOutputConnectivityIncidentHistoryReport?
        var connectivityRepairLedger: XTConnectivityRepairLedgerSnapshot?
        var freshPairReconnectSmoke: XTFreshPairReconnectSmokeDiagnosisSnapshot?
        var firstPairCompletionProof: XTFirstPairCompletionProofDiagnosisSnapshot?

        enum CodingKeys: String, CodingKey {
            case highRiskLaneWithoutGrant = "high_risk_lane_without_grant"
            case unauditedAutoResolution = "unaudited_auto_resolution"
            case highRiskBypassCount = "high_risk_bypass_count"
            case blockedEventMissRate = "blocked_event_miss_rate"
            case nonMessageIngressPolicyCoverage = "non_message_ingress_policy_coverage"
            case memoryAssemblyReady = "memory_assembly_ready"
            case memoryAssemblyIssueCount = "memory_assembly_issue_count"
            case memoryAssemblyRequestedProfile = "memory_assembly_requested_profile"
            case memoryAssemblyResolvedProfile = "memory_assembly_resolved_profile"
            case memoryAssemblyTruncatedLayerCount = "memory_assembly_truncated_layer_count"
            case durableCandidateMirrorStatus = "durable_candidate_mirror_status"
            case durableCandidateMirrorTarget = "durable_candidate_mirror_target"
            case durableCandidateMirrorAttempted = "durable_candidate_mirror_attempted"
            case durableCandidateMirrorErrorCode = "durable_candidate_mirror_error_code"
            case durableCandidateLocalStoreRole = "durable_candidate_local_store_role"
            case pairedRouteSetSnapshot = "paired_route_set_snapshot"
            case pairedRouteSnapshot = "paired_route_snapshot"
            case connectivityIncident = "connectivity_incident"
            case connectivityIncidentHistory = "connectivity_incident_history"
            case connectivityRepairLedger = "connectivity_repair_ledger"
            case freshPairReconnectSmoke = "fresh_pair_reconnect_smoke"
            case firstPairCompletionProof = "first_pair_completion_proof"
        }
    }
}
