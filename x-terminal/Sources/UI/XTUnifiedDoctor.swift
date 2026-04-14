import Foundation
import SwiftUI

enum XTUnifiedDoctorSectionKind: String, CaseIterable, Codable, Sendable {
    case hubReachability = "hub_reachability"
    case pairingValidity = "pairing_validity"
    case modelRouteReadiness = "model_route_readiness"
    case bridgeToolReadiness = "bridge_tool_readiness"
    case sessionRuntimeReadiness = "session_runtime_readiness"
    case wakeProfileReadiness = "wake_profile_readiness"
    case talkLoopReadiness = "talk_loop_readiness"
    case voicePlaybackReadiness = "voice_playback_readiness"
    case calendarReminderReadiness = "calendar_reminder_readiness"
    case skillsCompatibilityReadiness = "skills_compatibility_readiness"

    var title: String {
        switch self {
        case .hubReachability:
            return "Hub 可达性"
        case .pairingValidity:
            return "配对有效性"
        case .modelRouteReadiness:
            return "模型路由就绪"
        case .bridgeToolReadiness:
            return "桥接 / 工具就绪"
        case .sessionRuntimeReadiness:
            return "会话运行时就绪"
        case .wakeProfileReadiness:
            return "唤醒配置就绪"
        case .talkLoopReadiness:
            return "对话链路就绪"
        case .voicePlaybackReadiness:
            return "语音播放就绪"
        case .calendarReminderReadiness:
            return "日历提醒就绪"
        case .skillsCompatibilityReadiness:
            return "技能兼容性"
        }
    }

    var contributesToFirstTaskReadiness: Bool {
        switch self {
        case .hubReachability, .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness:
            return true
        case .pairingValidity, .wakeProfileReadiness, .talkLoopReadiness, .voicePlaybackReadiness, .calendarReminderReadiness, .skillsCompatibilityReadiness:
            return false
        }
    }
}

struct XTUnifiedDoctorRouteSnapshot: Codable, Equatable, Sendable {
    var transportMode: String
    var routeLabel: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String
}

struct XTUnifiedDoctorRemotePaidAccessProjection: Codable, Equatable, Sendable {
    var trustProfilePresent: Bool
    var policyMode: String?
    var dailyTokenLimit: Int
    var singleRequestTokenLimit: Int

    init(
        trustProfilePresent: Bool,
        policyMode: String?,
        dailyTokenLimit: Int,
        singleRequestTokenLimit: Int
    ) {
        self.trustProfilePresent = trustProfilePresent
        self.policyMode = policyMode?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dailyTokenLimit = max(0, dailyTokenLimit)
        self.singleRequestTokenLimit = max(0, singleRequestTokenLimit)
    }

    init(snapshot: HubRemotePaidAccessSnapshot) {
        self.init(
            trustProfilePresent: snapshot.trustProfilePresent,
            policyMode: snapshot.paidModelPolicyMode,
            dailyTokenLimit: snapshot.dailyTokenLimit,
            singleRequestTokenLimit: snapshot.singleRequestTokenLimit
        )
    }

    var policyDisplayLabel: String {
        switch normalizedPolicyMode {
        case "all_paid_models":
            return "全部付费模型"
        case "custom_selected_models":
            return "指定付费模型"
        case "off":
            return "已关闭"
        case "legacy_grant":
            return "旧版授权"
        case "":
            return "未回报"
        default:
            return normalizedPolicyMode
        }
    }

    var compactBudgetLine: String {
        if !trustProfilePresent {
            return "仍走旧授权路径 · 策略 \(policyDisplayLabel)"
        }

        let singleLine = "单次 \(budgetTokenText(singleRequestTokenLimit))"
        let dailyLine = "当日 \(budgetTokenText(dailyTokenLimit))"
        return "\(singleLine) · \(dailyLine) · 策略 \(policyDisplayLabel)"
    }

    private var normalizedPolicyMode: String {
        (policyMode ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func budgetTokenText(_ value: Int) -> String {
        value > 0 ? "\(value) tok" : "未设"
    }
}

struct XTUnifiedDoctorDurableCandidateMirrorProjection: Codable, Equatable, Sendable {
    var status: SupervisorDurableCandidateMirrorStatus
    var target: String
    var attempted: Bool
    var errorCode: String?
    var localStoreRole: String

    var detailLine: String {
        var parts = [
            "durable_candidate_mirror",
            "status=\(status.rawValue)",
            "target=\(target)",
            "attempted=\(attempted)"
        ]
        if let errorCode, !errorCode.isEmpty {
            parts.append("reason=\(errorCode)")
        }
        if !localStoreRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("local_store_role=\(localStoreRole)")
        }
        return parts.joined(separator: " ")
    }

    static func from(detailLines: [String]) -> XTUnifiedDoctorDurableCandidateMirrorProjection? {
        guard let line = detailLines.first(where: { $0.hasPrefix("durable_candidate_mirror ") }) else {
            return nil
        }
        let rawFields = line.dropFirst("durable_candidate_mirror ".count)
        var fields: [String: String] = [:]
        for token in rawFields.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        guard let rawStatus = fields["status"],
              let status = SupervisorDurableCandidateMirrorStatus(rawValue: rawStatus) else {
            return nil
        }
        return XTUnifiedDoctorDurableCandidateMirrorProjection(
            status: status,
            target: normalizedDoctorField(
                fields["target"],
                fallback: XTSupervisorDurableCandidateMirror.mirrorTarget
            ),
            attempted: fields["attempted"].map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            } ?? (status != .notNeeded),
            errorCode: normalizedOptionalDoctorField(fields["reason"] ?? fields["error_code"]),
            localStoreRole: normalizedDoctorField(
                fields["local_store_role"],
                fallback: XTSupervisorDurableCandidateMirror.localStoreRole
            )
        )
    }
}

struct XTUnifiedDoctorLocalStoreWriteProjection: Codable, Equatable, Sendable {
    var personalMemoryIntent: String?
    var crossLinkIntent: String?
    var personalReviewIntent: String?

    var detailLine: String {
        let parts = [
            "xt_local_store_writes",
            personalMemoryIntent.map { "personal_memory=\($0)" },
            crossLinkIntent.map { "cross_link=\($0)" },
            personalReviewIntent.map { "personal_review=\($0)" }
        ].compactMap { $0 }
        return parts.joined(separator: " ")
    }

    var hasAnyIntent: Bool {
        personalMemoryIntent != nil
            || crossLinkIntent != nil
            || personalReviewIntent != nil
    }

    static func from(detailLines: [String]) -> XTUnifiedDoctorLocalStoreWriteProjection? {
        guard let line = detailLines.first(where: { $0.hasPrefix("xt_local_store_writes ") }) else {
            return nil
        }
        let rawFields = line.dropFirst("xt_local_store_writes ".count)
        var fields: [String: String] = [:]
        for token in rawFields.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        let projection = XTUnifiedDoctorLocalStoreWriteProjection(
            personalMemoryIntent: normalizedOptionalDoctorField(fields["personal_memory"]),
            crossLinkIntent: normalizedOptionalDoctorField(fields["cross_link"]),
            personalReviewIntent: normalizedOptionalDoctorField(fields["personal_review"])
        )
        return projection.hasAnyIntent ? projection : nil
    }
}

private final class XTUnifiedDoctorSupervisorGuidanceContinuityProjectionStorage: Codable, Equatable, Sendable {
    let schemaVersion: String
    let reviewGuidanceCarrierPresent: Bool
    let latestReviewNoteAvailable: Bool
    let latestReviewNoteActualized: Bool
    let latestGuidanceAvailable: Bool
    let latestGuidanceActualized: Bool
    let latestGuidanceAckStatus: String?
    let latestGuidanceAckRequired: Bool?
    let latestGuidanceDeliveryMode: String?
    let latestGuidanceInterventionMode: String?
    let latestGuidanceSafePointPolicy: String?
    let pendingAckGuidanceAvailable: Bool
    let pendingAckGuidanceActualized: Bool
    let pendingAckGuidanceAckStatus: String?
    let pendingAckGuidanceAckRequired: Bool?
    let pendingAckGuidanceDeliveryMode: String?
    let pendingAckGuidanceInterventionMode: String?
    let pendingAckGuidanceSafePointPolicy: String?
    let renderedRefs: [String]
    let summaryLine: String

    init(
        schemaVersion: String,
        reviewGuidanceCarrierPresent: Bool,
        latestReviewNoteAvailable: Bool,
        latestReviewNoteActualized: Bool,
        latestGuidanceAvailable: Bool,
        latestGuidanceActualized: Bool,
        latestGuidanceAckStatus: String?,
        latestGuidanceAckRequired: Bool?,
        latestGuidanceDeliveryMode: String?,
        latestGuidanceInterventionMode: String?,
        latestGuidanceSafePointPolicy: String?,
        pendingAckGuidanceAvailable: Bool,
        pendingAckGuidanceActualized: Bool,
        pendingAckGuidanceAckStatus: String?,
        pendingAckGuidanceAckRequired: Bool?,
        pendingAckGuidanceDeliveryMode: String?,
        pendingAckGuidanceInterventionMode: String?,
        pendingAckGuidanceSafePointPolicy: String?,
        renderedRefs: [String],
        summaryLine: String
    ) {
        self.schemaVersion = schemaVersion
        self.reviewGuidanceCarrierPresent = reviewGuidanceCarrierPresent
        self.latestReviewNoteAvailable = latestReviewNoteAvailable
        self.latestReviewNoteActualized = latestReviewNoteActualized
        self.latestGuidanceAvailable = latestGuidanceAvailable
        self.latestGuidanceActualized = latestGuidanceActualized
        self.latestGuidanceAckStatus = latestGuidanceAckStatus
        self.latestGuidanceAckRequired = latestGuidanceAckRequired
        self.latestGuidanceDeliveryMode = latestGuidanceDeliveryMode
        self.latestGuidanceInterventionMode = latestGuidanceInterventionMode
        self.latestGuidanceSafePointPolicy = latestGuidanceSafePointPolicy
        self.pendingAckGuidanceAvailable = pendingAckGuidanceAvailable
        self.pendingAckGuidanceActualized = pendingAckGuidanceActualized
        self.pendingAckGuidanceAckStatus = pendingAckGuidanceAckStatus
        self.pendingAckGuidanceAckRequired = pendingAckGuidanceAckRequired
        self.pendingAckGuidanceDeliveryMode = pendingAckGuidanceDeliveryMode
        self.pendingAckGuidanceInterventionMode = pendingAckGuidanceInterventionMode
        self.pendingAckGuidanceSafePointPolicy = pendingAckGuidanceSafePointPolicy
        self.renderedRefs = renderedRefs
        self.summaryLine = summaryLine
    }

    static func ==(
        lhs: XTUnifiedDoctorSupervisorGuidanceContinuityProjectionStorage,
        rhs: XTUnifiedDoctorSupervisorGuidanceContinuityProjectionStorage
    ) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion
            && lhs.reviewGuidanceCarrierPresent == rhs.reviewGuidanceCarrierPresent
            && lhs.latestReviewNoteAvailable == rhs.latestReviewNoteAvailable
            && lhs.latestReviewNoteActualized == rhs.latestReviewNoteActualized
            && lhs.latestGuidanceAvailable == rhs.latestGuidanceAvailable
            && lhs.latestGuidanceActualized == rhs.latestGuidanceActualized
            && lhs.latestGuidanceAckStatus == rhs.latestGuidanceAckStatus
            && lhs.latestGuidanceAckRequired == rhs.latestGuidanceAckRequired
            && lhs.latestGuidanceDeliveryMode == rhs.latestGuidanceDeliveryMode
            && lhs.latestGuidanceInterventionMode == rhs.latestGuidanceInterventionMode
            && lhs.latestGuidanceSafePointPolicy == rhs.latestGuidanceSafePointPolicy
            && lhs.pendingAckGuidanceAvailable == rhs.pendingAckGuidanceAvailable
            && lhs.pendingAckGuidanceActualized == rhs.pendingAckGuidanceActualized
            && lhs.pendingAckGuidanceAckStatus == rhs.pendingAckGuidanceAckStatus
            && lhs.pendingAckGuidanceAckRequired == rhs.pendingAckGuidanceAckRequired
            && lhs.pendingAckGuidanceDeliveryMode == rhs.pendingAckGuidanceDeliveryMode
            && lhs.pendingAckGuidanceInterventionMode == rhs.pendingAckGuidanceInterventionMode
            && lhs.pendingAckGuidanceSafePointPolicy == rhs.pendingAckGuidanceSafePointPolicy
            && lhs.renderedRefs == rhs.renderedRefs
            && lhs.summaryLine == rhs.summaryLine
    }
}

