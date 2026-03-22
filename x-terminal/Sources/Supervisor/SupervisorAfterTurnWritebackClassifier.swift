import Foundation
import CryptoKit

enum SupervisorAfterTurnWritebackScope: String, Codable, CaseIterable, Equatable, Sendable {
    case userScope = "user_scope"
    case projectScope = "project_scope"
    case crossLinkScope = "cross_link_scope"
    case workingSetOnly = "working_set_only"
    case dropAsNoise = "drop_as_noise"
}

extension SupervisorAfterTurnWritebackScope {
    var isDurableMirrorEligible: Bool {
        switch self {
        case .userScope, .projectScope, .crossLinkScope:
            return true
        case .workingSetOnly, .dropAsNoise:
            return false
        }
    }
}

struct SupervisorAfterTurnWritebackCandidate: Equatable, Sendable {
    var scope: SupervisorAfterTurnWritebackScope
    var recordType: String
    var confidence: Double
    var whyPromoted: String
    var sourceRef: String
    var auditRef: String
    var sessionParticipationClass: String = "scoped_write"
    var writePermissionScope: String = ""
    var idempotencyKey: String = ""
    var payloadSummary: String = ""
}

struct SupervisorAfterTurnWritebackClassification: Equatable, Sendable {
    var turnMode: SupervisorTurnMode?
    var candidates: [SupervisorAfterTurnWritebackCandidate]
    var summaryLine: String
    var mirrorStatus: SupervisorDurableCandidateMirrorStatus = .notNeeded
    var mirrorTarget: String? = nil
    var mirrorAttempted: Bool = false
    var mirrorErrorCode: String? = nil
    var localStoreRole: String = XTSupervisorDurableCandidateMirror.localStoreRole

    var durableCandidates: [SupervisorAfterTurnWritebackCandidate] {
        candidates.filter { $0.scope.isDurableMirrorEligible }
    }
}

struct SupervisorAfterTurnWritebackClassificationRequest: Equatable, Sendable {
    var userMessage: String
    var responseText: String
    var routingDecision: SupervisorTurnRoutingDecision?
    var projects: [AXProjectEntry]
    var personalMemory: SupervisorPersonalMemorySnapshot
}

enum SupervisorAfterTurnWritebackClassifier {
    static func classify(
        _ request: SupervisorAfterTurnWritebackClassificationRequest,
        now: Date = Date()
    ) -> SupervisorAfterTurnWritebackClassification {
        var candidates: [SupervisorAfterTurnWritebackCandidate] = []
        let normalizedUser = normalizedAfterTurnWritebackText(request.userMessage)
        let sourceRef = "user_message"
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let turnMode = request.routingDecision?.mode

        if let preferredName = SupervisorPersonalMemoryAutoCapture.extract(from: request.userMessage)?.preferredUserName {
            candidates.append(
                candidate(
                    scope: .userScope,
                    recordType: "preferred_name",
                    confidence: 0.98,
                    whyPromoted: "explicit preferred-name statement",
                    sourceRef: sourceRef,
                    nowMs: nowMs,
                    stable: preferredName
                )
            )
        }

        let explicitRecords = SupervisorPersonalMemoryAutoCapture.extractAdditionalRecords(
            from: request.userMessage,
            now: now
        )
        candidates.append(contentsOf: explicitRecords.map { record in
            candidate(
                scope: .userScope,
                recordType: record.category.rawValue,
                confidence: 0.97,
                whyPromoted: "explicit memory intent for durable personal context",
                sourceRef: sourceRef,
                nowMs: nowMs,
                stable: record.memoryId
            )
        })

        if candidates.isEmpty,
           let inferredUserPreference = inferredUserPreferenceFact(from: request.userMessage) {
            candidates.append(
                candidate(
                    scope: .userScope,
                    recordType: "personal_preference",
                    confidence: 0.72,
                    whyPromoted: "stable first-person preference statement",
                    sourceRef: sourceRef,
                    nowMs: nowMs,
                    stable: inferredUserPreference
                )
            )
        }

        if let routingDecision = request.routingDecision,
           let projectId = normalizedAfterTurnWritebackScalar(routingDecision.focusedProjectId),
           let projectRecordType = inferredProjectRecordType(
                normalizedUserMessage: normalizedUser,
                routingDecision: routingDecision
           ) {
            candidates.append(
                candidate(
                    scope: .projectScope,
                    recordType: projectRecordType,
                    confidence: routingDecision.mode == .projectFirst ? 0.9 : 0.82,
                    whyPromoted: "focused project fact with durable planning/blocker significance",
                    sourceRef: sourceRef,
                    nowMs: nowMs,
                    stable: "\(projectId)|\(projectRecordType)"
                )
            )
        }

        if let routingDecision = request.routingDecision,
           let projectId = normalizedAfterTurnWritebackScalar(routingDecision.focusedProjectId),
           let personName = normalizedAfterTurnWritebackScalar(routingDecision.focusedPersonName),
           looksLikeCrossLinkFact(normalizedUser) {
            candidates.append(
                candidate(
                    scope: .crossLinkScope,
                    recordType: "person_waiting_on_project",
                    confidence: 0.93,
                    whyPromoted: "person-project dependency is explicit in the current turn",
                    sourceRef: sourceRef,
                    nowMs: nowMs,
                    stable: "\(personName)|\(projectId)"
                )
            )
        } else if let routingDecision = request.routingDecision,
                  let projectId = normalizedAfterTurnWritebackScalar(routingDecision.focusedProjectId),
                  let commitmentId = normalizedAfterTurnWritebackScalar(routingDecision.focusedCommitmentId),
                  looksLikeCrossLinkFact(normalizedUser) {
            candidates.append(
                candidate(
                    scope: .crossLinkScope,
                    recordType: "commitment_depends_on_project",
                    confidence: 0.9,
                    whyPromoted: "commitment-project dependency is explicit in the current turn",
                    sourceRef: sourceRef,
                    nowMs: nowMs,
                    stable: "\(commitmentId)|\(projectId)"
                )
            )
        }

        let durableCandidates = deduplicatedAfterTurnWritebackCandidates(candidates)
        if !durableCandidates.isEmpty {
            return SupervisorAfterTurnWritebackClassification(
                turnMode: turnMode,
                candidates: durableCandidates,
                summaryLine: durableCandidates.map(\.scope.rawValue).joined(separator: ", ")
            )
        }

        if looksLikeNoise(normalizedUser) {
            let noise = candidate(
                scope: .dropAsNoise,
                recordType: "small_talk",
                confidence: 0.95,
                whyPromoted: "no durable factual payload was detected",
                sourceRef: sourceRef,
                nowMs: nowMs,
                stable: normalizedUser
            )
            return SupervisorAfterTurnWritebackClassification(
                turnMode: turnMode,
                candidates: [noise],
                summaryLine: noise.scope.rawValue
            )
        }

        let workingSet = candidate(
            scope: .workingSetOnly,
            recordType: "transient_turn_note",
            confidence: 0.66,
            whyPromoted: "turn carries temporary planning context but no durable verified fact",
            sourceRef: sourceRef,
            nowMs: nowMs,
            stable: normalizedUser.isEmpty ? request.responseText : normalizedUser
        )
        return SupervisorAfterTurnWritebackClassification(
            turnMode: turnMode,
            candidates: [workingSet],
            summaryLine: workingSet.scope.rawValue
        )
    }