struct XTUnifiedDoctorSupervisorGuidanceContinuityProjection: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_guidance_continuity.v1"

    private let storage: XTUnifiedDoctorSupervisorGuidanceContinuityProjectionStorage

    var schemaVersion: String { storage.schemaVersion }
    var reviewGuidanceCarrierPresent: Bool { storage.reviewGuidanceCarrierPresent }
    var latestReviewNoteAvailable: Bool { storage.latestReviewNoteAvailable }
    var latestReviewNoteActualized: Bool { storage.latestReviewNoteActualized }
    var latestGuidanceAvailable: Bool { storage.latestGuidanceAvailable }
    var latestGuidanceActualized: Bool { storage.latestGuidanceActualized }
    var latestGuidanceAckStatus: String? { storage.latestGuidanceAckStatus }
    var latestGuidanceAckRequired: Bool? { storage.latestGuidanceAckRequired }
    var latestGuidanceDeliveryMode: String? { storage.latestGuidanceDeliveryMode }
    var latestGuidanceInterventionMode: String? { storage.latestGuidanceInterventionMode }
    var latestGuidanceSafePointPolicy: String? { storage.latestGuidanceSafePointPolicy }
    var pendingAckGuidanceAvailable: Bool { storage.pendingAckGuidanceAvailable }
    var pendingAckGuidanceActualized: Bool { storage.pendingAckGuidanceActualized }
    var pendingAckGuidanceAckStatus: String? { storage.pendingAckGuidanceAckStatus }
    var pendingAckGuidanceAckRequired: Bool? { storage.pendingAckGuidanceAckRequired }
    var pendingAckGuidanceDeliveryMode: String? { storage.pendingAckGuidanceDeliveryMode }
    var pendingAckGuidanceInterventionMode: String? { storage.pendingAckGuidanceInterventionMode }
    var pendingAckGuidanceSafePointPolicy: String? { storage.pendingAckGuidanceSafePointPolicy }
    var renderedRefs: [String] { storage.renderedRefs }
    var summaryLine: String { storage.summaryLine }

    init(
        schemaVersion: String = currentSchemaVersion,
        reviewGuidanceCarrierPresent: Bool,
        latestReviewNoteAvailable: Bool,
        latestReviewNoteActualized: Bool,
        latestGuidanceAvailable: Bool,
        latestGuidanceActualized: Bool,
        latestGuidanceAckStatus: String?,
        latestGuidanceAckRequired: Bool?,
        latestGuidanceDeliveryMode: String?,
        latestGuidanceInterventionMode: String?,
        latestGuidanceSafePointPolicy: String?,
        pendingAckGuidanceAvailable: Bool,
        pendingAckGuidanceActualized: Bool,
        pendingAckGuidanceAckStatus: String?,
        pendingAckGuidanceAckRequired: Bool?,
        pendingAckGuidanceDeliveryMode: String?,
        pendingAckGuidanceInterventionMode: String?,
        pendingAckGuidanceSafePointPolicy: String?,
        renderedRefs: [String],
        summaryLine: String
    ) {
        self.storage = XTUnifiedDoctorSupervisorGuidanceContinuityProjectionStorage(
            schemaVersion: schemaVersion,
            reviewGuidanceCarrierPresent: reviewGuidanceCarrierPresent,
            latestReviewNoteAvailable: latestReviewNoteAvailable,
            latestReviewNoteActualized: latestReviewNoteActualized,
            latestGuidanceAvailable: latestGuidanceAvailable,
            latestGuidanceActualized: latestGuidanceActualized,
            latestGuidanceAckStatus: normalizedMeaningfulValue(latestGuidanceAckStatus),
            latestGuidanceAckRequired: latestGuidanceAckRequired,
            latestGuidanceDeliveryMode: normalizedMeaningfulValue(latestGuidanceDeliveryMode),
            latestGuidanceInterventionMode: normalizedMeaningfulValue(latestGuidanceInterventionMode),
            latestGuidanceSafePointPolicy: normalizedMeaningfulValue(latestGuidanceSafePointPolicy),
            pendingAckGuidanceAvailable: pendingAckGuidanceAvailable,
            pendingAckGuidanceActualized: pendingAckGuidanceActualized,
            pendingAckGuidanceAckStatus: normalizedMeaningfulValue(pendingAckGuidanceAckStatus),
            pendingAckGuidanceAckRequired: pendingAckGuidanceAckRequired,
            pendingAckGuidanceDeliveryMode: normalizedMeaningfulValue(pendingAckGuidanceDeliveryMode),
            pendingAckGuidanceInterventionMode: normalizedMeaningfulValue(pendingAckGuidanceInterventionMode),
            pendingAckGuidanceSafePointPolicy: normalizedMeaningfulValue(pendingAckGuidanceSafePointPolicy),
            renderedRefs: Self.orderedUniqueTokens(renderedRefs),
            summaryLine: summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func ==(
        lhs: XTUnifiedDoctorSupervisorGuidanceContinuityProjection,
        rhs: XTUnifiedDoctorSupervisorGuidanceContinuityProjection
    ) -> Bool {
        lhs.storage == rhs.storage
    }

    init(from decoder: Decoder) throws {
        self.storage = try XTUnifiedDoctorSupervisorGuidanceContinuityProjectionStorage(
            from: decoder
        )
    }

    func encode(to encoder: Encoder) throws {
        try storage.encode(to: encoder)
    }

    init?(snapshot: SupervisorMemoryAssemblySnapshot) {
        let summaryLine = snapshot.guidanceContinuityHumanLine
            ?? Self.summaryLine(
                latestReviewNoteAvailable: snapshot.latestReviewNoteAvailable,
                latestReviewNoteActualized: snapshot.latestReviewNoteActualized,
                latestGuidanceAvailable: snapshot.latestGuidanceAvailable,
                latestGuidanceActualized: snapshot.latestGuidanceActualized,
                latestGuidanceAckStatus: snapshot.latestGuidanceAckStatus,
                latestGuidanceAckRequired: snapshot.latestGuidanceAckRequired,
                latestGuidanceSafePointPolicy: snapshot.latestGuidanceSafePointPolicy,
                pendingAckGuidanceAvailable: snapshot.pendingAckGuidanceAvailable,
                pendingAckGuidanceActualized: snapshot.pendingAckGuidanceActualized,
                pendingAckGuidanceAckStatus: snapshot.pendingAckGuidanceAckStatus,
                pendingAckGuidanceAckRequired: snapshot.pendingAckGuidanceAckRequired,
                pendingAckGuidanceSafePointPolicy: snapshot.pendingAckGuidanceSafePointPolicy
            )
        guard Self.hasAnySignal(
            latestReviewNoteAvailable: snapshot.latestReviewNoteAvailable,
            latestGuidanceAvailable: snapshot.latestGuidanceAvailable,
            latestGuidanceAckStatus: snapshot.latestGuidanceAckStatus,
            latestGuidanceDeliveryMode: snapshot.latestGuidanceDeliveryMode,
            latestGuidanceInterventionMode: snapshot.latestGuidanceInterventionMode,
            latestGuidanceSafePointPolicy: snapshot.latestGuidanceSafePointPolicy,
            pendingAckGuidanceAvailable: snapshot.pendingAckGuidanceAvailable,
            pendingAckGuidanceAckStatus: snapshot.pendingAckGuidanceAckStatus,
            pendingAckGuidanceDeliveryMode: snapshot.pendingAckGuidanceDeliveryMode,
            pendingAckGuidanceInterventionMode: snapshot.pendingAckGuidanceInterventionMode,
            pendingAckGuidanceSafePointPolicy: snapshot.pendingAckGuidanceSafePointPolicy,
            summaryLine: summaryLine
        ) else {
            return nil
        }

        self.init(
            reviewGuidanceCarrierPresent: snapshot.reviewGuidanceCarrierPresent,
            latestReviewNoteAvailable: snapshot.latestReviewNoteAvailable,
            latestReviewNoteActualized: snapshot.latestReviewNoteActualized,
            latestGuidanceAvailable: snapshot.latestGuidanceAvailable,
            latestGuidanceActualized: snapshot.latestGuidanceActualized,
            latestGuidanceAckStatus: snapshot.latestGuidanceAckStatus,
            latestGuidanceAckRequired: snapshot.latestGuidanceAckRequired,
            latestGuidanceDeliveryMode: snapshot.latestGuidanceDeliveryMode,
            latestGuidanceInterventionMode: snapshot.latestGuidanceInterventionMode,
            latestGuidanceSafePointPolicy: snapshot.latestGuidanceSafePointPolicy,
            pendingAckGuidanceAvailable: snapshot.pendingAckGuidanceAvailable,
            pendingAckGuidanceActualized: snapshot.pendingAckGuidanceActualized,
            pendingAckGuidanceAckStatus: snapshot.pendingAckGuidanceAckStatus,
            pendingAckGuidanceAckRequired: snapshot.pendingAckGuidanceAckRequired,
            pendingAckGuidanceDeliveryMode: snapshot.pendingAckGuidanceDeliveryMode,
            pendingAckGuidanceInterventionMode: snapshot.pendingAckGuidanceInterventionMode,
            pendingAckGuidanceSafePointPolicy: snapshot.pendingAckGuidanceSafePointPolicy,
            renderedRefs: snapshot.guidanceContinuityRenderedRefs,
            summaryLine: summaryLine ?? "Review / Guidance：当前没有 review / guidance 连续性对象"
        )
    }

    static func from(detailLines: [String]) -> XTUnifiedDoctorSupervisorGuidanceContinuityProjection? {
        let summaryLine = normalizedOptionalDoctorField(
            detailLines.first(where: { $0.hasPrefix("Review / Guidance：") })
        ) ?? Self.summaryLine(
            latestReviewNoteAvailable: detailBoolValue(
                "supervisor_memory_latest_review_note_available",
                from: detailLines
            ) ?? false,
            latestReviewNoteActualized: detailBoolValue(
                "supervisor_memory_latest_review_note_actualized",
                from: detailLines
            ) ?? false,
            latestGuidanceAvailable: detailBoolValue(
                "supervisor_memory_latest_guidance_available",
                from: detailLines
            ) ?? false,
            latestGuidanceActualized: detailBoolValue(
                "supervisor_memory_latest_guidance_actualized",
                from: detailLines
            ) ?? false,
            latestGuidanceAckStatus: detailValue(
                "supervisor_memory_latest_guidance_ack_status",
                from: detailLines
            ),
            latestGuidanceAckRequired: detailBoolValue(
                "supervisor_memory_latest_guidance_ack_required",
                from: detailLines
            ),
            latestGuidanceSafePointPolicy: detailValue(
                "supervisor_memory_latest_guidance_safe_point_policy",
                from: detailLines
            ) ?? "",
            pendingAckGuidanceAvailable: detailBoolValue(
                "supervisor_memory_pending_ack_guidance_available",
                from: detailLines
            ) ?? false,
            pendingAckGuidanceActualized: detailBoolValue(
                "supervisor_memory_pending_ack_guidance_actualized",
                from: detailLines
            ) ?? false,
            pendingAckGuidanceAckStatus: detailValue(
                "supervisor_memory_pending_ack_guidance_ack_status",
                from: detailLines
            ),
            pendingAckGuidanceAckRequired: detailBoolValue(
                "supervisor_memory_pending_ack_guidance_ack_required",
                from: detailLines
            ),
            pendingAckGuidanceSafePointPolicy: detailValue(
                "supervisor_memory_pending_ack_guidance_safe_point_policy",
                from: detailLines
            ) ?? ""
        )

        let latestReviewNoteAvailable = detailBoolValue(
            "supervisor_memory_latest_review_note_available",
            from: detailLines
        ) ?? false
        let latestReviewNoteActualized = detailBoolValue(
            "supervisor_memory_latest_review_note_actualized",
            from: detailLines
        ) ?? false
        let latestGuidanceAvailable = detailBoolValue(
            "supervisor_memory_latest_guidance_available",
            from: detailLines
        ) ?? false
        let latestGuidanceActualized = detailBoolValue(
            "supervisor_memory_latest_guidance_actualized",
            from: detailLines
        ) ?? false
        let latestGuidanceAckStatus = detailValue(
            "supervisor_memory_latest_guidance_ack_status",
            from: detailLines
        )
        let latestGuidanceAckRequired = detailBoolValue(
            "supervisor_memory_latest_guidance_ack_required",
            from: detailLines
        )
        let latestGuidanceDeliveryMode = detailValue(
            "supervisor_memory_latest_guidance_delivery_mode",
            from: detailLines
        )
        let latestGuidanceInterventionMode = detailValue(
            "supervisor_memory_latest_guidance_intervention_mode",
            from: detailLines
        )
        let latestGuidanceSafePointPolicy = detailValue(
            "supervisor_memory_latest_guidance_safe_point_policy",
            from: detailLines
        )
        let pendingAckGuidanceAvailable = detailBoolValue(
            "supervisor_memory_pending_ack_guidance_available",
            from: detailLines
        ) ?? false
        let pendingAckGuidanceActualized = detailBoolValue(
            "supervisor_memory_pending_ack_guidance_actualized",
            from: detailLines
        ) ?? false
        let pendingAckGuidanceAckStatus = detailValue(
            "supervisor_memory_pending_ack_guidance_ack_status",
            from: detailLines
        )
        let pendingAckGuidanceAckRequired = detailBoolValue(
            "supervisor_memory_pending_ack_guidance_ack_required",
            from: detailLines
        )
        let pendingAckGuidanceDeliveryMode = detailValue(
            "supervisor_memory_pending_ack_guidance_delivery_mode",
            from: detailLines
        )
        let pendingAckGuidanceInterventionMode = detailValue(
            "supervisor_memory_pending_ack_guidance_intervention_mode",
            from: detailLines
        )
        let pendingAckGuidanceSafePointPolicy = detailValue(
            "supervisor_memory_pending_ack_guidance_safe_point_policy",
            from: detailLines
        )

        guard Self.hasAnySignal(
            latestReviewNoteAvailable: latestReviewNoteAvailable,
            latestGuidanceAvailable: latestGuidanceAvailable,
            latestGuidanceAckStatus: latestGuidanceAckStatus,
            latestGuidanceDeliveryMode: latestGuidanceDeliveryMode,
            latestGuidanceInterventionMode: latestGuidanceInterventionMode,
            latestGuidanceSafePointPolicy: latestGuidanceSafePointPolicy,
            pendingAckGuidanceAvailable: pendingAckGuidanceAvailable,
            pendingAckGuidanceAckStatus: pendingAckGuidanceAckStatus,
            pendingAckGuidanceDeliveryMode: pendingAckGuidanceDeliveryMode,
            pendingAckGuidanceInterventionMode: pendingAckGuidanceInterventionMode,
            pendingAckGuidanceSafePointPolicy: pendingAckGuidanceSafePointPolicy,
            summaryLine: summaryLine
        ) else {
            return nil
        }

        let reviewGuidanceCarrierPresent = detailBoolValue(
            "supervisor_review_guidance_carrier_present",
            from: detailLines
        ) ?? false
        let renderedRefs = Self.orderedUniqueTokens([
            latestReviewNoteActualized ? "latest_review_note" : nil,
            latestGuidanceActualized ? "latest_guidance" : nil,
            pendingAckGuidanceActualized ? "pending_ack_guidance" : nil
        ].compactMap { $0 })

        return XTUnifiedDoctorSupervisorGuidanceContinuityProjection(
            reviewGuidanceCarrierPresent: reviewGuidanceCarrierPresent,
            latestReviewNoteAvailable: latestReviewNoteAvailable,
            latestReviewNoteActualized: latestReviewNoteActualized,
            latestGuidanceAvailable: latestGuidanceAvailable,
            latestGuidanceActualized: latestGuidanceActualized,
            latestGuidanceAckStatus: latestGuidanceAckStatus,
            latestGuidanceAckRequired: latestGuidanceAckRequired,
            latestGuidanceDeliveryMode: latestGuidanceDeliveryMode,
            latestGuidanceInterventionMode: latestGuidanceInterventionMode,
            latestGuidanceSafePointPolicy: latestGuidanceSafePointPolicy,
            pendingAckGuidanceAvailable: pendingAckGuidanceAvailable,
            pendingAckGuidanceActualized: pendingAckGuidanceActualized,
            pendingAckGuidanceAckStatus: pendingAckGuidanceAckStatus,
            pendingAckGuidanceAckRequired: pendingAckGuidanceAckRequired,
            pendingAckGuidanceDeliveryMode: pendingAckGuidanceDeliveryMode,
            pendingAckGuidanceInterventionMode: pendingAckGuidanceInterventionMode,
            pendingAckGuidanceSafePointPolicy: pendingAckGuidanceSafePointPolicy,
            renderedRefs: renderedRefs,
            summaryLine: summaryLine ?? "Review / Guidance：当前没有 review / guidance 连续性对象"
        )
    }

    private static func hasAnySignal(
        latestReviewNoteAvailable: Bool,
        latestGuidanceAvailable: Bool,
        latestGuidanceAckStatus: String?,
        latestGuidanceDeliveryMode: String?,
        latestGuidanceInterventionMode: String?,
        latestGuidanceSafePointPolicy: String?,
        pendingAckGuidanceAvailable: Bool,
        pendingAckGuidanceAckStatus: String?,
        pendingAckGuidanceDeliveryMode: String?,
        pendingAckGuidanceInterventionMode: String?,
        pendingAckGuidanceSafePointPolicy: String?,
        summaryLine: String?
    ) -> Bool {
        latestReviewNoteAvailable
            || latestGuidanceAvailable
            || pendingAckGuidanceAvailable
            || normalizedMeaningfulValue(latestGuidanceAckStatus) != nil
            || normalizedMeaningfulValue(latestGuidanceDeliveryMode) != nil
            || normalizedMeaningfulValue(latestGuidanceInterventionMode) != nil
            || normalizedMeaningfulValue(latestGuidanceSafePointPolicy) != nil
            || normalizedMeaningfulValue(pendingAckGuidanceAckStatus) != nil
            || normalizedMeaningfulValue(pendingAckGuidanceDeliveryMode) != nil
            || normalizedMeaningfulValue(pendingAckGuidanceInterventionMode) != nil
            || normalizedMeaningfulValue(pendingAckGuidanceSafePointPolicy) != nil
            || normalizedOptionalDoctorField(summaryLine) != nil
    }

    private static func summaryLine(
        latestReviewNoteAvailable: Bool,
        latestReviewNoteActualized: Bool,
        latestGuidanceAvailable: Bool,
        latestGuidanceActualized: Bool,
        latestGuidanceAckStatus: String?,
        latestGuidanceAckRequired: Bool?,
        latestGuidanceSafePointPolicy: String?,
        pendingAckGuidanceAvailable: Bool,
        pendingAckGuidanceActualized: Bool,
        pendingAckGuidanceAckStatus: String?,
        pendingAckGuidanceAckRequired: Bool?,
        pendingAckGuidanceSafePointPolicy: String?
    ) -> String? {
        var parts: [String] = []
        if latestReviewNoteAvailable {
            parts.append("latest review \(latestReviewNoteActualized ? "carried" : "omitted")")
        }
        if latestGuidanceAvailable {
            parts.append(
                "latest guidance \(latestGuidanceActualized ? "carried" : "omitted")"
                    + guidanceAckStateSummary(
                        ackStatus: latestGuidanceAckStatus,
                        ackRequired: latestGuidanceAckRequired,
                        safePointPolicy: latestGuidanceSafePointPolicy
                    )
            )
        }
        if pendingAckGuidanceAvailable {
            parts.append(
                "pending guidance \(pendingAckGuidanceActualized ? "carried" : "omitted")"
                    + guidanceAckStateSummary(
                        ackStatus: pendingAckGuidanceAckStatus,
                        ackRequired: pendingAckGuidanceAckRequired,
                        safePointPolicy: pendingAckGuidanceSafePointPolicy
                    )
            )
        }
        guard !parts.isEmpty else { return nil }
        return "Review / Guidance：\(parts.joined(separator: " · "))"
    }

    private static func guidanceAckStateSummary(
        ackStatus: String?,
        ackRequired: Bool?,
        safePointPolicy: String?
    ) -> String {
        var parts: [String] = []
        if let ackStatus = normalizedOptionalDoctorField(ackStatus) {
            parts.append("ack=\(ackStatus)")
        }
        if let ackRequired {
            parts.append(ackRequired ? "required" : "optional")
        }
        if let safePointPolicy = normalizedOptionalDoctorField(safePointPolicy) {
            parts.append("safe_point=\(safePointPolicy)")
        }
        guard !parts.isEmpty else { return "" }
        return " [" + parts.joined(separator: " · ") + "]"
    }

    private static func detailValue(_ key: String, from detailLines: [String]) -> String? {
        guard let line = detailLines.first(where: { $0.hasPrefix("\(key)=") }) else {
            return nil
        }
        return String(line.dropFirst(key.count + 1))
    }

    private static func detailBoolValue(_ key: String, from detailLines: [String]) -> Bool? {
        guard let raw = normalizedOptionalDoctorField(detailValue(key, from: detailLines)) else {
            return nil
        }
        switch raw.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func orderedUniqueTokens(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }
}

private struct XTUnifiedDoctorSupervisorSafePointTimelineProjectionStorage: Codable, Equatable, Sendable {
    let schemaVersion: String
    let pendingGuidanceAvailable: Bool
    let pendingGuidanceInjectionId: String?
    let pendingGuidanceDeliveryMode: String?
    let pendingGuidanceInterventionMode: String?
    let pendingGuidanceSafePointPolicy: String?
    let liveStateSource: String?
    let flowStep: Int?
    let toolResultsCount: Int?
    let verifyRunIndex: Int?
    let finalizeOnly: Bool?
    let checkpointReached: Bool?
    let promptVisibleNow: Bool?
    let visibleFromPreRunMemory: Bool?
    let pauseRecorded: Bool?
    let deliverableNow: Bool?
    let shouldPauseToolBatchAfterBoundary: Bool?
    let deliveryState: String?
    let executionGate: String?
    let summaryLine: String

    init(
        schemaVersion: String,
        pendingGuidanceAvailable: Bool,
        pendingGuidanceInjectionId: String?,
        pendingGuidanceDeliveryMode: String?,
        pendingGuidanceInterventionMode: String?,
        pendingGuidanceSafePointPolicy: String?,
        liveStateSource: String?,
        flowStep: Int?,
        toolResultsCount: Int?,
        verifyRunIndex: Int?,
        finalizeOnly: Bool?,
        checkpointReached: Bool?,
        promptVisibleNow: Bool?,
        visibleFromPreRunMemory: Bool?,
        pauseRecorded: Bool?,
        deliverableNow: Bool?,
        shouldPauseToolBatchAfterBoundary: Bool?,
        deliveryState: String?,
        executionGate: String?,
        summaryLine: String
    ) {
        self.schemaVersion = schemaVersion
        self.pendingGuidanceAvailable = pendingGuidanceAvailable
        self.pendingGuidanceInjectionId = pendingGuidanceInjectionId
        self.pendingGuidanceDeliveryMode = pendingGuidanceDeliveryMode
        self.pendingGuidanceInterventionMode = pendingGuidanceInterventionMode
        self.pendingGuidanceSafePointPolicy = pendingGuidanceSafePointPolicy
        self.liveStateSource = liveStateSource
        self.flowStep = flowStep
        self.toolResultsCount = toolResultsCount
        self.verifyRunIndex = verifyRunIndex
        self.finalizeOnly = finalizeOnly
        self.checkpointReached = checkpointReached
        self.promptVisibleNow = promptVisibleNow
        self.visibleFromPreRunMemory = visibleFromPreRunMemory
        self.pauseRecorded = pauseRecorded
        self.deliverableNow = deliverableNow
        self.shouldPauseToolBatchAfterBoundary = shouldPauseToolBatchAfterBoundary
        self.deliveryState = deliveryState
        self.executionGate = executionGate
        self.summaryLine = summaryLine
    }

}

struct XTUnifiedDoctorSupervisorSafePointTimelineProjection: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_safe_point_timeline.v1"

    private let storage: XTUnifiedDoctorSupervisorSafePointTimelineProjectionStorage

    var schemaVersion: String { storage.schemaVersion }
    var pendingGuidanceAvailable: Bool { storage.pendingGuidanceAvailable }
    var pendingGuidanceInjectionId: String? { storage.pendingGuidanceInjectionId }
    var pendingGuidanceDeliveryMode: String? { storage.pendingGuidanceDeliveryMode }
    var pendingGuidanceInterventionMode: String? { storage.pendingGuidanceInterventionMode }
    var pendingGuidanceSafePointPolicy: String? { storage.pendingGuidanceSafePointPolicy }
    var liveStateSource: String? { storage.liveStateSource }
    var flowStep: Int? { storage.flowStep }
    var toolResultsCount: Int? { storage.toolResultsCount }
    var verifyRunIndex: Int? { storage.verifyRunIndex }
    var finalizeOnly: Bool? { storage.finalizeOnly }
    var checkpointReached: Bool? { storage.checkpointReached }
    var promptVisibleNow: Bool? { storage.promptVisibleNow }
    var visibleFromPreRunMemory: Bool? { storage.visibleFromPreRunMemory }
    var pauseRecorded: Bool? { storage.pauseRecorded }
    var deliverableNow: Bool? { storage.deliverableNow }
    var shouldPauseToolBatchAfterBoundary: Bool? { storage.shouldPauseToolBatchAfterBoundary }
    var deliveryState: String? { storage.deliveryState }
    var executionGate: String? { storage.executionGate }
    var summaryLine: String { storage.summaryLine }

    init(
        schemaVersion: String = currentSchemaVersion,
        pendingGuidanceAvailable: Bool,
        pendingGuidanceInjectionId: String?,
        pendingGuidanceDeliveryMode: String?,
        pendingGuidanceInterventionMode: String?,
        pendingGuidanceSafePointPolicy: String?,
        liveStateSource: String?,
        flowStep: Int?,
        toolResultsCount: Int?,
        verifyRunIndex: Int?,
        finalizeOnly: Bool?,
        checkpointReached: Bool?,
        promptVisibleNow: Bool?,
        visibleFromPreRunMemory: Bool?,
        pauseRecorded: Bool?,
        deliverableNow: Bool?,
        shouldPauseToolBatchAfterBoundary: Bool?,
        deliveryState: String?,
        executionGate: String?,
        summaryLine: String
    ) {
        self.storage = XTUnifiedDoctorSupervisorSafePointTimelineProjectionStorage(
            schemaVersion: schemaVersion,
            pendingGuidanceAvailable: pendingGuidanceAvailable,
            pendingGuidanceInjectionId: normalizedMeaningfulValue(pendingGuidanceInjectionId),
            pendingGuidanceDeliveryMode: normalizedMeaningfulValue(pendingGuidanceDeliveryMode),
            pendingGuidanceInterventionMode: normalizedMeaningfulValue(pendingGuidanceInterventionMode),
            pendingGuidanceSafePointPolicy: normalizedMeaningfulValue(pendingGuidanceSafePointPolicy),
            liveStateSource: normalizedMeaningfulValue(liveStateSource),
            flowStep: flowStep,
            toolResultsCount: toolResultsCount,
            verifyRunIndex: verifyRunIndex,
            finalizeOnly: finalizeOnly,
            checkpointReached: checkpointReached,
            promptVisibleNow: promptVisibleNow,
            visibleFromPreRunMemory: visibleFromPreRunMemory,
            pauseRecorded: pauseRecorded,
            deliverableNow: deliverableNow,
            shouldPauseToolBatchAfterBoundary: shouldPauseToolBatchAfterBoundary,
            deliveryState: normalizedMeaningfulValue(deliveryState),
            executionGate: normalizedMeaningfulValue(executionGate),
            summaryLine: summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    init(from decoder: Decoder) throws {
        self.storage = try XTUnifiedDoctorSupervisorSafePointTimelineProjectionStorage(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try storage.encode(to: encoder)
    }

    static func ==(
        lhs: XTUnifiedDoctorSupervisorSafePointTimelineProjection,
        rhs: XTUnifiedDoctorSupervisorSafePointTimelineProjection
    ) -> Bool {
        lhs.storage == rhs.storage
    }

    init?(ctx: AXProjectContext) {
        guard let guidance = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx) else {
            return nil
        }

        let pendingToolFlow = AXPendingActionsStore.pendingToolApproval(for: ctx)?.flow
        let liveStateSource = pendingToolFlow == nil ? "no_live_flow" : "pending_tool_approval"
        let safePointState = pendingToolFlow.map {
            SupervisorSafePointExecutionState(
                runStartedAtMs: $0.runStartedAtMs,
                flowStep: $0.step,
                toolResultsCount: $0.toolResults.count,
                verifyRunIndex: $0.verifyRunIndex,
                finalizeOnly: $0.finalizeOnly
            )
        }
        let promptVisibleNow = pendingToolFlow.map { flow in
            normalizedMeaningfulValue(flow.lastPromptVisibleGuidanceInjectionId) == guidance.injectionId
        }
        let pauseRecorded = pendingToolFlow.map { flow in
            normalizedMeaningfulValue(flow.lastSafePointPauseInjectionId) == guidance.injectionId
        }
        let visibleFromPreRunMemory = safePointState.map { state in
            guidance.injectedAtMs <= 0 || guidance.injectedAtMs <= state.runStartedAtMs
        }
        let deliverableNow = safePointState.map { state in
            SupervisorSafePointCoordinator.deliverablePendingGuidance(for: ctx, state: state)?.injectionId == guidance.injectionId
        }
        let rawPauseCandidate = safePointState.map { state in
            SupervisorSafePointCoordinator.shouldPauseToolBatchAfterBoundary(for: ctx, state: state)?.injectionId == guidance.injectionId
        }
        let shouldPauseToolBatchAfterBoundary = rawPauseCandidate.map { candidate in
            candidate && pauseRecorded != true
        }
        let deliveryState = Self.deliveryState(
            guidance: guidance,
            liveStateSource: liveStateSource,
            promptVisibleNow: promptVisibleNow,
            visibleFromPreRunMemory: visibleFromPreRunMemory,
            deliverableNow: deliverableNow
        )
        let executionGate = Self.executionGate(guidance)
        let summaryLine = Self.summaryLine(
            deliveryState: deliveryState,
            executionGate: executionGate,
            shouldPauseToolBatchAfterBoundary: shouldPauseToolBatchAfterBoundary,
            pauseRecorded: pauseRecorded
        ) ?? "Safe Point：当前没有可投递 guidance"

        self.init(
            pendingGuidanceAvailable: true,
            pendingGuidanceInjectionId: guidance.injectionId,
            pendingGuidanceDeliveryMode: guidance.deliveryMode.rawValue,
            pendingGuidanceInterventionMode: guidance.interventionMode.rawValue,
            pendingGuidanceSafePointPolicy: guidance.safePointPolicy.rawValue,
            liveStateSource: liveStateSource,
            flowStep: safePointState?.flowStep,
            toolResultsCount: safePointState?.toolResultsCount,
            verifyRunIndex: safePointState?.verifyRunIndex,
            finalizeOnly: safePointState?.finalizeOnly,
            checkpointReached: safePointState?.checkpointReached,
            promptVisibleNow: promptVisibleNow,
            visibleFromPreRunMemory: visibleFromPreRunMemory,
            pauseRecorded: pauseRecorded,
            deliverableNow: deliverableNow,
            shouldPauseToolBatchAfterBoundary: shouldPauseToolBatchAfterBoundary,
            deliveryState: deliveryState,
            executionGate: executionGate,
            summaryLine: summaryLine
        )
    }

    static func from(detailLines: [String]) -> XTUnifiedDoctorSupervisorSafePointTimelineProjection? {
        let summaryLine = normalizedOptionalDoctorField(
            detailLines.first(where: { $0.hasPrefix("Safe Point：") })
        ) ?? summaryLine(
            deliveryState: detailValue(
                "supervisor_safe_point_delivery_state",
                from: detailLines
            ),
            executionGate: detailValue(
                "supervisor_safe_point_execution_gate",
                from: detailLines
            ),
            shouldPauseToolBatchAfterBoundary: detailBoolValue(
                "supervisor_safe_point_should_pause_tool_batch_after_boundary",
                from: detailLines
            ),
            pauseRecorded: detailBoolValue(
                "supervisor_safe_point_pause_recorded",
                from: detailLines
            )
        )
        let pendingGuidanceAvailable = detailBoolValue(
            "supervisor_safe_point_pending_guidance_available",
            from: detailLines
        ) ?? false
        let pendingGuidanceInjectionId = detailValue(
            "supervisor_safe_point_pending_guidance_injection_id",
            from: detailLines
        )
        let pendingGuidanceDeliveryMode = detailValue(
            "supervisor_safe_point_pending_guidance_delivery_mode",
            from: detailLines
        )
        let pendingGuidanceInterventionMode = detailValue(
            "supervisor_safe_point_pending_guidance_intervention_mode",
            from: detailLines
        )
        let pendingGuidanceSafePointPolicy = detailValue(
            "supervisor_safe_point_pending_guidance_safe_point_policy",
            from: detailLines
        )
        let liveStateSource = detailValue(
            "supervisor_safe_point_live_state_source",
            from: detailLines
        )
        let flowStep = detailIntValue(
            "supervisor_safe_point_flow_step",
            from: detailLines
        )
        let toolResultsCount = detailIntValue(
            "supervisor_safe_point_tool_results_count",
            from: detailLines
        )
        let verifyRunIndex = detailIntValue(
            "supervisor_safe_point_verify_run_index",
            from: detailLines
        )
        let finalizeOnly = detailBoolValue(
            "supervisor_safe_point_finalize_only",
            from: detailLines
        )
        let checkpointReached = detailBoolValue(
            "supervisor_safe_point_checkpoint_reached",
            from: detailLines
        )
        let promptVisibleNow = detailBoolValue(
            "supervisor_safe_point_prompt_visible_now",
            from: detailLines
        )
        let visibleFromPreRunMemory = detailBoolValue(
            "supervisor_safe_point_visible_from_pre_run_memory",
            from: detailLines
        )
        let pauseRecorded = detailBoolValue(
            "supervisor_safe_point_pause_recorded",
            from: detailLines
        )
        let deliverableNow = detailBoolValue(
            "supervisor_safe_point_deliverable_now",
            from: detailLines
        )
        let shouldPauseToolBatchAfterBoundary = detailBoolValue(
            "supervisor_safe_point_should_pause_tool_batch_after_boundary",
            from: detailLines
        )
        let deliveryState = detailValue(
            "supervisor_safe_point_delivery_state",
            from: detailLines
        )
        let executionGate = detailValue(
            "supervisor_safe_point_execution_gate",
            from: detailLines
        )

        guard pendingGuidanceAvailable
                || normalizedMeaningfulValue(pendingGuidanceInjectionId) != nil
                || normalizedMeaningfulValue(deliveryState) != nil
                || normalizedOptionalDoctorField(summaryLine) != nil else {
            return nil
        }

        return XTUnifiedDoctorSupervisorSafePointTimelineProjection(
            pendingGuidanceAvailable: pendingGuidanceAvailable,
            pendingGuidanceInjectionId: pendingGuidanceInjectionId,
            pendingGuidanceDeliveryMode: pendingGuidanceDeliveryMode,
            pendingGuidanceInterventionMode: pendingGuidanceInterventionMode,
            pendingGuidanceSafePointPolicy: pendingGuidanceSafePointPolicy,
            liveStateSource: liveStateSource,
            flowStep: flowStep,
            toolResultsCount: toolResultsCount,
            verifyRunIndex: verifyRunIndex,
            finalizeOnly: finalizeOnly,
            checkpointReached: checkpointReached,
            promptVisibleNow: promptVisibleNow,
            visibleFromPreRunMemory: visibleFromPreRunMemory,
            pauseRecorded: pauseRecorded,
            deliverableNow: deliverableNow,
            shouldPauseToolBatchAfterBoundary: shouldPauseToolBatchAfterBoundary,
            deliveryState: deliveryState,
            executionGate: executionGate,
            summaryLine: summaryLine ?? "Safe Point：当前没有可投递 guidance"
        )
    }

    func detailLines() -> [String] {
        var lines = [
            "supervisor_safe_point_timeline_schema_version=\(schemaVersion)",
            "supervisor_safe_point_pending_guidance_available=\(pendingGuidanceAvailable)"
        ]
        if let pendingGuidanceInjectionId {
            lines.append("supervisor_safe_point_pending_guidance_injection_id=\(pendingGuidanceInjectionId)")
        }
        if let pendingGuidanceDeliveryMode {
            lines.append("supervisor_safe_point_pending_guidance_delivery_mode=\(pendingGuidanceDeliveryMode)")
        }
        if let pendingGuidanceInterventionMode {
            lines.append("supervisor_safe_point_pending_guidance_intervention_mode=\(pendingGuidanceInterventionMode)")
        }
        if let pendingGuidanceSafePointPolicy {
            lines.append("supervisor_safe_point_pending_guidance_safe_point_policy=\(pendingGuidanceSafePointPolicy)")
        }
        if let liveStateSource {
            lines.append("supervisor_safe_point_live_state_source=\(liveStateSource)")
        }
        if let flowStep {
            lines.append("supervisor_safe_point_flow_step=\(flowStep)")
        }
        if let toolResultsCount {
            lines.append("supervisor_safe_point_tool_results_count=\(toolResultsCount)")
        }
        if let verifyRunIndex {
            lines.append("supervisor_safe_point_verify_run_index=\(verifyRunIndex)")
        }
        if let finalizeOnly {
            lines.append("supervisor_safe_point_finalize_only=\(finalizeOnly)")
        }
        if let checkpointReached {
            lines.append("supervisor_safe_point_checkpoint_reached=\(checkpointReached)")
        }
        if let promptVisibleNow {
            lines.append("supervisor_safe_point_prompt_visible_now=\(promptVisibleNow)")
        }
        if let visibleFromPreRunMemory {
            lines.append("supervisor_safe_point_visible_from_pre_run_memory=\(visibleFromPreRunMemory)")
        }
        if let pauseRecorded {
            lines.append("supervisor_safe_point_pause_recorded=\(pauseRecorded)")
        }
        if let deliverableNow {
            lines.append("supervisor_safe_point_deliverable_now=\(deliverableNow)")
        }
        if let shouldPauseToolBatchAfterBoundary {
            lines.append(
                "supervisor_safe_point_should_pause_tool_batch_after_boundary=\(shouldPauseToolBatchAfterBoundary)"
            )
        }
        if let deliveryState {
            lines.append("supervisor_safe_point_delivery_state=\(deliveryState)")
        }
        if let executionGate {
            lines.append("supervisor_safe_point_execution_gate=\(executionGate)")
        }
        lines.append(summaryLine)
        return lines
    }

    private static func deliveryState(
        guidance: SupervisorGuidanceInjectionRecord,
        liveStateSource: String,
        promptVisibleNow: Bool?,
        visibleFromPreRunMemory: Bool?,
        deliverableNow: Bool?
    ) -> String {
        if promptVisibleNow == true, visibleFromPreRunMemory == true {
            return "already_visible_pre_run_memory"
        }
        if promptVisibleNow == true {
            return "already_visible_in_prompt_memory"
        }
        if deliverableNow == true {
            return "deliverable_now"
        }
        if liveStateSource == "no_live_flow" {
            return "pending_guidance_no_live_flow"
        }
        switch guidance.safePointPolicy {
        case .immediate:
            return "deliverable_now"
        case .nextToolBoundary:
            return "waiting_next_tool_boundary"
        case .nextStepBoundary:
            return "waiting_next_step_boundary"
        case .checkpointBoundary:
            return "waiting_checkpoint_boundary"
        }
    }

    private static func executionGate(_ guidance: SupervisorGuidanceInjectionRecord) -> String {
        if guidance.deliveryMode == .stopSignal
            || guidance.interventionMode == .stopImmediately
            || guidance.safePointPolicy == .immediate {
            return "final_only_until_ack"
        }
        return "normal"
    }

    private static func summaryLine(
        deliveryState: String?,
        executionGate: String?,
        shouldPauseToolBatchAfterBoundary: Bool?,
        pauseRecorded: Bool?
    ) -> String? {
        guard let deliveryState = normalizedOptionalDoctorField(deliveryState) else {
            return nil
        }

        var parts = [deliveryStateSummary(deliveryState)]
        if let executionGate = normalizedOptionalDoctorField(executionGate) {
            parts.append("execution_gate=\(executionGate)")
        }
        if shouldPauseToolBatchAfterBoundary == true {
            parts.append("pause_after_tool_boundary")
        } else if pauseRecorded == true {
            parts.append("pause_already_recorded")
        }
        return "Safe Point：\(parts.joined(separator: " · "))"
    }

    private static func deliveryStateSummary(_ raw: String) -> String {
        switch raw {
        case "already_visible_pre_run_memory":
            return "pending guidance 已在 run 前进入 prompt memory"
        case "already_visible_in_prompt_memory":
            return "pending guidance 已在当前 prompt memory 可见"
        case "deliverable_now":
            return "pending guidance 当前可立即投递"
        case "waiting_next_tool_boundary":
            return "pending guidance 等待下一个工具边界"
        case "waiting_next_step_boundary":
            return "pending guidance 等待下一步边界"
        case "waiting_checkpoint_boundary":
            return "pending guidance 等待检查点边界"
        case "pending_guidance_no_live_flow":
            return "pending guidance 存在，但当前缺少 live flow"
        default:
            return raw
        }
    }

    private static func detailValue(_ key: String, from detailLines: [String]) -> String? {
        guard let line = detailLines.first(where: { $0.hasPrefix("\(key)=") }) else {
            return nil
        }
        return String(line.dropFirst(key.count + 1))
    }

    private static func detailBoolValue(_ key: String, from detailLines: [String]) -> Bool? {
        guard let raw = normalizedOptionalDoctorField(detailValue(key, from: detailLines)) else {
            return nil
        }
        switch raw.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func detailIntValue(_ key: String, from detailLines: [String]) -> Int? {
        guard let raw = normalizedOptionalDoctorField(detailValue(key, from: detailLines)) else {
            return nil
        }
        return Int(raw)
    }
}

struct XTUnifiedDoctorSkillReadinessPreview: Codable, Equatable, Sendable {
    var skillID: String
    var name: String
    var executionReadiness: String
    var stateLabel: String
    var reasonCode: String
    var grantFloor: String
    var approvalFloor: String
    var capabilityProfiles: [String]
    var capabilityFamilies: [String]
    var unblockActions: [String]

    init(_ entry: AXSkillGovernanceSurfaceEntry) {
        self.skillID = entry.skillID
        self.name = entry.name
        self.executionReadiness = entry.executionReadiness
        self.stateLabel = entry.stateLabel
        self.reasonCode = entry.whyNotRunnable
        self.grantFloor = entry.grantFloor
        self.approvalFloor = entry.approvalFloor
        self.capabilityProfiles = entry.capabilityProfiles
        self.capabilityFamilies = entry.capabilityFamilies
        self.unblockActions = entry.unblockActions
    }
}

struct XTUnifiedDoctorSkillDoctorTruthProjection: Codable, Equatable, Sendable {
    private static let previewLimit = 5

    var effectiveProfileSnapshot: XTProjectEffectiveSkillProfileSnapshot
    var installedSkillCount: Int
    var readySkillCount: Int
    var grantRequiredSkillCount: Int
    var approvalRequiredSkillCount: Int
    var blockedSkillCount: Int
    var degradedSkillCount: Int
    var grantRequiredSkillPreview: [XTUnifiedDoctorSkillReadinessPreview]
    var approvalRequiredSkillPreview: [XTUnifiedDoctorSkillReadinessPreview]
    var blockedSkillPreview: [XTUnifiedDoctorSkillReadinessPreview]

    init(
        effectiveProfileSnapshot: XTProjectEffectiveSkillProfileSnapshot,
        governanceEntries: [AXSkillGovernanceSurfaceEntry]
    ) {
        var readySkillCount = 0
        var grantRequiredSkillCount = 0
        var approvalRequiredSkillCount = 0
        var blockedSkillCount = 0
        var degradedSkillCount = 0
        var grantRequiredSkillPreview: [XTUnifiedDoctorSkillReadinessPreview] = []
        var approvalRequiredSkillPreview: [XTUnifiedDoctorSkillReadinessPreview] = []
        var blockedSkillPreview: [XTUnifiedDoctorSkillReadinessPreview] = []

        for entry in governanceEntries {
            let preview = XTUnifiedDoctorSkillReadinessPreview(entry)
            let readiness = XTSkillCapabilityProfileSupport.readinessState(from: entry.executionReadiness) ?? .degraded

            switch readiness {
            case .ready:
                readySkillCount += 1
            case .grantRequired:
                grantRequiredSkillCount += 1
                if grantRequiredSkillPreview.count < Self.previewLimit {
                    grantRequiredSkillPreview.append(preview)
                }
            case .localApprovalRequired:
                approvalRequiredSkillCount += 1
                if approvalRequiredSkillPreview.count < Self.previewLimit {
                    approvalRequiredSkillPreview.append(preview)
                }
            case .degraded:
                degradedSkillCount += 1
                blockedSkillCount += 1
                if blockedSkillPreview.count < Self.previewLimit {
                    blockedSkillPreview.append(preview)
                }
            case .policyClamped, .runtimeUnavailable, .hubDisconnected, .quarantined, .revoked, .notInstalled, .unsupported:
                blockedSkillCount += 1
                if blockedSkillPreview.count < Self.previewLimit {
                    blockedSkillPreview.append(preview)
                }
            }
        }

        self.effectiveProfileSnapshot = effectiveProfileSnapshot
        self.installedSkillCount = governanceEntries.count
        self.readySkillCount = readySkillCount
        self.grantRequiredSkillCount = grantRequiredSkillCount
        self.approvalRequiredSkillCount = approvalRequiredSkillCount
        self.blockedSkillCount = blockedSkillCount
        self.degradedSkillCount = degradedSkillCount
        self.grantRequiredSkillPreview = grantRequiredSkillPreview
        self.approvalRequiredSkillPreview = approvalRequiredSkillPreview
        self.blockedSkillPreview = blockedSkillPreview
    }
}

struct XTUnifiedDoctorRemoteSnapshotCacheProjection: Codable, Equatable, Sendable {
    var source: String?
    var freshness: String?
    var cacheHit: Bool?
    var scope: String?
    var cachedAtMs: Int64?
    var ageMs: Int?
    var ttlRemainingMs: Int?
    var cachePosture: String?
    var invalidationReason: String?

    init?(
        source: String?,
        freshness: String?,
        cacheHit: Bool?,
        scope: String?,
        cachedAtMs: Int64?,
        ageMs: Int?,
        ttlRemainingMs: Int?,
        cachePosture: String? = nil,
        invalidationReason: String? = nil
    ) {
        let source = normalizedOptionalDoctorField(source)
        let freshness = normalizedOptionalDoctorField(freshness)
        let scope = normalizedOptionalDoctorField(scope)
        let cachePosture = normalizedOptionalDoctorField(cachePosture)
        let invalidationReason = normalizedOptionalDoctorField(invalidationReason)

        guard source != nil
                || freshness != nil
                || cacheHit != nil
                || scope != nil
                || cachedAtMs != nil
                || ageMs != nil
                || ttlRemainingMs != nil
                || cachePosture != nil
                || invalidationReason != nil else {
            return nil
        }

        self.source = source
        self.freshness = freshness
        self.cacheHit = cacheHit
        self.scope = scope
        self.cachedAtMs = cachedAtMs
        self.ageMs = ageMs
        self.ttlRemainingMs = ttlRemainingMs
        self.cachePosture = cachePosture
        self.invalidationReason = invalidationReason
    }
}

private final class XTUnifiedDoctorSupervisorReviewTriggerProjectionStorage: Codable, Equatable, Sendable {
    let schemaVersion: String
    let reviewPolicyMode: String?
    let eventDrivenReviewEnabled: Bool
    let eventFollowUpCadenceLabel: String?
    let mandatoryReviewTriggers: [String]
    let effectiveEventReviewTriggers: [String]
    let derivedReviewTriggers: [String]
    let activeCandidateAvailable: Bool
    let activeCandidateTrigger: String?
    let activeCandidateRunKind: String?
    let activeCandidateReviewLevel: String?
    let activeCandidatePriority: Int?
    let activeCandidatePolicyReason: String?
    let activeCandidateQueued: Bool?
    let queuedReviewTrigger: String?
    let queuedReviewRunKind: String?
    let queuedReviewLevel: String?
    let latestReviewSource: String?
    let latestReviewTrigger: String?
    let latestReviewLevel: String?
    let latestReviewAtMs: Int64?
    let lastPulseReviewAtMs: Int64?
    let lastBrainstormReviewAtMs: Int64?
    let summaryLine: String

    init(
        schemaVersion: String,
        reviewPolicyMode: String?,
        eventDrivenReviewEnabled: Bool,
        eventFollowUpCadenceLabel: String?,
        mandatoryReviewTriggers: [String],
        effectiveEventReviewTriggers: [String],
        derivedReviewTriggers: [String],
        activeCandidateAvailable: Bool,
        activeCandidateTrigger: String?,
        activeCandidateRunKind: String?,
        activeCandidateReviewLevel: String?,
        activeCandidatePriority: Int?,
        activeCandidatePolicyReason: String?,
        activeCandidateQueued: Bool?,
        queuedReviewTrigger: String?,
        queuedReviewRunKind: String?,
        queuedReviewLevel: String?,
        latestReviewSource: String?,
        latestReviewTrigger: String?,
        latestReviewLevel: String?,
        latestReviewAtMs: Int64?,
        lastPulseReviewAtMs: Int64?,
        lastBrainstormReviewAtMs: Int64?,
        summaryLine: String
    ) {
        self.schemaVersion = schemaVersion
        self.reviewPolicyMode = reviewPolicyMode
        self.eventDrivenReviewEnabled = eventDrivenReviewEnabled
        self.eventFollowUpCadenceLabel = eventFollowUpCadenceLabel
        self.mandatoryReviewTriggers = mandatoryReviewTriggers
        self.effectiveEventReviewTriggers = effectiveEventReviewTriggers
        self.derivedReviewTriggers = derivedReviewTriggers
        self.activeCandidateAvailable = activeCandidateAvailable
        self.activeCandidateTrigger = activeCandidateTrigger
        self.activeCandidateRunKind = activeCandidateRunKind
        self.activeCandidateReviewLevel = activeCandidateReviewLevel
        self.activeCandidatePriority = activeCandidatePriority
        self.activeCandidatePolicyReason = activeCandidatePolicyReason
        self.activeCandidateQueued = activeCandidateQueued
        self.queuedReviewTrigger = queuedReviewTrigger
        self.queuedReviewRunKind = queuedReviewRunKind
        self.queuedReviewLevel = queuedReviewLevel
        self.latestReviewSource = latestReviewSource
        self.latestReviewTrigger = latestReviewTrigger
        self.latestReviewLevel = latestReviewLevel
        self.latestReviewAtMs = latestReviewAtMs
        self.lastPulseReviewAtMs = lastPulseReviewAtMs
        self.lastBrainstormReviewAtMs = lastBrainstormReviewAtMs
        self.summaryLine = summaryLine
    }

    static func ==(
        lhs: XTUnifiedDoctorSupervisorReviewTriggerProjectionStorage,
        rhs: XTUnifiedDoctorSupervisorReviewTriggerProjectionStorage
    ) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion
            && lhs.reviewPolicyMode == rhs.reviewPolicyMode
            && lhs.eventDrivenReviewEnabled == rhs.eventDrivenReviewEnabled
            && lhs.eventFollowUpCadenceLabel == rhs.eventFollowUpCadenceLabel
            && lhs.mandatoryReviewTriggers == rhs.mandatoryReviewTriggers
            && lhs.effectiveEventReviewTriggers == rhs.effectiveEventReviewTriggers
            && lhs.derivedReviewTriggers == rhs.derivedReviewTriggers
            && lhs.activeCandidateAvailable == rhs.activeCandidateAvailable
            && lhs.activeCandidateTrigger == rhs.activeCandidateTrigger
            && lhs.activeCandidateRunKind == rhs.activeCandidateRunKind
            && lhs.activeCandidateReviewLevel == rhs.activeCandidateReviewLevel
            && lhs.activeCandidatePriority == rhs.activeCandidatePriority
            && lhs.activeCandidatePolicyReason == rhs.activeCandidatePolicyReason
            && lhs.activeCandidateQueued == rhs.activeCandidateQueued
            && lhs.queuedReviewTrigger == rhs.queuedReviewTrigger
            && lhs.queuedReviewRunKind == rhs.queuedReviewRunKind
            && lhs.queuedReviewLevel == rhs.queuedReviewLevel
            && lhs.latestReviewSource == rhs.latestReviewSource
            && lhs.latestReviewTrigger == rhs.latestReviewTrigger
            && lhs.latestReviewLevel == rhs.latestReviewLevel
            && lhs.latestReviewAtMs == rhs.latestReviewAtMs
            && lhs.lastPulseReviewAtMs == rhs.lastPulseReviewAtMs
            && lhs.lastBrainstormReviewAtMs == rhs.lastBrainstormReviewAtMs
            && lhs.summaryLine == rhs.summaryLine
    }
}

struct XTUnifiedDoctorSupervisorReviewTriggerProjection: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_review_trigger.v1"

    private let storage: XTUnifiedDoctorSupervisorReviewTriggerProjectionStorage

    var schemaVersion: String { storage.schemaVersion }
    var reviewPolicyMode: String? { storage.reviewPolicyMode }
    var eventDrivenReviewEnabled: Bool { storage.eventDrivenReviewEnabled }
    var eventFollowUpCadenceLabel: String? { storage.eventFollowUpCadenceLabel }
    var mandatoryReviewTriggers: [String] { storage.mandatoryReviewTriggers }
    var effectiveEventReviewTriggers: [String] { storage.effectiveEventReviewTriggers }
    var derivedReviewTriggers: [String] { storage.derivedReviewTriggers }
    var activeCandidateAvailable: Bool { storage.activeCandidateAvailable }
    var activeCandidateTrigger: String? { storage.activeCandidateTrigger }
    var activeCandidateRunKind: String? { storage.activeCandidateRunKind }
    var activeCandidateReviewLevel: String? { storage.activeCandidateReviewLevel }
    var activeCandidatePriority: Int? { storage.activeCandidatePriority }
    var activeCandidatePolicyReason: String? { storage.activeCandidatePolicyReason }
    var activeCandidateQueued: Bool? { storage.activeCandidateQueued }
    var queuedReviewTrigger: String? { storage.queuedReviewTrigger }
    var queuedReviewRunKind: String? { storage.queuedReviewRunKind }
    var queuedReviewLevel: String? { storage.queuedReviewLevel }
    var latestReviewSource: String? { storage.latestReviewSource }
    var latestReviewTrigger: String? { storage.latestReviewTrigger }
    var latestReviewLevel: String? { storage.latestReviewLevel }
    var latestReviewAtMs: Int64? { storage.latestReviewAtMs }
    var lastPulseReviewAtMs: Int64? { storage.lastPulseReviewAtMs }
    var lastBrainstormReviewAtMs: Int64? { storage.lastBrainstormReviewAtMs }
    var summaryLine: String { storage.summaryLine }

    init(
        schemaVersion: String = currentSchemaVersion,
        reviewPolicyMode: String?,
        eventDrivenReviewEnabled: Bool,
        eventFollowUpCadenceLabel: String?,
        mandatoryReviewTriggers: [String],
        effectiveEventReviewTriggers: [String],
        derivedReviewTriggers: [String],
        activeCandidateAvailable: Bool,
        activeCandidateTrigger: String?,
        activeCandidateRunKind: String?,
        activeCandidateReviewLevel: String?,
        activeCandidatePriority: Int?,
        activeCandidatePolicyReason: String?,
        activeCandidateQueued: Bool?,
        queuedReviewTrigger: String?,
        queuedReviewRunKind: String?,
        queuedReviewLevel: String?,
        latestReviewSource: String?,
        latestReviewTrigger: String?,
        latestReviewLevel: String?,
        latestReviewAtMs: Int64?,
        lastPulseReviewAtMs: Int64?,
        lastBrainstormReviewAtMs: Int64?,
        summaryLine: String
    ) {
        self.storage = XTUnifiedDoctorSupervisorReviewTriggerProjectionStorage(
            schemaVersion: schemaVersion,
            reviewPolicyMode: normalizedMeaningfulValue(reviewPolicyMode),
            eventDrivenReviewEnabled: eventDrivenReviewEnabled,
            eventFollowUpCadenceLabel: normalizedMeaningfulValue(eventFollowUpCadenceLabel),
            mandatoryReviewTriggers: Self.orderedUniqueTokens(mandatoryReviewTriggers),
            effectiveEventReviewTriggers: Self.orderedUniqueTokens(effectiveEventReviewTriggers),
            derivedReviewTriggers: Self.orderedUniqueTokens(derivedReviewTriggers),
            activeCandidateAvailable: activeCandidateAvailable,
            activeCandidateTrigger: normalizedMeaningfulValue(activeCandidateTrigger),
            activeCandidateRunKind: normalizedMeaningfulValue(activeCandidateRunKind),
            activeCandidateReviewLevel: normalizedMeaningfulValue(activeCandidateReviewLevel),
            activeCandidatePriority: activeCandidatePriority.map { max(0, $0) },
            activeCandidatePolicyReason: normalizedMeaningfulValue(activeCandidatePolicyReason),
            activeCandidateQueued: activeCandidateQueued,
            queuedReviewTrigger: normalizedMeaningfulValue(queuedReviewTrigger),
            queuedReviewRunKind: normalizedMeaningfulValue(queuedReviewRunKind),
            queuedReviewLevel: normalizedMeaningfulValue(queuedReviewLevel),
            latestReviewSource: normalizedMeaningfulValue(latestReviewSource),
            latestReviewTrigger: normalizedMeaningfulValue(latestReviewTrigger),
            latestReviewLevel: normalizedMeaningfulValue(latestReviewLevel),
            latestReviewAtMs: latestReviewAtMs.map { max(Int64(0), $0) },
            lastPulseReviewAtMs: lastPulseReviewAtMs.map { max(Int64(0), $0) },
            lastBrainstormReviewAtMs: lastBrainstormReviewAtMs.map { max(Int64(0), $0) },
            summaryLine: summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    init(from decoder: Decoder) throws {
        self.storage = try XTUnifiedDoctorSupervisorReviewTriggerProjectionStorage(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try storage.encode(to: encoder)
    }

    static func ==(
        lhs: XTUnifiedDoctorSupervisorReviewTriggerProjection,
        rhs: XTUnifiedDoctorSupervisorReviewTriggerProjection
    ) -> Bool {
        lhs.storage == rhs.storage
    }

    init?(
        governance: AXProjectResolvedGovernanceState,
        heartbeatSnapshot: XTProjectHeartbeatGovernanceDoctorSnapshot?,
        ctx: AXProjectContext,
        now: Date = Date()
    ) {
        let schedule = SupervisorReviewScheduleStore.load(for: ctx)
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let activeCandidate = SupervisorReviewPolicyEngine.heartbeatCandidate(
            governance: governance,
            schedule: schedule,
            blockerDetected: Self.hasMeaningfulBlocker(heartbeatSnapshot?.blockerSummary),
            nowMs: nowMs
        )
        let recoveryDecision = SupervisorReviewPolicyEngine.recoveryDecision(
            schedule: schedule,
            laneSnapshot: nil,
            reviewCandidate: activeCandidate,
            openAnomalies: schedule.openAnomalies
        )
        let latestReview = Self.latestReviewState(ctx: ctx, schedule: schedule)
        let summaryLine = Self.summaryLine(
            reviewPolicyMode: governance.effectiveBundle.reviewPolicyMode.rawValue,
            eventDrivenReviewEnabled: governance.effectiveBundle.schedule.eventDrivenReviewEnabled,
            activeCandidate: activeCandidate,
            activeCandidateQueued: Self.activeCandidateQueued(
                candidate: activeCandidate,
                recoveryDecision: recoveryDecision
            ),
            recoveryDecision: recoveryDecision,
            latestReview: latestReview
        ) ?? "Review Trigger：当前没有可解释的 review trigger posture"

        let mandatoryReviewTriggers = governance.effectiveBundle.executionTier.mandatoryReviewTriggers.map(\.rawValue)
        let effectiveEventReviewTriggers = governance.effectiveBundle.schedule.eventReviewTriggers.map(\.rawValue)
        let derivedReviewTriggers = Self.derivedReviewTriggers(
            governance: governance,
            heartbeatSnapshot: heartbeatSnapshot
        )

        guard !mandatoryReviewTriggers.isEmpty
                || !effectiveEventReviewTriggers.isEmpty
                || !derivedReviewTriggers.isEmpty
                || activeCandidate != nil
                || recoveryDecision?.queuedReviewTrigger != nil
                || latestReview.trigger != nil
                || normalizedOptionalDoctorField(summaryLine) != nil else {
            return nil
        }

        self.init(
            reviewPolicyMode: governance.effectiveBundle.reviewPolicyMode.rawValue,
            eventDrivenReviewEnabled: governance.effectiveBundle.schedule.eventDrivenReviewEnabled,
            eventFollowUpCadenceLabel: SupervisorReviewPolicyEngine.eventFollowUpCadenceLabel(
                governance: governance
            ),
            mandatoryReviewTriggers: mandatoryReviewTriggers,
            effectiveEventReviewTriggers: effectiveEventReviewTriggers,
            derivedReviewTriggers: derivedReviewTriggers,
            activeCandidateAvailable: activeCandidate != nil,
            activeCandidateTrigger: activeCandidate?.trigger.rawValue,
            activeCandidateRunKind: activeCandidate?.runKind.rawValue,
            activeCandidateReviewLevel: activeCandidate?.reviewLevel.rawValue,
            activeCandidatePriority: activeCandidate?.priority,
            activeCandidatePolicyReason: activeCandidate?.policyReason,
            activeCandidateQueued: Self.activeCandidateQueued(
                candidate: activeCandidate,
                recoveryDecision: recoveryDecision
            ),
            queuedReviewTrigger: recoveryDecision?.queuedReviewTrigger?.rawValue,
            queuedReviewRunKind: recoveryDecision?.queuedReviewRunKind?.rawValue,
            queuedReviewLevel: recoveryDecision?.queuedReviewLevel?.rawValue,
            latestReviewSource: latestReview.source,
            latestReviewTrigger: latestReview.trigger,
            latestReviewLevel: latestReview.level,
            latestReviewAtMs: latestReview.atMs,
            lastPulseReviewAtMs: schedule.lastPulseReviewAtMs > 0 ? schedule.lastPulseReviewAtMs : nil,
            lastBrainstormReviewAtMs: schedule.lastBrainstormReviewAtMs > 0 ? schedule.lastBrainstormReviewAtMs : nil,
            summaryLine: summaryLine
        )
    }

    static func from(detailLines: [String]) -> XTUnifiedDoctorSupervisorReviewTriggerProjection? {
        let summaryLine = normalizedOptionalDoctorField(
            detailLines.first(where: { $0.hasPrefix("Review Trigger：") })
        ) ?? Self.summaryLine(
            reviewPolicyMode: detailValue("supervisor_review_policy_mode", from: detailLines),
            eventDrivenReviewEnabled: detailBoolValue(
                "supervisor_review_event_driven_enabled",
                from: detailLines
            ) ?? false,
            activeCandidate: Self.activeCandidate(
                detailLines: detailLines
            ),
            activeCandidateQueued: detailBoolValue(
                "supervisor_review_active_candidate_queued",
                from: detailLines
            ),
            recoveryDecision: Self.queuedReview(
                detailLines: detailLines
            ),
            latestReview: (
                source: detailValue("supervisor_review_latest_review_source", from: detailLines),
                trigger: detailValue("supervisor_review_latest_review_trigger", from: detailLines),
                level: detailValue("supervisor_review_latest_review_level", from: detailLines),
                atMs: detailInt64Value("supervisor_review_latest_review_at_ms", from: detailLines)
            )
        )

        let mandatoryReviewTriggers = detailCSVValues(
            "supervisor_review_mandatory_triggers",
            from: detailLines
        )
        let effectiveEventReviewTriggers = detailCSVValues(
            "supervisor_review_effective_event_triggers",
            from: detailLines
        )
        let derivedReviewTriggers = detailCSVValues(
            "supervisor_review_derived_triggers",
            from: detailLines
        )
        let activeCandidateAvailable = detailBoolValue(
            "supervisor_review_active_candidate_available",
            from: detailLines
        ) ?? false

        guard !mandatoryReviewTriggers.isEmpty
                || !effectiveEventReviewTriggers.isEmpty
                || !derivedReviewTriggers.isEmpty
                || activeCandidateAvailable
                || normalizedMeaningfulValue(
                    detailValue("supervisor_review_queued_trigger", from: detailLines)
                ) != nil
                || normalizedMeaningfulValue(
                    detailValue("supervisor_review_latest_review_trigger", from: detailLines)
                ) != nil
                || normalizedOptionalDoctorField(summaryLine) != nil else {
            return nil
        }

        return XTUnifiedDoctorSupervisorReviewTriggerProjection(
            reviewPolicyMode: detailValue("supervisor_review_policy_mode", from: detailLines),
            eventDrivenReviewEnabled: detailBoolValue(
                "supervisor_review_event_driven_enabled",
                from: detailLines
            ) ?? false,
            eventFollowUpCadenceLabel: detailValue(
                "supervisor_review_event_follow_up_cadence_label",
                from: detailLines
            ),
            mandatoryReviewTriggers: mandatoryReviewTriggers,
            effectiveEventReviewTriggers: effectiveEventReviewTriggers,
            derivedReviewTriggers: derivedReviewTriggers,
            activeCandidateAvailable: activeCandidateAvailable,
            activeCandidateTrigger: detailValue(
                "supervisor_review_active_candidate_trigger",
                from: detailLines
            ),
            activeCandidateRunKind: detailValue(
                "supervisor_review_active_candidate_run_kind",
                from: detailLines
            ),
            activeCandidateReviewLevel: detailValue(
                "supervisor_review_active_candidate_level",
                from: detailLines
            ),
            activeCandidatePriority: detailIntValue(
                "supervisor_review_active_candidate_priority",
                from: detailLines
            ),
            activeCandidatePolicyReason: detailValue(
                "supervisor_review_active_candidate_policy_reason",
                from: detailLines
            ),
            activeCandidateQueued: detailBoolValue(
                "supervisor_review_active_candidate_queued",
                from: detailLines
            ),
            queuedReviewTrigger: detailValue(
                "supervisor_review_queued_trigger",
                from: detailLines
            ),
            queuedReviewRunKind: detailValue(
                "supervisor_review_queued_run_kind",
                from: detailLines
            ),
            queuedReviewLevel: detailValue(
                "supervisor_review_queued_level",
                from: detailLines
            ),
            latestReviewSource: detailValue(
                "supervisor_review_latest_review_source",
                from: detailLines
            ),
            latestReviewTrigger: detailValue(
                "supervisor_review_latest_review_trigger",
                from: detailLines
            ),
            latestReviewLevel: detailValue(
                "supervisor_review_latest_review_level",
                from: detailLines
            ),
            latestReviewAtMs: detailInt64Value(
                "supervisor_review_latest_review_at_ms",
                from: detailLines
            ),
            lastPulseReviewAtMs: detailInt64Value(
                "supervisor_review_last_pulse_review_at_ms",
                from: detailLines
            ),
            lastBrainstormReviewAtMs: detailInt64Value(
                "supervisor_review_last_brainstorm_review_at_ms",
                from: detailLines
            ),
            summaryLine: summaryLine ?? "Review Trigger：当前没有可解释的 review trigger posture"
        )
    }

    func detailLines() -> [String] {
        var lines = [
            "supervisor_review_trigger_schema_version=\(schemaVersion)",
            "supervisor_review_event_driven_enabled=\(eventDrivenReviewEnabled)",
            "supervisor_review_mandatory_triggers=\(csv(mandatoryReviewTriggers))",
            "supervisor_review_effective_event_triggers=\(csv(effectiveEventReviewTriggers))",
            "supervisor_review_derived_triggers=\(csv(derivedReviewTriggers))",
            "supervisor_review_active_candidate_available=\(activeCandidateAvailable)"
        ]
        if let reviewPolicyMode {
            lines.append("supervisor_review_policy_mode=\(reviewPolicyMode)")
        }
        if let eventFollowUpCadenceLabel {
            lines.append("supervisor_review_event_follow_up_cadence_label=\(eventFollowUpCadenceLabel)")
        }
        if let activeCandidateTrigger {
            lines.append("supervisor_review_active_candidate_trigger=\(activeCandidateTrigger)")
        }
        if let activeCandidateRunKind {
            lines.append("supervisor_review_active_candidate_run_kind=\(activeCandidateRunKind)")
        }
        if let activeCandidateReviewLevel {
            lines.append("supervisor_review_active_candidate_level=\(activeCandidateReviewLevel)")
        }
        if let activeCandidatePriority {
            lines.append("supervisor_review_active_candidate_priority=\(activeCandidatePriority)")
        }
        if let activeCandidatePolicyReason {
            lines.append("supervisor_review_active_candidate_policy_reason=\(activeCandidatePolicyReason)")
        }
        if let activeCandidateQueued {
            lines.append("supervisor_review_active_candidate_queued=\(activeCandidateQueued)")
        }
        if let queuedReviewTrigger {
            lines.append("supervisor_review_queued_trigger=\(queuedReviewTrigger)")
        }
        if let queuedReviewRunKind {
            lines.append("supervisor_review_queued_run_kind=\(queuedReviewRunKind)")
        }
        if let queuedReviewLevel {
            lines.append("supervisor_review_queued_level=\(queuedReviewLevel)")
        }
        if let latestReviewSource {
            lines.append("supervisor_review_latest_review_source=\(latestReviewSource)")
        }
        if let latestReviewTrigger {
            lines.append("supervisor_review_latest_review_trigger=\(latestReviewTrigger)")
        }
        if let latestReviewLevel {
            lines.append("supervisor_review_latest_review_level=\(latestReviewLevel)")
        }
        if let latestReviewAtMs {
            lines.append("supervisor_review_latest_review_at_ms=\(max(Int64(0), latestReviewAtMs))")
        }
        if let lastPulseReviewAtMs {
            lines.append("supervisor_review_last_pulse_review_at_ms=\(max(Int64(0), lastPulseReviewAtMs))")
        }
        if let lastBrainstormReviewAtMs {
            lines.append("supervisor_review_last_brainstorm_review_at_ms=\(max(Int64(0), lastBrainstormReviewAtMs))")
        }
        lines.append(summaryLine)
        return lines
    }

    private static func hasMeaningfulBlocker(_ raw: String?) -> Bool {
        normalizedMeaningfulValue(raw) != nil
    }

    private static func derivedReviewTriggers(
        governance: AXProjectResolvedGovernanceState,
        heartbeatSnapshot: XTProjectHeartbeatGovernanceDoctorSnapshot?
    ) -> [String] {
        var derived: [String] = [
            SupervisorReviewTrigger.manualRequest.rawValue,
            SupervisorReviewTrigger.userOverride.rawValue
        ]
        let pulseSeconds = heartbeatSnapshot?.cadence.reviewPulse.effectiveSeconds
            ?? governance.effectiveBundle.schedule.reviewPulseSeconds
        let brainstormSeconds = heartbeatSnapshot?.cadence.brainstormReview.effectiveSeconds
            ?? governance.effectiveBundle.schedule.brainstormReviewSeconds
        if governance.effectiveBundle.reviewPolicyMode.supportsPulseCadence, pulseSeconds > 0 {
            derived.append(SupervisorReviewTrigger.periodicPulse.rawValue)
        }
        if governance.effectiveBundle.reviewPolicyMode.supportsBrainstormCadence, brainstormSeconds > 0 {
            derived.append(SupervisorReviewTrigger.noProgressWindow.rawValue)
        }
        return orderedUniqueTokens(derived)
    }

    private static func activeCandidateQueued(
        candidate: SupervisorHeartbeatReviewCandidate?,
        recoveryDecision: HeartbeatRecoveryDecision?
    ) -> Bool? {
        guard let candidate else { return nil }
        return recoveryDecision?.queuedReviewTrigger == candidate.trigger
            && recoveryDecision?.queuedReviewRunKind == candidate.runKind
            && recoveryDecision?.queuedReviewLevel == candidate.reviewLevel
    }

    private static func latestReviewState(
        ctx: AXProjectContext,
        schedule: SupervisorReviewScheduleState
    ) -> (source: String?, trigger: String?, level: String?, atMs: Int64?) {
        let latestReviewNote = SupervisorReviewNoteStore.load(for: ctx).notes.first
        if let latestReviewNote, latestReviewNote.createdAtMs > 0 {
            return (
                source: "review_note_store",
                trigger: latestReviewNote.trigger.rawValue,
                level: latestReviewNote.reviewLevel.rawValue,
                atMs: latestReviewNote.createdAtMs
            )
        }

        var scheduleCandidates: [(trigger: String, atMs: Int64)] = schedule.lastTriggerReviewAtMs
            .compactMap { key, value in
                value > 0 ? (trigger: key, atMs: value) : nil
            }
        if schedule.lastPulseReviewAtMs > 0 {
            scheduleCandidates.append(
                (trigger: SupervisorReviewTrigger.periodicPulse.rawValue, atMs: schedule.lastPulseReviewAtMs)
            )
        }
        if schedule.lastBrainstormReviewAtMs > 0 {
            scheduleCandidates.append(
                (trigger: SupervisorReviewTrigger.noProgressWindow.rawValue, atMs: schedule.lastBrainstormReviewAtMs)
            )
        }
        guard let latestScheduleReview = scheduleCandidates.max(by: { lhs, rhs in
            if lhs.atMs != rhs.atMs {
                return lhs.atMs < rhs.atMs
            }
            return lhs.trigger > rhs.trigger
        }) else {
            return (source: nil, trigger: nil, level: nil, atMs: nil)
        }
        return (
            source: "schedule_state",
            trigger: latestScheduleReview.trigger,
            level: nil,
            atMs: latestScheduleReview.atMs
        )
    }

    private static func summaryLine(
        reviewPolicyMode: String?,
        eventDrivenReviewEnabled: Bool,
        activeCandidate: SupervisorHeartbeatReviewCandidate?,
        activeCandidateQueued: Bool?,
        recoveryDecision: HeartbeatRecoveryDecision?,
        latestReview: (source: String?, trigger: String?, level: String?, atMs: Int64?)
    ) -> String? {
        var parts: [String] = []
        if let activeCandidate {
            parts.append(
                "当前候选 \(activeCandidate.trigger.rawValue) / \(activeCandidate.reviewLevel.rawValue) / \(activeCandidate.runKind.rawValue)"
            )
            if activeCandidateQueued == true {
                parts.append("已进入治理排队")
            }
        } else if let queuedReviewTrigger = recoveryDecision?.queuedReviewTrigger?.rawValue {
            let queuedReviewLevel = recoveryDecision?.queuedReviewLevel?.rawValue ?? "none"
            let queuedReviewRunKind = recoveryDecision?.queuedReviewRunKind?.rawValue ?? "none"
            parts.append("当前已排队 \(queuedReviewTrigger) / \(queuedReviewLevel) / \(queuedReviewRunKind)")
        } else {
            parts.append("当前没有激活中的 review candidate")
        }

        if let reviewPolicyMode = normalizedMeaningfulValue(reviewPolicyMode) {
            parts.append("review_policy=\(reviewPolicyMode)")
        }
        parts.append("event_driven=\(eventDrivenReviewEnabled)")
        if let latestReviewTrigger = normalizedMeaningfulValue(latestReview.trigger) {
            parts.append("latest_review=\(latestReviewTrigger)")
        }

        guard !parts.isEmpty else { return nil }
        return "Review Trigger：" + parts.joined(separator: " · ")
    }

    private static func activeCandidate(
        detailLines: [String]
    ) -> SupervisorHeartbeatReviewCandidate? {
        let available = detailBoolValue(
            "supervisor_review_active_candidate_available",
            from: detailLines
        ) ?? false
        guard available,
              let rawTrigger = detailValue(
                "supervisor_review_active_candidate_trigger",
                from: detailLines
              ),
              let trigger = SupervisorReviewTrigger(rawValue: rawTrigger),
              let rawRunKind = detailValue(
                "supervisor_review_active_candidate_run_kind",
                from: detailLines
              ),
              let runKind = SupervisorReviewRunKind(rawValue: rawRunKind),
              let rawReviewLevel = detailValue(
                "supervisor_review_active_candidate_level",
                from: detailLines
              ),
              let reviewLevel = SupervisorReviewLevel(rawValue: rawReviewLevel) else {
            return nil
        }

        return SupervisorHeartbeatReviewCandidate(
            projectId: "",
            trigger: trigger,
            runKind: runKind,
            reviewLevel: reviewLevel,
            priority: max(
                0,
                detailIntValue(
                    "supervisor_review_active_candidate_priority",
                    from: detailLines
                ) ?? 0
            ),
            policyReason: detailValue(
                "supervisor_review_active_candidate_policy_reason",
                from: detailLines
            ) ?? ""
        )
    }

    private static func queuedReview(
        detailLines: [String]
    ) -> HeartbeatRecoveryDecision? {
        guard let rawTrigger = detailValue("supervisor_review_queued_trigger", from: detailLines),
              let trigger = SupervisorReviewTrigger(rawValue: rawTrigger) else {
            return nil
        }
        let level = detailValue("supervisor_review_queued_level", from: detailLines)
            .flatMap(SupervisorReviewLevel.init(rawValue:))
        let runKind = detailValue("supervisor_review_queued_run_kind", from: detailLines)
            .flatMap(SupervisorReviewRunKind.init(rawValue:))
        return HeartbeatRecoveryDecision(
            action: .queueStrategicReview,
            urgency: .active,
            reasonCode: "",
            summary: "",
            sourceSignals: [],
            anomalyTypes: [],
            blockedLaneReasons: [],
            blockedLaneCount: 0,
            stalledLaneCount: 0,
            failedLaneCount: 0,
            recoveringLaneCount: 0,
            requiresUserAction: false,
            queuedReviewTrigger: trigger,
            queuedReviewLevel: level,
            queuedReviewRunKind: runKind
        )
    }

    private static func orderedUniqueTokens(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in values {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            ordered.append(token)
        }
        return ordered
    }

    private static func detailValue(_ key: String, from detailLines: [String]) -> String? {
        guard let line = detailLines.first(where: { $0.hasPrefix("\(key)=") }) else {
            return nil
        }
        return String(line.dropFirst(key.count + 1))
    }

    private static func detailCSVValues(_ key: String, from detailLines: [String]) -> [String] {
        guard let raw = detailValue(key, from: detailLines),
              let normalized = normalizedOptionalDoctorField(raw),
              normalized != "none" else {
            return []
        }
        return orderedUniqueTokens(
            normalized
                .split(separator: ",")
                .map(String.init)
        )
    }

    private static func detailBoolValue(_ key: String, from detailLines: [String]) -> Bool? {
        guard let raw = normalizedOptionalDoctorField(detailValue(key, from: detailLines)) else {
            return nil
        }
        switch raw.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func detailIntValue(_ key: String, from detailLines: [String]) -> Int? {
        guard let raw = normalizedOptionalDoctorField(detailValue(key, from: detailLines)) else {
            return nil
        }
        return Int(raw)
    }

    private static func detailInt64Value(_ key: String, from detailLines: [String]) -> Int64? {
        guard let raw = normalizedOptionalDoctorField(detailValue(key, from: detailLines)) else {
            return nil
        }
        return Int64(raw)
    }

    private func csv(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: ",")
    }
}

struct XTUnifiedDoctorHeartbeatCadenceDimensionProjection: Codable, Equatable, Sendable {
    var dimension: String
    var configuredSeconds: Int?
    var recommendedSeconds: Int?
    var effectiveSeconds: Int?
    var effectiveReasonCodes: [String]
    var nextDueAtMs: Int64?
    var nextDueReasonCodes: [String]
    var isDue: Bool?

    init(
        dimension: String,
        configuredSeconds: Int? = nil,
        recommendedSeconds: Int? = nil,
        effectiveSeconds: Int? = nil,
        effectiveReasonCodes: [String] = [],
        nextDueAtMs: Int64? = nil,
        nextDueReasonCodes: [String] = [],
        isDue: Bool? = nil
    ) {
        self.dimension = dimension
        self.configuredSeconds = configuredSeconds
        self.recommendedSeconds = recommendedSeconds
        self.effectiveSeconds = effectiveSeconds
        self.effectiveReasonCodes = effectiveReasonCodes
        self.nextDueAtMs = nextDueAtMs
        self.nextDueReasonCodes = nextDueReasonCodes
        self.isDue = isDue
    }

    init(_ explainability: SupervisorCadenceDimensionExplainability) {
        self.init(
            dimension: explainability.dimension.rawValue,
            configuredSeconds: explainability.configuredSeconds,
            recommendedSeconds: explainability.recommendedSeconds,
            effectiveSeconds: explainability.effectiveSeconds,
            effectiveReasonCodes: explainability.effectiveReasonCodes,
            nextDueAtMs: explainability.nextDueAtMs,
            nextDueReasonCodes: explainability.nextDueReasonCodes,
            isDue: explainability.isDue
        )
    }

    var dimensionDisplayText: String {
        HeartbeatGovernanceUserFacingText.cadenceDimensionText(dimension)
    }

    var effectiveReasonDisplayTexts: [String] {
        HeartbeatGovernanceUserFacingText.cadenceReasonTexts(effectiveReasonCodes)
    }

    var nextDueReasonDisplayTexts: [String] {
        HeartbeatGovernanceUserFacingText.cadenceReasonTexts(nextDueReasonCodes)
    }
}

struct XTUnifiedDoctorHeartbeatNextReviewDueProjection: Codable, Equatable, Sendable {
    var kind: String?
    var due: Bool?
    var atMs: Int64?
    var reasonCodes: [String]

    init(
        kind: String? = nil,
        due: Bool? = nil,
        atMs: Int64? = nil,
        reasonCodes: [String] = []
    ) {
        self.kind = normalizedOptionalDoctorField(kind)
        self.due = due
        self.atMs = atMs
        self.reasonCodes = reasonCodes
    }

    var kindDisplayText: String? {
        guard let kind = normalizedOptionalDoctorField(kind) else {
            return nil
        }
        return HeartbeatGovernanceUserFacingText.cadenceDimensionText(kind)
    }

    var reasonDisplayTexts: [String] {
        HeartbeatGovernanceUserFacingText.cadenceReasonTexts(reasonCodes)
    }
}

struct XTUnifiedDoctorHeartbeatRecoveryProjection: Codable, Equatable, Sendable {
    var action: String?
    var urgency: String?
    var reasonCode: String?
    var summary: String
    var sourceSignals: [String]
    var anomalyTypes: [String]
    var blockedLaneReasons: [String]
    var blockedLaneCount: Int?
    var stalledLaneCount: Int?
    var failedLaneCount: Int?
    var recoveringLaneCount: Int?
    var requiresUserAction: Bool?
    var queuedReviewTrigger: String?
    var queuedReviewLevel: String?
    var queuedReviewRunKind: String?

    init(
        action: String? = nil,
        urgency: String? = nil,
        reasonCode: String? = nil,
        summary: String = "",
        sourceSignals: [String] = [],
        anomalyTypes: [String] = [],
        blockedLaneReasons: [String] = [],
        blockedLaneCount: Int? = nil,
        stalledLaneCount: Int? = nil,
        failedLaneCount: Int? = nil,
        recoveringLaneCount: Int? = nil,
        requiresUserAction: Bool? = nil,
        queuedReviewTrigger: String? = nil,
        queuedReviewLevel: String? = nil,
        queuedReviewRunKind: String? = nil
    ) {
        self.action = normalizedOptionalDoctorField(action)
        self.urgency = normalizedOptionalDoctorField(urgency)
        self.reasonCode = normalizedOptionalDoctorField(reasonCode)
        self.summary = summary
        self.sourceSignals = sourceSignals
        self.anomalyTypes = anomalyTypes
        self.blockedLaneReasons = blockedLaneReasons
        self.blockedLaneCount = blockedLaneCount
        self.stalledLaneCount = stalledLaneCount
        self.failedLaneCount = failedLaneCount
        self.recoveringLaneCount = recoveringLaneCount
        self.requiresUserAction = requiresUserAction
        self.queuedReviewTrigger = normalizedOptionalDoctorField(queuedReviewTrigger)
        self.queuedReviewLevel = normalizedOptionalDoctorField(queuedReviewLevel)
        self.queuedReviewRunKind = normalizedOptionalDoctorField(queuedReviewRunKind)
    }

    init(_ decision: HeartbeatRecoveryDecision) {
        self.init(
            action: decision.action.rawValue,
            urgency: decision.urgency.rawValue,
            reasonCode: decision.reasonCode,
            summary: decision.summary,
            sourceSignals: decision.sourceSignals,
            anomalyTypes: decision.anomalyTypes.map(\.rawValue),
            blockedLaneReasons: decision.blockedLaneReasons.map(\.rawValue),
            blockedLaneCount: decision.blockedLaneCount,
            stalledLaneCount: decision.stalledLaneCount,
            failedLaneCount: decision.failedLaneCount,
            recoveringLaneCount: decision.recoveringLaneCount,
            requiresUserAction: decision.requiresUserAction,
            queuedReviewTrigger: decision.queuedReviewTrigger?.rawValue,
            queuedReviewLevel: decision.queuedReviewLevel?.rawValue,
            queuedReviewRunKind: decision.queuedReviewRunKind?.rawValue
        )
    }

    var doctorExplainabilityText: String {
        HeartbeatRecoveryUserFacingText.doctorExplainabilityText(
            action: normalizedOptionalDoctorField(action).flatMap(HeartbeatRecoveryAction.init(rawValue:)),
            urgency: normalizedOptionalDoctorField(urgency).flatMap(HeartbeatRecoveryUrgency.init(rawValue:)),
            reasonCode: reasonCode,
            sourceSignals: sourceSignals,
            blockedLaneReasons: blockedLaneReasons.compactMap(LaneBlockedReason.init(rawValue:)),
            failedLaneCount: max(0, failedLaneCount ?? 0),
            requiresUserAction: requiresUserAction ?? false,
            queuedReviewLevel: normalizedOptionalDoctorField(queuedReviewLevel).flatMap(SupervisorReviewLevel.init(rawValue:)),
            trigger: normalizedOptionalDoctorField(queuedReviewTrigger).flatMap(SupervisorReviewTrigger.init(rawValue:)),
            runKind: normalizedOptionalDoctorField(queuedReviewRunKind).flatMap(SupervisorReviewRunKind.init(rawValue:))
        )
    }

    var systemNextStepDisplayText: String {
        HeartbeatRecoveryUserFacingText.trimTerminalPunctuation(
            HeartbeatRecoveryUserFacingText.systemNextStepText(
                action: normalizedOptionalDoctorField(action).flatMap(HeartbeatRecoveryAction.init(rawValue:)),
                failedLaneCount: max(0, failedLaneCount ?? 0),
                blockedLaneReasons: blockedLaneReasons.compactMap(LaneBlockedReason.init(rawValue:)),
                queuedReviewLevel: normalizedOptionalDoctorField(queuedReviewLevel).flatMap(SupervisorReviewLevel.init(rawValue:)),
                trigger: normalizedOptionalDoctorField(queuedReviewTrigger).flatMap(SupervisorReviewTrigger.init(rawValue:)),
                runKind: normalizedOptionalDoctorField(queuedReviewRunKind).flatMap(SupervisorReviewRunKind.init(rawValue:))
            )
        )
    }

    var actionDisplayText: String? {
        normalizedOptionalDoctorField(action)
            .flatMap(HeartbeatRecoveryAction.init(rawValue:))
            .flatMap(HeartbeatRecoveryUserFacingText.actionText)
    }

    var urgencyDisplayText: String? {
        normalizedOptionalDoctorField(urgency)
            .flatMap(HeartbeatRecoveryUrgency.init(rawValue:))
            .flatMap(HeartbeatRecoveryUserFacingText.urgencyText)
    }

    var reasonDisplayText: String? {
        HeartbeatRecoveryUserFacingText.reasonText(reasonCode)
    }

    var sourceSignalDisplayTexts: [String] {
        HeartbeatRecoveryUserFacingText.sourceSignalTexts(sourceSignals)
    }

    var anomalyTypeDisplayTexts: [String] {
        HeartbeatRecoveryUserFacingText.anomalyTypeTexts(anomalyTypes)
    }

    var blockedLaneReasonDisplayTexts: [String] {
        HeartbeatRecoveryUserFacingText.blockedReasonTexts(blockedLaneReasons)
    }

    var queuedReviewTriggerDisplayText: String? {
        normalizedOptionalDoctorField(queuedReviewTrigger)
            .flatMap(SupervisorReviewTrigger.init(rawValue:))
            .flatMap(HeartbeatRecoveryUserFacingText.queuedReviewTriggerText)
    }

    var queuedReviewLevelDisplayText: String? {
        normalizedOptionalDoctorField(queuedReviewLevel)
            .flatMap(SupervisorReviewLevel.init(rawValue:))
            .map(HeartbeatRecoveryUserFacingText.queuedReviewLevelText)
    }

    var queuedReviewRunKindDisplayText: String? {
        normalizedOptionalDoctorField(queuedReviewRunKind)
            .flatMap(SupervisorReviewRunKind.init(rawValue:))
            .flatMap(HeartbeatRecoveryUserFacingText.queuedReviewRunKindText)
    }
}

struct XTUnifiedDoctorHeartbeatGovernanceProjection: Codable, Equatable, Sendable {
    var projectId: String
    var projectName: String
    var statusDigest: String
    var currentStateSummary: String
    var nextStepSummary: String
    var blockerSummary: String
    var lastHeartbeatAtMs: Int64
    var latestQualityBand: String?
    var latestQualityScore: Int?
    var weakReasons: [String]
    var openAnomalyTypes: [String]
    var projectPhase: String?
    var executionStatus: String?
    var riskTier: String?
    var digestVisibility: String
    var digestReasonCodes: [String]
    var digestWhatChangedText: String
    var digestWhyImportantText: String
    var digestSystemNextStepText: String
    var progressHeartbeat: XTUnifiedDoctorHeartbeatCadenceDimensionProjection
    var reviewPulse: XTUnifiedDoctorHeartbeatCadenceDimensionProjection
    var brainstormReview: XTUnifiedDoctorHeartbeatCadenceDimensionProjection
    var nextReviewDue: XTUnifiedDoctorHeartbeatNextReviewDueProjection
    var recoveryDecision: XTUnifiedDoctorHeartbeatRecoveryProjection?
    var projectMemoryReady: Bool? = nil
    var projectMemoryStatusLine: String? = nil
    var projectMemoryIssueCodes: [String] = []
    var projectMemoryTopIssueSummary: String? = nil

    private enum CodingKeys: String, CodingKey {
        case projectId
        case projectName
        case statusDigest
        case currentStateSummary
        case nextStepSummary
        case blockerSummary
        case lastHeartbeatAtMs
        case latestQualityBand
        case latestQualityScore
        case weakReasons
        case openAnomalyTypes
        case projectPhase
        case executionStatus
        case riskTier
        case digestVisibility
        case digestReasonCodes
        case digestWhatChangedText
        case digestWhyImportantText
        case digestSystemNextStepText
        case progressHeartbeat
        case reviewPulse
        case brainstormReview
        case nextReviewDue
        case recoveryDecision
        case projectMemoryReady
        case projectMemoryStatusLine
        case projectMemoryIssueCodes
        case projectMemoryTopIssueSummary
    }

    init(
        projectId: String,
        projectName: String,
        statusDigest: String,
        currentStateSummary: String,
        nextStepSummary: String,
        blockerSummary: String,
        lastHeartbeatAtMs: Int64,
        latestQualityBand: String?,
        latestQualityScore: Int?,
        weakReasons: [String],
        openAnomalyTypes: [String],
        projectPhase: String?,
        executionStatus: String?,
        riskTier: String?,
        digestVisibility: String,
        digestReasonCodes: [String],
        digestWhatChangedText: String,
        digestWhyImportantText: String,
        digestSystemNextStepText: String,
        progressHeartbeat: XTUnifiedDoctorHeartbeatCadenceDimensionProjection,
        reviewPulse: XTUnifiedDoctorHeartbeatCadenceDimensionProjection,
        brainstormReview: XTUnifiedDoctorHeartbeatCadenceDimensionProjection,
        nextReviewDue: XTUnifiedDoctorHeartbeatNextReviewDueProjection,
        recoveryDecision: XTUnifiedDoctorHeartbeatRecoveryProjection? = nil,
        projectMemoryReady: Bool? = nil,
        projectMemoryStatusLine: String? = nil,
        projectMemoryIssueCodes: [String] = [],
        projectMemoryTopIssueSummary: String? = nil
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.statusDigest = statusDigest
        self.currentStateSummary = currentStateSummary
        self.nextStepSummary = nextStepSummary
        self.blockerSummary = blockerSummary
        self.lastHeartbeatAtMs = lastHeartbeatAtMs
        self.latestQualityBand = latestQualityBand
        self.latestQualityScore = latestQualityScore
        self.weakReasons = weakReasons
        self.openAnomalyTypes = openAnomalyTypes
        self.projectPhase = projectPhase
        self.executionStatus = executionStatus
        self.riskTier = riskTier
        self.digestVisibility = digestVisibility
        self.digestReasonCodes = digestReasonCodes
        self.digestWhatChangedText = digestWhatChangedText
        self.digestWhyImportantText = digestWhyImportantText
        self.digestSystemNextStepText = digestSystemNextStepText
        self.progressHeartbeat = progressHeartbeat
        self.reviewPulse = reviewPulse
        self.brainstormReview = brainstormReview
        self.nextReviewDue = nextReviewDue
        self.recoveryDecision = recoveryDecision
        self.projectMemoryReady = projectMemoryReady
        self.projectMemoryStatusLine = projectMemoryStatusLine
        self.projectMemoryIssueCodes = projectMemoryIssueCodes
        self.projectMemoryTopIssueSummary = projectMemoryTopIssueSummary
    }

    init(
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot,
        projectMemoryReadiness: XTProjectMemoryAssemblyReadiness? = nil
    ) {
        let resolvedProjectMemoryReadiness = projectMemoryReadiness ?? snapshot.projectMemoryReadiness
        let projectMemoryNeedsAttention = resolvedProjectMemoryReadiness?.ready == false
        let projectMemoryStatusLine = Self.combinedProjectMemoryStatusLine(
            readinessStatusLine: resolvedProjectMemoryReadiness?.statusLine,
            contextStatusLine: Self.projectMemoryContextStatusLine(from: snapshot.projectMemoryContext)
        )
        self.projectId = snapshot.projectId
        self.projectName = snapshot.projectName
        self.statusDigest = snapshot.statusDigest
        self.currentStateSummary = snapshot.currentStateSummary
        self.nextStepSummary = snapshot.nextStepSummary
        self.blockerSummary = snapshot.blockerSummary
        self.lastHeartbeatAtMs = snapshot.lastHeartbeatAtMs
        self.latestQualityBand = snapshot.latestQualityBand?.rawValue
        self.latestQualityScore = snapshot.latestQualityScore
        self.weakReasons = Self.mergedProjectMemoryAttention(
            snapshot.weakReasons,
            needsAttention: projectMemoryNeedsAttention
        )
        self.openAnomalyTypes = snapshot.openAnomalyTypes.map(\.rawValue)
        self.projectPhase = snapshot.projectPhase?.rawValue
        self.executionStatus = snapshot.executionStatus?.rawValue
        self.riskTier = snapshot.riskTier?.rawValue
        self.digestVisibility = snapshot.digestExplainability.visibility.rawValue
        self.digestReasonCodes = Self.mergedProjectMemoryAttention(
            snapshot.digestExplainability.reasonCodes,
            needsAttention: projectMemoryNeedsAttention
        )
        self.digestWhatChangedText = snapshot.digestExplainability.whatChangedText
        self.digestWhyImportantText = snapshot.digestExplainability.whyImportantText
        self.digestSystemNextStepText = snapshot.digestExplainability.systemNextStepText
        self.progressHeartbeat = XTUnifiedDoctorHeartbeatCadenceDimensionProjection(snapshot.cadence.progressHeartbeat)
        self.reviewPulse = XTUnifiedDoctorHeartbeatCadenceDimensionProjection(snapshot.cadence.reviewPulse)
        self.brainstormReview = XTUnifiedDoctorHeartbeatCadenceDimensionProjection(snapshot.cadence.brainstormReview)
        self.nextReviewDue = Self.nextReviewDue(from: snapshot.cadence)
        self.recoveryDecision = snapshot.recoveryDecision.map(XTUnifiedDoctorHeartbeatRecoveryProjection.init)
        self.projectMemoryReady = resolvedProjectMemoryReadiness?.ready
        self.projectMemoryStatusLine = projectMemoryStatusLine
        self.projectMemoryIssueCodes = resolvedProjectMemoryReadiness?.issueCodes ?? []
        self.projectMemoryTopIssueSummary = resolvedProjectMemoryReadiness?.topIssue?.summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectId = try container.decode(String.self, forKey: .projectId)
        self.projectName = try container.decode(String.self, forKey: .projectName)
        self.statusDigest = try container.decode(String.self, forKey: .statusDigest)
        self.currentStateSummary = try container.decode(String.self, forKey: .currentStateSummary)
        self.nextStepSummary = try container.decode(String.self, forKey: .nextStepSummary)
        self.blockerSummary = try container.decode(String.self, forKey: .blockerSummary)
        self.lastHeartbeatAtMs = try container.decode(Int64.self, forKey: .lastHeartbeatAtMs)
        self.latestQualityBand = try container.decodeIfPresent(String.self, forKey: .latestQualityBand)
        self.latestQualityScore = try container.decodeIfPresent(Int.self, forKey: .latestQualityScore)
        self.weakReasons = try container.decode([String].self, forKey: .weakReasons)
        self.openAnomalyTypes = try container.decode([String].self, forKey: .openAnomalyTypes)
        self.projectPhase = try container.decodeIfPresent(String.self, forKey: .projectPhase)
        self.executionStatus = try container.decodeIfPresent(String.self, forKey: .executionStatus)
        self.riskTier = try container.decodeIfPresent(String.self, forKey: .riskTier)
        self.digestVisibility = try container.decode(String.self, forKey: .digestVisibility)
        self.digestReasonCodes = try container.decode([String].self, forKey: .digestReasonCodes)
        self.digestWhatChangedText = try container.decode(String.self, forKey: .digestWhatChangedText)
        self.digestWhyImportantText = try container.decode(String.self, forKey: .digestWhyImportantText)
        self.digestSystemNextStepText = try container.decode(String.self, forKey: .digestSystemNextStepText)
        self.progressHeartbeat = try container.decode(
            XTUnifiedDoctorHeartbeatCadenceDimensionProjection.self,
            forKey: .progressHeartbeat
        )
        self.reviewPulse = try container.decode(
            XTUnifiedDoctorHeartbeatCadenceDimensionProjection.self,
            forKey: .reviewPulse
        )
        self.brainstormReview = try container.decode(
            XTUnifiedDoctorHeartbeatCadenceDimensionProjection.self,
            forKey: .brainstormReview
        )
        self.nextReviewDue = try container.decode(
            XTUnifiedDoctorHeartbeatNextReviewDueProjection.self,
            forKey: .nextReviewDue
        )
        self.recoveryDecision = try container.decodeIfPresent(
            XTUnifiedDoctorHeartbeatRecoveryProjection.self,
            forKey: .recoveryDecision
        )
        self.projectMemoryReady = try container.decodeIfPresent(Bool.self, forKey: .projectMemoryReady)
        self.projectMemoryStatusLine = try container.decodeIfPresent(String.self, forKey: .projectMemoryStatusLine)
        self.projectMemoryIssueCodes = try container.decodeIfPresent(
            [String].self,
            forKey: .projectMemoryIssueCodes
        ) ?? []
        self.projectMemoryTopIssueSummary = try container.decodeIfPresent(
            String.self,
            forKey: .projectMemoryTopIssueSummary
        )
    }

    var latestQualityBandDisplayText: String? {
        guard let latestQualityBand = normalizedOptionalDoctorField(latestQualityBand) else {
            return nil
        }
        return HeartbeatGovernanceUserFacingText.qualityBandText(latestQualityBand)
    }

    var weakReasonDisplayTexts: [String] {
        HeartbeatGovernanceUserFacingText.weakReasonTexts(weakReasons)
    }

    var openAnomalyDisplayTexts: [String] {
        HeartbeatGovernanceUserFacingText.anomalyTypeTexts(openAnomalyTypes)
    }

    var projectPhaseDisplayText: String? {
        guard let projectPhase = normalizedOptionalDoctorField(projectPhase) else {
            return nil
        }
        return HeartbeatGovernanceUserFacingText.projectPhaseText(projectPhase)
    }

    var executionStatusDisplayText: String? {
        guard let executionStatus = normalizedOptionalDoctorField(executionStatus) else {
            return nil
        }
        return HeartbeatGovernanceUserFacingText.executionStatusText(executionStatus)
    }

    var riskTierDisplayText: String? {
        guard let riskTier = normalizedOptionalDoctorField(riskTier) else {
            return nil
        }
        return HeartbeatGovernanceUserFacingText.riskTierText(riskTier)
    }

    var digestVisibilityDisplayText: String? {
        guard let digestVisibility = normalizedOptionalDoctorField(digestVisibility) else {
            return nil
        }
        return HeartbeatGovernanceUserFacingText.digestVisibilityText(digestVisibility)
    }

    var digestReasonDisplayTexts: [String] {
        HeartbeatGovernanceUserFacingText.digestReasonTexts(digestReasonCodes)
    }

    static func from(detailLines: [String]) -> XTUnifiedDoctorHeartbeatGovernanceProjection? {
        guard detailLines.contains(where: { $0.hasPrefix("heartbeat_") }) else {
            return nil
        }

        let projectRef = parseProjectRef(detailLines)
        let effectiveSeconds = parseCadenceSeconds(
            detailLines,
            prefix: "heartbeat_effective_cadence "
        )
        let effectiveReasons = parseCadenceReasonCodes(
            detailLines,
            prefix: "heartbeat_effective_cadence_reasons "
        )
        let nextReviewDue = parseNextReviewDue(detailLines)
        let recoveryDecision = parseHeartbeatRecovery(detailLines)
        let projectMemoryReady = boolValue(rawValue(detailLines, prefix: "heartbeat_project_memory_ready="))
        let projectMemoryStatusLine = combinedProjectMemoryStatusLine(
            readinessStatusLine: rawValue(detailLines, prefix: "heartbeat_project_memory_status_line="),
            contextStatusLine: projectMemoryContextStatusLine(from: detailLines)
        )
        let projectMemoryIssueCodes = csvTokens(rawValue(detailLines, prefix: "heartbeat_project_memory_issue_codes="))
        let projectMemoryTopIssueSummary = rawValue(detailLines, prefix: "heartbeat_project_memory_top_issue_summary=")
        let projectMemoryNeedsAttention = projectMemoryReady == false || !projectMemoryIssueCodes.isEmpty

        var progressHeartbeat = XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
            dimension: SupervisorCadenceDimension.progressHeartbeat.rawValue,
            effectiveSeconds: effectiveSeconds[SupervisorCadenceDimension.progressHeartbeat.rawValue],
            effectiveReasonCodes: effectiveReasons[SupervisorCadenceDimension.progressHeartbeat.rawValue] ?? []
        )
        var reviewPulse = XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
            dimension: SupervisorCadenceDimension.reviewPulse.rawValue,
            effectiveSeconds: effectiveSeconds[SupervisorCadenceDimension.reviewPulse.rawValue],
            effectiveReasonCodes: effectiveReasons[SupervisorCadenceDimension.reviewPulse.rawValue] ?? []
        )
        var brainstormReview = XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
            dimension: SupervisorCadenceDimension.brainstormReview.rawValue,
            effectiveSeconds: effectiveSeconds[SupervisorCadenceDimension.brainstormReview.rawValue],
            effectiveReasonCodes: effectiveReasons[SupervisorCadenceDimension.brainstormReview.rawValue] ?? []
        )

        switch nextReviewDue.kind {
        case SupervisorCadenceDimension.reviewPulse.rawValue:
            reviewPulse.nextDueAtMs = nextReviewDue.atMs
            reviewPulse.nextDueReasonCodes = nextReviewDue.reasonCodes
            reviewPulse.isDue = nextReviewDue.due
        case SupervisorCadenceDimension.brainstormReview.rawValue:
            brainstormReview.nextDueAtMs = nextReviewDue.atMs
            brainstormReview.nextDueReasonCodes = nextReviewDue.reasonCodes
            brainstormReview.isDue = nextReviewDue.due
        case SupervisorCadenceDimension.progressHeartbeat.rawValue:
            progressHeartbeat.nextDueAtMs = nextReviewDue.atMs
            progressHeartbeat.nextDueReasonCodes = nextReviewDue.reasonCodes
            progressHeartbeat.isDue = nextReviewDue.due
        default:
            break
        }

        return XTUnifiedDoctorHeartbeatGovernanceProjection(
            projectId: projectRef.id,
            projectName: projectRef.name,
            statusDigest: rawValue(detailLines, prefix: "heartbeat_truth status_digest=") ?? "",
            currentStateSummary: rawValue(detailLines, prefix: "heartbeat_current_state=") ?? "",
            nextStepSummary: rawValue(detailLines, prefix: "heartbeat_next_step=") ?? "",
            blockerSummary: rawValue(detailLines, prefix: "heartbeat_blocker=") ?? "",
            lastHeartbeatAtMs: int64Value(detailLines, prefix: "heartbeat_last_heartbeat_at_ms=") ?? 0,
            latestQualityBand: meaningfulToken(rawValue(detailLines, prefix: "heartbeat_quality_band=")),
            latestQualityScore: intValue(detailLines, prefix: "heartbeat_quality_score="),
            weakReasons: mergedProjectMemoryAttention(
                csvTokens(rawValue(detailLines, prefix: "heartbeat_quality_weak_reasons=")),
                needsAttention: projectMemoryNeedsAttention
            ),
            openAnomalyTypes: csvTokens(rawValue(detailLines, prefix: "heartbeat_open_anomalies=")),
            projectPhase: meaningfulToken(rawValue(detailLines, prefix: "heartbeat_project_phase=")),
            executionStatus: meaningfulToken(rawValue(detailLines, prefix: "heartbeat_execution_status=")),
            riskTier: meaningfulToken(rawValue(detailLines, prefix: "heartbeat_risk_tier=")),
            digestVisibility: meaningfulToken(rawValue(detailLines, prefix: "heartbeat_digest_visibility=")) ?? XTHeartbeatDigestVisibilityDecision.suppressed.rawValue,
            digestReasonCodes: mergedProjectMemoryAttention(
                csvTokens(rawValue(detailLines, prefix: "heartbeat_digest_reason_codes=")),
                needsAttention: projectMemoryNeedsAttention
            ),
            digestWhatChangedText: rawValue(detailLines, prefix: "heartbeat_digest_what_changed=") ?? "",
            digestWhyImportantText: rawValue(detailLines, prefix: "heartbeat_digest_why_important=") ?? "",
            digestSystemNextStepText: rawValue(detailLines, prefix: "heartbeat_digest_system_next_step=") ?? "",
            progressHeartbeat: progressHeartbeat,
            reviewPulse: reviewPulse,
            brainstormReview: brainstormReview,
            nextReviewDue: nextReviewDue,
            recoveryDecision: recoveryDecision,
            projectMemoryReady: projectMemoryReady,
            projectMemoryStatusLine: projectMemoryStatusLine,
            projectMemoryIssueCodes: projectMemoryIssueCodes,
            projectMemoryTopIssueSummary: projectMemoryTopIssueSummary
        )
    }

    private static func nextReviewDue(
        from cadence: SupervisorCadenceExplainability
    ) -> XTUnifiedDoctorHeartbeatNextReviewDueProjection {
        let candidates = [
            cadence.reviewPulse,
            cadence.brainstormReview
        ].filter { $0.effectiveSeconds > 0 }

        guard let next = candidates.min(by: { compareDue(lhs: $0, rhs: $1) }) else {
            return XTUnifiedDoctorHeartbeatNextReviewDueProjection(
                kind: "none",
                due: false,
                atMs: 0,
                reasonCodes: ["cadence_disabled"]
            )
        }

        return XTUnifiedDoctorHeartbeatNextReviewDueProjection(
            kind: next.dimension.rawValue,
            due: next.isDue,
            atMs: next.nextDueAtMs,
            reasonCodes: next.nextDueReasonCodes
        )
    }

    private static func compareDue(
        lhs: SupervisorCadenceDimensionExplainability,
        rhs: SupervisorCadenceDimensionExplainability
    ) -> Bool {
        if lhs.isDue != rhs.isDue {
            return lhs.isDue && !rhs.isDue
        }
        if lhs.nextDueAtMs != rhs.nextDueAtMs {
            return lhs.nextDueAtMs < rhs.nextDueAtMs
        }
        return lhs.dimension.rawValue < rhs.dimension.rawValue
    }

    private static func parseProjectRef(_ detailLines: [String]) -> (name: String, id: String) {
        guard let raw = rawValue(detailLines, prefix: "heartbeat_project=") else {
            return ("", "")
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"),
              let openParen = trimmed.lastIndex(of: "(") else {
            return (trimmed, "")
        }

        let name = String(trimmed[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
        let idStart = trimmed.index(after: openParen)
        let idEnd = trimmed.index(before: trimmed.endIndex)
        let id = String(trimmed[idStart..<idEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, id)
    }

    private static func parseCadenceSeconds(
        _ detailLines: [String],
        prefix: String
    ) -> [String: Int] {
        guard let line = detailLines.first(where: { $0.hasPrefix(prefix) }) else {
            return [:]
        }
        let fields = tokenFields(String(line.dropFirst(prefix.count)))
        var values: [String: Int] = [:]
        for dimension in SupervisorCadenceDimension.allCases {
            let key = cadenceFieldKey(for: dimension)
            guard let raw = fields[key] else { continue }
            values[dimension.rawValue] = Int(raw.replacingOccurrences(of: "s", with: ""))
        }
        return values
    }

    private static func parseCadenceReasonCodes(
        _ detailLines: [String],
        prefix: String
    ) -> [String: [String]] {
        guard let line = detailLines.first(where: { $0.hasPrefix(prefix) }) else {
            return [:]
        }
        let fields = tokenFields(String(line.dropFirst(prefix.count)))
        var values: [String: [String]] = [:]
        for dimension in SupervisorCadenceDimension.allCases {
            let key = cadenceFieldKey(for: dimension)
            values[dimension.rawValue] = csvTokens(fields[key])
        }
        return values
    }

    private static func parseNextReviewDue(
        _ detailLines: [String]
    ) -> XTUnifiedDoctorHeartbeatNextReviewDueProjection {
        let prefix = "heartbeat_next_review_due "
        guard let line = detailLines.first(where: { $0.hasPrefix(prefix) }) else {
            return XTUnifiedDoctorHeartbeatNextReviewDueProjection()
        }
        let fields = tokenFields(String(line.dropFirst(prefix.count)))
        return XTUnifiedDoctorHeartbeatNextReviewDueProjection(
            kind: fields["kind"],
            due: boolValue(fields["due"]),
            atMs: int64Value(fields["at_ms"]),
            reasonCodes: csvTokens(fields["reasons"])
        )
    }

    private static func parseHeartbeatRecovery(
        _ detailLines: [String]
    ) -> XTUnifiedDoctorHeartbeatRecoveryProjection? {
        let prefix = "heartbeat_recovery "
        guard let line = detailLines.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let fields = tokenFields(String(line.dropFirst(prefix.count)))
        let signalFields = tokenFields(
            rawValue(detailLines, prefix: "heartbeat_recovery_signals ") ?? ""
        )
        let reviewFields = tokenFields(
            rawValue(detailLines, prefix: "heartbeat_recovery_review ") ?? ""
        )
        return XTUnifiedDoctorHeartbeatRecoveryProjection(
            action: fields["action"],
            urgency: fields["urgency"],
            reasonCode: fields["reason"],
            summary: rawValue(detailLines, prefix: "heartbeat_recovery_summary=") ?? "",
            sourceSignals: csvTokens(signalFields["sources"]),
            anomalyTypes: csvTokens(signalFields["anomalies"]),
            blockedLaneReasons: csvTokens(signalFields["blocked_reasons"]),
            blockedLaneCount: intValue(fields["blocked_lanes"]),
            stalledLaneCount: intValue(fields["stalled_lanes"]),
            failedLaneCount: intValue(fields["failed_lanes"]),
            recoveringLaneCount: intValue(fields["recovering_lanes"]),
            requiresUserAction: boolValue(fields["requires_user"]),
            queuedReviewTrigger: reviewFields["trigger"],
            queuedReviewLevel: reviewFields["level"],
            queuedReviewRunKind: reviewFields["run_kind"]
        )
    }

    private static func cadenceFieldKey(for dimension: SupervisorCadenceDimension) -> String {
        switch dimension {
        case .progressHeartbeat:
            return "progress"
        case .reviewPulse:
            return "pulse"
        case .brainstormReview:
            return "brainstorm"
        }
    }

    private static func rawValue(_ detailLines: [String], prefix: String) -> String? {
        guard let line = detailLines.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return String(line.dropFirst(prefix.count))
    }

    private static func intValue(_ detailLines: [String], prefix: String) -> Int? {
        intValue(rawValue(detailLines, prefix: prefix))
    }

    private static func intValue(_ raw: String?) -> Int? {
        guard let token = meaningfulToken(raw) else { return nil }
        return Int(token)
    }

    private static func int64Value(_ detailLines: [String], prefix: String) -> Int64? {
        int64Value(rawValue(detailLines, prefix: prefix))
    }

    private static func int64Value(_ raw: String?) -> Int64? {
        guard let token = meaningfulToken(raw) else { return nil }
        return Int64(token)
    }

    private static func boolValue(_ raw: String?) -> Bool? {
        switch meaningfulToken(raw)?.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func tokenFields(_ raw: String) -> [String: String] {
        var fields: [String: String] = [:]
        for token in raw.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        return fields
    }

    private static func csvTokens(_ raw: String?) -> [String] {
        guard let token = meaningfulToken(raw) else { return [] }
        return token
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func meaningfulToken(_ raw: String?) -> String? {
        guard let value = normalizedOptionalDoctorField(raw) else { return nil }
        switch value.lowercased() {
        case "none", "(none)", "unknown", "n/a":
            return nil
        default:
            return value
        }
    }

    private static func mergedProjectMemoryAttention(
        _ values: [String],
        needsAttention: Bool
    ) -> [String] {
        guard needsAttention else { return orderedUniqueTokens(values) }
        return orderedUniqueTokens(values + ["project_memory_attention"])
    }

    private static func combinedProjectMemoryStatusLine(
        readinessStatusLine: String?,
        contextStatusLine: String?
    ) -> String? {
        let parts = orderedUniqueTokens(
            [readinessStatusLine, contextStatusLine].compactMap(normalizedOptionalDoctorField)
        )
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "；")
    }

    private static func projectMemoryContextStatusLine(
        from context: XTHeartbeatProjectMemoryContextSnapshot?
    ) -> String? {
        guard let context else { return nil }

        var parts: [String] = []
        switch meaningfulToken(context.diagnosticsSource) {
        case "latest_coder_usage":
            parts.append("Project AI 最近一轮 memory truth 来自 latest coder usage")
        case "config_only":
            parts.append("Project AI 当前还是 config-only baseline")
        case let source?:
            parts.append("Project AI 最近一轮 memory truth 来自 \(source)")
        case nil:
            break
        }

        if let effectiveDepth = context.effectiveResolution.flatMap({ meaningfulToken($0.effectiveDepth) }) {
            parts.append("effective depth=\(effectiveDepth)")
        }

        if context.heartbeatDigestWorkingSetPresent {
            parts.append("heartbeat digest 已在 Project AI working set 中")
        } else if let visibility = meaningfulToken(context.heartbeatDigestVisibility) {
            parts.append("heartbeat digest 尚未进入 Project AI working set（visibility=\(visibility)）")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "；")
    }

    private static func projectMemoryContextStatusLine(
        from detailLines: [String]
    ) -> String? {
        let source = rawValue(detailLines, prefix: "heartbeat_project_memory_source=")
        let actualResolution = rawValue(
            detailLines,
            prefix: "heartbeat_project_memory_actual_resolution "
        )
        let policyResolution = rawValue(
            detailLines,
            prefix: "heartbeat_project_memory_policy_resolution "
        )
        let resolutionFields = tokenFields(actualResolution ?? policyResolution ?? "")
        let effectiveDepth = resolutionFields["effective_depth"]
        let digestPresent = boolValue(
            rawValue(detailLines, prefix: "heartbeat_project_memory_heartbeat_digest_present=")
        )
        let digestVisibility = rawValue(
            detailLines,
            prefix: "heartbeat_project_memory_heartbeat_digest_visibility="
        )

        var parts: [String] = []
        switch meaningfulToken(source) {
        case "latest_coder_usage":
            parts.append("Project AI 最近一轮 memory truth 来自 latest coder usage")
        case "config_only":
            parts.append("Project AI 当前还是 config-only baseline")
        case let resolvedSource?:
            parts.append("Project AI 最近一轮 memory truth 来自 \(resolvedSource)")
        case nil:
            break
        }

        if let effectiveDepth = meaningfulToken(effectiveDepth) {
            parts.append("effective depth=\(effectiveDepth)")
        }

        if digestPresent == true {
            parts.append("heartbeat digest 已在 Project AI working set 中")
        } else if let visibility = meaningfulToken(digestVisibility) {
            parts.append("heartbeat digest 尚未进入 Project AI working set（visibility=\(visibility)）")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "；")
    }

    private static func orderedUniqueTokens(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }
}

final class XTUnifiedDoctorSection: Identifiable, Codable, Equatable, @unchecked Sendable {
    var kind: XTUnifiedDoctorSectionKind
    var state: XTUISurfaceState
    var headline: String
    var summary: String
    var nextStep: String
    var repairEntry: UITroubleshootDestination
    var detailLines: [String]
    var projectContextPresentation: AXProjectContextAssemblyPresentation? = nil
    var projectGovernanceRuntimeReadinessProjection: AXProjectGovernanceRuntimeReadinessSnapshot? = nil
    var projectMemoryPolicyProjection: XTProjectMemoryPolicySnapshot? = nil
    var projectMemoryReadinessProjection: XTProjectMemoryAssemblyReadiness? = nil
    var projectMemoryAssemblyResolutionProjection: XTMemoryAssemblyResolution? = nil
    var heartbeatGovernanceProjection: XTUnifiedDoctorHeartbeatGovernanceProjection? = nil
    var supervisorMemoryPolicyProjection: XTSupervisorMemoryPolicySnapshot? = nil
    var supervisorMemoryAssemblyResolutionProjection: XTMemoryAssemblyResolution? = nil
    var supervisorReviewTriggerProjection: XTUnifiedDoctorSupervisorReviewTriggerProjection? = nil
    var supervisorGuidanceContinuityProjection: XTUnifiedDoctorSupervisorGuidanceContinuityProjection? = nil
    var supervisorSafePointTimelineProjection: XTUnifiedDoctorSupervisorSafePointTimelineProjection? = nil
    var projectRemoteSnapshotCacheProjection: XTUnifiedDoctorRemoteSnapshotCacheProjection? = nil
    var supervisorRemoteSnapshotCacheProjection: XTUnifiedDoctorRemoteSnapshotCacheProjection? = nil
    var hubMemoryPromptProjection: HubMemoryPromptProjectionSnapshot? = nil
    var memoryRouteTruthProjection: AXModelRouteTruthProjection? = nil
    var durableCandidateMirrorProjection: XTUnifiedDoctorDurableCandidateMirrorProjection? = nil
    var localStoreWriteProjection: XTUnifiedDoctorLocalStoreWriteProjection? = nil
    var skillDoctorTruthProjection: XTUnifiedDoctorSkillDoctorTruthProjection? = nil

    var id: String { kind.rawValue }

    static func == (lhs: XTUnifiedDoctorSection, rhs: XTUnifiedDoctorSection) -> Bool {
        lhs.kind == rhs.kind
            && lhs.state == rhs.state
            && lhs.headline == rhs.headline
            && lhs.summary == rhs.summary
            && lhs.nextStep == rhs.nextStep
            && lhs.repairEntry == rhs.repairEntry
            && lhs.detailLines == rhs.detailLines
            && lhs.projectContextPresentation == rhs.projectContextPresentation
            && lhs.projectGovernanceRuntimeReadinessProjection == rhs.projectGovernanceRuntimeReadinessProjection
            && lhs.projectMemoryPolicyProjection == rhs.projectMemoryPolicyProjection
            && lhs.projectMemoryReadinessProjection == rhs.projectMemoryReadinessProjection
            && lhs.projectMemoryAssemblyResolutionProjection == rhs.projectMemoryAssemblyResolutionProjection
            && lhs.heartbeatGovernanceProjection == rhs.heartbeatGovernanceProjection
            && lhs.supervisorMemoryPolicyProjection == rhs.supervisorMemoryPolicyProjection
            && lhs.supervisorMemoryAssemblyResolutionProjection == rhs.supervisorMemoryAssemblyResolutionProjection
            && lhs.supervisorReviewTriggerProjection == rhs.supervisorReviewTriggerProjection
            && lhs.supervisorGuidanceContinuityProjection == rhs.supervisorGuidanceContinuityProjection
            && lhs.supervisorSafePointTimelineProjection == rhs.supervisorSafePointTimelineProjection
            && lhs.projectRemoteSnapshotCacheProjection == rhs.projectRemoteSnapshotCacheProjection
            && lhs.supervisorRemoteSnapshotCacheProjection == rhs.supervisorRemoteSnapshotCacheProjection
            && lhs.hubMemoryPromptProjection == rhs.hubMemoryPromptProjection
            && lhs.memoryRouteTruthProjection == rhs.memoryRouteTruthProjection
            && lhs.durableCandidateMirrorProjection == rhs.durableCandidateMirrorProjection
            && lhs.localStoreWriteProjection == rhs.localStoreWriteProjection
            && lhs.skillDoctorTruthProjection == rhs.skillDoctorTruthProjection
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case state
        case headline
        case summary
        case nextStep
        case repairEntry
        case detailLines
        case projectContextPresentation
        case projectGovernanceRuntimeReadinessProjection
        case projectMemoryPolicyProjection
        case projectMemoryReadinessProjection
        case projectMemoryAssemblyResolutionProjection
        case heartbeatGovernanceProjection
        case supervisorMemoryPolicyProjection
        case supervisorMemoryAssemblyResolutionProjection
        case supervisorReviewTriggerProjection
        case supervisorGuidanceContinuityProjection
        case supervisorSafePointTimelineProjection
        case projectRemoteSnapshotCacheProjection
        case supervisorRemoteSnapshotCacheProjection
        case hubMemoryPromptProjection
        case memoryRouteTruthProjection
        case durableCandidateMirrorProjection
        case localStoreWriteProjection
        case skillDoctorTruthProjection
    }

    init(
        kind: XTUnifiedDoctorSectionKind,
        state: XTUISurfaceState,
        headline: String,
        summary: String,
        nextStep: String,
        repairEntry: UITroubleshootDestination,
        detailLines: [String]
    ) {
        self.kind = kind
        self.state = state
        self.headline = headline
        self.summary = summary
        self.nextStep = nextStep
        self.repairEntry = repairEntry
        self.detailLines = detailLines
    }

    init(
        kind: XTUnifiedDoctorSectionKind,
        state: XTUISurfaceState,
        headline: String,
        summary: String,
        nextStep: String,
        repairEntry: UITroubleshootDestination,
        detailLines: [String],
        projectContextPresentation: AXProjectContextAssemblyPresentation? = nil,
        projectGovernanceRuntimeReadinessProjection: AXProjectGovernanceRuntimeReadinessSnapshot? = nil,
        projectMemoryPolicyProjection: XTProjectMemoryPolicySnapshot? = nil,
        projectMemoryReadinessProjection: XTProjectMemoryAssemblyReadiness? = nil,
        projectMemoryAssemblyResolutionProjection: XTMemoryAssemblyResolution? = nil,
        heartbeatGovernanceProjection: XTUnifiedDoctorHeartbeatGovernanceProjection? = nil,
        supervisorMemoryPolicyProjection: XTSupervisorMemoryPolicySnapshot? = nil,
        supervisorMemoryAssemblyResolutionProjection: XTMemoryAssemblyResolution? = nil,
        supervisorReviewTriggerProjection: XTUnifiedDoctorSupervisorReviewTriggerProjection? = nil,
        supervisorGuidanceContinuityProjection: XTUnifiedDoctorSupervisorGuidanceContinuityProjection? = nil,
        supervisorSafePointTimelineProjection: XTUnifiedDoctorSupervisorSafePointTimelineProjection? = nil,
        projectRemoteSnapshotCacheProjection: XTUnifiedDoctorRemoteSnapshotCacheProjection? = nil,
        supervisorRemoteSnapshotCacheProjection: XTUnifiedDoctorRemoteSnapshotCacheProjection? = nil,
        hubMemoryPromptProjection: HubMemoryPromptProjectionSnapshot? = nil,
        memoryRouteTruthProjection: AXModelRouteTruthProjection? = nil,
        durableCandidateMirrorProjection: XTUnifiedDoctorDurableCandidateMirrorProjection? = nil,
        localStoreWriteProjection: XTUnifiedDoctorLocalStoreWriteProjection? = nil,
        skillDoctorTruthProjection: XTUnifiedDoctorSkillDoctorTruthProjection? = nil
    ) {
        self.kind = kind
        self.state = state
        self.headline = headline
        self.summary = summary
        self.nextStep = nextStep
        self.repairEntry = repairEntry
        self.detailLines = detailLines
        self.projectContextPresentation = projectContextPresentation
        self.projectGovernanceRuntimeReadinessProjection = projectGovernanceRuntimeReadinessProjection
        self.projectMemoryPolicyProjection = projectMemoryPolicyProjection
        self.projectMemoryReadinessProjection = projectMemoryReadinessProjection
        self.projectMemoryAssemblyResolutionProjection = projectMemoryAssemblyResolutionProjection
        self.heartbeatGovernanceProjection = heartbeatGovernanceProjection
        self.supervisorMemoryPolicyProjection = supervisorMemoryPolicyProjection
        self.supervisorMemoryAssemblyResolutionProjection = supervisorMemoryAssemblyResolutionProjection
        self.supervisorReviewTriggerProjection = supervisorReviewTriggerProjection
        self.supervisorGuidanceContinuityProjection = supervisorGuidanceContinuityProjection
        self.supervisorSafePointTimelineProjection = supervisorSafePointTimelineProjection
        self.projectRemoteSnapshotCacheProjection = projectRemoteSnapshotCacheProjection
        self.supervisorRemoteSnapshotCacheProjection = supervisorRemoteSnapshotCacheProjection
        self.hubMemoryPromptProjection = hubMemoryPromptProjection
        self.memoryRouteTruthProjection = memoryRouteTruthProjection
        self.durableCandidateMirrorProjection = durableCandidateMirrorProjection
        self.localStoreWriteProjection = localStoreWriteProjection
        self.skillDoctorTruthProjection = skillDoctorTruthProjection
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(XTUnifiedDoctorSectionKind.self, forKey: .kind),
            state: try container.decode(XTUISurfaceState.self, forKey: .state),
            headline: try container.decode(String.self, forKey: .headline),
            summary: try container.decode(String.self, forKey: .summary),
            nextStep: try container.decode(String.self, forKey: .nextStep),
            repairEntry: try container.decode(UITroubleshootDestination.self, forKey: .repairEntry),
            detailLines: try container.decode([String].self, forKey: .detailLines),
            projectContextPresentation: try container.decodeIfPresent(
                AXProjectContextAssemblyPresentation.self,
                forKey: .projectContextPresentation
            ),
            projectGovernanceRuntimeReadinessProjection: try container.decodeIfPresent(
                AXProjectGovernanceRuntimeReadinessSnapshot.self,
                forKey: .projectGovernanceRuntimeReadinessProjection
            ),
            projectMemoryPolicyProjection: try container.decodeIfPresent(
                XTProjectMemoryPolicySnapshot.self,
                forKey: .projectMemoryPolicyProjection
            ),
            projectMemoryReadinessProjection: try container.decodeIfPresent(
                XTProjectMemoryAssemblyReadiness.self,
                forKey: .projectMemoryReadinessProjection
            ),
            projectMemoryAssemblyResolutionProjection: try container.decodeIfPresent(
                XTMemoryAssemblyResolution.self,
                forKey: .projectMemoryAssemblyResolutionProjection
            ),
            heartbeatGovernanceProjection: try container.decodeIfPresent(
                XTUnifiedDoctorHeartbeatGovernanceProjection.self,
                forKey: .heartbeatGovernanceProjection
            ),
            supervisorMemoryPolicyProjection: try container.decodeIfPresent(
                XTSupervisorMemoryPolicySnapshot.self,
                forKey: .supervisorMemoryPolicyProjection
            ),
            supervisorMemoryAssemblyResolutionProjection: try container.decodeIfPresent(
                XTMemoryAssemblyResolution.self,
                forKey: .supervisorMemoryAssemblyResolutionProjection
            ),
            supervisorReviewTriggerProjection: try container.decodeIfPresent(
                XTUnifiedDoctorSupervisorReviewTriggerProjection.self,
                forKey: .supervisorReviewTriggerProjection
            ),
            supervisorGuidanceContinuityProjection: try container.decodeIfPresent(
                XTUnifiedDoctorSupervisorGuidanceContinuityProjection.self,
                forKey: .supervisorGuidanceContinuityProjection
            ),
            supervisorSafePointTimelineProjection: try container.decodeIfPresent(
                XTUnifiedDoctorSupervisorSafePointTimelineProjection.self,
                forKey: .supervisorSafePointTimelineProjection
            ),
            projectRemoteSnapshotCacheProjection: try container.decodeIfPresent(
                XTUnifiedDoctorRemoteSnapshotCacheProjection.self,
                forKey: .projectRemoteSnapshotCacheProjection
            ),
            supervisorRemoteSnapshotCacheProjection: try container.decodeIfPresent(
                XTUnifiedDoctorRemoteSnapshotCacheProjection.self,
                forKey: .supervisorRemoteSnapshotCacheProjection
            ),
            hubMemoryPromptProjection: try container.decodeIfPresent(
                HubMemoryPromptProjectionSnapshot.self,
                forKey: .hubMemoryPromptProjection
            ),
            memoryRouteTruthProjection: try container.decodeIfPresent(
                AXModelRouteTruthProjection.self,
                forKey: .memoryRouteTruthProjection
            ),
            durableCandidateMirrorProjection: try container.decodeIfPresent(
                XTUnifiedDoctorDurableCandidateMirrorProjection.self,
                forKey: .durableCandidateMirrorProjection
            ),
            localStoreWriteProjection: try container.decodeIfPresent(
                XTUnifiedDoctorLocalStoreWriteProjection.self,
                forKey: .localStoreWriteProjection
            ),
            skillDoctorTruthProjection: try container.decodeIfPresent(
                XTUnifiedDoctorSkillDoctorTruthProjection.self,
                forKey: .skillDoctorTruthProjection
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(state, forKey: .state)
        try container.encode(headline, forKey: .headline)
        try container.encode(summary, forKey: .summary)
        try container.encode(nextStep, forKey: .nextStep)
        try container.encode(repairEntry, forKey: .repairEntry)
        try container.encode(detailLines, forKey: .detailLines)
        try container.encodeIfPresent(projectContextPresentation, forKey: .projectContextPresentation)
        try container.encodeIfPresent(
            projectGovernanceRuntimeReadinessProjection,
            forKey: .projectGovernanceRuntimeReadinessProjection
        )
        try container.encodeIfPresent(projectMemoryPolicyProjection, forKey: .projectMemoryPolicyProjection)
        try container.encodeIfPresent(projectMemoryReadinessProjection, forKey: .projectMemoryReadinessProjection)
        try container.encodeIfPresent(
            projectMemoryAssemblyResolutionProjection,
            forKey: .projectMemoryAssemblyResolutionProjection
        )
        try container.encodeIfPresent(heartbeatGovernanceProjection, forKey: .heartbeatGovernanceProjection)
        try container.encodeIfPresent(supervisorMemoryPolicyProjection, forKey: .supervisorMemoryPolicyProjection)
        try container.encodeIfPresent(
            supervisorMemoryAssemblyResolutionProjection,
            forKey: .supervisorMemoryAssemblyResolutionProjection
        )
        try container.encodeIfPresent(
            supervisorReviewTriggerProjection,
            forKey: .supervisorReviewTriggerProjection
        )
        try container.encodeIfPresent(
            supervisorGuidanceContinuityProjection,
            forKey: .supervisorGuidanceContinuityProjection
        )
        try container.encodeIfPresent(
            supervisorSafePointTimelineProjection,
            forKey: .supervisorSafePointTimelineProjection
        )
        try container.encodeIfPresent(
            projectRemoteSnapshotCacheProjection,
            forKey: .projectRemoteSnapshotCacheProjection
        )
        try container.encodeIfPresent(
            supervisorRemoteSnapshotCacheProjection,
            forKey: .supervisorRemoteSnapshotCacheProjection
        )
        try container.encodeIfPresent(hubMemoryPromptProjection, forKey: .hubMemoryPromptProjection)
        try container.encodeIfPresent(memoryRouteTruthProjection, forKey: .memoryRouteTruthProjection)
        try container.encodeIfPresent(durableCandidateMirrorProjection, forKey: .durableCandidateMirrorProjection)
        try container.encodeIfPresent(localStoreWriteProjection, forKey: .localStoreWriteProjection)
        try container.encodeIfPresent(skillDoctorTruthProjection, forKey: .skillDoctorTruthProjection)
    }
}

struct XTUnifiedDoctorReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.unified_doctor_report.v1"

    static let empty = XTUnifiedDoctorReport(
        schemaVersion: currentSchemaVersion,
        generatedAtMs: 0,
        overallState: .blockedWaitingUpstream,
        overallSummary: "Doctor 正在等待就绪信号",
        readyForFirstTask: false,
        currentFailureCode: "",
        currentFailureIssue: nil,
        configuredModelRoles: 0,
        availableModelCount: 0,
        loadedModelCount: 0,
        currentSessionID: nil,
        currentRoute: XTUnifiedDoctorRouteSnapshot(
            transportMode: "disconnected",
            routeLabel: "disconnected",
            pairingPort: 50052,
            grpcPort: 50051,
            internetHost: ""
        ),
        firstPairCompletionProofSnapshot: nil,
        pairedRouteSetSnapshot: nil,
        connectivityIncidentSnapshot: nil,
        sections: [],
        consumedContracts: [],
        reportPath: XTUnifiedDoctorStore.defaultReportURL().path
    )

    var schemaVersion: String
    var generatedAtMs: Int64
    var overallState: XTUISurfaceState
    var overallSummary: String
    var readyForFirstTask: Bool
    var currentFailureCode: String
    var currentFailureIssue: UITroubleshootIssue?
    var configuredModelRoles: Int
    var availableModelCount: Int
    var loadedModelCount: Int
    var currentSessionID: String?
    var currentRoute: XTUnifiedDoctorRouteSnapshot
    var firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot? = nil
    var pairedRouteSetSnapshot: XTPairedRouteSetSnapshot? = nil
    var connectivityIncidentSnapshot: XTHubConnectivityIncidentSnapshot? = nil
    var remotePaidAccessProjection: XTUnifiedDoctorRemotePaidAccessProjection? = nil
    var sections: [XTUnifiedDoctorSection]
    var consumedContracts: [String]
    var reportPath: String

    func section(_ kind: XTUnifiedDoctorSectionKind) -> XTUnifiedDoctorSection? {
        sections.first { $0.kind == kind }
    }
}

struct XTUnifiedDoctorReportContract: Codable, Equatable {
    let schemaVersion: String
    let reportSchemaVersion: String
    let sectionKinds: [XTUnifiedDoctorSectionKind]
    let structuredProjectionFields: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case reportSchemaVersion = "report_schema_version"
        case sectionKinds = "section_kinds"
        case structuredProjectionFields = "structured_projection_fields"
        case auditRef = "audit_ref"
    }

    static let frozen = XTUnifiedDoctorReportContract(
        schemaVersion: "xt.unified_doctor_report_contract.v1",
        reportSchemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
        sectionKinds: XTUnifiedDoctorSectionKind.allCases,
        structuredProjectionFields: [
            "projectContextPresentation",
            "projectGovernanceRuntimeReadinessProjection",
            "projectMemoryPolicyProjection",
            "projectMemoryReadinessProjection",
            "projectMemoryAssemblyResolutionProjection",
            "heartbeatGovernanceProjection",
            "supervisorMemoryPolicyProjection",
            "supervisorMemoryAssemblyResolutionProjection",
            "supervisorReviewTriggerProjection",
            "supervisorGuidanceContinuityProjection",
            "supervisorSafePointTimelineProjection",
            "projectRemoteSnapshotCacheProjection",
            "supervisorRemoteSnapshotCacheProjection",
            "hubMemoryPromptProjection",
            "memoryRouteTruthProjection",
            "durableCandidateMirrorProjection",
            "localStoreWriteProjection",
            "skillDoctorTruthProjection",
            "remotePaidAccessProjection",
            "firstPairCompletionProofSnapshot"
        ],
        auditRef: "audit-xt-unified-doctor-contract-v1"
    )
}

struct XTUnifiedDoctorCalendarReminderSnapshot: Codable, Equatable, Sendable {
    static let empty = XTUnifiedDoctorCalendarReminderSnapshot(
        enabled: false,
        headsUpMinutes: 15,
        finalCallMinutes: 3,
        notificationFallbackEnabled: true,
        authorizationStatus: .notDetermined,
        authorizationGuidanceText: XTCalendarAuthorizationStatus.notDetermined.guidanceText,
        schedulerStatusLine: "Calendar reminders are off",
        schedulerLastRunAtMs: 0,
        eventStoreStatusLine: "Calendar reminders are off",
        eventStoreLastRefreshedAtMs: 0,
        upcomingMeetingCount: 0,
        upcomingMeetingPreviewLines: []
    )

    var enabled: Bool
    var headsUpMinutes: Int
    var finalCallMinutes: Int
    var notificationFallbackEnabled: Bool
    var authorizationStatus: XTCalendarAuthorizationStatus
    var authorizationGuidanceText: String
    var schedulerStatusLine: String
    var schedulerLastRunAtMs: Int64
    var eventStoreStatusLine: String
    var eventStoreLastRefreshedAtMs: Int64
    var upcomingMeetingCount: Int
    var upcomingMeetingPreviewLines: [String]
}

final class XTUnifiedDoctorInput: @unchecked Sendable {
    var generatedAt: Date
    var localConnected: Bool
    var remoteConnected: Bool
    var remoteRoute: HubRemoteRoute
    var remotePaidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil
    var linking: Bool
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String
    var configuredModelIDs: [String]
    var totalModelRoles: Int
    var failureCode: String
    var runtime: UIFailClosedRuntimeSnapshot
    var runtimeStatus: AIRuntimeStatus?
    var modelsState: ModelStateSnapshot
    var bridgeAlive: Bool
    var bridgeEnabled: Bool
    var bridgeLastError: String
    var sessionID: String?
    var sessionTitle: String?
    var sessionRuntime: AXSessionRuntimeSnapshot?
    var voiceRouteDecision: VoiceRouteDecision
    var voiceRuntimeState: SupervisorVoiceRuntimeState
    var voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus
    var voicePermissionSnapshot: VoicePermissionSnapshot
    var voiceActiveHealthReasonCode: String
    var voiceSidecarHealth: VoiceSidecarHealthSnapshot?
    var wakeProfileSnapshot: VoiceWakeProfileSnapshot
    var conversationSession: SupervisorConversationSessionSnapshot
    var voicePreferences: VoiceRuntimePreferences
    var voicePlaybackActivity: VoicePlaybackActivity
    var calendarReminderSnapshot: XTUnifiedDoctorCalendarReminderSnapshot
    var skillsSnapshot: AXSkillsDoctorSnapshot
    var skillDoctorTruthProjection: XTUnifiedDoctorSkillDoctorTruthProjection? = nil
    var reportPath: String
    var modelRouteDiagnostics: AXModelRouteDiagnosticsSummary
    var projectContextDiagnostics: AXProjectContextAssemblyDiagnosticsSummary
    var projectGovernanceResolved: AXProjectResolvedGovernanceState? = nil
    var heartbeatGovernanceSnapshot: XTProjectHeartbeatGovernanceDoctorSnapshot? = nil
    var supervisorMemoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot?
    var supervisorLatestTurnContextAssembly: SupervisorTurnContextAssemblyResult? = nil
    var doctorProjectContext: AXProjectContext? = nil
    var supervisorVoiceSmokeReport: XTSupervisorVoiceSmokeReportSummary?
    var freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot? = nil
    var firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot? = nil
    var pairedRouteSetSnapshot: XTPairedRouteSetSnapshot? = nil
    var connectivityIncidentSnapshot: XTHubConnectivityIncidentSnapshot? = nil

    init(
        generatedAt: Date = Date(),
        localConnected: Bool,
        remoteConnected: Bool,
        remoteRoute: HubRemoteRoute,
        remotePaidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        linking: Bool,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String,
        configuredModelIDs: [String],
        totalModelRoles: Int,
        failureCode: String,
        runtime: UIFailClosedRuntimeSnapshot,
        runtimeStatus: AIRuntimeStatus?,
        modelsState: ModelStateSnapshot,
        bridgeAlive: Bool,
        bridgeEnabled: Bool,
        bridgeLastError: String = "",
        sessionID: String?,
        sessionTitle: String?,
        sessionRuntime: AXSessionRuntimeSnapshot?,
        voiceRouteDecision: VoiceRouteDecision = .unavailable,
        voiceRuntimeState: SupervisorVoiceRuntimeState = .idle,
        voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus = .undetermined,
        voicePermissionSnapshot: VoicePermissionSnapshot = .unknown,
        voiceActiveHealthReasonCode: String = "",
        voiceSidecarHealth: VoiceSidecarHealthSnapshot? = nil,
        wakeProfileSnapshot: VoiceWakeProfileSnapshot = .empty,
        conversationSession: SupervisorConversationSessionSnapshot = .idle(
            policy: .default(),
            wakeMode: .pushToTalk,
            route: .manualText
        ),
        voicePreferences: VoiceRuntimePreferences = .default(),
        voicePlaybackActivity: VoicePlaybackActivity = .empty,
        calendarReminderSnapshot: XTUnifiedDoctorCalendarReminderSnapshot = .empty,
        skillsSnapshot: AXSkillsDoctorSnapshot,
        skillDoctorTruthProjection: XTUnifiedDoctorSkillDoctorTruthProjection? = nil,
        reportPath: String = XTUnifiedDoctorStore.defaultReportURL().path,
        modelRouteDiagnostics: AXModelRouteDiagnosticsSummary = .empty,
        projectContextDiagnostics: AXProjectContextAssemblyDiagnosticsSummary = .empty,
        projectGovernanceResolved: AXProjectResolvedGovernanceState? = nil,
        heartbeatGovernanceSnapshot: XTProjectHeartbeatGovernanceDoctorSnapshot? = nil,
        supervisorMemoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot? = nil,
        supervisorLatestTurnContextAssembly: SupervisorTurnContextAssemblyResult? = nil,
        doctorProjectContext: AXProjectContext? = nil,
        supervisorVoiceSmokeReport: XTSupervisorVoiceSmokeReportSummary? = nil,
        freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot? = nil,
        firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot? = nil,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot? = nil,
        connectivityIncidentSnapshot: XTHubConnectivityIncidentSnapshot? = nil
    ) {
        self.generatedAt = generatedAt
        self.localConnected = localConnected
        self.remoteConnected = remoteConnected
        self.remoteRoute = remoteRoute
        self.remotePaidAccessSnapshot = remotePaidAccessSnapshot
        self.linking = linking
        self.pairingPort = pairingPort
        self.grpcPort = grpcPort
        self.internetHost = internetHost
        self.configuredModelIDs = configuredModelIDs
        self.totalModelRoles = totalModelRoles
        self.failureCode = failureCode
        self.runtime = runtime
        self.runtimeStatus = runtimeStatus
        self.modelsState = modelsState
        self.bridgeAlive = bridgeAlive
        self.bridgeEnabled = bridgeEnabled
        self.bridgeLastError = bridgeLastError
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.sessionRuntime = sessionRuntime
        self.voiceRouteDecision = voiceRouteDecision
        self.voiceRuntimeState = voiceRuntimeState
        self.voiceAuthorizationStatus = voiceAuthorizationStatus
        self.voicePermissionSnapshot = voicePermissionSnapshot
        self.voiceActiveHealthReasonCode = voiceActiveHealthReasonCode
        self.voiceSidecarHealth = voiceSidecarHealth
        self.wakeProfileSnapshot = wakeProfileSnapshot
        self.conversationSession = conversationSession
        self.voicePreferences = voicePreferences
        self.voicePlaybackActivity = voicePlaybackActivity
        self.calendarReminderSnapshot = calendarReminderSnapshot
        self.skillsSnapshot = skillsSnapshot
        self.skillDoctorTruthProjection = skillDoctorTruthProjection
        self.reportPath = reportPath
        self.modelRouteDiagnostics = modelRouteDiagnostics
        self.projectContextDiagnostics = projectContextDiagnostics
        self.projectGovernanceResolved = projectGovernanceResolved
        self.heartbeatGovernanceSnapshot = heartbeatGovernanceSnapshot
        self.supervisorMemoryAssemblySnapshot = supervisorMemoryAssemblySnapshot
        self.supervisorLatestTurnContextAssembly = supervisorLatestTurnContextAssembly
        self.doctorProjectContext = doctorProjectContext
        self.supervisorVoiceSmokeReport = supervisorVoiceSmokeReport
        self.freshPairReconnectSmokeSnapshot = freshPairReconnectSmokeSnapshot
        self.firstPairCompletionProofSnapshot = firstPairCompletionProofSnapshot
        self.pairedRouteSetSnapshot = pairedRouteSetSnapshot
        self.connectivityIncidentSnapshot = connectivityIncidentSnapshot
    }
}

private struct XTUnifiedDoctorHubReachabilityInput: Sendable {
    var localConnected: Bool
    var remoteConnected: Bool
    var linking: Bool
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String
    var connectivityIncidentSnapshot: XTHubConnectivityIncidentSnapshot?

    init(_ input: XTUnifiedDoctorInput) {
        self.localConnected = input.localConnected
        self.remoteConnected = input.remoteConnected
        self.linking = input.linking
        self.pairingPort = input.pairingPort
        self.grpcPort = input.grpcPort
        self.internetHost = input.internetHost
        self.connectivityIncidentSnapshot = input.connectivityIncidentSnapshot
    }
}

enum XTUnifiedDoctorBuilder {
    static func build(input: XTUnifiedDoctorInput) -> XTUnifiedDoctorReport {
        let failureCode = input.failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureIssue = UITroubleshootKnowledgeBase.issue(forFailureCode: failureCode) ?? input.runtime.primaryIssue
        let route = routeSnapshot(for: input)
        let hubReachabilityInput = XTUnifiedDoctorHubReachabilityInput(input)
        let remotePaidAccessProjection = input.remotePaidAccessSnapshot.map(XTUnifiedDoctorRemotePaidAccessProjection.init)
        let availableModels = input.modelsState.models
        let availableModelCount = availableModels.count
        let loadedModelCount = availableModels.filter { $0.state == .loaded }.count
        let interactiveLoadedModels = availableModels.filter { $0.state == .loaded && $0.isSelectableForInteractiveRouting }
        let localInteractiveLoadedCount = interactiveLoadedModels.filter(\.isLocalModel).count
        let remoteInteractiveLoadedCount = interactiveLoadedModels.count - localInteractiveLoadedCount
        let configuredModelIDs = orderedUnique(input.configuredModelIDs)
        let configuredModelCount = configuredModelIDs.count
        let availableModelIDs = Set(availableModels.map(\.id))
        let missingAssignedModels = configuredModelIDs.filter { !availableModelIDs.contains($0) }
        let hubInteractive = input.localConnected || input.remoteConnected
        let runtimeAlive = input.runtimeStatus?.isAlive(ttl: 3.0) == true
        let toolRouteExecutable = toolRouteExecutable(
            localConnected: input.localConnected,
            remoteConnected: input.remoteConnected,
            bridgeAlive: input.bridgeAlive,
            bridgeEnabled: input.bridgeEnabled
        )
        let trimmedHost = input.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceReadiness = VoiceReadinessAggregator.build(
            input: VoiceReadinessAggregatorInput.fromDoctorInput(input)
        )

        let hubReachability = enrichFreshPairReconnectSmokeSection(
            buildHubReachabilitySection(
                hubInteractive: hubInteractive,
                runtimeAlive: runtimeAlive,
                failureCode: failureCode,
                route: route,
                input: hubReachabilityInput
            ),
            snapshot: input.freshPairReconnectSmokeSnapshot
        )
        let pairingValidity = enrichPairingValiditySection(
            voiceReadiness.check(.pairingValidity)?.asDoctorSection()
                ?? buildPairingValidityFallback(
                    localConnected: input.localConnected,
                    remoteConnected: input.remoteConnected,
                    linking: input.linking,
                    pairingPort: input.pairingPort,
                    grpcPort: input.grpcPort,
                    internetHost: trimmedHost,
                    route: route
                ),
            firstPairCompletionProofSnapshot: input.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: input.pairedRouteSetSnapshot
        )
        let modelRoute = enrichModelRouteSection(
            normalizeModelRoutePosture(
                voiceReadiness.check(.modelRouteReadiness)?.asDoctorSection()
                    ?? buildModelRouteFallback(
                hubInteractive: hubInteractive,
                runtimeAlive: runtimeAlive,
                runtimeStatus: input.runtimeStatus,
                availableModelCount: availableModelCount,
                loadedModelCount: loadedModelCount,
                localInteractiveLoadedCount: localInteractiveLoadedCount,
                remoteInteractiveLoadedCount: remoteInteractiveLoadedCount,
                configuredModelCount: configuredModelCount,
                totalModelRoles: input.totalModelRoles,
                missingAssignedModels: missingAssignedModels,
                configuredModelIDs: configuredModelIDs
                    ),
                localInteractiveLoadedCount: localInteractiveLoadedCount,
                remoteInteractiveLoadedCount: remoteInteractiveLoadedCount
            ),
            diagnostics: input.modelRouteDiagnostics,
            route: route
        )
        let bridgeTool = voiceReadiness.check(.bridgeToolReadiness)?.asDoctorSection()
            ?? buildBridgeToolFallback(
                localConnected: input.localConnected,
                remoteConnected: input.remoteConnected,
                hubInteractive: hubInteractive,
                modelRouteReady: modelRoute.state == .ready,
                bridgeAlive: input.bridgeAlive,
                bridgeEnabled: input.bridgeEnabled,
                bridgeLastError: input.bridgeLastError,
                route: route
            )
        let sessionRuntime = enrichSessionRuntimeSection(
            voiceReadiness.check(.sessionRuntimeReadiness)?.asDoctorSection()
                ?? buildSessionRuntimeFallback(
                    toolRouteExecutable: toolRouteExecutable,
                    sessionID: input.sessionID,
                    sessionTitle: input.sessionTitle,
                    runtime: input.sessionRuntime
                ),
            diagnostics: input.projectContextDiagnostics,
            governance: input.projectGovernanceResolved,
            heartbeatGovernanceSnapshot: input.heartbeatGovernanceSnapshot,
            memoryAssemblySnapshot: input.supervisorMemoryAssemblySnapshot,
            turnContextAssembly: input.supervisorLatestTurnContextAssembly,
            projectContext: input.doctorProjectContext
        )
        let wakeProfile = enrichVoiceSmokeSection(
            voiceReadiness.check(.wakeProfileReadiness)?.asDoctorSection(),
            report: input.supervisorVoiceSmokeReport,
            phase: .wake
        )
        let talkLoop = enrichVoiceSmokeSection(
            voiceReadiness.check(.talkLoopReadiness)?.asDoctorSection(),
            report: input.supervisorVoiceSmokeReport,
            phase: .grant
        )
        let voicePlayback = enrichVoiceSmokeSection(
            enrichVoicePlaybackSection(
            voiceReadiness.check(.ttsReadiness)?.asDoctorSection(),
            playbackActivity: input.voicePlaybackActivity
            ),
            report: input.supervisorVoiceSmokeReport,
            phase: .briefPlayback
        )
        let calendarReminder = buildCalendarReminderSection(
            snapshot: input.calendarReminderSnapshot
        )
        let skillsCompatibility = buildSkillsCompatibilitySection(
            hubInteractive: hubInteractive,
            snapshot: input.skillsSnapshot,
            skillDoctorTruthProjection: input.skillDoctorTruthProjection
        )

        let sections = [
            hubReachability,
            pairingValidity,
            modelRoute,
            bridgeTool,
            sessionRuntime,
            wakeProfile,
            talkLoop,
            voicePlayback,
            calendarReminder,
            skillsCompatibility
        ].compactMap { $0 }
        let readyForFirstTask = hubReachability.state == .ready
            && modelRoute.state == .ready
            && bridgeTool.state == .ready
            && sessionRuntime.state == .ready
        let overallState = overallState(for: sections)
        let overallSummary = overallSummary(
            overallState: overallState,
            readyForFirstTask: readyForFirstTask,
            sections: sections,
            pairedRouteSetSnapshot: input.pairedRouteSetSnapshot
        )
        let consumedContracts = orderedUnique(
            input.runtime.consumedContracts + [
                XTUIInformationArchitectureContract.frozen.schemaVersion,
                XTUISurfaceStateContract.frozen.schemaVersion,
                XTUIDesignTokenBundleContract.frozen.schemaVersion,
                XTUIReleaseScopeBadgeContract.frozen.schemaVersion,
                VoiceReadinessSnapshot.currentSchemaVersion,
                XTUnifiedDoctorReportContract.frozen.schemaVersion
            ]
        )

        return XTUnifiedDoctorReport(
            schemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
            generatedAtMs: Int64(input.generatedAt.timeIntervalSince1970 * 1000),
            overallState: overallState,
            overallSummary: overallSummary,
            readyForFirstTask: readyForFirstTask,
            currentFailureCode: failureCode,
            currentFailureIssue: failureIssue,
            configuredModelRoles: configuredModelCount,
            availableModelCount: availableModelCount,
            loadedModelCount: loadedModelCount,
            currentSessionID: input.sessionID,
            currentRoute: route,
            firstPairCompletionProofSnapshot: input.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: input.pairedRouteSetSnapshot,
            connectivityIncidentSnapshot: input.connectivityIncidentSnapshot,
            remotePaidAccessProjection: remotePaidAccessProjection,
            sections: sections,
            consumedContracts: consumedContracts,
            reportPath: input.reportPath
        )
    }

    private static func buildHubReachabilitySection(
        hubInteractive: Bool,
        runtimeAlive: Bool,
        failureCode: String,
        route: XTUnifiedDoctorRouteSnapshot,
        input: XTUnifiedDoctorHubReachabilityInput
    ) -> XTUnifiedDoctorSection {
        let normalizedFailureCode = failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostClassification = XTHubRemoteAccessHostClassification.classify(input.internetHost)
        let failureIssue = UITroubleshootKnowledgeBase.issue(forFailureCode: normalizedFailureCode)

        if input.localConnected,
           let failureIssue,
           shouldSurfaceRemoteTargetFailureWhileRunningLocally(
            issue: failureIssue,
            failureCode: normalizedFailureCode,
            internetHost: input.internetHost,
            remoteConnected: input.remoteConnected
           ) {
            return buildLocalPathWithRemoteTargetFailureSection(
                failureIssue: failureIssue,
                failureCode: normalizedFailureCode,
                route: route,
                runtimeAlive: runtimeAlive,
                input: input,
                hostClassification: hostClassification
            )
        }

        if input.localConnected {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .ready,
                headline: "Hub 已通过本机直连可达",
                summary: "X-Terminal 正在直接读取这台 Mac 上的 Hub 当前状态。对首次验证来说，这是最直接、最清晰的一条路径。",
                nextStep: "留在当前向导里，继续检查模型路由、工具链路和会话运行时。",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=local_fileipc",
                    "route=local:fileipc",
                    "runtime_alive=\(runtimeAlive)",
                    failureCode.isEmpty ? "failure_code=none" : "failure_code=\(failureCode)"
                ]
            )
        }

        if input.remoteConnected {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .ready,
                headline: "Hub 已通过远端连接可达",
                summary: "X-Terminal 已经拿到一条可用的远端连接路径。既然当前传输已经跑通，就不需要再开第二套说明。",
                nextStep: "继续沿着当前这条有效链路检查模型路由和工具链路。",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=\(route.transportMode)",
                    "route=\(route.routeLabel)",
                    "runtime_alive=\(runtimeAlive)",
                    failureCode.isEmpty ? "failure_code=none" : "failure_code=\(failureCode)"
                ]
            )
        }

        if input.linking, !normalizedFailureCode.isEmpty {
            if let specializedPairingSection = buildSpecializedPairingFailureSection(
                failureCode: normalizedFailureCode,
                route: route,
                runtimeAlive: runtimeAlive,
                input: input,
                linkingStalled: true
            ) {
                return specializedPairingSection
            }

            let headline: String
            let summary: String
            let nextStep: String

            switch failureIssue {
            case .pairingRepairRequired:
                headline = "Hub 配对引导已卡住，需要修复现有配对"
                summary = "XT 仍处在连接恢复流程里，但最近一次失败已经不是“单纯等待上游”，而是配对档案、令牌或证书材料本身有问题。继续原地等待不会恢复。"
                nextStep = "先在 XT 连接 Hub 里清除旧配对后重连，再到 REL Flow Hub → 配对与设备信任清理旧设备条目并重新批准。"
            case .hubUnreachable:
                return buildHubUnreachableSection(
                    route: route,
                    runtimeAlive: runtimeAlive,
                    input: input,
                    failureCode: normalizedFailureCode,
                    hostClassification: hostClassification,
                    linkingStalled: true
                )
            case .multipleHubsAmbiguous:
                headline = "Hub 配对引导已卡住，当前目标不唯一"
                summary = "XT 仍处在连接恢复流程里，但最近一次失败已经说明局域网里发现了多台候选 Hub。继续等待不会自动收敛到正确目标。"
                nextStep = "先在 XT 连接 Hub 固定一台目标 Hub，或手填唯一的 Internet Host / 端口后再重试。"
            default:
                headline = "Hub 配对引导已卡住"
                summary = "XT 仍处在连接恢复流程里，但最近一次失败已经给出了明确错误。当前不该继续把它解释成“仍在进行中”。"
                nextStep = "先看当前失败原因，回 XT 连接 Hub 修正当前目标 Hub 与配对参数后再重试。"
            }

            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .diagnosticRequired,
                headline: headline,
                summary: summary,
                nextStep: nextStep,
                repairEntry: .xtPairHub,
                detailLines: hubReachabilityDiagnosticLines(
                    route: route,
                    runtimeAlive: runtimeAlive,
                    input: input,
                    failureCode: normalizedFailureCode
                )
            )
        }

        if input.linking {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .inProgress,
                headline: "Hub 配对引导仍在进行中",
                summary: "发现、引导或重连流程还没结束。在它真正完成前，后续验证都会先停在安全状态，不会假装已经恢复。",
                nextStep: "等连接 Hub 这一步完成后，再回到这里重新检查当前有效链路。",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=\(route.transportMode)",
                    "route=\(route.routeLabel)",
                    "runtime_alive=\(runtimeAlive)",
                    failureCode.isEmpty ? "failure_code=none" : "failure_code=\(failureCode)"
                ]
            )
        }

        if failureIssue == .multipleHubsAmbiguous {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .diagnosticRequired,
                headline: "发现到多台 Hub，必须先固定目标",
                summary: "当前不是单纯的 Hub 不可达，而是局域网扫描同时发现了多台候选 Hub；在明确绑定目标前，系统不能假装下一步已经清楚。",
                nextStep: "先在 XT 连接 Hub 里固定一台目标 Hub，或手填 Internet Host / 端口；必要时到目标 Hub 的网络连接页面停掉另一台 Hub 的广播后再重试。",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=\(route.transportMode)",
                    "route=\(route.routeLabel)",
                    "runtime_alive=\(runtimeAlive)",
                    normalizedFailureCode.isEmpty ? "failure_code=multiple_hubs_ambiguous" : "failure_code=\(normalizedFailureCode)"
                ]
            )
        }

        if failureIssue == .hubPortConflict {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .diagnosticRequired,
                headline: "Hub 端口冲突，必须先修复网络端口",
                summary: "当前阻塞更像是目标 Hub 的 gRPC 端口或配对端口已被占用；只要端口占用问题还在，系统就不能把连接链路当成可恢复。",
                nextStep: "先到 REL Flow Hub → 网络连接 或 REL Flow Hub → 诊断与恢复切换到空闲端口，或释放占用进程；再把新端口同步回 XT 后重跑重连自检。",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=\(route.transportMode)",
                    "route=\(route.routeLabel)",
                    "runtime_alive=\(runtimeAlive)",
                    normalizedFailureCode.isEmpty ? "failure_code=hub_port_conflict" : "failure_code=\(normalizedFailureCode)"
                ]
            )
        }

        if failureIssue == .pairingRepairRequired {
            if let specializedPairingSection = buildSpecializedPairingFailureSection(
                failureCode: normalizedFailureCode,
                route: route,
                runtimeAlive: runtimeAlive,
                input: input,
                linkingStalled: false
            ) {
                return specializedPairingSection
            }

            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .diagnosticRequired,
                headline: "现有配对档案已失效，需要清理并重配",
                summary: "当前不是单纯的 Hub 不可达，更像是本地缓存的令牌、客户端证书或旧配对档案已经失效；继续拿旧档案重连只会反复失败。",
                nextStep: "先在 XT 连接 Hub 执行“清除配对后重连”，再到 REL Flow Hub → 配对与设备信任清理旧设备条目并重新批准。",
                repairEntry: .xtPairHub,
                detailLines: hubReachabilityDiagnosticLines(
                    route: route,
                    runtimeAlive: runtimeAlive,
                    input: input,
                    failureCode: normalizedFailureCode.isEmpty ? "pairing_repair_required" : normalizedFailureCode
                )
            )
        }

        return buildHubUnreachableSection(
            route: route,
            runtimeAlive: runtimeAlive,
            input: input,
            failureCode: normalizedFailureCode.isEmpty ? "hub_unreachable" : normalizedFailureCode,
            hostClassification: hostClassification,
            linkingStalled: false
        )
    }

    private static func buildSpecializedPairingFailureSection(
        failureCode: String,
        route: XTUnifiedDoctorRouteSnapshot,
        runtimeAlive: Bool,
        input: XTUnifiedDoctorHubReachabilityInput,
        linkingStalled: Bool
    ) -> XTUnifiedDoctorSection? {
        let normalized = failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let hostClassification = XTHubRemoteAccessHostClassification.classify(input.internetHost)
        let host = hostClassification.displayHost ?? "当前目标"

        let headline: String
        let summary: String
        let nextStep: String

        if normalized.contains("first_pair_requires_same_lan") {
            headline = linkingStalled
                ? "首次配对被同网策略拦住，必须回到同一局域网"
                : "首次配对必须回到同一 Wi-Fi / 同一局域网"
            switch hostClassification.kind {
            case .lanOnly, .rawIP(scope: .privateLAN), .rawIP(scope: .loopback), .rawIP(scope: .linkLocal):
                summary = "当前不是 Hub 坏了，而是 Hub 明确判定这次首配不是“同一局域网来源”。即使你看到的是同一个 Wi‑Fi 名称，也可能因为 client isolation、访客网络或 VLAN 分段而被 Hub 识别成不同 LAN。"
                nextStep = "确认 XT 与 Hub 真正在同一局域网内：若目标 \(host) 仍报这个错误，优先检查当前 Wi‑Fi / AP 是否开启了 client isolation、同 SSID 是否被切到不同 VLAN；修好后重新打开连接 Hub，并在 Hub 本机完成一次本地批准。"
            case .stableNamed, .rawIP(scope: .carrierGradeNat), .rawIP(scope: .publicInternet), .rawIP(scope: .unknown):
                summary = "当前不是 Hub 坏了，而是 Hub 明确要求首次配对必须先在同一局域网内完成一次本地批准。正式异网入口、公网 raw IP 或 NAT 入口都不能直接替代这一步。"
                nextStep = "先把 XT 和 Hub 放回同一局域网完成首配；Hub 本机批准成功后，再回到异网环境使用正式远端入口。"
            case .missing:
                summary = "当前不是 Hub 坏了，而是 Hub 明确要求首次配对只能在同一 Wi-Fi / 同一局域网内完成。异网、蜂窝或只有公网入口时，系统会故意拒绝继续配对。"
                nextStep = "把 XT 和 Hub 放回同一 Wi-Fi / 同一局域网后重新打开连接 Hub；在 Hub 本机完成一次本地批准后，再回到异网环境使用远端重连。"
            }
        } else if normalized.contains("pairing_approval_timeout") {
            headline = "Hub 本地批准超时，首次配对没有完成"
            summary = "Hub 已经发现这台 XT，但主机侧的本地批准没有在时限内完成。当前不是单纯网络不可达，而是安全确认链停在 Hub 本机。"
            nextStep = "回到 Hub 机器，打开 REL Flow Hub 的首次配对审批卡，用 Touch ID、Face ID 或本机密码完成批准；若审批卡已消失，就在 XT 重新发起一次连接。"
        } else if normalized.contains("pairing_owner_auth_cancelled") {
            headline = "Hub 本地批准被取消，首次配对未生效"
            summary = "Hub 主机侧已经弹出本地认证，但这次 Touch ID、Face ID 或本机密码确认被取消，所以配对材料没有签发。"
            nextStep = "回到 Hub 机器重新发起批准；确认时不要取消本地认证。Hub 批准成功后，XT 再继续当前连接。"
        } else if normalized.contains("pairing_owner_auth_failed") {
            headline = "Hub 本地批准认证失败，首次配对未生效"
            summary = "Hub 主机侧的本地认证没有成功通过，因此系统按 fail-closed 终止了这次首次配对。继续原地重试 XT 并不会自动恢复。"
            nextStep = "回到 Hub 机器重新批准，确认本机密码、Touch ID 或 Face ID 能正常通过；若仍失败，再检查系统认证服务后重试。"
        } else {
            return nil
        }

        return XTUnifiedDoctorSection(
            kind: .hubReachability,
            state: .diagnosticRequired,
            headline: headline,
            summary: summary,
            nextStep: nextStep,
            repairEntry: .xtPairHub,
            detailLines: hubReachabilityDiagnosticLines(
                route: route,
                runtimeAlive: runtimeAlive,
                input: input,
                failureCode: normalized
            )
        )
    }

    private static func buildHubUnreachableSection(
        route: XTUnifiedDoctorRouteSnapshot,
        runtimeAlive: Bool,
        input: XTUnifiedDoctorHubReachabilityInput,
        failureCode: String,
        hostClassification: XTHubRemoteAccessHostClassification,
        linkingStalled: Bool
    ) -> XTUnifiedDoctorSection {
        let headline: String
        let summary: String
        let nextStep: String
        let host = hostClassification.displayHost ?? "未设置"

        switch hostClassification.kind {
        case .missing:
            headline = linkingStalled
                ? "Hub 配对引导已停住，还没有正式远端入口"
                : "Hub 暂时不可达，而且还没有正式远端入口"
            summary = "当前没有 Internet Host。XT 一旦离开同网环境，就只能依赖旧缓存或本地发现；既然现在两者都没连上，就不能把它当成“Hub 只是慢一点”。"
            nextStep = "若还没完成首次配对，先把 XT 和 Hub 放回同一 Wi-Fi / 同一局域网；若要长期异网接入，再到 Hub 配置稳定主机名并重新导出正式接入包。"
        case .lanOnly:
            headline = linkingStalled
                ? "Hub 配对引导已停住，当前只有同网入口"
                : "Hub 暂时不可达，当前只有同网入口"
            summary = "当前 Internet Host 仍是 \(host)，这类入口只适合同一 Wi-Fi、同一局域网或同一 VPN 自动发现。换到别的互联网后，这条入口不会自动成立。"
            nextStep = "若此刻就在同一局域网，优先回同网完成首次配对；若要异网接入，在 Hub 上配置 tailnet、relay 或 DNS 主机名，再让 XT 重新拿正式接入包。"
        case .rawIP(let scope):
            headline = linkingStalled
                ? "Hub 配对引导已停住，当前还是临时 raw IP 入口"
                : "Hub 暂时不可达，当前还是临时 raw IP 入口"
            switch scope {
            case .privateLAN, .loopback, .linkLocal:
                summary = "当前记录的是 \(scope.doctorLabel) \(host)。这类 raw IP 只适合同一局域网、同一 VPN 或本机回环路径；一旦换 Wi‑Fi、跨 VLAN / 网段或离开 VPN，通常就会直接超时。"
                nextStep = "先确认 XT 现在仍在能直达 \(host) 的同一局域网 / 同一 VPN；若要长期异网使用，改成稳定命名入口并重新导出正式接入包。"
            case .carrierGradeNat:
                summary = "当前记录的是运营商 NAT 地址 \(host)。这类入口通常不能被另一台设备稳定反向访问，所以 XT 无法把它当作可靠的 Hub 远端入口。"
                nextStep = "改成稳定命名入口、relay 或 VPN 地址后再重试，不要继续依赖运营商 NAT raw IP。"
            case .publicInternet, .unknown:
                summary = "当前记录的是 \(scope.doctorLabel) \(host)。它可以短时直连，但网络切换、休眠、NAT 或公网 IP 变化后很容易失效，所以 XT 现在无法确认这条入口仍指向 Hub。"
                nextStep = "先确认这个 raw IP 现在仍能打到 Hub；若要长期异网使用，改成稳定命名入口并重新导出正式接入包，避免每次换网都手工修。"
            }
        case .stableNamed:
            headline = linkingStalled
                ? "Hub 配对引导已停住，正式异网入口当前不可达"
                : "Hub 暂时不可达，但正式异网入口已配置"
            summary = "XT 已经有稳定命名入口 \(host)，但此刻仍无法连到配对或 gRPC 端口。更像是 Hub 服务离线、防火墙拦截，或远端入口没有转到当前这台 Hub。"
            nextStep = "到 Hub 主机确认 app 没休眠、配对 / gRPC 端口正在监听，再检查防火墙、NAT 或 relay 转发；修好后回 XT 重试。"
        }

        return XTUnifiedDoctorSection(
            kind: .hubReachability,
            state: .diagnosticRequired,
            headline: headline,
            summary: summary,
            nextStep: nextStep,
            repairEntry: .xtPairHub,
            detailLines: hubReachabilityDiagnosticLines(
                route: route,
                runtimeAlive: runtimeAlive,
                input: input,
                failureCode: failureCode
            )
        )
    }

    private static func shouldSurfaceRemoteTargetFailureWhileRunningLocally(
        issue: UITroubleshootIssue,
        failureCode: String,
        internetHost: String,
        remoteConnected: Bool
    ) -> Bool {
        guard !remoteConnected else { return false }
        guard !failureCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !internetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        switch issue {
        case .hubUnreachable, .pairingRepairRequired, .multipleHubsAmbiguous, .hubPortConflict:
            return true
        default:
            return false
        }
    }

    private static func buildLocalPathWithRemoteTargetFailureSection(
        failureIssue: UITroubleshootIssue,
        failureCode: String,
        route: XTUnifiedDoctorRouteSnapshot,
        runtimeAlive: Bool,
        input: XTUnifiedDoctorHubReachabilityInput,
        hostClassification: XTHubRemoteAccessHostClassification
    ) -> XTUnifiedDoctorSection {
        let baseSection: XTUnifiedDoctorSection
        switch failureIssue {
        case .pairingRepairRequired:
            baseSection = buildSpecializedPairingFailureSection(
                failureCode: failureCode,
                route: route,
                runtimeAlive: runtimeAlive,
                input: input,
                linkingStalled: false
            ) ?? XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .diagnosticRequired,
                headline: "现有配对档案已失效，需要清理并重配",
                summary: "当前不是单纯的 Hub 不可达，更像是本地缓存的令牌、客户端证书或旧配对档案已经失效；继续拿旧档案重连只会反复失败。",
                nextStep: "先在 XT 连接 Hub 执行“清除配对后重连”，再到 REL Flow Hub → 配对与设备信任清理旧设备条目并重新批准。",
                repairEntry: .xtPairHub,
                detailLines: hubReachabilityDiagnosticLines(
                    route: route,
                    runtimeAlive: runtimeAlive,
                    input: input,
                    failureCode: failureCode
                )
            )
        case .multipleHubsAmbiguous:
            baseSection = XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .diagnosticRequired,
                headline: "发现到多台 Hub，必须先固定目标",
                summary: "当前不是单纯的 Hub 不可达，而是局域网扫描同时发现了多台候选 Hub；在明确绑定目标前，系统不能假装下一步已经清楚。",
                nextStep: "先在 XT 连接 Hub 里固定一台目标 Hub，或手填 Internet Host / 端口；必要时到目标 Hub 的网络连接页面停掉另一台 Hub 的广播后再重试。",
                repairEntry: .xtPairHub,
                detailLines: hubReachabilityDiagnosticLines(
                    route: route,
                    runtimeAlive: runtimeAlive,
                    input: input,
                    failureCode: failureCode
                )
            )
        case .hubPortConflict:
            baseSection = XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .diagnosticRequired,
                headline: "Hub 端口冲突，必须先修复网络端口",
                summary: "当前阻塞更像是目标 Hub 的 gRPC 端口或配对端口已被占用；只要端口占用问题还在，系统就不能把连接链路当成可恢复。",
                nextStep: "先到 REL Flow Hub → 网络连接 或 REL Flow Hub → 诊断与恢复切换到空闲端口，或释放占用进程；再把新端口同步回 XT 后重跑重连自检。",
                repairEntry: .xtPairHub,
                detailLines: hubReachabilityDiagnosticLines(
                    route: route,
                    runtimeAlive: runtimeAlive,
                    input: input,
                    failureCode: failureCode
                )
            )
        case .hubUnreachable:
            baseSection = buildHubUnreachableSection(
                route: route,
                runtimeAlive: runtimeAlive,
                input: input,
                failureCode: failureCode,
                hostClassification: hostClassification,
                linkingStalled: false
            )
        default:
            baseSection = buildHubUnreachableSection(
                route: route,
                runtimeAlive: runtimeAlive,
                input: input,
                failureCode: failureCode,
                hostClassification: hostClassification,
                linkingStalled: false
            )
        }

        var section = baseSection
        let host = input.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let localPrefix = "XT 当前还能通过本机文件通道读取本机 Hub，但你手填的远端目标 \(host) 还没有连通；这里不会把“本机可用”误写成“远端已恢复”。"

        switch failureIssue {
        case .hubUnreachable:
            section.headline = "本机 Hub 可达，但手填远端 Hub 当前不可达"
            section.nextStep = "先到目标 Hub 主机确认 gRPC / pairing 端口正在监听，再检查同网、防火墙或路由；修好后回 XT 重试。"
        case .pairingRepairRequired:
            section.headline = "本机 Hub 可达，但手填远端 Hub 的配对资料需要修复"
        case .multipleHubsAmbiguous:
            section.headline = "本机 Hub 可达，但远端目标仍不唯一"
        case .hubPortConflict:
            section.headline = "本机 Hub 可达，但手填远端 Hub 的端口有冲突"
        default:
            break
        }

        section.summary = "\(localPrefix) \(baseSection.summary)"
        section.detailLines = orderedUnique([
            "active_local_path=true",
            "active_local_transport=local_fileipc",
            "remote_target_requested=true"
        ] + baseSection.detailLines)
        return section
    }

    private static func hubReachabilityDiagnosticLines(
        route: XTUnifiedDoctorRouteSnapshot,
        runtimeAlive: Bool,
        input: XTUnifiedDoctorHubReachabilityInput,
        failureCode: String
    ) -> [String] {
        let failureLine = failureCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "failure_code=none"
            : "failure_code=\(failureCode)"
        return orderedUnique([
            "transport=\(route.transportMode)",
            "route=\(route.routeLabel)",
            "runtime_alive=\(runtimeAlive)",
            unreachableEndpointLine(input: input)
        ] + hubReachabilityHostClassificationLines(input.internetHost)
            + (input.connectivityIncidentSnapshot?.detailLines() ?? [])
            + [failureLine])
    }

    private static func hubReachabilityHostClassificationLines(_ rawHost: String) -> [String] {
        let classification = XTHubRemoteAccessHostClassification.classify(rawHost)
        var lines = [
            "internet_host=\(classification.displayHost ?? "missing")",
            "internet_host_kind=\(classification.kindCode)"
        ]
        if let scope = classification.ipScope {
            lines.append("internet_host_scope=\(scope.rawValue)")
        }
        return lines
    }

    private static func enrichFreshPairReconnectSmokeSection(
        _ section: XTUnifiedDoctorSection,
        snapshot: XTFreshPairReconnectSmokeSnapshot?
    ) -> XTUnifiedDoctorSection {
        guard let snapshot else { return section }
        var section = section
        section.detailLines = orderedUnique(section.detailLines + snapshot.detailLines())

        switch snapshot.status {
        case .running:
            section.state = .inProgress
            section.headline = "首次配对已完成，正在验证缓存路由"
            section.summary = "\(snapshot.source.doctorLabel) 刚完成 fresh pair，XT 正在补一轮 reconnect-only smoke，确认缓存配对资料下次能直接复用。"
            section.nextStep = "等待这轮缓存路由验证完成；如果失败，再按当前远端入口或配对失败原因修复。"
        case .succeeded:
            if section.state == .ready {
                section.summary = "\(section.summary) 最近一次\(snapshot.source.doctorLabel)后的缓存路由验证已通过。"
            }
        case .failed:
            let smokeLine = "最近一次\(snapshot.source.doctorLabel)后的缓存路由验证失败，说明 fresh pair 已下发成功，但缓存路由还不能稳定复用。"
            if !section.summary.contains(smokeLine) {
                section.summary = "\(smokeLine) \(section.summary)"
            }
        }
        return section
    }

    private static func unreachableEndpointLine(input: XTUnifiedDoctorInput) -> String {
        let host = input.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostLabel = host.isEmpty ? "missing" : host
        return "target=\(hostLabel):pairing=\(input.pairingPort),grpc=\(input.grpcPort)"
    }

    private static func unreachableEndpointLine(input: XTUnifiedDoctorHubReachabilityInput) -> String {
        let host = input.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostLabel = host.isEmpty ? "missing" : host
        return "target=\(hostLabel):pairing=\(input.pairingPort),grpc=\(input.grpcPort)"
    }

    private static func buildPairingValidityFallback(
        localConnected: Bool,
        remoteConnected: Bool,
        linking: Bool,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String,
        route: XTUnifiedDoctorRouteSnapshot
    ) -> XTUnifiedDoctorSection {
        let pairingLooksValid = portLooksValid(pairingPort) && portLooksValid(grpcPort) && pairingPort != grpcPort
        let pairingMatchesConvention = pairingPort == max(1, min(65_535, grpcPort + 1))
        let hostLabel = internetHost.isEmpty ? "missing" : internetHost
        let details = [
            "pairing_port=\(pairingPort)",
            "grpc_port=\(grpcPort)",
            "internet_host=\(hostLabel)",
            "pairing_equals_grpc_plus_one=\(pairingMatchesConvention)",
            "active_route=\(route.routeLabel)"
        ]

        if !pairingLooksValid {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .diagnosticRequired,
                headline: "配对参数暂时无效",
                summary: "在继续引导之前，配对端口和 gRPC 端口必须是明确且彼此不同的值，不能让用户靠猜。",
                nextStep: "去 REL Flow Hub → 网络连接复制配对端口和 gRPC 端口，然后重新执行连接 Hub。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if remoteConnected {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .ready,
                headline: "配对参数已匹配当前远端链路",
                summary: "同一组配对端口、gRPC 端口和 Internet Host 已经成功建立过可用的远端连接。",
                nextStep: "后续重连时继续保留这组值即可，不需要再找第二个真值来源。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if !internetHost.isEmpty {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .ready,
                headline: "配对参数已明确，可重复复用",
                summary: "X-Terminal 已经拿到了用户可见的全部配对字段：配对端口、gRPC 端口和 Internet Host。",
                nextStep: "后续做 LAN、VPN 或隧道配对时，直接复用这组值即可，不需要重新到别处查找。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if localConnected || linking {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .inProgress,
                headline: "本机链路可用，但远端引导参数还不完整",
                summary: "同机验证可以继续，但 Internet Host 仍为空，所以第二台设备还不知道该填什么。",
                nextStep: "先去 REL Flow Hub → 网络连接 复制 Internet Host 到 X-Terminal，再做远端配对。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .pairingValidity,
            state: .diagnosticRequired,
            headline: "配对参数不足以完成引导",
            summary: "如果没有明确的 Internet Host，面向局域网、VPN 或隧道设备的配对路径就是不完整的。",
            nextStep: "去 REL Flow Hub → 网络连接 复制 Internet Host，然后重新执行一键设置。",
            repairEntry: .xtPairHub,
            detailLines: details
        )
    }

    private static func enrichPairingValiditySection(
        _ base: XTUnifiedDoctorSection,
        firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot?,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot?
    ) -> XTUnifiedDoctorSection {
        guard let pairingContext = UITroubleshootPairingContext(
            firstPairCompletionProofSnapshot: firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot
        ) else {
            return base
        }

        var section = base
        section.detailLines = orderedUnique(
            base.detailLines + pairingReadinessDetailLines(
                firstPairCompletionProofSnapshot: firstPairCompletionProofSnapshot,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot,
                pairingContext: pairingContext
            )
        )

        let stableHost = normalizedOptionalDoctorField(pairingContext.stableRemoteHost)
        let stableHostSuffix = stableHost.map { "（host=\($0)）" } ?? ""

        switch pairingContext.readiness {
        case .remoteReady:
            section.state = .ready
            section.headline = "正式异网入口已验证，切网后可继续工作"
            section.summary = [
                "同网首配、本机批准和正式异网入口已经闭环\(stableHostSuffix)。",
                "切网后，XT 会优先沿这条已验证的正式入口继续连接 Hub。"
            ].joined(separator: " ")
            section.nextStep = "继续保留当前配对档案与正式入口；只有更换 Hub、重置配对材料或入口变更时才需要重新批准。"
        case .remoteBlocked:
            section.state = .diagnosticRequired
            section.headline = "正式异网入口存在，但被配对或身份边界阻断"
            section.summary = [
                "同网首配已经完成，XT 也有正式异网入口\(stableHostSuffix)，但当前被配对或身份边界挡住。",
                "这不是“重新首配就会自己好”的问题，先修批准、证书、令牌或身份约束。"
            ].joined(separator: " ")
            section.nextStep = "先保留现有配对档案，在 XT 连接 Hub 查看当前失败原因；再到 Hub 的配对与设备信任或诊断与恢复修复身份/批准边界。"
        case .remoteDegraded:
            section.state = .diagnosticRequired
            section.headline = "正式异网入口存在，但切网续连目前不稳定"
            section.summary = [
                "同网首配已经完成，XT 也拿到了正式异网入口\(stableHostSuffix)，但最近一次正式异网验证没有通过。",
                "离开当前 Wi-Fi 后，还不能把这条路径当成稳定可恢复。"
            ].joined(separator: " ")
            section.nextStep = "先检查 Hub app 是否在线、pairing / gRPC 端口是否还在监听，以及防火墙、NAT、relay 或 tailnet 路由；修好后再重跑异网验证。"
        case .localReady:
            if pairingContext.formalRemoteVerificationPending {
                section.state = .inProgress
                section.headline = "同网首配已完成，正在验证正式异网入口"
                section.summary = [
                    "同网首配和 Hub 本地批准已经完成，XT 也拿到了正式异网入口\(stableHostSuffix)。",
                    "当前正在补跑正式异网验证，在它真正通过前，不要把状态误判成已经可以无感切网。"
                ].joined(separator: " ")
                section.nextStep = "先保留当前配对档案，等待这轮正式异网验证结束；如果长时间不通过，再检查 Hub 的 stable remote host、relay / tailnet / DNS 和端口可达性。"
            } else {
                section.state = .inProgress
                section.headline = "同网首配已完成，但还没有正式异网入口"
                section.summary = [
                    "同网首配和 Hub 本地批准已经完成，但 XT 还没有稳定命名的正式异网入口。",
                    "当前留在同网环境可以继续用；离开当前 Wi-Fi 后还不能保证继续连回 Hub。"
                ].joined(separator: " ")
                section.nextStep = "先在 Hub 配置 tailnet、relay 或 DNS 这类正式异网入口，再回 XT 刷新配对资料并补一轮异网验证。"
            }
        case .unknown:
            break
        }

        return section
    }

    private static func pairingReadinessDetailLines(
        firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot?,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot?,
        pairingContext: UITroubleshootPairingContext
    ) -> [String] {
        var lines = [
            "paired_route_readiness=\(pairingContext.readiness.rawValue)",
            "pairing_formal_remote_verification_pending=\(pairingContext.formalRemoteVerificationPending)",
            "pairing_remote_shadow_failed=\(pairingContext.remoteShadowFailed)"
        ]

        if let pairedRouteSetSnapshot {
            lines.append("paired_route_reason_code=\(pairedRouteSetSnapshot.readinessReasonCode)")
            lines.append("paired_route_summary=\(pairedRouteSetSnapshot.summaryLine)")

            if let activeRoute = pairedRouteSetSnapshot.activeRoute {
                lines.append("paired_active_route=\(pairedRouteTargetSummary(activeRoute))")
            }
            if let stableRemoteRoute = pairedRouteSetSnapshot.stableRemoteRoute {
                lines.append("paired_stable_remote_route=\(pairedRouteTargetSummary(stableRemoteRoute))")
            }
            if let lastKnownGoodRoute = pairedRouteSetSnapshot.lastKnownGoodRoute {
                lines.append("paired_last_known_good_route=\(pairedRouteTargetSummary(lastKnownGoodRoute))")
            }
            if let cachedReconnectSmokeStatus = normalizedOptionalDoctorField(pairedRouteSetSnapshot.cachedReconnectSmokeStatus) {
                lines.append("paired_cached_reconnect_smoke_status=\(cachedReconnectSmokeStatus)")
            }
            if let cachedReconnectSmokeReasonCode = normalizedOptionalDoctorField(pairedRouteSetSnapshot.cachedReconnectSmokeReasonCode) {
                lines.append("paired_cached_reconnect_smoke_reason_code=\(cachedReconnectSmokeReasonCode)")
            }
            if let cachedReconnectSmokeSummary = normalizedOptionalDoctorField(pairedRouteSetSnapshot.cachedReconnectSmokeSummary) {
                lines.append("paired_cached_reconnect_smoke_summary=\(cachedReconnectSmokeSummary)")
            }
        }

        if let firstPairCompletionProofSnapshot {
            lines.append("first_pair_proof_readiness=\(firstPairCompletionProofSnapshot.readiness.rawValue)")
            lines.append("first_pair_same_lan_verified=\(firstPairCompletionProofSnapshot.sameLanVerified)")
            lines.append("first_pair_owner_local_approval_verified=\(firstPairCompletionProofSnapshot.ownerLocalApprovalVerified)")
            lines.append("first_pair_pairing_material_issued=\(firstPairCompletionProofSnapshot.pairingMaterialIssued)")
            lines.append("first_pair_cached_reconnect_smoke_passed=\(firstPairCompletionProofSnapshot.cachedReconnectSmokePassed)")
            lines.append("first_pair_stable_remote_route_present=\(firstPairCompletionProofSnapshot.stableRemoteRoutePresent)")
            lines.append("first_pair_remote_shadow_status=\(firstPairCompletionProofSnapshot.remoteShadowSmokeStatus.rawValue)")
            lines.append("first_pair_summary=\(firstPairCompletionProofSnapshot.summaryLine)")

            if let remoteShadowSource = firstPairCompletionProofSnapshot.remoteShadowSmokeSource?.rawValue {
                lines.append("first_pair_remote_shadow_source=\(remoteShadowSource)")
            }
            if let remoteShadowRoute = firstPairCompletionProofSnapshot.remoteShadowRoute?.rawValue {
                lines.append("first_pair_remote_shadow_route=\(remoteShadowRoute)")
            }
            if let remoteShadowReasonCode = normalizedOptionalDoctorField(firstPairCompletionProofSnapshot.remoteShadowReasonCode) {
                lines.append("first_pair_remote_shadow_reason_code=\(remoteShadowReasonCode)")
            }
            if let remoteShadowSummary = normalizedOptionalDoctorField(firstPairCompletionProofSnapshot.remoteShadowSummary) {
                lines.append("first_pair_remote_shadow_summary=\(remoteShadowSummary)")
            }
        }

        return lines
    }

    private static func pairedRouteTargetSummary(_ target: XTPairedRouteTargetSnapshot) -> String {
        "\(target.routeKind.rawValue):\(target.host):pairing=\(target.pairingPort),grpc=\(target.grpcPort),source=\(target.source.rawValue)"
    }

    private static func buildModelRouteFallback(
        hubInteractive: Bool,
        runtimeAlive: Bool,
        runtimeStatus: AIRuntimeStatus?,
        availableModelCount: Int,
        loadedModelCount: Int,
        localInteractiveLoadedCount: Int,
        remoteInteractiveLoadedCount: Int,
        configuredModelCount: Int,
        totalModelRoles: Int,
        missingAssignedModels: [String],
        configuredModelIDs: [String]
    ) -> XTUnifiedDoctorSection {
        let interactivePosture: String
        switch (localInteractiveLoadedCount > 0, remoteInteractiveLoadedCount > 0) {
        case (true, false):
            interactivePosture = "local_only"
        case (false, true):
            interactivePosture = "remote_only"
        case (true, true):
            interactivePosture = "mixed"
        case (false, false):
            interactivePosture = "none"
        }

        let providerStateCode = runtimeStatus?.providerReadinessStateCode(ttl: 3.0)

        var details = [
            "runtime_alive=\(runtimeAlive)",
            "available_models=\(availableModelCount)",
            "loaded_models=\(loadedModelCount)",
            "interactive_local_loaded=\(localInteractiveLoadedCount)",
            "interactive_remote_loaded=\(remoteInteractiveLoadedCount)",
            "interactive_posture=\(interactivePosture)",
            "configured_roles=\(configuredModelCount)/\(totalModelRoles)",
            configuredModelIDs.isEmpty ? "configured_model_ids=none" : "configured_model_ids=\(configuredModelIDs.joined(separator: ","))"
        ]

        if !missingAssignedModels.isEmpty {
            details.append("missing_assigned_models=\(missingAssignedModels.joined(separator: ","))")
        }
        if let runtimeStatus {
            details = orderedUnique(details + runtimeStatus.providerReadinessDetailLines(ttl: 3.0))
        }

        if !hubInteractive {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .blockedWaitingUpstream,
                headline: "模型路由正在等待可用的 Hub 链路",
                summary: "在 Hub 真正进入可交互状态前，XT 还无法确认哪些模型实际可用。",
                nextStep: "先完成连接 Hub，再回到 Supervisor Control Center · AI 模型。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if availableModelCount == 0 {
            if providerStateCode == "runtime_heartbeat_stale" {
                return XTUnifiedDoctorSection(
                    kind: .modelRouteReadiness,
                    state: .diagnosticRequired,
                    headline: "本地 provider 心跳已过期，模型清单当前不可信",
                    summary: "Hub 已可达，但本地 runtime/provider 心跳已过期，所以 XT 当前拿不到可信的本地模型清单。",
                    nextStep: "先到 REL Flow Hub 重启或刷新本地运行时，再回到 Supervisor Control Center · AI 模型刷新真实可执行列表，然后重新检查当前状态。",
                    repairEntry: .xtChooseModel,
                    detailLines: details
                )
            }

            if providerStateCode == "no_ready_provider" {
                return XTUnifiedDoctorSection(
                    kind: .modelRouteReadiness,
                    state: .diagnosticRequired,
                    headline: "本地 provider 全部未就绪，模型路由当前不可用",
                    summary: "Hub 已可达，但本地 provider 当前全部未就绪，所以 XT 还看不到任何真正可执行的本地模型。",
                    nextStep: "先到 REL Flow Hub → Models & Paid Access 检查 provider pack、helper 服务和导入失败原因，确认至少有一个 provider ready；再回到 Supervisor Control Center · AI 模型刷新真实可执行列表。",
                    repairEntry: .xtChooseModel,
                    detailLines: details
                )
            }

            if providerStateCode == "provider_partial_readiness" {
                return XTUnifiedDoctorSection(
                    kind: .modelRouteReadiness,
                    state: .diagnosticRequired,
                    headline: "本地 provider 只有部分就绪，当前模型清单可能缺项",
                    summary: "Hub 已可达，但本地 provider 只起来了一部分，所以 XT 现在看到的模型目录和能力覆盖还不完整。",
                    nextStep: "先到 REL Flow Hub → Models & Paid Access 检查还没起来的 provider pack 和 runtime；确认目标 provider ready 后，再回 Supervisor Control Center · AI 模型刷新列表。",
                    repairEntry: .xtChooseModel,
                    detailLines: details
                )
            }

            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                headline: "配对已通，但模型路由不可用",
                summary: "Hub 已可达，但 XT 还看不到任何可用模型。这个问题需要和配对失败、授权失败区分开。",
                nextStep: "先到 REL Flow Hub → 模型与付费访问，确认至少有一个模型已激活且服务方可用；再回到 Supervisor Control Center · AI 模型确认它进入真实可执行列表，然后重新检查当前状态。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if configuredModelCount == 0 {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .inProgress,
                headline: "Hub 模型可见，但 XT 的角色分配还是空的",
                summary: "模型路由已经存在，但 X-Terminal 还没有把任何角色绑定到具体的 Hub 模型上。",
                nextStep: "至少先在 Supervisor Control Center · AI 模型里给 coder 和 supervisor 分配模型。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if !missingAssignedModels.isEmpty {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                headline: "XT 的角色分配指向了当前未暴露的模型",
                summary: "虽然配对成功，但至少有一个已分配的模型 ID 不在当前的 Hub 模型清单里。",
                nextStep: "去 Supervisor Control Center · AI 模型替换过期模型 ID；如果目标模型已在 Hub 侧停用，再到 REL Flow Hub → Models & Paid Access 重新启用。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if interactivePosture == "local_only", providerStateCode == "runtime_heartbeat_stale" {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                headline: "当前走纯本地，但本地 provider 心跳已过期",
                summary: "XT 现在只剩本地模型路径，但本地 runtime/provider 心跳已过期，所以这条执行链不应继续当成可信状态。",
                nextStep: "先到 REL Flow Hub 重启或刷新本地运行时，确认 provider 心跳恢复后，再回 Supervisor Control Center · AI 模型重新验证。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if interactivePosture == "local_only", providerStateCode == "no_ready_provider" {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                headline: "当前走纯本地，但本地 provider 全部未就绪",
                summary: "XT 当前只看到本地模型路径，可 Hub 报告本地 provider 全部未就绪，所以这条纯本地执行链还不能继续当成可执行状态。",
                nextStep: "先到 REL Flow Hub → Models & Paid Access 修复本地 provider，就绪后再回 Supervisor Control Center · AI 模型重新验证。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        let readyHeadline: String
        let readySummary: String
        let readyNextStep: String

        switch (interactivePosture, providerStateCode) {
        case ("local_only", _):
            readyHeadline = "模型路由已就绪（纯本地）"
            readySummary = "XT 当前只看到本地对话模型，这本身不是异常；即使没有云端服务或 API key，也可以继续完成首个任务。"
            readyNextStep = "如果你只需要本地路径，直接继续做桥接 / 工具链验证；只有你要远端 GPT 或云能力时，再去补远端模型。"
        case ("remote_only", "no_ready_provider"):
            readyHeadline = "模型路由已就绪（当前无本地兜底）"
            readySummary = "当前角色分配还能命中远端模型，所以首个任务可以继续；但本地 provider 当前全部未就绪，远端失联时不会有本地兜底。"
            readyNextStep = "如果你只依赖远端链路，先继续桥接 / 工具链验证；如果你也要本地兜底，再去 REL Flow Hub → Models & Paid Access 修复本地 provider。"
        case ("remote_only", "runtime_heartbeat_stale"):
            readyHeadline = "模型路由已就绪，但本地运行时状态已过期"
            readySummary = "当前角色分配还能命中远端模型，所以首个任务可以继续；但本地 runtime/provider 心跳已过期，本地兜底当前不可信。"
            readyNextStep = "先继续桥接 / 工具链验证；如果你需要本地兜底，再到 REL Flow Hub 重启本地运行时并刷新模型列表。"
        case (_, "provider_partial_readiness"):
            readyHeadline = "模型路由已就绪，但本地能力覆盖还不完整"
            readySummary = "当前角色分配能命中可见模型，仍可继续首个任务；但部分本地 provider 未就绪，所以模型目录和能力覆盖可能不完整。"
            readyNextStep = "继续桥接 / 工具链验证；如果你需要更完整的本地能力覆盖，再去 REL Flow Hub → Models & Paid Access 检查未就绪 provider。"
        default:
            readyHeadline = "模型路由已就绪"
            readySummary = "XT 已经能看到可用的 Hub 模型，当前角色分配也都映射到了可见模型 ID。"
            readyNextStep = "不用离开当前页面，直接继续做桥接 / 工具链验证。"
        }

        return XTUnifiedDoctorSection(
            kind: .modelRouteReadiness,
            state: .ready,
            headline: readyHeadline,
            summary: readySummary,
            nextStep: readyNextStep,
            repairEntry: .xtChooseModel,
            detailLines: details
        )
    }

    private static func enrichModelRouteSection(
        _ base: XTUnifiedDoctorSection,
        diagnostics: AXModelRouteDiagnosticsSummary,
        route: XTUnifiedDoctorRouteSnapshot
    ) -> XTUnifiedDoctorSection {
        var section = base
        let projection = diagnostics.truthProjection
        section.memoryRouteTruthProjection = projection

        if diagnostics.recentEventCount > 0
            || diagnostics.recentFailureCount > 0
            || diagnostics.recentRemoteRetryRecoveryCount > 0 {
            section.detailLines = orderedUnique(base.detailLines + diagnostics.detailLines)
        }

        if let issueOverride = modelRouteIssueOverride(
            diagnostics: diagnostics,
            projection: projection
        ) {
            section.state = issueOverride.state
            section.headline = issueOverride.headline
            section.summary = issueOverride.summary
            section.nextStep = issueOverride.nextStep
            section.repairEntry = issueOverride.repairEntry
            section.detailLines = orderedUnique(section.detailLines + issueOverride.detailLines)
            applyGrpcRouteTruthHint(
                to: &section,
                diagnostics: diagnostics,
                projection: projection,
                route: route
            )
            return section
        }

        guard base.state == .ready,
              diagnostics.recentFailureCount > 0 else {
            return section
        }

        section.headline = "模型路由已就绪，但最近有项目链路退化"
        section.summary = "XT 当前能看到可分配模型，但最近仍有项目请求在执行时降到本地或远端失败；这通常不是“完全没连上 Hub”，而是具体项目选中的远端没有稳定命中。"
        section.nextStep = "打开受影响项目后运行 `/route diagnose`；如果诊断里已经提示 XT 会自动改试上次稳定远端，就直接继续。只有你想把模型固定下来时，再到 Supervisor Control Center · AI 模型手动切。"
        applyGrpcRouteTruthHint(
            to: &section,
            diagnostics: diagnostics,
            projection: projection,
            route: route
        )
        return section
    }

    private struct ModelRouteIssueOverride {
        let state: XTUISurfaceState
        let headline: String
        let summary: String
        let nextStep: String
        let repairEntry: UITroubleshootDestination
        let detailLines: [String]
    }

    private static func modelRouteIssueOverride(
        diagnostics: AXModelRouteDiagnosticsSummary,
        projection: AXModelRouteTruthProjection?
    ) -> ModelRouteIssueOverride? {
        if let supervisorRouteOverride = supervisorRouteIssueOverride(
            diagnostics: diagnostics,
            projection: projection
        ) {
            return supervisorRouteOverride
        }

        guard let evidence = modelRouteIssueEvidence(
            diagnostics: diagnostics,
            projection: projection
        ) else {
            return nil
        }

        let detailLines = orderedUnique(
            [
                "route_truth_issue=\(evidence.issue.rawValue)",
                "route_truth_primary_code=\(evidence.primaryCode)"
            ] + (evidence.denyCode.map { ["route_truth_deny_code=\($0)"] } ?? [])
        )

        switch evidence.issue {
        case .modelNotReady:
            let normalizedCode = normalizedOptionalDoctorField(evidence.copyCode)?
                .lowercased()
                .replacingOccurrences(of: "-", with: "_") ?? ""
            let state: XTUISurfaceState
            let headline: String
            let summary: String

            switch normalizedCode {
            case "blocked_waiting_upstream":
                state = .blockedWaitingUpstream
                headline = "模型路由正在等待上游就绪"
                summary = "最近一次模型路由核对显示上游仍在等待，所以当前不能把模型路由继续算成已就绪；这不是普通授权问题。"
            case "provider_not_ready":
                state = .blockedWaitingUpstream
                headline = "模型提供方尚未就绪"
                summary = "最近一次模型路由核对已经收敛到提供方未就绪；虽然 XT 还能看到模型列表，但这条执行链当前还不能稳定命中目标模型。"
            case "model_not_found", "remote_model_not_found":
                state = .diagnosticRequired
                headline = "模型角色分配指向了当前不可用的模型"
                summary = "最近一次模型路由核对显示目标模型 ID 不在真实可执行清单里；当前不是连接 Hub 断开，而是模型绑定已经失效。"
            default:
                state = .diagnosticRequired
                headline = "检测到模型未就绪，当前还不能把模型路由算成已就绪"
                summary = "最近一次模型路由核对已经把问题收敛到模型或提供方这一侧，而不是桥接链路或连接 Hub 本身。"
            }

            return ModelRouteIssueOverride(
                state: state,
                headline: headline,
                summary: summary,
                nextStep: "先到 Supervisor Control Center · AI 模型核对当前模型 ID、配置链路和实际命中的链路；再到 REL Flow Hub → 模型与付费访问检查提供方是否就绪以及真实可用清单；修复后回 XT 设置 → 诊断与核对 或 `/route diagnose` 重跑一次路由验证。",
                repairEntry: .xtChooseModel,
                detailLines: detailLines
            )
        case .connectorScopeBlocked:
            let normalizedCode = normalizedOptionalDoctorField(evidence.copyCode)?
                .lowercased()
                .replacingOccurrences(of: "-", with: "_") ?? ""
            let headline: String

            switch normalizedCode {
            case "remote_export_blocked":
                headline = "远端导出被 Hub 导出开关拦住"
            case "device_remote_export_denied":
                headline = "当前设备不允许远端导出"
            case "policy_remote_denied":
                headline = "当前策略阻止远端导出"
            case "budget_remote_denied":
                headline = "当前预算策略阻止远端导出"
            case "remote_disabled_by_user_pref":
                headline = "当前远端偏好已关闭远端导出"
            default:
                headline = "检测到远端导出范围受阻"
            }

            return ModelRouteIssueOverride(
                state: .diagnosticRequired,
                headline: headline,
                summary: "最近一次模型路由核对显示付费远端路由被导出开关、设备范围、策略或预算边界挡住了；这不是模型缺失，也不是连接 Hub 没连上。",
                nextStep: "先在 XT 设置 → 诊断与核对 或 `/route diagnose` 记下这次拒绝原因和审计编号；再到 REL Flow Hub → 诊断与恢复检查远端导出开关；如果拒绝原因指向策略、设备边界、预算或用户偏好，再继续去 REL Flow Hub → 安全边界、模型与付费访问，或 XT 的远端偏好入口修复。",
                repairEntry: .hubDiagnostics,
                detailLines: detailLines
            )
        case .paidModelAccessBlocked:
            let normalizedCode = normalizedOptionalDoctorField(evidence.copyCode)?
                .lowercased()
                .replacingOccurrences(of: "-", with: "_") ?? ""
            let headline: String

            switch normalizedCode {
            case "device_paid_model_disabled", "device_paid_model_not_allowed":
                headline = "当前设备不允许使用付费模型"
            case "device_daily_token_budget_exceeded", "device_single_request_token_exceeded":
                headline = "付费模型预算已触顶"
            case "legacy_grant_flow_required":
                headline = "付费模型访问仍停在旧授权链"
            default:
                headline = "检测到付费模型访问受阻"
            }

            return ModelRouteIssueOverride(
                state: .diagnosticRequired,
                headline: headline,
                summary: "最近一次模型路由核对显示付费模型白名单、设备级付费策略或预算把请求挡住了；当前不能再把模型路由显示成已就绪。",
                nextStep: "先到 Supervisor Control Center · AI 模型确认被拦截的模型 ID；再到 REL Flow Hub → 配对与设备信任检查设备的付费模型模式和白名单，必要时到 REL Flow Hub → 模型与付费访问核对预算；修复后回 XT 设置 → 诊断与核对 或 `/route diagnose` 重跑一次路由验证。",
                repairEntry: .xtChooseModel,
                detailLines: detailLines
            )
        default:
            return nil
        }
    }

    private static func supervisorRouteIssueOverride(
        diagnostics: AXModelRouteDiagnosticsSummary,
        projection: AXModelRouteTruthProjection?
    ) -> ModelRouteIssueOverride? {
        let candidateCodes = orderedUnique([
            projection.flatMap { normalizedOptionalDoctorField($0.routeResult.routeReasonCode) },
            projection.flatMap { normalizedOptionalDoctorField($0.routeResult.denyCode) },
            diagnostics.latestEvent.flatMap { normalizedOptionalDoctorField($0.effectiveFailureReasonCode) },
            diagnostics.latestEvent.flatMap { normalizedOptionalDoctorField($0.denyCode) }
        ].compactMap { $0 })

        guard let primaryCode = candidateCodes.first,
              let blockedComponent = supervisorRouteBlockedComponent(for: primaryCode) else {
            return nil
        }

        let reasonText = AXProjectGovernanceRuntimeReadinessSnapshot.reasonText(primaryCode)
        let detailLines = orderedUnique([
            "route_truth_issue=supervisor_route_governance_blocked",
            "route_truth_primary_code=\(primaryCode)",
            "route_truth_supervisor_component=\(blockedComponent.rawValue)"
        ] + (primaryCode.isEmpty ? [] : ["route_truth_deny_code=\(primaryCode)"]))

        switch blockedComponent {
        case .routeReady:
            return ModelRouteIssueOverride(
                state: .diagnosticRequired,
                headline: "Supervisor route 还没就绪",
                summary: "最近一次失败更像 Supervisor 到 XT / runner 的路由面未就绪，不是模型 ID 缺失，也不是 XT 静默改写了模型路由。当前阻塞：\(reasonText)。",
                nextStep: "先看 `/route diagnose` 里的 Supervisor 路由诊断；重点检查 XT 是否在线、preferred device 是否仍可达，以及当前 project scope 是否一致。",
                repairEntry: .xtPairHub,
                detailLines: detailLines
            )
        case .grantReady:
            return ModelRouteIssueOverride(
                state: .diagnosticRequired,
                headline: "Supervisor grant / governance 还没就绪",
                summary: "最近一次失败更像 Supervisor 的治理 / grant 面未就绪；当前不是模型未加载，而是 trusted automation、permission owner 或 kill-switch 这类治理边界挡住了路由。当前阻塞：\(reasonText)。",
                nextStep: "先看 `/route diagnose` 里的 Supervisor 路由诊断；重点检查 trusted automation、permission owner、kill-switch 和当前 project 绑定。",
                repairEntry: .hubDiagnostics,
                detailLines: detailLines
            )
        default:
            return nil
        }
    }

    private static func supervisorRouteBlockedComponent(
        for rawCode: String
    ) -> AXProjectGovernanceRuntimeReadinessComponentKey? {
        let normalizedCode = normalizedOptionalDoctorField(rawCode)?
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") ?? ""
        guard !normalizedCode.isEmpty else { return nil }

        if [
            "preferred_device_offline",
            "preferred_device_missing",
            "xt_device_missing",
            "runner_device_missing",
            "xt_route_ambiguous",
            "runner_route_ambiguous",
            "supervisor_intent_unknown",
            "project_id_required",
            "preferred_device_project_scope_mismatch"
        ].contains(normalizedCode) {
            return .routeReady
        }

        if [
            "device_permission_owner_missing",
            "trusted_automation_mode_off",
            "trusted_automation_project_not_bound",
            "trusted_automation_profile_missing",
            "trusted_automation_workspace_mismatch",
            "trusted_automation_not_ready",
            "runtime_surface_kill_switch",
            "kill_switch_active",
            "runtime_surface_ttl_expired",
            "legacy_grant_flow_required",
            "governance_fail_closed"
        ].contains(normalizedCode) {
            return .grantReady
        }

        return nil
    }

    private struct ModelRouteIssueEvidence {
        let issue: UITroubleshootIssue
        let primaryCode: String
        let copyCode: String
        let denyCode: String?
    }

    private struct GrpcRouteTruthHint {
        let detailCode: String
        let summary: String
        let nextStep: String
    }

    private static func applyGrpcRouteTruthHint(
        to section: inout XTUnifiedDoctorSection,
        diagnostics: AXModelRouteDiagnosticsSummary,
        projection: AXModelRouteTruthProjection?,
        route: XTUnifiedDoctorRouteSnapshot
    ) {
        guard let hint = grpcRouteTruthHint(
            diagnostics: diagnostics,
            projection: projection,
            route: route
        ) else {
            return
        }

        if !section.summary.contains(hint.summary) {
            section.summary = "\(section.summary) \(hint.summary)"
        }

        if !section.nextStep.contains(hint.nextStep) {
            section.nextStep = "\(section.nextStep) \(hint.nextStep)"
        }

        section.detailLines = orderedUnique(
            section.detailLines + ["route_truth_grpc_hint=\(hint.detailCode)"]
        )
    }

    private static func grpcRouteTruthHint(
        diagnostics: AXModelRouteDiagnosticsSummary,
        projection: AXModelRouteTruthProjection?,
        route: XTUnifiedDoctorRouteSnapshot
    ) -> GrpcRouteTruthHint? {
        guard route.transportMode.hasPrefix("remote_grpc") else { return nil }

        let executionPath = normalizedOptionalDoctorField(
            diagnostics.latestEvent?.executionPath
        )?.lowercased() ?? normalizedOptionalDoctorField(
            projection?.routeResult.routeSource
        )?.lowercased() ?? ""

        let primaryCode = normalizedOptionalDoctorField(
            diagnostics.latestEvent?.effectiveFailureReasonCode
        )?.lowercased() ?? normalizedOptionalDoctorField(
            projection?.routeResult.routeReasonCode
        )?.lowercased() ?? ""

        let denyCode = normalizedOptionalDoctorField(
            diagnostics.latestEvent?.denyCode
        )?.lowercased() ?? normalizedOptionalDoctorField(
            projection?.routeResult.denyCode
        )?.lowercased() ?? ""

        let exportGateBlocked = primaryCode.contains("remote_export_blocked")
            || denyCode.contains("remote_export_blocked")

        switch executionPath {
        case "hub_downgraded_to_local":
            if exportGateBlocked {
                return GrpcRouteTruthHint(
                    detailCode: "remote_export_gate_not_xt_rewrite",
                    summary: "当前传输已经是远端 gRPC；如果最近仍落到本地，更像是 Hub 的远端导出闸门或策略把付费远端调用挡住了，不是 XT 把模型静默改成了本地。",
                    nextStep: "优先去 Hub 审计看 `remote_export_blocked`，再决定是否调整 XT 模型设置。"
                )
            }

            return GrpcRouteTruthHint(
                detailCode: "hub_downgrade_not_xt_rewrite",
                summary: "当前传输已经是远端 gRPC；如果最近仍落到本地，更像是 Hub 在执行阶段主动降级，或远端导出闸门生效，不是 XT 把模型静默改成了本地。",
                nextStep: "优先去 Hub 审计看 `ai.generate.downgraded_to_local` / `remote_export_blocked`，不要先怀疑 XT 设置页偷偷改了模型。"
            )
        case "local_fallback_after_remote_error":
            if exportGateBlocked {
                return GrpcRouteTruthHint(
                    detailCode: "remote_export_gate_not_xt_rewrite",
                    summary: "当前传输已经是远端 gRPC；如果最近仍落到本地，更像是 Hub 的远端导出闸门或策略把付费远端调用挡住了，不是 XT 把模型静默改成了本地。",
                    nextStep: "优先去 Hub 审计看 `remote_export_blocked`，再决定是否调整 XT 模型设置。"
                )
            }

            return GrpcRouteTruthHint(
                    detailCode: "upstream_remote_failure_not_xt_rewrite",
                summary: "当前传输已经是远端 gRPC；如果最近仍落到本地，更像上游远端不可用、提供方未就绪，或执行链失败，不是 XT 静默改成本地。",
                nextStep: "优先检查 Hub 和上游远端链路，再决定是否继续改 XT 模型设置。"
            )
        case "remote_error":
            return GrpcRouteTruthHint(
                detailCode: "failed_remote_attempt_not_xt_rewrite",
                summary: "当前传输已经是远端 gRPC；最近停在失败态说明 XT 没有把请求静默改成本地，优先检查 Hub 和上游远端链路。",
                nextStep: "优先在 Hub 审计和上游服务方状态里定位失败码，再决定是否改 XT 模型设置。"
            )
        default:
            return nil
        }
    }

    private static func modelRouteIssueEvidence(
        diagnostics: AXModelRouteDiagnosticsSummary,
        projection: AXModelRouteTruthProjection?
    ) -> ModelRouteIssueEvidence? {
        let candidateCodes = orderedUnique([
            projection.flatMap { normalizedOptionalDoctorField($0.routeResult.routeReasonCode) },
            projection.flatMap { normalizedOptionalDoctorField($0.routeResult.denyCode) },
            projection.flatMap { normalizedOptionalDoctorField($0.routeResult.fallbackReason) },
            diagnostics.latestEvent.flatMap { normalizedOptionalDoctorField($0.effectiveFailureReasonCode) },
            diagnostics.latestEvent.flatMap { normalizedOptionalDoctorField($0.denyCode) }
        ].compactMap { $0 })

        guard let primaryCode = candidateCodes.first(where: { code in
            guard let issue = UITroubleshootKnowledgeBase.issue(forFailureCode: code) else {
                return false
            }
            switch issue {
            case .modelNotReady, .connectorScopeBlocked, .paidModelAccessBlocked:
                return true
            default:
                return false
            }
        }), let issue = UITroubleshootKnowledgeBase.issue(forFailureCode: primaryCode) else {
            return nil
        }

        let explicitDenyCode = normalizedOptionalDoctorField(
            projection?.routeResult.denyCode
        ) ?? normalizedOptionalDoctorField(diagnostics.latestEvent?.denyCode)
        let copyCode = explicitDenyCode.flatMap { denyCode in
            UITroubleshootKnowledgeBase.issue(forFailureCode: denyCode) == issue ? denyCode : nil
        } ?? primaryCode

        return ModelRouteIssueEvidence(
            issue: issue,
            primaryCode: primaryCode,
            copyCode: copyCode,
            denyCode: explicitDenyCode
        )
    }

    private static func normalizeModelRoutePosture(
        _ base: XTUnifiedDoctorSection,
        localInteractiveLoadedCount: Int,
        remoteInteractiveLoadedCount: Int
    ) -> XTUnifiedDoctorSection {
        var section = base
        let interactivePosture: String
        switch (localInteractiveLoadedCount > 0, remoteInteractiveLoadedCount > 0) {
        case (true, false):
            interactivePosture = "local_only"
        case (false, true):
            interactivePosture = "remote_only"
        case (true, true):
            interactivePosture = "mixed"
        case (false, false):
            interactivePosture = "none"
        }

        section.detailLines = orderedUnique(
            section.detailLines + [
                "interactive_local_loaded=\(localInteractiveLoadedCount)",
                "interactive_remote_loaded=\(remoteInteractiveLoadedCount)",
                "interactive_posture=\(interactivePosture)"
            ]
        )

        guard section.state == .ready, interactivePosture == "local_only" else {
            return section
        }

        section.headline = "模型路由已就绪（纯本地）"
        section.summary = "XT 当前只看到本地对话模型，这本身不是异常；即使没有云端服务或 API key，也可以继续完成首个任务。"
        section.nextStep = "如果你只需要本地路径，直接继续做桥接 / 工具链验证；只有你要远端 GPT 或云能力时，再去补远端模型。"
        return section
    }

    private static func buildBridgeToolFallback(
        localConnected: Bool,
        remoteConnected: Bool,
        hubInteractive: Bool,
        modelRouteReady: Bool,
        bridgeAlive: Bool,
        bridgeEnabled: Bool,
        bridgeLastError: String,
        route: XTUnifiedDoctorRouteSnapshot
    ) -> XTUnifiedDoctorSection {
        let remoteToolRoute = remoteConnected && !localConnected
        let toolRouteExecutable = toolRouteExecutable(
            localConnected: localConnected,
            remoteConnected: remoteConnected,
            bridgeAlive: bridgeAlive,
            bridgeEnabled: bridgeEnabled
        )
        let normalizedBridgeLastError = bridgeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = [
            "bridge_alive=\(bridgeAlive)",
            "bridge_enabled=\(bridgeEnabled)",
            "tool_route_executable=\(toolRouteExecutable)",
            "active_route=\(route.routeLabel)",
            "remote_tool_route=\(remoteToolRoute)"
        ] + (normalizedBridgeLastError.isEmpty ? [] : ["bridge_last_error=\(normalizedBridgeLastError)"])

        if !hubInteractive {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .blockedWaitingUpstream,
                headline: "工具链路正在等待 Hub 可达",
                summary: "在 X-Terminal 建立可用的 Hub 连接路径之前，桥接和工具执行都无法被验证。",
                nextStep: "先完成连接 Hub，再回来重新检查当前状态。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if remoteToolRoute {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .ready,
                headline: "远端 Hub 工具主链已就绪",
                summary: "当前主链走远端 gRPC。即使本机桥接心跳缺失，也不会阻塞远端授权与远端工具调用。",
                nextStep: "继续在当前远端主链上做会话运行时验证。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeAlive {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                headline: modelRouteReady ? "模型路由已通，但桥接 / 工具链路不可用" : "桥接 / 工具链路不可用",
                summary: normalizedBridgeLastError.isEmpty
                    ? "Hub 已可达，但桥接心跳缺失，所以工具调用会继续被拦住，不会假装已经恢复。"
                    : "Hub 已可达，但桥接心跳缺失，而且上一次启用桥接的请求也失败了，所以工具调用会继续被拦住，不会假装已经恢复。",
                nextStep: normalizedBridgeLastError.isEmpty
                    ? "打开 Hub 诊断与恢复，必要时重启桥接，然后回来重新检查当前状态。"
                    : "打开 Hub 诊断与恢复，先修桥接请求链路，必要时重启桥接，然后回来重新检查当前状态。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeEnabled {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                headline: "桥接进程已在，但工具执行窗口未启用",
                summary: normalizedBridgeLastError.isEmpty
                    ? "桥接进程已经存在，但当前执行窗口没有激活，所以工具还不能真正执行。"
                    : "桥接进程已经存在，但当前执行窗口没有激活，而且上一次启用工具窗口的请求还报告了投递失败。",
                nextStep: normalizedBridgeLastError.isEmpty
                    ? "执行重连自检，或重新启用工具窗口，然后再验证工具。"
                    : "先修桥接命令投递链路，再重新启用工具窗口并重新验证工具。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .bridgeToolReadiness,
            state: .ready,
            headline: "桥接 / 工具链路已就绪",
            summary: "Bridge heartbeat 正常，执行窗口也已启用，因此工具调用可以通过当前 Hub 链路执行。",
            nextStep: "继续在同一路径上做会话运行时验证。",
            repairEntry: .hubDiagnostics,
            detailLines: details
        )
    }

    private static func toolRouteExecutable(
        localConnected: Bool,
        remoteConnected: Bool,
        bridgeAlive: Bool,
        bridgeEnabled: Bool
    ) -> Bool {
        if localConnected {
            return bridgeAlive && bridgeEnabled
        }
        if remoteConnected {
            return true
        }
        return false
    }

    private static func buildSessionRuntimeFallback(
        toolRouteExecutable: Bool,
        sessionID: String?,
        sessionTitle: String?,
        runtime: AXSessionRuntimeSnapshot?
    ) -> XTUnifiedDoctorSection {
        let snapshot = runtime ?? AXSessionRuntimeSnapshot.idle()
        let details = [
            sessionID == nil ? "session_id=none" : "session_id=\(sessionID!)",
            sessionTitle == nil ? "session_title=none" : "session_title=\(sessionTitle!)",
            "state=\(snapshot.state.rawValue)",
            "recoverable=\(snapshot.recoverable)",
            "pending_tool_calls=\(snapshot.pendingToolCallCount)",
            snapshot.lastFailureCode?.isEmpty == false ? "last_failure_code=\(snapshot.lastFailureCode!)" : "last_failure_code=none",
            snapshot.resumeToken?.isEmpty == false ? "resume_token_present=true" : "resume_token_present=false"
        ]

        if !toolRouteExecutable {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .blockedWaitingUpstream,
                headline: "会话运行时正在等待工具链路变为可执行",
                summary: "在桥接和工具层准备好之前，运行时验证必须保持阻塞，而不是假装会话已经能自行恢复。",
                nextStep: "先修复桥接和工具的就绪状态，再回来重新检查当前状态。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.state == .failed_recoverable && !snapshot.recoverable {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .diagnosticRequired,
                headline: "桥接已通，但会话运行时不可恢复",
                summary: "运行时进入了失败状态，但没有有效恢复路径。这个问题必须与桥接或模型路由问题分开看待。",
                nextStep: "打开 XT 设置 → 诊断与核对，检查最后一次失败代码，然后先重建或修复受影响会话，再继续。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.state == .failed_recoverable {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                headline: "会话运行时存在可恢复失败路径",
                summary: "当前会话暂停在一个可恢复失败之后。虽然存在恢复路径，但整体验证还没有完成。",
                nextStep: "走恢复路径或重跑被阻塞的请求，然后确认运行时是否回到稳定完成状态。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.pendingToolCallCount > 0 || runtimeBusy(snapshot.state) {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                headline: "会话运行时当前处于活动中",
                summary: "运行时当前正在处理或等待某一步完成。验证应当等它回到稳定状态后再做。",
                nextStep: "等当前会话活动结束，再回来重新检查当前状态。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if sessionID == nil {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .ready,
                headline: "会话运行时基础已就绪",
                summary: "当前还没有主会话，但运行时基础处于空闲稳定状态，已经可以在第一个任务到来时创建主会话。",
                nextStep: "直接开始第一个任务，在已验证的路由上创建主会话。",
                repairEntry: .homeSupervisor,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "会话运行时已就绪",
            summary: "当前会话处于稳定状态，可以在已验证的路由上恢复正常工作。",
            nextStep: "不用切页，直接继续进入首个任务即可。",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func enrichSessionRuntimeSection(
        _ base: XTUnifiedDoctorSection,
        diagnostics: AXProjectContextAssemblyDiagnosticsSummary,
        governance: AXProjectResolvedGovernanceState?,
        heartbeatGovernanceSnapshot: XTProjectHeartbeatGovernanceDoctorSnapshot?,
        memoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot?,
        turnContextAssembly: SupervisorTurnContextAssemblyResult?,
        projectContext: AXProjectContext?
    ) -> XTUnifiedDoctorSection {
        var section = base
        var detailLines = base.detailLines
        let projectMemoryReadiness = diagnostics.memoryAssemblyReadiness

        if let governance {
            section.projectGovernanceRuntimeReadinessProjection = governance.runtimeReadinessSnapshot
            detailLines += governance.runtimeReadinessSnapshot.detailLines()
        }
        if !diagnostics.detailLines.isEmpty {
            section.projectContextPresentation = diagnostics.presentation
            section.projectMemoryPolicyProjection = diagnostics.projectMemoryPolicy
            section.projectMemoryReadinessProjection = projectMemoryReadiness
            section.projectMemoryAssemblyResolutionProjection = diagnostics.memoryAssemblyResolution
            section.hubMemoryPromptProjection = diagnostics.hubMemoryPromptProjection
            detailLines += diagnostics.detailLines
            detailLines += projectMemoryReadiness.detailLines()
        }
        section.projectRemoteSnapshotCacheProjection = projectRemoteSnapshotCacheProjection(from: diagnostics)
        if let heartbeatGovernanceSnapshot {
            section.heartbeatGovernanceProjection = XTUnifiedDoctorHeartbeatGovernanceProjection(
                snapshot: heartbeatGovernanceSnapshot,
                projectMemoryReadiness: projectMemoryReadiness
            )
            detailLines += heartbeatGovernanceSnapshot.detailLines(
                projectMemoryReadiness: projectMemoryReadiness
            )
        }
        if let memoryAssemblySnapshot {
            section.supervisorMemoryPolicyProjection = memoryAssemblySnapshot.supervisorMemoryPolicy
            section.supervisorMemoryAssemblyResolutionProjection = memoryAssemblySnapshot.actualizedMemoryAssemblyResolution
            section.supervisorGuidanceContinuityProjection = XTUnifiedDoctorSupervisorGuidanceContinuityProjection(
                snapshot: memoryAssemblySnapshot
            )
            section.supervisorRemoteSnapshotCacheProjection = supervisorRemoteSnapshotCacheProjection(
                from: memoryAssemblySnapshot
            )
            detailLines += memoryAssemblySnapshot.continuityDrillDownLines
        }
        if let governance,
           let projectContext,
           let reviewTriggerProjection = XTUnifiedDoctorSupervisorReviewTriggerProjection(
                governance: governance,
                heartbeatSnapshot: heartbeatGovernanceSnapshot,
                ctx: projectContext
           ) {
            section.supervisorReviewTriggerProjection = reviewTriggerProjection
            detailLines += reviewTriggerProjection.detailLines()
        }
        if let projectContext,
           let safePointProjection = XTUnifiedDoctorSupervisorSafePointTimelineProjection(ctx: projectContext) {
            section.supervisorSafePointTimelineProjection = safePointProjection
            detailLines += safePointProjection.detailLines()
        }
        detailLines += supervisorTurnContextDetailLines(turnContextAssembly)
        if let mirrorProjection = durableCandidateMirrorProjection(from: memoryAssemblySnapshot) {
            section.durableCandidateMirrorProjection = mirrorProjection
            detailLines.append(mirrorProjection.detailLine)
        }
        if let localStoreWriteProjection = localStoreWriteProjection(from: memoryAssemblySnapshot) {
            section.localStoreWriteProjection = localStoreWriteProjection
            detailLines.append(localStoreWriteProjection.detailLine)
        }
        guard detailLines != base.detailLines
                || section.projectContextPresentation != nil
                || section.projectGovernanceRuntimeReadinessProjection != nil
                || section.projectMemoryPolicyProjection != nil
                || section.projectMemoryReadinessProjection != nil
                || section.projectMemoryAssemblyResolutionProjection != nil
                || section.projectRemoteSnapshotCacheProjection != nil
                || section.heartbeatGovernanceProjection != nil
                || section.supervisorMemoryPolicyProjection != nil
                || section.supervisorMemoryAssemblyResolutionProjection != nil
                || section.supervisorReviewTriggerProjection != nil
                || section.supervisorGuidanceContinuityProjection != nil
                || section.supervisorSafePointTimelineProjection != nil
                || section.supervisorRemoteSnapshotCacheProjection != nil
                || section.hubMemoryPromptProjection != nil
                || section.durableCandidateMirrorProjection != nil
                || section.localStoreWriteProjection != nil else {
            return base
        }
        section.detailLines = orderedUnique(detailLines)
        return section
    }

    private static func supervisorTurnContextDetailLines(
        _ assembly: SupervisorTurnContextAssemblyResult?
    ) -> [String] {
        guard let assembly else { return [] }

        let supportingPlanes = assembly.supportingPlanes
            .map(supervisorTurnContextToken)
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        let requestedSlots = assembly.requestedSlots
            .map(\.rawValue)
            .joined(separator: ",")
        let selectedSlots = assembly.selectedSlots
            .map(\.rawValue)
            .joined(separator: ",")
        let omittedSlots = assembly.omittedSlots
            .map(\.rawValue)
            .joined(separator: ",")
        let requestedRefs = assembly.requestedRefs.joined(separator: ",")
        let selectedRefs = assembly.selectedRefs.joined(separator: ",")

        return [
            [
                "supervisor_turn_context",
                "turn_mode=\(assembly.turnMode.rawValue)",
                "dominant_plane=\(supervisorTurnContextToken(assembly.dominantPlane))",
                "supporting_planes=\(supportingPlanes.isEmpty ? "none" : supportingPlanes)",
                "continuity_depth=\(assembly.continuityLaneDepth.rawValue)",
                "assistant_depth=\(assembly.assistantPlaneDepth.rawValue)",
                "project_depth=\(assembly.projectPlaneDepth.rawValue)",
                "cross_link_depth=\(assembly.crossLinkPlaneDepth.rawValue)",
                "requested_slots=\(requestedSlots.isEmpty ? "none" : requestedSlots)",
                "selected_slots=\(selectedSlots.isEmpty ? "none" : selectedSlots)",
                "omitted_requested_slots=\(omittedSlots.isEmpty ? "none" : omittedSlots)",
                "requested_refs=\(requestedRefs.isEmpty ? "none" : requestedRefs)",
                "selected_refs=\(selectedRefs.isEmpty ? "none" : selectedRefs)"
            ].joined(separator: " ")
        ]
    }

    private static func supervisorTurnContextToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }

    private static func durableCandidateMirrorProjection(
        from snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> XTUnifiedDoctorDurableCandidateMirrorProjection? {
        guard let snapshot else { return nil }
        let status = snapshot.durableCandidateMirrorStatus
        guard snapshot.durableCandidateMirrorAttempted || status != .notNeeded else {
            return nil
        }
        return XTUnifiedDoctorDurableCandidateMirrorProjection(
            status: status,
            target: normalizedDoctorField(
                snapshot.durableCandidateMirrorTarget,
                fallback: XTSupervisorDurableCandidateMirror.mirrorTarget
            ),
            attempted: snapshot.durableCandidateMirrorAttempted,
            errorCode: normalizedOptionalDoctorField(snapshot.durableCandidateMirrorErrorCode),
            localStoreRole: normalizedDoctorField(
                snapshot.durableCandidateLocalStoreRole,
                fallback: XTSupervisorDurableCandidateMirror.localStoreRole
            )
        )
    }

    private static func projectRemoteSnapshotCacheProjection(
        from diagnostics: AXProjectContextAssemblyDiagnosticsSummary
    ) -> XTUnifiedDoctorRemoteSnapshotCacheProjection? {
        let detailLines = diagnostics.detailLines
        // Avoid repeatedly materializing the large latestEvent value on the
        // cooperative test runner stack. In debug builds that path can blow the
        // thread stack before the first doctor test even reaches its assertions.
        let latestEvent = diagnostics.latestEvent
        let source = latestEvent?.memoryV1Source
            ?? detailValue("project_memory_v1_source", from: detailLines)
        let freshness = latestEvent?.memoryV1Freshness
            ?? detailValue("memory_v1_freshness", from: detailLines)
        let cacheHit = latestEvent?.memoryV1CacheHit
            ?? detailBoolValue("memory_v1_cache_hit", from: detailLines)
        let scope = latestEvent?.remoteSnapshotCacheScope
            ?? detailValue("memory_v1_remote_snapshot_cache_scope", from: detailLines)
        let cachedAtMs = latestEvent?.remoteSnapshotCachedAtMs
            ?? detailInt64Value("memory_v1_remote_snapshot_cached_at_ms", from: detailLines)
        let ageMs = latestEvent?.remoteSnapshotAgeMs
            ?? detailIntValue("memory_v1_remote_snapshot_age_ms", from: detailLines)
        let ttlRemainingMs = latestEvent?.remoteSnapshotTTLRemainingMs
            ?? detailIntValue("memory_v1_remote_snapshot_ttl_remaining_ms", from: detailLines)
        let cachePosture = latestEvent?.remoteSnapshotCachePosture
            ?? detailValue("memory_v1_remote_snapshot_cache_posture", from: detailLines)
        let invalidationReason = latestEvent?.remoteSnapshotInvalidationReason
            ?? detailValue("memory_v1_remote_snapshot_invalidation_reason", from: detailLines)

        return XTUnifiedDoctorRemoteSnapshotCacheProjection(
            source: source,
            freshness: freshness,
            cacheHit: cacheHit,
            scope: scope,
            cachedAtMs: cachedAtMs,
            ageMs: ageMs,
            ttlRemainingMs: ttlRemainingMs,
            cachePosture: cachePosture,
            invalidationReason: invalidationReason
        )
    }

    private static func supervisorRemoteSnapshotCacheProjection(
        from snapshot: SupervisorMemoryAssemblySnapshot
    ) -> XTUnifiedDoctorRemoteSnapshotCacheProjection? {
        XTUnifiedDoctorRemoteSnapshotCacheProjection(
            source: snapshot.source,
            freshness: snapshot.freshness,
            cacheHit: snapshot.cacheHit,
            scope: snapshot.remoteSnapshotCacheScope,
            cachedAtMs: snapshot.remoteSnapshotCachedAtMs,
            ageMs: snapshot.remoteSnapshotAgeMs,
            ttlRemainingMs: snapshot.remoteSnapshotTTLRemainingMs,
            cachePosture: snapshot.remoteSnapshotCachePosture,
            invalidationReason: snapshot.remoteSnapshotInvalidationReason
        )
    }

    private static func localStoreWriteProjection(
        from snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> XTUnifiedDoctorLocalStoreWriteProjection? {
        guard let snapshot else { return nil }
        let projection = XTUnifiedDoctorLocalStoreWriteProjection(
            personalMemoryIntent: normalizedOptionalDoctorField(snapshot.localPersonalMemoryWriteIntent),
            crossLinkIntent: normalizedOptionalDoctorField(snapshot.localCrossLinkWriteIntent),
            personalReviewIntent: normalizedOptionalDoctorField(snapshot.localPersonalReviewWriteIntent)
        )
        return projection.hasAnyIntent ? projection : nil
    }

    private static func detailValue(_ key: String, from detailLines: [String]) -> String? {
        guard let line = detailLines.first(where: { $0.hasPrefix("\(key)=") }) else {
            return nil
        }
        return String(line.dropFirst(key.count + 1))
    }

    private static func detailBoolValue(_ key: String, from detailLines: [String]) -> Bool? {
        switch normalizedOptionalDoctorField(detailValue(key, from: detailLines))?.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func detailIntValue(_ key: String, from detailLines: [String]) -> Int? {
        guard let raw = normalizedOptionalDoctorField(detailValue(key, from: detailLines)) else {
            return nil
        }
        return Int(raw)
    }

    private static func detailInt64Value(_ key: String, from detailLines: [String]) -> Int64? {
        guard let raw = normalizedOptionalDoctorField(detailValue(key, from: detailLines)) else {
            return nil
        }
        return Int64(raw)
    }

    private static func buildCalendarReminderSection(
        snapshot: XTUnifiedDoctorCalendarReminderSnapshot
    ) -> XTUnifiedDoctorSection {
        let guidance = snapshot.authorizationGuidanceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let schedulerStatus = snapshot.schedulerStatusLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let eventStoreStatus = snapshot.eventStoreStatusLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let previewLines = snapshot.upcomingMeetingPreviewLines.enumerated().map { index, line in
            "calendar_meeting_\(index + 1)=\(line)"
        }
        let details = orderedUnique(
            [
                "calendar_permission_owner=xt_device_local",
                "hub_calendar_permission=request_blocked",
                "raw_calendar_event_visibility=device_local_only",
                "calendar_reminders_enabled=\(snapshot.enabled)",
                "calendar_authorization=\(snapshot.authorizationStatus.rawValue)",
                "calendar_authorization_can_read=\(snapshot.authorizationStatus.canReadEvents)",
                guidance.isEmpty ? "calendar_authorization_guidance=none" : "calendar_authorization_guidance=\(guidance)",
                "calendar_heads_up_minutes=\(snapshot.headsUpMinutes)",
                "calendar_final_call_minutes=\(snapshot.finalCallMinutes)",
                "calendar_notification_fallback_enabled=\(snapshot.notificationFallbackEnabled)",
                snapshot.schedulerLastRunAtMs > 0
                    ? "calendar_scheduler_last_run_ms=\(snapshot.schedulerLastRunAtMs)"
                    : "calendar_scheduler_last_run_ms=0",
                schedulerStatus.isEmpty
                    ? "calendar_scheduler_status=unknown"
                    : "calendar_scheduler_status=\(schedulerStatus)",
                snapshot.eventStoreLastRefreshedAtMs > 0
                    ? "calendar_snapshot_last_refresh_ms=\(snapshot.eventStoreLastRefreshedAtMs)"
                    : "calendar_snapshot_last_refresh_ms=0",
                eventStoreStatus.isEmpty
                    ? "calendar_snapshot_status=unknown"
                    : "calendar_snapshot_status=\(eventStoreStatus)",
                "calendar_upcoming_meeting_count=\(snapshot.upcomingMeetingCount)"
            ] + previewLines
        )

        if !snapshot.enabled {
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .ready,
                headline: "XT 自管的日历提醒当前按你的设置保持关闭",
                summary: "Hub 已不再请求 Calendar 权限。个人会议提醒继续只保留在这台 X-Terminal 本机上，现在只是按设置关闭，并不是坏了。",
                nextStep: "如果你想在这台设备上开启会议提醒，去 Supervisor Settings -> Calendar Reminders 运行本地 smoke 动作即可。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        switch snapshot.authorizationStatus {
        case .notDetermined:
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .inProgress,
                headline: "日历提醒已开启，但 XT 还没有日历权限",
                summary: "提醒链路已经打开，但在这台设备授予 Calendar 权限之前，XT 还读不到本地会议。",
                nextStep: "先在 macOS 系统设置里给 X-Terminal 授予 Calendar 权限，然后刷新会议并重跑 live delivery smoke。",
                repairEntry: .systemPermissions,
                detailLines: details
            )
        case .denied, .writeOnly:
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .permissionDenied,
                headline: "当前权限状态下，日历提醒还读不到会议",
                summary: guidance.isEmpty
                    ? "X-Terminal 现在还不能读取 Calendar 事件，所以 Supervisor 的会议提醒在这台设备上必须继续保持阻塞。"
                    : guidance,
                nextStep: "先在 macOS 系统设置里恢复 Calendar 读取权限，再运行 Refresh Meetings，并补一次 live reminder smoke。",
                repairEntry: .systemPermissions,
                detailLines: details
            )
        case .restricted, .unavailable:
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .blockedWaitingUpstream,
                headline: "日历提醒被系统可用性或策略拦住了",
                summary: guidance.isEmpty
                    ? "这台 XT 设备当前还不能向 Supervisor 提供可读取的 Calendar 事件。"
                    : guidance,
                nextStep: "先解决系统层面的 Calendar 限制，再刷新 XT 的提醒快照。",
                repairEntry: .systemPermissions,
                detailLines: details
            )
        case .authorized, .fullAccess:
            if snapshot.upcomingMeetingCount > 0 {
                return XTUnifiedDoctorSection(
                    kind: .calendarReminderReadiness,
                    state: .ready,
                    headline: "XT 日历提醒已就绪，并拿到了本地会议快照",
                    summary: "XT 已在这台设备上持有 Calendar 权限，提醒调度器也在运行，临近会议可以直接在本机可见，不需要把原始事件再绕回 Hub。",
                    nextStep: "先运行一次 Simulate Live Delivery，再在这台 XT 设备上核对一笔真实的临近会议。",
                    repairEntry: .xtDiagnostics,
                    detailLines: details
                )
            }
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .ready,
                headline: "XT 日历提醒已就绪，但暂时没有临近会议",
                summary: "这台设备上的 Calendar 权限和提醒调度器都正常，只是当前本地快照里还没有临近会议。",
                nextStep: "现在先运行 Preview Voice Reminder / Test Notification Fallback / Simulate Live Delivery，然后创建一笔临近测试会议做端到端验证。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }
    }

    private static func buildSkillsCompatibilitySection(
        hubInteractive: Bool,
        snapshot: AXSkillsDoctorSnapshot,
        skillDoctorTruthProjection: XTUnifiedDoctorSkillDoctorTruthProjection?
    ) -> XTUnifiedDoctorSection {
        let projectRefs = snapshot.projectIndexEntries.map(\.path)
        let globalRefs = snapshot.globalIndexEntries.map(\.path)
        let activePublishers = snapshot.activePublisherIDs
        let activeSources = snapshot.activeSourceIDs
        let baselinePublishers = snapshot.baselinePublisherIDs
        let builtinPreview = snapshot.builtinGovernedSkillIDs.prefix(5)
        let details = [
            "hub_index_available=\(snapshot.hubIndexAvailable)",
            "installed_skills=\(snapshot.installedSkillCount)",
            "compatible_skills=\(snapshot.compatibleSkillCount)",
            "partial_skills=\(snapshot.partialCompatibilityCount)",
            "revoked_matches=\(snapshot.revokedMatchCount)",
            "trusted_publishers=\(snapshot.trustEnabledPublisherCount)",
            "xt_builtin_governed_skills=\(snapshot.builtinGovernedSkillCount)",
            builtinPreview.isEmpty ? "xt_builtin_governed_preview=none" : "xt_builtin_governed_preview=\(builtinPreview.joined(separator: ","))",
            "xt_builtin_supervisor_voice=\(snapshot.builtinSupervisorVoiceAvailable ? "available" : "missing")",
            snapshot.officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel=unknown"
                : "official_channel=\(snapshot.officialChannelStatus)",
            "official_channel_skills=\(snapshot.officialChannelSkillCount)",
            snapshot.officialChannelLastSuccessAtMs > 0
                ? "official_channel_last_success_ms=\(snapshot.officialChannelLastSuccessAtMs)"
                : "official_channel_last_success_ms=0",
            "official_channel_maintenance_enabled=\(snapshot.officialChannelMaintenanceEnabled)",
            "official_channel_maintenance_interval_ms=\(snapshot.officialChannelMaintenanceIntervalMs)",
            snapshot.officialChannelMaintenanceLastRunAtMs > 0
                ? "official_channel_maintenance_last_run_ms=\(snapshot.officialChannelMaintenanceLastRunAtMs)"
                : "official_channel_maintenance_last_run_ms=0",
            snapshot.officialChannelMaintenanceSourceKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel_maintenance_source=unknown"
                : "official_channel_maintenance_source=\(snapshot.officialChannelMaintenanceSourceKind)",
            snapshot.officialChannelLastTransitionAtMs > 0
                ? "official_channel_last_transition_ms=\(snapshot.officialChannelLastTransitionAtMs)"
                : "official_channel_last_transition_ms=0",
            snapshot.officialChannelLastTransitionKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel_last_transition_kind=none"
                : "official_channel_last_transition_kind=\(snapshot.officialChannelLastTransitionKind)",
            snapshot.officialChannelLastTransitionSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel_last_transition_summary=none"
                : "official_channel_last_transition_summary=\(snapshot.officialChannelLastTransitionSummary)",
            snapshot.officialChannelErrorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel_error=none"
                : "official_channel_error=\(snapshot.officialChannelErrorCode)",
            activePublishers.isEmpty ? "active_publishers=none" : "active_publishers=\(activePublishers.joined(separator: ","))",
            activeSources.isEmpty ? "active_sources=none" : "active_sources=\(activeSources.joined(separator: ","))",
            "local_dev_publisher_active=\(snapshot.localDevPublisherActive ? "yes" : "no")",
            snapshot.baselineRecommendedSkills.isEmpty
                ? "baseline_publishers=none"
                : (baselinePublishers.isEmpty ? "baseline_publishers=none" : "baseline_publishers=\(baselinePublishers.joined(separator: ","))"),
            snapshot.baselineRecommendedSkills.isEmpty
                ? "baseline_local_dev=0/0"
                : "baseline_local_dev=\(snapshot.baselineLocalDevSkillCount)/\(snapshot.baselineRecommendedSkills.count)",
            snapshot.missingBaselineSkillIDs.isEmpty
                ? "baseline_missing=none"
                : "baseline_missing=\(snapshot.missingBaselineSkillIDs.joined(separator: ","))",
            projectRefs.isEmpty ? "project_indexes=none" : "project_indexes=\(projectRefs.joined(separator: ","))",
            globalRefs.isEmpty ? "global_indexes=none" : "global_indexes=\(globalRefs.joined(separator: ","))"
        ] + skillDoctorTruthDetailLines(skillDoctorTruthProjection)

        func makeSection(
            state: XTUISurfaceState,
            headline: String,
            summary: String,
            nextStep: String,
            extraDetailLines: [String] = []
        ) -> XTUnifiedDoctorSection {
            XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: state,
                headline: headline,
                summary: summary,
                nextStep: nextStep,
                repairEntry: .xtDiagnostics,
                detailLines: details + extraDetailLines,
                skillDoctorTruthProjection: skillDoctorTruthProjection
            )
        }

        if !snapshot.hubIndexAvailable {
            return makeSection(
                state: hubInteractive ? .diagnosticRequired : .blockedWaitingUpstream,
                headline: hubInteractive ? "Hub 技能索引暂时不可用" : "技能兼容性正在等待 Hub 可达",
                summary: hubInteractive
                    ? "Hub 控制面已经可达，但技能索引还不可读，所以这部分兼容性会继续先拦住。XT 原生内置技能仍可用。"
                    : "在 Hub 可达恢复前，XT 还无法验证托管技能的兼容性。XT 原生内置技能仍可用。",
                nextStep: "先刷新 Hub 技能索引，再重新打开当前项目或全局技能索引，然后再依赖托管技能。"
            )
        }

        if snapshot.revokedMatchCount > 0 {
            return makeSection(
                state: .diagnosticRequired,
                headline: "已安装技能里包含被撤销来源",
                summary: "至少有一个已安装或已固定来源的技能命中了被撤销的包或发布者，所以当前兼容性还不能算已就绪。",
                nextStep: "移除这些被撤销的技能，或重新固定到正确来源，然后重新打开技能索引并重新检查当前状态。",
                extraDetailLines: Array(snapshot.conflictWarnings.prefix(3))
            )
        }

        if !snapshot.missingBaselineSkillIDs.isEmpty {
            let missing = snapshot.missingBaselineSkillIDs.joined(separator: ", ")
            return makeSection(
                state: .inProgress,
                headline: "默认技能基线还不完整",
                summary: "XT 已经可达，也基本兼容，可以继续往下走；但托管技能集合里仍缺少一个或多个默认基线技能。XT 原生内置技能仍可用，包含已提供的语音 Supervisor，无需额外固定来源。",
                nextStep: "先导入并启用缺失的基线技能，再重新固定项目或全局配置。缺失项：\(missing)。"
            )
        }

        if snapshot.partialCompatibilityCount > 0 || !snapshot.conflictWarnings.isEmpty {
            return makeSection(
                state: .inProgress,
                headline: "技能兼容性已部分就绪",
                summary: "托管技能已经存在，但至少还有一个包需要继续做兼容性清理，或解决固定来源冲突。XT 原生内置技能仍可并行使用。",
                nextStep: "在默认认为所有托管技能都能稳定运行前，先复核项目 / 全局技能索引。",
                extraDetailLines: Array(snapshot.conflictWarnings.prefix(3))
            )
        }

        if let skillDoctorTruthProjection {
            let runnableProfiles = doctorListSummary(
                skillDoctorTruthProjection.effectiveProfileSnapshot.runnableNowProfiles,
                empty: "none"
            )
            let grantPreview = doctorSkillPreviewSummary(
                skillDoctorTruthProjection.grantRequiredSkillPreview
            )
            let approvalPreview = doctorSkillPreviewSummary(
                skillDoctorTruthProjection.approvalRequiredSkillPreview
            )
            let blockedPreview = doctorSkillPreviewSummary(
                skillDoctorTruthProjection.blockedSkillPreview
            )

            if skillDoctorTruthProjection.blockedSkillCount > 0 {
                return makeSection(
                    state: .diagnosticRequired,
                    headline: "技能 doctor truth 已发现不可运行项",
                    summary: "技能兼容性表面已经可读，但 typed capability/readiness 仍显示 \(skillDoctorTruthProjection.blockedSkillCount) 个技能当前不可运行。当前项目可直接运行的 profiles：\(runnableProfiles)。",
                    nextStep: "先在 Skills Governance 里处理这些不可运行项，优先核对 \(blockedPreview) 的 deny reason、grant floor、approval floor 和 unblock actions。"
                )
            }

            if skillDoctorTruthProjection.grantRequiredSkillCount > 0
                || skillDoctorTruthProjection.approvalRequiredSkillCount > 0 {
                return makeSection(
                    state: .inProgress,
                    headline: "技能 capability 已算清，但仍有待放行项",
                    summary: "当前项目的 effective skill profile 已算出，但还有 \(skillDoctorTruthProjection.grantRequiredSkillCount) 个技能待 Hub grant、\(skillDoctorTruthProjection.approvalRequiredSkillCount) 个技能待本地确认。当前可直接运行的 profiles：\(runnableProfiles)。",
                    nextStep: "先完成待 grant / local approval 的技能放行，再把这些能力当成 runnable_now。优先处理：\(doctorNonEmptySummaries([grantPreview, approvalPreview], fallback: "待放行技能"))."
                )
            }
        }

        return makeSection(
            state: .ready,
            headline: "技能兼容性已就绪",
            summary: skillDoctorTruthProjection.map {
                "已安装技能已经足够兼容 XT 使用，默认技能基线也已齐备，同时 typed capability/readiness 已明确当前 runnable_now profiles 为 \(doctorListSummary($0.effectiveProfileSnapshot.runnableNowProfiles, empty: "none"))。XT 原生内置技能也会继续和托管集合一起可用。"
            } ?? "已安装技能已经足够兼容 XT 使用，默认技能基线也已齐备，同时不存在被撤销匹配或固定来源冲突。XT 原生内置技能也会继续和托管集合一起可用。",
            nextStep: "当前项目 / 全局 skills index 就可以作为唯一兼容性参考。"
        )
    }

    private static func skillDoctorTruthDetailLines(
        _ projection: XTUnifiedDoctorSkillDoctorTruthProjection?
    ) -> [String] {
        guard let projection else { return [] }
        return [
            "skill_doctor_truth_present=true",
            "skill_profile_source=\(projection.effectiveProfileSnapshot.source)",
            "skill_profile_execution_tier=\(projection.effectiveProfileSnapshot.executionTier)",
            "skill_profile_runtime_surface_mode=\(projection.effectiveProfileSnapshot.runtimeSurfaceMode)",
            "skill_profile_hub_override_mode=\(projection.effectiveProfileSnapshot.hubOverrideMode)",
            "skill_profile_local_auto_approve_enabled=\(projection.effectiveProfileSnapshot.localAutoApproveEnabled)",
            "skill_profile_trusted_automation_ready=\(projection.effectiveProfileSnapshot.trustedAutomationReady)",
            "skill_profile_runnable_now_profiles=\(doctorListSummary(projection.effectiveProfileSnapshot.runnableNowProfiles, empty: "none"))",
            "skill_profile_grant_required_profiles=\(doctorListSummary(projection.effectiveProfileSnapshot.grantRequiredProfiles, empty: "none"))",
            "skill_profile_approval_required_profiles=\(doctorListSummary(projection.effectiveProfileSnapshot.approvalRequiredProfiles, empty: "none"))",
            "skill_profile_blocked_profiles=\(doctorListSummary(projection.effectiveProfileSnapshot.blockedProfiles.map(\.profileID), empty: "none"))",
            "skill_readiness_installed_skills=\(projection.installedSkillCount)",
            "skill_readiness_ready_skills=\(projection.readySkillCount)",
            "skill_readiness_grant_required_skills=\(projection.grantRequiredSkillCount)",
            "skill_readiness_local_approval_required_skills=\(projection.approvalRequiredSkillCount)",
            "skill_readiness_blocked_skills=\(projection.blockedSkillCount)",
            "skill_readiness_degraded_skills=\(projection.degradedSkillCount)",
            "skill_readiness_grant_preview=\(doctorSkillPreviewSummary(projection.grantRequiredSkillPreview))",
            "skill_readiness_local_approval_preview=\(doctorSkillPreviewSummary(projection.approvalRequiredSkillPreview))",
            "skill_readiness_blocked_preview=\(doctorSkillPreviewSummary(projection.blockedSkillPreview))"
        ]
    }

    private static func doctorListSummary(_ values: [String], empty: String) -> String {
        let normalized = orderedUnique(
            values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return normalized.isEmpty ? empty : normalized.joined(separator: ",")
    }

    private static func doctorSkillPreviewSummary(
        _ previews: [XTUnifiedDoctorSkillReadinessPreview]
    ) -> String {
        let normalized = previews.map { preview in
            let reason = preview.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let state = preview.executionReadiness.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                return "\(preview.skillID):\(state)"
            }
            return "\(preview.skillID):\(state):\(reason)"
        }
        return normalized.isEmpty ? "none" : normalized.joined(separator: ",")
    }

    private static func doctorNonEmptySummaries(_ values: [String], fallback: String) -> String {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "none" }
        return normalized.isEmpty ? fallback : normalized.joined(separator: " / ")
    }

    private static func routeSnapshot(for input: XTUnifiedDoctorInput) -> XTUnifiedDoctorRouteSnapshot {
        let host = input.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.localConnected {
            return XTUnifiedDoctorRouteSnapshot(
                transportMode: "local_fileipc",
                routeLabel: "local fileIPC",
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                internetHost: host
            )
        }
        if input.remoteConnected {
            switch input.remoteRoute {
            case .lan:
                return XTUnifiedDoctorRouteSnapshot(
                    transportMode: "remote_grpc_lan",
                    routeLabel: "remote gRPC (LAN)",
                    pairingPort: input.pairingPort,
                    grpcPort: input.grpcPort,
                    internetHost: host
                )
            case .internet:
                return XTUnifiedDoctorRouteSnapshot(
                    transportMode: "remote_grpc_internet",
                    routeLabel: "remote gRPC (internet)",
                    pairingPort: input.pairingPort,
                    grpcPort: input.grpcPort,
                    internetHost: host
                )
            case .internetTunnel:
                return XTUnifiedDoctorRouteSnapshot(
                    transportMode: "remote_grpc_tunnel",
                    routeLabel: "remote gRPC (tunnel)",
                    pairingPort: input.pairingPort,
                    grpcPort: input.grpcPort,
                    internetHost: host
                )
            case .none:
                return XTUnifiedDoctorRouteSnapshot(
                    transportMode: "remote_grpc",
                    routeLabel: "remote gRPC",
                    pairingPort: input.pairingPort,
                    grpcPort: input.grpcPort,
                    internetHost: host
                )
            }
        }
        if input.linking {
            return XTUnifiedDoctorRouteSnapshot(
                transportMode: "pairing_bootstrap",
                routeLabel: "pairing bootstrap",
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                internetHost: host
            )
        }
        return XTUnifiedDoctorRouteSnapshot(
            transportMode: "disconnected",
            routeLabel: "disconnected",
            pairingPort: input.pairingPort,
            grpcPort: input.grpcPort,
            internetHost: host
        )
    }

    private static func overallState(for sections: [XTUnifiedDoctorSection]) -> XTUISurfaceState {
        if sections.contains(where: { $0.state == .permissionDenied }) {
            return .permissionDenied
        }
        if sections.contains(where: { $0.state == .grantRequired }) {
            return .grantRequired
        }
        if sections.contains(where: { $0.state == .diagnosticRequired }) {
            return .diagnosticRequired
        }
        if sections.contains(where: { $0.state == .blockedWaitingUpstream }) {
            return .blockedWaitingUpstream
        }
        if sections.contains(where: { $0.state == .inProgress }) {
            return .inProgress
        }
        return .ready
    }

    private static func overallSummary(
        overallState: XTUISurfaceState,
        readyForFirstTask: Bool,
        sections: [XTUnifiedDoctorSection],
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot?
    ) -> String {
        let localOnlyReady = sections.first(where: { $0.kind == .modelRouteReadiness })?.detailLines.contains("interactive_posture=local_only") == true
        if let firstMainlineBlocker = sections.first(where: {
            $0.kind.contributesToFirstTaskReadiness && failClosedSummaryPriority(for: $0.state) != nil
        }) {
            return "当前先停在安全状态：\(summaryKindLabel(firstMainlineBlocker.kind)) 仍未就绪：\(firstMainlineBlocker.headline)"
        }
        if let firstMainlineInProgress = sections.first(where: {
            $0.kind.contributesToFirstTaskReadiness && $0.state == .inProgress
        }) {
            return "当前仍在收敛：\(summaryKindLabel(firstMainlineInProgress.kind))仍在处理中：\(firstMainlineInProgress.headline)"
        }
        if readyForFirstTask {
            let firstAdvisoryIssue = sections.first(where: { advisorySummaryPriority(for: $0.state) == 0 })
                ?? sections.first(where: { advisorySummaryPriority(for: $0.state) == 1 })
            if let firstAdvisoryIssue {
                if localOnlyReady {
                    return appendedPairedRouteSummary(
                        base: "当前走纯本地路径，不依赖云端服务或 API key；首个任务已可启动，但\(summaryKindLabel(firstAdvisoryIssue.kind)) 仍需修复：\(firstAdvisoryIssue.headline)",
                        readyForFirstTask: readyForFirstTask,
                        pairedRouteSetSnapshot: pairedRouteSetSnapshot
                    )
                }
                return appendedPairedRouteSummary(
                    base: "首个任务已可启动，但\(summaryKindLabel(firstAdvisoryIssue.kind)) 仍需修复：\(firstAdvisoryIssue.headline)",
                    readyForFirstTask: readyForFirstTask,
                    pairedRouteSetSnapshot: pairedRouteSetSnapshot
                )
            }
            if localOnlyReady {
                return appendedPairedRouteSummary(
                    base: "配对、模型路由、工具链路和会话运行时已在同一路径验证通过；当前走纯本地路径，不依赖云端服务或 API key。",
                    readyForFirstTask: readyForFirstTask,
                    pairedRouteSetSnapshot: pairedRouteSetSnapshot
                )
            }
            return appendedPairedRouteSummary(
                base: "配对、模型路由、工具链路和会话运行时已在同一路径验证通过",
                readyForFirstTask: readyForFirstTask,
                pairedRouteSetSnapshot: pairedRouteSetSnapshot
            )
        }
        if let firstBlocking = sections.first(where: { failClosedSummaryPriority(for: $0.state) != nil }) {
            return "当前先停在安全状态：\(summaryKindLabel(firstBlocking.kind)) 仍未就绪：\(firstBlocking.headline)"
        }
        if let firstInProgress = sections.first(where: { $0.state == .inProgress }) {
            return "当前仍在收敛：\(summaryKindLabel(firstInProgress.kind))仍在处理中：\(firstInProgress.headline)"
        }
        return "诊断页仍在收集就绪信号"
    }

    private static func appendedPairedRouteSummary(
        base: String,
        readyForFirstTask: Bool,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot?
    ) -> String {
        guard readyForFirstTask,
              let pairedRouteSetSnapshot else {
            return base
        }
        let summaryLine = pairedRouteSetSnapshot.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summaryLine.isEmpty, !base.contains(summaryLine) else {
            return base
        }
        return "\(base)；\(summaryLine)"
    }

    private static func failClosedSummaryPriority(for state: XTUISurfaceState) -> Int? {
        switch state {
        case .permissionDenied, .grantRequired, .diagnosticRequired, .blockedWaitingUpstream, .releaseFrozen:
            return 0
        case .inProgress, .ready:
            return nil
        }
    }

    private static func advisorySummaryPriority(for state: XTUISurfaceState) -> Int? {
        switch state {
        case .permissionDenied, .grantRequired, .diagnosticRequired, .blockedWaitingUpstream, .releaseFrozen:
            return 0
        case .inProgress:
            return 1
        case .ready:
            return nil
        }
    }

    private static func enrichVoicePlaybackSection(
        _ section: XTUnifiedDoctorSection?,
        playbackActivity: VoicePlaybackActivity
    ) -> XTUnifiedDoctorSection? {
        let actionablePlaybackState = playbackActivity.state == .fallbackPlayed
            || playbackActivity.state == .failed
        guard var section else {
            guard actionablePlaybackState else { return nil }
            return XTUnifiedDoctorSection(
                kind: .voicePlaybackReadiness,
                state: mergedVoicePlaybackState(
                    configuredState: .ready,
                    playbackState: playbackActivity.state
                ),
                headline: voicePlaybackHeadline(playbackActivity),
                summary: playbackActivity.summaryLine,
                nextStep: playbackActivity.recommendedNextStep ?? "打开 Supervisor 设置，确认当前播放输出链路。",
                repairEntry: voicePlaybackRepairEntry(playbackActivity),
                detailLines: voicePlaybackEvidenceLines(playbackActivity)
            )
        }
        guard actionablePlaybackState else { return section }

        let configuredSummary = section.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        section.state = mergedVoicePlaybackState(
            configuredState: section.state,
            playbackState: playbackActivity.state
        )
        section.headline = voicePlaybackHeadline(playbackActivity)
        if configuredSummary.isEmpty || configuredSummary == playbackActivity.summaryLine {
            section.summary = playbackActivity.summaryLine
        } else {
            section.summary = "\(playbackActivity.summaryLine) 当前播放配置检查：\(configuredSummary)"
        }
        if let nextStep = playbackActivity.recommendedNextStep {
            section.nextStep = nextStep
        }
        section.repairEntry = voicePlaybackRepairEntry(playbackActivity)
        section.detailLines = orderedUnique(section.detailLines + voicePlaybackEvidenceLines(playbackActivity))
        return section
    }

    private static func enrichVoiceSmokeSection(
        _ section: XTUnifiedDoctorSection?,
        report: XTSupervisorVoiceSmokeReportSummary?,
        phase: XTSupervisorVoiceSmokeReportSummary.Phase
    ) -> XTUnifiedDoctorSection? {
        guard var section else { return nil }
        guard let report else { return section }

        section.detailLines = orderedUnique(section.detailLines + report.detailLines(for: phase))

        guard shouldApplyVoiceSmokeOverride(
            to: section.state,
            phaseStatus: report.phaseStatus(phase)
        ) else {
            return section
        }

        section.state = .diagnosticRequired
        section.headline = "Supervisor 语音自检显示：\(phase.headline)未通过"
        section.summary = report.failureSummaryLine(for: phase)
            ?? "最近一次 Supervisor 语音自检没有通过\(phase.headline)。"
        section.nextStep = voiceSmokeNextStep(for: phase)
        section.repairEntry = .xtDiagnostics
        return section
    }

    private static func shouldApplyVoiceSmokeOverride(
        to state: XTUISurfaceState,
        phaseStatus: XTSupervisorVoiceSmokeReportSummary.PhaseStatus
    ) -> Bool {
        guard phaseStatus == .failed else { return false }
        switch state {
        case .ready, .inProgress:
            return true
        case .permissionDenied, .grantRequired, .diagnosticRequired, .blockedWaitingUpstream, .releaseFrozen:
            return false
        }
    }

    private static func voiceSmokeNextStep(
        for phase: XTSupervisorVoiceSmokeReportSummary.Phase
    ) -> String {
        switch phase {
        case .wake:
            return "先在 XT 设置 → 诊断与核对 运行一次 Supervisor 语音自检；如果仍卡在唤醒阶段，再核对唤醒方式、FunASR 关键词检测和当前唤醒词配置。"
        case .grant:
            return "先在 XT 设置 → 诊断与核对 重跑 Supervisor 语音自检；如果仍卡在授权挑战阶段，再核对授权挑战、手机批准回传和通话循环恢复链路。"
        case .briefPlayback:
            return "先在 XT 设置 → 诊断与核对 重跑 Supervisor 语音自检；如果仍卡在 Hub 简报播报阶段，再核对简报投影、TTS 播报和播报后恢复监听的链路。"
        }
    }

    private static func mergedVoicePlaybackState(
        configuredState: XTUISurfaceState,
        playbackState: VoicePlaybackActivityState
    ) -> XTUISurfaceState {
        switch playbackState {
        case .fallbackPlayed:
            switch configuredState {
            case .permissionDenied, .grantRequired, .diagnosticRequired, .blockedWaitingUpstream:
                return configuredState
            case .ready, .inProgress, .releaseFrozen:
                return .inProgress
            }
        case .failed:
            switch configuredState {
            case .permissionDenied, .grantRequired:
                return configuredState
            case .ready, .inProgress, .releaseFrozen, .diagnosticRequired, .blockedWaitingUpstream:
                return .diagnosticRequired
            }
        case .idle, .played, .suppressed:
            return configuredState
        }
    }

    private static func voicePlaybackHeadline(
        _ playbackActivity: VoicePlaybackActivity
    ) -> String {
        switch playbackActivity.state {
        case .fallbackPlayed:
            return "最近一次播放已回退到系统语音"
        case .failed:
            return "最近一次播放失败"
        case .idle, .played, .suppressed:
            return playbackActivity.headline
        }
    }

    private static func voicePlaybackRepairEntry(
        _ playbackActivity: VoicePlaybackActivity
    ) -> UITroubleshootDestination {
        switch playbackActivity.state {
        case .fallbackPlayed:
            return .homeSupervisor
        case .failed:
            return .xtDiagnostics
        case .idle, .played, .suppressed:
            return .homeSupervisor
        }
    }

    private static func voicePlaybackEvidenceLines(
        _ playbackActivity: VoicePlaybackActivity
    ) -> [String] {
        var lines = ["recent_playback_state=\(playbackActivity.state.rawValue)"]
        if let output = playbackActivity.actualSource?.rawValue,
           !output.isEmpty {
            lines.append("recent_playback_output=\(output)")
        }
        let reasonCode = playbackActivity.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reasonCode.isEmpty {
            lines.append("recent_playback_reason=\(reasonCode)")
        }
        if let runtimeLine = playbackActivity.runtimeLogSummaryLine {
            lines.append(runtimeLine)
        }
        return lines
    }

    private static func summaryKindLabel(_ kind: XTUnifiedDoctorSectionKind) -> String {
        switch kind {
        case .hubReachability:
            return "Hub 可达性"
        case .pairingValidity:
            return "配对有效性"
        case .modelRouteReadiness:
            return "模型路由"
        case .bridgeToolReadiness:
            return "桥接 / 工具链路"
        case .sessionRuntimeReadiness:
            return "会话运行时"
        case .wakeProfileReadiness:
            return "唤醒配置就绪"
        case .talkLoopReadiness:
            return "对话链路就绪"
        case .voicePlaybackReadiness:
            return "语音播放就绪"
        case .calendarReminderReadiness:
            return "日历提醒就绪"
        case .skillsCompatibilityReadiness:
            return "技能兼容性"
        }
    }

    private static func runtimeBusy(_ state: AXSessionRuntimeState) -> Bool {
        switch state {
        case .planning, .awaiting_model, .awaiting_tool_approval, .running_tools, .awaiting_hub:
            return true
        case .idle, .failed_recoverable, .completed:
            return false
        }
    }

    private static func portLooksValid(_ port: Int) -> Bool {
        (1...65_535).contains(port)
    }

    private static func orderedUnique(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if seen.insert(line).inserted {
                ordered.append(line)
            }
        }
        return ordered
    }
}

private func normalizedOptionalDoctorField(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedMeaningfulValue(_ value: String?) -> String? {
    guard let trimmed = normalizedOptionalDoctorField(value) else { return nil }

    switch trimmed.lowercased() {
    case "unknown", "none", "(none)", "n/a":
        return nil
    default:
        return trimmed
    }
}

private func normalizedDoctorField(_ value: String?, fallback: String) -> String {
    normalizedOptionalDoctorField(value) ?? fallback
}

enum XTUnifiedDoctorStore {
    typealias WriteAttemptOverride = @Sendable (Data, URL, Data.WritingOptions) throws -> Void
    typealias LogSink = @Sendable (String) -> Void
    typealias NowProvider = @Sendable () -> Date

    private struct WriteFailureLogState {
        var signature: String
        var nextAllowedLogAt: Date
        var suppressedCount: Int
    }

    private static let testingOverrideLock = NSLock()
    private static var writeAttemptOverrideForTesting: WriteAttemptOverride?
    private static var logSinkForTesting: LogSink?
    private static var nowProviderForTesting: NowProvider?
    private static var writeFailureLogStateByPath: [String: WriteFailureLogState] = [:]
    private static let writeFailureLogCooldown: TimeInterval = 30

    static func workspaceRootFromEnvOrCWD() -> URL {
        let env = (ProcessInfo.processInfo.environment["XTERMINAL_WORKSPACE_ROOT"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            return URL(fileURLWithPath: NSString(string: env).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    static func defaultReportURL(workspaceRoot: URL = workspaceRootFromEnvOrCWD()) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent("xt_unified_doctor_report.json")
    }

    static func loadReport(from url: URL) throws -> XTUnifiedDoctorReport {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
    }

    static func writeReport(_ report: XTUnifiedDoctorReport, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            emitWriteFailureLog(error, url: url, usedFallback: false)
            return
        }

        if existingReportMatches(data, at: url) {
            clearWriteFailureLogState(for: url)
            return
        }

        do {
            try writeData(data, to: url, options: .atomic)
            clearWriteFailureLogState(for: url)
            return
        } catch {
            guard looksLikeDiskSpaceExhaustion(error),
                  FileManager.default.fileExists(atPath: url.path) else {
                emitWriteFailureLog(error, url: url, usedFallback: false)
                return
            }

            do {
                try writeData(data, to: url, options: [])
                clearWriteFailureLogState(for: url)
            } catch {
                emitWriteFailureLog(error, url: url, usedFallback: true)
            }
        }
    }

    static func installWriteAttemptOverrideForTesting(_ override: WriteAttemptOverride?) {
        withTestingOverrideLock {
            writeAttemptOverrideForTesting = override
        }
    }

    static func installLogSinkForTesting(_ sink: LogSink?) {
        withTestingOverrideLock {
            logSinkForTesting = sink
        }
    }

    static func installNowProviderForTesting(_ provider: NowProvider?) {
        withTestingOverrideLock {
            nowProviderForTesting = provider
        }
    }

    static func resetWriteBehaviorForTesting() {
        withTestingOverrideLock {
            writeAttemptOverrideForTesting = nil
            logSinkForTesting = nil
            nowProviderForTesting = nil
            writeFailureLogStateByPath = [:]
        }
    }

    private static func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        if let override = withTestingOverrideLock({ writeAttemptOverrideForTesting }) {
            try override(data, url, options)
            return
        }
        try data.write(to: url, options: options)
    }

    private static func existingReportMatches(_ data: Data, at url: URL) -> Bool {
        guard let existing = try? Data(contentsOf: url) else { return false }
        return existing == data
    }

    private static func looksLikeDiskSpaceExhaustion(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 28 {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return looksLikeDiskSpaceExhaustion(underlying)
        }
        return false
    }

    private static func emitWriteFailureLog(_ error: Error, url: URL, usedFallback: Bool) {
        let nsError = error as NSError
        let now = currentDate()
        let signature = "\(usedFallback ? "fallback" : "direct"):\(nsError.domain):\(nsError.code)"
        let path = url.path
        let maybeMessage = withTestingOverrideLock { () -> String? in
            if var state = writeFailureLogStateByPath[path],
               state.signature == signature,
               now < state.nextAllowedLogAt {
                state.suppressedCount += 1
                writeFailureLogStateByPath[path] = state
                return nil
            }

            let suppressedCount = writeFailureLogStateByPath[path]?.suppressedCount ?? 0
            writeFailureLogStateByPath[path] = WriteFailureLogState(
                signature: signature,
                nextAllowedLogAt: now.addingTimeInterval(writeFailureLogCooldown),
                suppressedCount: 0
            )

            let prefix = usedFallback
                ? "XTUnifiedDoctor write report failed after non-atomic fallback"
                : "XTUnifiedDoctor write report failed"
            let suppressedSuffix = suppressedCount > 0 ? " suppressed=\(suppressedCount)" : ""
            return "\(prefix): \(error) path=\(path)\(suppressedSuffix)"
        }

        guard let message = maybeMessage else { return }
        if let sink = withTestingOverrideLock({ logSinkForTesting }) {
            sink(message)
            return
        }
        print(message)
    }

    private static func clearWriteFailureLogState(for url: URL) {
        withTestingOverrideLock {
            writeFailureLogStateByPath.removeValue(forKey: url.path)
        }
    }

    private static func currentDate() -> Date {
        if let provider = withTestingOverrideLock({ nowProviderForTesting }) {
            return provider()
        }
        return Date()
    }

    @discardableResult
    private static func withTestingOverrideLock<T>(_ body: () -> T) -> T {
        testingOverrideLock.lock()
        defer { testingOverrideLock.unlock() }
        return body()
    }
}

struct XTUnifiedDoctorSummaryView: View {
    let report: XTUnifiedDoctorReport
    @State private var diagnosticsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(report.overallSummary, systemImage: report.overallState.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(report.overallState.tint)
                Spacer()
                Text(doctorStateLabel(report.overallState))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(report.overallState.tint)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("当前执行路径")
                        .foregroundStyle(.secondary)
                    Text(routeLabel(report.currentRoute))
                }
                GridRow {
                    Text("当前执行传输")
                        .foregroundStyle(.secondary)
                    Text(transportModeLabel(report.currentRoute))
                }
                GridRow {
                    Text("Hub 配对端口")
                        .foregroundStyle(.secondary)
                    Text("\(report.currentRoute.pairingPort)")
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Hub gRPC 端口")
                        .foregroundStyle(.secondary)
                    Text("\(report.currentRoute.grpcPort)")
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Hub 公网地址")
                        .foregroundStyle(.secondary)
                    Text(report.currentRoute.internetHost.isEmpty ? "未设置" : report.currentRoute.internetHost)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(report.currentRoute.internetHost.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }
                if shouldShowRemoteTargetStatus(report) {
                    GridRow {
                        Text("远端目标状态")
                            .foregroundStyle(.secondary)
                        Text(remoteTargetStatusSummary(report))
                            .foregroundStyle(remoteTargetStatusColor(report))
                    }
                }
                GridRow {
                    Text("模型概况")
                        .foregroundStyle(.secondary)
                    Text("已配置 \(report.configuredModelRoles) 个，可用 \(report.availableModelCount) 个，已加载 \(report.loadedModelCount) 个")
                }
                GridRow {
                    Text("付费模型额度")
                        .foregroundStyle(.secondary)
                    Text(remotePaidAccessSummary(report))
                        .foregroundStyle(remotePaidAccessColor(report))
                }
                GridRow {
                    Text("首个任务")
                        .foregroundStyle(.secondary)
                    Text(report.readyForFirstTask ? "可启动" : "暂缓")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(report.readyForFirstTask ? UIThemeTokens.color(for: .ready) : UIThemeTokens.color(for: .diagnosticRequired))
                }
            }
            .font(.caption)

            ForEach(report.sections) { section in
                XTUnifiedDoctorSectionCard(section: section)
            }

            if hasDiagnostics(report) {
                DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let sessionID = report.currentSessionID, !sessionID.isEmpty {
                            Text("当前会话：\(sessionID)")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Text("当前路径原始值：\(report.currentRoute.routeLabel)")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("传输方式原始值：\(report.currentRoute.transportMode)")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if !report.consumedContracts.isEmpty {
                            Text("诊断合同：\(report.consumedContracts.joined(separator: ", "))")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if !report.reportPath.isEmpty {
                            Text("报告路径：\(report.reportPath)")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("原始诊断")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(diagnosticsExpanded ? "展开中" : "已折叠")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func doctorStateLabel(_ state: XTUISurfaceState) -> String {
        switch state {
        case .ready:
            return "已就绪"
        case .inProgress:
            return "处理中"
        case .grantRequired:
            return "待授权"
        case .permissionDenied:
            return "权限拒绝"
        case .blockedWaitingUpstream:
            return "上游阻塞"
        case .releaseFrozen:
            return "已冻结"
        case .diagnosticRequired:
            return "需诊断"
        }
    }

    private func routeLabel(_ route: XTUnifiedDoctorRouteSnapshot) -> String {
        switch route.routeLabel {
        case "local fileIPC":
            return "本机直连"
        case "remote gRPC (LAN)":
            return "远端直连（局域网）"
        case "remote gRPC (internet)":
            return "远端直连（公网）"
        case "remote gRPC (tunnel)":
            return "远端隧道"
        case "remote gRPC":
            return "远端直连"
        case "pairing bootstrap":
            return "正在配对"
        case "disconnected":
            return "未连接"
        default:
            return route.routeLabel
        }
    }

    private func remotePaidAccessSummary(_ report: XTUnifiedDoctorReport) -> String {
        if let projection = report.remotePaidAccessProjection {
            return projection.compactBudgetLine
        }

        if shouldShowRemoteTargetStatus(report) {
            return "远端未连通，当前仍走本机路径"
        }

        if report.currentRoute.transportMode == "local_fileipc" {
            return "当前为本机路径"
        }

        if report.currentRoute.transportMode.hasPrefix("remote_") {
            return "未回报"
        }

        return "暂不可用"
    }

    private func remotePaidAccessColor(_ report: XTUnifiedDoctorReport) -> Color {
        guard let projection = report.remotePaidAccessProjection else {
            return .secondary
        }
        return projection.trustProfilePresent ? .primary : .orange
    }

    private func transportModeLabel(_ route: XTUnifiedDoctorRouteSnapshot) -> String {
        switch route.transportMode {
        case "local_fileipc":
            return "本机文件通道"
        case "remote_grpc_lan":
            return "远端 gRPC（局域网）"
        case "remote_grpc_internet":
            return "远端 gRPC（公网）"
        case "remote_grpc_tunnel":
            return "远端 gRPC（隧道）"
        case "remote_grpc":
            return "远端 gRPC"
        case "pairing_bootstrap":
            return "配对引导中"
        case "disconnected":
            return "未连接"
        default:
            return route.transportMode
        }
    }

    private func shouldShowRemoteTargetStatus(_ report: XTUnifiedDoctorReport) -> Bool {
        guard report.currentRoute.transportMode == "local_fileipc" else { return false }
        guard !report.currentRoute.internetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let issue = report.currentFailureIssue else { return false }

        switch issue {
        case .hubUnreachable, .pairingRepairRequired, .multipleHubsAmbiguous, .hubPortConflict:
            return true
        default:
            return false
        }
    }

    private func remoteTargetStatusSummary(_ report: XTUnifiedDoctorReport) -> String {
        switch report.currentFailureIssue {
        case .hubUnreachable:
            return "未连通（\(friendlyRemoteFailureLabel(report.currentFailureCode))）"
        case .pairingRepairRequired:
            return "需修复配对后再连"
        case .multipleHubsAmbiguous:
            return "存在多台候选 Hub，需先固定目标"
        case .hubPortConflict:
            return "目标端口冲突，需先修复"
        default:
            return "待验证"
        }
    }

    private func remoteTargetStatusColor(_ report: XTUnifiedDoctorReport) -> Color {
        shouldShowRemoteTargetStatus(report)
            ? UIThemeTokens.color(for: .diagnosticRequired)
            : .secondary
    }

    private func friendlyRemoteFailureLabel(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("grpc_unavailable") {
            return "gRPC 不可达"
        }
        if normalized.contains("tcp_timeout") || normalized.contains("timeout") {
            return "连接超时"
        }
        if normalized.contains("connection_refused") {
            return "连接被拒"
        }
        if normalized.contains("network_unreachable") {
            return "网络不可达"
        }
        if normalized.contains("hub_unreachable") {
            return "Hub 不可达"
        }
        return normalized.isEmpty ? "直连失败" : normalized
    }

    private func hasDiagnostics(_ report: XTUnifiedDoctorReport) -> Bool {
        (report.currentSessionID?.isEmpty == false)
            || !report.consumedContracts.isEmpty
            || !report.reportPath.isEmpty
            || !report.currentRoute.routeLabel.isEmpty
            || !report.currentRoute.transportMode.isEmpty
    }
}

private struct XTUnifiedDoctorSectionCard: View {
    let section: XTUnifiedDoctorSection
    @State private var diagnosticsExpanded = false

    private var routeTruthProjection: AXModelRouteTruthProjection? {
        guard section.kind == .modelRouteReadiness else { return nil }
        if let projection = section.memoryRouteTruthProjection {
            return projection
        }
        return AXModelRouteTruthProjection(doctorDetailLines: section.detailLines)
    }

    private var routeTruthSummary: XTDoctorProjectionSummary? {
        guard let routeTruthProjection else { return nil }
        return XTDoctorRouteTruthPresentation.summary(projection: routeTruthProjection)
    }

    private var skillDoctorTruthSummary: XTDoctorProjectionSummary? {
        guard section.kind == .skillsCompatibilityReadiness,
              let projection = section.skillDoctorTruthProjection else { return nil }
        return XTDoctorSkillDoctorTruthPresentation.summary(projection: projection)
    }

    private var projectContextPresentation: AXProjectContextAssemblyPresentation? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let presentation = section.projectContextPresentation {
            return presentation
        }
        return AXProjectContextAssemblyPresentation.from(detailLines: section.detailLines)
    }

    private var projectMemoryReadinessProjection: XTProjectMemoryAssemblyReadiness? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let projection = section.projectMemoryReadinessProjection {
            return projection
        }
        return XTProjectMemoryAssemblyReadiness.from(detailLines: section.detailLines)
    }

    private var projectMemoryReadinessSummary: XTDoctorProjectionSummary? {
        guard let projectMemoryReadinessProjection else { return nil }
        return XTDoctorProjectMemoryReadinessPresentation.summary(
            projection: projectMemoryReadinessProjection
        )
    }

    private var governanceRuntimeReadinessSummary: XTDoctorProjectionSummary? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        return XTDoctorGovernanceRuntimeReadinessPresentation.summary(detailLines: section.detailLines)
    }

    private var heartbeatGovernanceProjection: XTUnifiedDoctorHeartbeatGovernanceProjection? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let projection = section.heartbeatGovernanceProjection {
            return projection
        }
        return XTUnifiedDoctorHeartbeatGovernanceProjection.from(detailLines: section.detailLines)
    }

    private var heartbeatGovernanceSummary: XTDoctorProjectionSummary? {
        guard let heartbeatGovernanceProjection else { return nil }
        return XTDoctorHeartbeatGovernancePresentation.summary(
            projection: heartbeatGovernanceProjection
        )
    }

    private var supervisorGuidanceContinuityProjection: XTUnifiedDoctorSupervisorGuidanceContinuityProjection? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let projection = section.supervisorGuidanceContinuityProjection {
            return projection
        }
        return XTUnifiedDoctorSupervisorGuidanceContinuityProjection.from(detailLines: section.detailLines)
    }

    private var supervisorReviewTriggerProjection: XTUnifiedDoctorSupervisorReviewTriggerProjection? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let projection = section.supervisorReviewTriggerProjection {
            return projection
        }
        return XTUnifiedDoctorSupervisorReviewTriggerProjection.from(detailLines: section.detailLines)
    }

    private var supervisorReviewTriggerSummary: XTDoctorProjectionSummary? {
        guard let supervisorReviewTriggerProjection else { return nil }
        return XTDoctorSupervisorReviewTriggerPresentation.summary(
            projection: supervisorReviewTriggerProjection
        )
    }

    private var supervisorGuidanceContinuitySummary: XTDoctorProjectionSummary? {
        guard let supervisorGuidanceContinuityProjection else { return nil }
        return XTDoctorSupervisorGuidanceContinuityPresentation.summary(
            projection: supervisorGuidanceContinuityProjection
        )
    }

    private var supervisorSafePointTimelineProjection: XTUnifiedDoctorSupervisorSafePointTimelineProjection? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let projection = section.supervisorSafePointTimelineProjection {
            return projection
        }
        return XTUnifiedDoctorSupervisorSafePointTimelineProjection.from(detailLines: section.detailLines)
    }

    private var supervisorSafePointTimelineSummary: XTDoctorProjectionSummary? {
        guard let supervisorSafePointTimelineProjection else { return nil }
        return XTDoctorSupervisorSafePointTimelinePresentation.summary(
            projection: supervisorSafePointTimelineProjection
        )
    }

    private var durableCandidateMirrorProjection: XTUnifiedDoctorDurableCandidateMirrorProjection? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let projection = section.durableCandidateMirrorProjection {
            return projection
        }
        return XTUnifiedDoctorDurableCandidateMirrorProjection.from(detailLines: section.detailLines)
    }

    private var durableCandidateMirrorSummary: XTDoctorProjectionSummary? {
        guard let durableCandidateMirrorProjection else { return nil }
        return XTDoctorDurableCandidateMirrorPresentation.summary(projection: durableCandidateMirrorProjection)
    }

    private var projectAutomationContinuitySummary: XTDoctorProjectionSummary? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        return XTDoctorProjectAutomationContinuityPresentation.summary(detailLines: section.detailLines)
    }

    private var hubMemoryPromptProjection: HubMemoryPromptProjectionSnapshot? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let projection = section.hubMemoryPromptProjection {
            return projection
        }
        return HubMemoryPromptProjectionSnapshot.fromDoctorDetailLines(section.detailLines)
    }

    private var hubMemoryPromptProjectionSummary: XTDoctorProjectionSummary? {
        guard let hubMemoryPromptProjection else { return nil }
        return XTDoctorHubMemoryPromptProjectionPresentation.summary(
            projection: hubMemoryPromptProjection
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(section.kind.title, systemImage: section.state.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(section.state.tint)
                Spacer()
                Text(sectionStateLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(section.state.tint)
            }

            Text(section.headline)
                .font(.caption.weight(.semibold))
            Text(section.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("下一步：\(section.nextStep)")
                .font(.caption)
            Text("建议去这里修：\(section.repairEntry.label)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let routeTruthSummary {
                XTDoctorProjectionSummaryView(summary: routeTruthSummary)
            }

            if let skillDoctorTruthSummary {
                XTDoctorProjectionSummaryView(summary: skillDoctorTruthSummary)
            }

            if let projectContextPresentation {
                XTDoctorProjectContextSummaryView(presentation: projectContextPresentation)
            }

            if let projectMemoryReadinessSummary {
                XTDoctorProjectionSummaryView(summary: projectMemoryReadinessSummary)
            }

            if let governanceRuntimeReadinessSummary {
                XTDoctorProjectionSummaryView(summary: governanceRuntimeReadinessSummary)
            }

            if let projectAutomationContinuitySummary {
                XTDoctorProjectionSummaryView(summary: projectAutomationContinuitySummary)
            }

            if let hubMemoryPromptProjectionSummary {
                XTDoctorProjectionSummaryView(summary: hubMemoryPromptProjectionSummary)
            }

            if let heartbeatGovernanceSummary {
                XTDoctorProjectionSummaryView(summary: heartbeatGovernanceSummary)
            }

            if let supervisorReviewTriggerSummary {
                XTDoctorProjectionSummaryView(summary: supervisorReviewTriggerSummary)
            }

            if let supervisorGuidanceContinuitySummary {
                XTDoctorProjectionSummaryView(summary: supervisorGuidanceContinuitySummary)
            }

            if let supervisorSafePointTimelineSummary {
                XTDoctorProjectionSummaryView(summary: supervisorSafePointTimelineSummary)
            }

            if let durableCandidateMirrorSummary {
                XTDoctorProjectionSummaryView(summary: durableCandidateMirrorSummary)
            }

            if !section.detailLines.isEmpty {
                DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(section.detailLines, id: \.self) { line in
                            Text("• \(line)")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("原始诊断")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(diagnosticsExpanded ? "展开中" : "已折叠")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UIThemeTokens.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }

    private var sectionStateLabel: String {
        switch section.state {
        case .ready:
            return "已就绪"
        case .inProgress:
            return "处理中"
        case .grantRequired:
            return "待授权"
        case .permissionDenied:
            return "权限拒绝"
        case .blockedWaitingUpstream:
            return "上游阻塞"
        case .releaseFrozen:
            return "已冻结"
        case .diagnosticRequired:
            return "需诊断"
        }
    }
}

private struct XTDoctorProjectionSummaryView: View {
    let summary: XTDoctorProjectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.title)
                .font(.caption.weight(.semibold))

            ForEach(summary.lines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct XTDoctorProjectContextSummaryView: View {
    let presentation: AXProjectContextAssemblyPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("项目上下文")
                    .font(.caption.weight(.semibold))
                Text(presentation.userSourceBadge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((presentation.sourceKind == .latestCoderUsage ? Color.green : Color.orange).opacity(0.16))
                    )
                    .foregroundStyle(presentation.sourceKind == .latestCoderUsage ? Color.green : Color.orange)
                Spacer()
            }

            if let projectLabel = presentation.projectLabel {
                Text(projectLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(presentation.userStatusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("对话")
                        .foregroundStyle(.secondary)
                    Text(presentation.userDialogueMetric)
                }
                GridRow {
                    Text("深度")
                        .foregroundStyle(.secondary)
                    Text(presentation.userDepthMetric)
                }
                if let coverageMetric = presentation.userCoverageSummary {
                    GridRow {
                        Text("纳入内容")
                            .foregroundStyle(.secondary)
                        Text(coverageMetric)
                    }
                }
                if let assemblySummary = presentation.userAssemblySummary {
                    GridRow {
                        Text("实际装配")
                            .foregroundStyle(.secondary)
                        Text(assemblySummary)
                    }
                }
                if let omissionSummary = presentation.userOmissionSummary {
                    GridRow {
                        Text("未带部分")
                            .foregroundStyle(.secondary)
                        Text(omissionSummary)
                    }
                }
                if let budgetSummary = presentation.userBudgetSummary {
                    GridRow {
                        Text("预算摘要")
                            .foregroundStyle(.secondary)
                        Text(budgetSummary)
                    }
                }
                if let boundaryMetric = presentation.userBoundarySummary {
                    GridRow {
                        Text("隐私边界")
                            .foregroundStyle(.secondary)
                        Text(boundaryMetric)
                    }
                }
            }
            .font(.caption2)

            Text(presentation.userDialogueLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.userDepthLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }
}