    private static func inferredProjectRecordType(
        normalizedUserMessage: String,
        routingDecision: SupervisorTurnRoutingDecision
    ) -> String? {
        guard routingDecision.focusedProjectId != nil else { return nil }
        guard !looksLikeProjectFactQuestion(normalizedUserMessage) else { return nil }
        if afterTurnWritebackContainsAny(normalizedUserMessage, ["blocker", "阻塞", "卡点", "卡住", "grant pending"]) {
            return "project_blocker"
        }
        if afterTurnWritebackContainsAny(
            normalizedUserMessage,
            [
                "goal",
                "done",
                "约束",
                "constraint",
                "需求",
                "requirement",
                "目标",
                "完成标准",
                "验收标准",
                "mvp",
                "先不做",
                "不要做",
                "只用",
                "必须用",
                "只能用",
                "技术栈",
                "tech stack"
            ]
        ) {
            return "project_goal_or_constraint"
        }
        if afterTurnWritebackContainsAny(normalizedUserMessage, ["计划", "步骤", "plan", "工单", "下一步", "推进"]) {
            return "project_plan_change"
        }
        return nil
    }

    private static func inferredUserPreferenceFact(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let patterns = [
            "我喜欢",
            "我偏好",
            "我习惯",
            "我一般",
            "我通常",
            "我不喜欢"
        ]
        guard patterns.contains(where: { trimmed.contains($0) }) else { return nil }
        return String(trimmed.prefix(120))
    }

    private static func looksLikeCrossLinkFact(_ normalizedText: String) -> Bool {
        afterTurnWritebackContainsAny(normalizedText, ["在等", "等待", "依赖", "取决于", "关于", "demo", "提醒", "会议"])
    }

    private static func looksLikeNoise(_ normalizedText: String) -> Bool {
        guard !normalizedText.isEmpty else { return true }
        let greetings = [
            "你好",
            "您好",
            "hi",
            "hello",
            "hey",
            "在吗",
            "谢谢",
            "ok",
            "好的"
        ]
        return greetings.contains(normalizedText)
    }

    private static func looksLikeProjectFactQuestion(_ normalizedText: String) -> Bool {
        guard !normalizedText.isEmpty else { return false }
        if normalizedText.contains("?") || normalizedText.contains("？") {
            return true
        }
        return afterTurnWritebackContainsAny(
            normalizedText,
            [
                "是什么",
                "是啥",
                "什么",
                "怎么",
                "如何",
                "吗"
            ]
        )
    }

    private static func candidate(
        scope: SupervisorAfterTurnWritebackScope,
        recordType: String,
        confidence: Double,
        whyPromoted: String,
        sourceRef: String,
        nowMs: Int64,
        stable: String
    ) -> SupervisorAfterTurnWritebackCandidate {
        let normalizedStable = normalizedAfterTurnWritebackText(stable)
        let payloadSummary = structuredPayloadSummary(
            scope: scope,
            recordType: recordType,
            stable: stable
        )
        let sessionParticipationClass = "scoped_write"
        let writePermissionScope = scope.rawValue
        let idempotencySeed = [
            "supervisor_durable_candidate",
            scope.rawValue,
            recordType,
            sessionParticipationClass,
            writePermissionScope,
            payloadSummary
        ].joined(separator: "|")
        return SupervisorAfterTurnWritebackCandidate(
            scope: scope,
            recordType: recordType,
            confidence: confidence,
            whyPromoted: whyPromoted,
            sourceRef: sourceRef,
            auditRef: "supervisor_writeback:\(scope.rawValue):\(recordType):\(normalizedStable):\(nowMs)",
            sessionParticipationClass: sessionParticipationClass,
            writePermissionScope: writePermissionScope,
            idempotencyKey: "sha256:\(afterTurnWritebackSHA256Hex(idempotencySeed))",
            payloadSummary: payloadSummary
        )
    }

    private static func structuredPayloadSummary(
        scope: SupervisorAfterTurnWritebackScope,
        recordType: String,
        stable: String
    ) -> String {
        let parts = stable.split(separator: "|", maxSplits: 1).map(String.init)

        switch scope {
        case .userScope:
            if recordType == "preferred_name" {
                return "preferred_name=\(sanitizedAfterTurnPayloadToken(stable))"
            }
            if recordType == "personal_preference" {
                return "preference=\(sanitizedAfterTurnPayloadToken(stable, maxChars: 140))"
            }
            return "memory_id=\(sanitizedAfterTurnPayloadToken(stable))"
        case .projectScope:
            let projectID = sanitizedAfterTurnPayloadToken(parts.first ?? stable)
            return "project_id=\(projectID);record_type=\(recordType)"
        case .crossLinkScope:
            let lhs = sanitizedAfterTurnPayloadToken(parts.first ?? stable)
            let rhs = sanitizedAfterTurnPayloadToken(parts.dropFirst().first ?? "")
            if recordType == "person_waiting_on_project" {
                return "person=\(lhs);project_id=\(rhs)"
            }
            if recordType == "commitment_depends_on_project" {
                return "commitment_id=\(lhs);project_id=\(rhs)"
            }
            return "stable=\(sanitizedAfterTurnPayloadToken(stable))"
        case .workingSetOnly, .dropAsNoise:
            return "stable=\(sanitizedAfterTurnPayloadToken(stable, maxChars: 100))"
        }
    }
}

private func normalizedAfterTurnWritebackScalar(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedAfterTurnWritebackText(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func afterTurnWritebackContainsAny(_ text: String, _ needles: [String]) -> Bool {
    needles.contains { text.contains($0) }
}

private func sanitizedAfterTurnPayloadToken(_ value: String, maxChars: Int = 80) -> String {
    let collapsed = value
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let scrubbed = collapsed.replacingOccurrences(
        of: "<private>",
        with: "[redacted]",
        options: [.caseInsensitive]
    )
    let normalized = scrubbed.isEmpty ? "unknown" : scrubbed
    guard normalized.count > maxChars else { return normalized }
    let idx = normalized.index(normalized.startIndex, offsetBy: maxChars)
    return String(normalized[..<idx])
}

private func afterTurnWritebackSHA256Hex(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func deduplicatedAfterTurnWritebackCandidates(
    _ candidates: [SupervisorAfterTurnWritebackCandidate]
) -> [SupervisorAfterTurnWritebackCandidate] {
    var seen = Set<String>()
    var output: [SupervisorAfterTurnWritebackCandidate] = []
    for candidate in candidates.sorted(by: afterTurnWritebackCandidateSort) {
        let key = candidate.idempotencyKey.isEmpty
            ? "\(candidate.scope.rawValue)|\(candidate.recordType)|\(candidate.sourceRef)"
            : candidate.idempotencyKey
        guard seen.insert(key).inserted else { continue }
        output.append(candidate)
    }
    return output
}

private func afterTurnWritebackCandidateSort(
    lhs: SupervisorAfterTurnWritebackCandidate,
    rhs: SupervisorAfterTurnWritebackCandidate
) -> Bool {
    if lhs.confidence != rhs.confidence {
        return lhs.confidence > rhs.confidence
    }
    if lhs.scope.rawValue != rhs.scope.rawValue {
        return lhs.scope.rawValue < rhs.scope.rawValue
    }
    return lhs.recordType < rhs.recordType
}
