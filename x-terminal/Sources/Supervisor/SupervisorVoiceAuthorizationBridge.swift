import Foundation
import CryptoKit

struct SupervisorVoiceAuthorizationRequest: Codable, Equatable {
    var requestId: String
    var projectId: String?
    var templateId: String
    var actionText: String
    var scopeText: String
    var amountText: String?
    var riskTier: LaneRiskTier
    var boundDeviceId: String?
    var mobileTerminalId: String?
    var challengeCode: String?
    var ttlMs: Int

    init(
        requestId: String,
        projectId: String? = nil,
        templateId: String = "voice.grant.v1",
        actionText: String,
        scopeText: String,
        amountText: String? = nil,
        riskTier: LaneRiskTier,
        boundDeviceId: String? = nil,
        mobileTerminalId: String? = nil,
        challengeCode: String? = nil,
        ttlMs: Int = 120_000
    ) {
        self.requestId = requestId
        self.projectId = projectId
        self.templateId = templateId
        self.actionText = actionText
        self.scopeText = scopeText
        self.amountText = amountText
        self.riskTier = riskTier
        self.boundDeviceId = boundDeviceId
        self.mobileTerminalId = mobileTerminalId
        self.challengeCode = challengeCode
        self.ttlMs = ttlMs
    }
}

struct SupervisorVoiceAuthorizationVerificationInput: Codable, Equatable {
    var requestId: String
    var challengeCode: String?
    var transcript: String?
    var transcriptHash: String?
    var semanticMatchScore: Double
    var actionText: String
    var scopeText: String
    var amountText: String?
    var verifyNonce: String
    var boundDeviceId: String?
    var mobileConfirmed: Bool

    init(
        requestId: String,
        challengeCode: String? = nil,
        transcript: String? = nil,
        transcriptHash: String? = nil,
        semanticMatchScore: Double,
        actionText: String,
        scopeText: String,
        amountText: String? = nil,
        verifyNonce: String,
        boundDeviceId: String? = nil,
        mobileConfirmed: Bool = false
    ) {
        self.requestId = requestId
        self.challengeCode = challengeCode
        self.transcript = transcript
        self.transcriptHash = transcriptHash
        self.semanticMatchScore = semanticMatchScore
        self.actionText = actionText
        self.scopeText = scopeText
        self.amountText = amountText
        self.verifyNonce = verifyNonce
        self.boundDeviceId = boundDeviceId
        self.mobileConfirmed = mobileConfirmed
    }
}

struct SupervisorVoiceAuthorizationDigests: Codable, Equatable {
    var actionDigest: String
    var scopeDigest: String
    var amountDigest: String?
}

struct SupervisorVoiceAuthorizationResolution: Codable, Equatable {
    static let currentSchemaVersion = "xt.supervisor_voice_authorization_resolution.v1"

    enum State: String, Codable, CaseIterable {
        case pending
        case verified
        case denied
        case escalatedToMobile = "escalated_to_mobile"
        case failClosed = "fail_closed"
    }

    var schemaVersion: String
    var state: State
    var ok: Bool
    var requestId: String
    var projectId: String?
    var templateId: String
    var riskTier: String
    var challengeId: String?
    var challenge: HubIPCClient.VoiceGrantChallengeSnapshot?
    var verified: Bool
    var requiresMobileConfirm: Bool
    var allowVoiceOnly: Bool
    var denyCode: String?
    var reasonCode: String?
    var transcriptHash: String?
    var semanticMatchScore: Double?
    var policyRef: String
    var nextAction: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state
        case ok
        case requestId = "request_id"
        case projectId = "project_id"
        case templateId = "template_id"
        case riskTier = "risk_tier"
        case challengeId = "challenge_id"
        case challenge
        case verified
        case requiresMobileConfirm = "requires_mobile_confirm"
        case allowVoiceOnly = "allow_voice_only"
        case denyCode = "deny_code"
        case reasonCode = "reason_code"
        case transcriptHash = "transcript_hash"
        case semanticMatchScore = "semantic_match_score"
        case policyRef = "policy_ref"
        case nextAction = "next_action"
    }
}

struct SupervisorVoiceAuthorizationBridge {
    typealias IssueHandler = (HubIPCClient.VoiceGrantChallengeRequestPayload) async -> HubIPCClient.VoiceGrantChallengeResult
    typealias VerifyHandler = (HubIPCClient.VoiceGrantVerificationPayload) async -> HubIPCClient.VoiceGrantVerificationResult

    private let issueHandler: IssueHandler
    private let verifyHandler: VerifyHandler

    init(
        issueHandler: @escaping IssueHandler = { payload in
            await HubIPCClient.issueVoiceGrantChallenge(payload)
        },
        verifyHandler: @escaping VerifyHandler = { payload in
            await HubIPCClient.verifyVoiceGrantResponse(payload)
        }
    ) {
        self.issueHandler = issueHandler
        self.verifyHandler = verifyHandler
    }

    func authorize(
        request: SupervisorVoiceAuthorizationRequest,
        verification: SupervisorVoiceAuthorizationVerificationInput? = nil
    ) async -> SupervisorVoiceAuthorizationResolution {
        let issueResolution = await beginAuthorization(request)
        guard issueResolution.state != .failClosed,
              let challenge = issueResolution.challenge else {
            return issueResolution
        }
        guard let verification else {
            return issueResolution
        }
        return await verifyAuthorization(
            request: request,
            challenge: challenge,
            verification: verification
        )
    }

    func beginAuthorization(
        _ request: SupervisorVoiceAuthorizationRequest
    ) async -> SupervisorVoiceAuthorizationResolution {
        let requestId = normalized(request.requestId)
        let templateId = normalized(request.templateId)
        guard let requestId, let templateId else {
            return failClosedResolution(
                requestId: request.requestId,
                projectId: request.projectId,
                templateId: request.templateId,
                riskTier: request.riskTier,
                reasonCode: requestId == nil ? "request_id_empty" : "template_id_empty"
            )
        }

        let digests = Self.makeDigests(
            actionText: request.actionText,
            scopeText: request.scopeText,
            amountText: request.amountText
        )

        let payload = HubIPCClient.VoiceGrantChallengeRequestPayload(
            requestId: requestId,
            projectId: normalized(request.projectId),
            templateId: templateId,
            actionDigest: digests.actionDigest,
            scopeDigest: digests.scopeDigest,
            amountDigest: digests.amountDigest,
            challengeCode: normalized(request.challengeCode),
            riskLevel: hubRiskLevel(for: request.riskTier),
            boundDeviceId: normalized(request.boundDeviceId),
            mobileTerminalId: normalized(request.mobileTerminalId),
            allowVoiceOnly: shouldAllowVoiceOnly(for: request.riskTier),
            requiresMobileConfirm: shouldRequireMobileConfirmation(for: request.riskTier),
            ttlMs: max(10_000, min(600_000, request.ttlMs))
        )

        let issue = await issueHandler(payload)
        guard issue.ok, let challenge = issue.challenge else {
            return failClosedResolution(
                requestId: requestId,
                projectId: request.projectId,
                templateId: templateId,
                riskTier: request.riskTier,
                reasonCode: issue.reasonCode ?? "voice_grant_challenge_failed"
            )
        }

        let state: SupervisorVoiceAuthorizationResolution.State = challenge.requiresMobileConfirm
            ? .escalatedToMobile
            : .pending
        let nextAction = challenge.requiresMobileConfirm
            ? "先完成 mobile confirmation，再核验 spoken challenge"
            : "先采集 spoken response，再核验 challenge"

        return SupervisorVoiceAuthorizationResolution(
            schemaVersion: SupervisorVoiceAuthorizationResolution.currentSchemaVersion,
            state: state,
            ok: true,
            requestId: requestId,
            projectId: normalized(request.projectId),
            templateId: templateId,
            riskTier: request.riskTier.rawValue,
            challengeId: challenge.challengeId,
            challenge: challenge,
            verified: false,
            requiresMobileConfirm: challenge.requiresMobileConfirm,
            allowVoiceOnly: challenge.allowVoiceOnly,
            denyCode: nil,
            reasonCode: nil,
            transcriptHash: nil,
            semanticMatchScore: nil,
            policyRef: policyRef(
                state: state,
                riskTier: request.riskTier,
                denyCode: nil,
                reasonCode: nil,
                challenge: challenge
            ),
            nextAction: nextAction
        )
    }

    func verifyAuthorization(
        request: SupervisorVoiceAuthorizationRequest,
        challenge: HubIPCClient.VoiceGrantChallengeSnapshot,
        verification: SupervisorVoiceAuthorizationVerificationInput
    ) async -> SupervisorVoiceAuthorizationResolution {
        let requestId = normalized(verification.requestId)
        guard let requestId else {
            return failClosedResolution(
                requestId: verification.requestId,
                projectId: request.projectId,
                templateId: request.templateId,
                riskTier: request.riskTier,
                reasonCode: "request_id_empty",
                challenge: challenge
            )
        }

        let challengeId = normalized(challenge.challengeId)
        let verifyNonce = normalized(verification.verifyNonce)
        guard let challengeId, let verifyNonce else {
            return failClosedResolution(
                requestId: requestId,
                projectId: request.projectId,
                templateId: request.templateId,
                riskTier: request.riskTier,
                reasonCode: challengeId == nil ? "challenge_id_empty" : "verify_nonce_empty",
                challenge: challenge
            )
        }

        let parsedDigests = Self.makeDigests(
            actionText: verification.actionText,
            scopeText: verification.scopeText,
            amountText: verification.amountText
        )

        let verifyPayload = HubIPCClient.VoiceGrantVerificationPayload(
            requestId: requestId,
            projectId: normalized(request.projectId),
            challengeId: challengeId,
            challengeCode: normalized(verification.challengeCode) ?? normalized(challenge.challengeCode),
            transcript: verification.transcript,
            transcriptHash: normalized(verification.transcriptHash),
            semanticMatchScore: verification.semanticMatchScore,
            parsedActionDigest: parsedDigests.actionDigest,
            parsedScopeDigest: parsedDigests.scopeDigest,
            parsedAmountDigest: parsedDigests.amountDigest,
            verifyNonce: verifyNonce,
            boundDeviceId: normalized(verification.boundDeviceId) ?? normalized(challenge.boundDeviceId),
            mobileConfirmed: verification.mobileConfirmed
        )

        let result = await verifyHandler(verifyPayload)
        if result.ok, result.verified {
            return SupervisorVoiceAuthorizationResolution(
                schemaVersion: SupervisorVoiceAuthorizationResolution.currentSchemaVersion,
                state: .verified,
                ok: true,
                requestId: requestId,
                projectId: normalized(request.projectId),
                templateId: normalized(request.templateId) ?? request.templateId,
                riskTier: request.riskTier.rawValue,
                challengeId: result.challengeId ?? challenge.challengeId,
                challenge: challenge,
                verified: true,
                requiresMobileConfirm: challenge.requiresMobileConfirm,
                allowVoiceOnly: challenge.allowVoiceOnly,
                denyCode: nil,
                reasonCode: nil,
                transcriptHash: result.transcriptHash,
                semanticMatchScore: result.semanticMatchScore,
                policyRef: policyRef(
                    state: .verified,
                    riskTier: request.riskTier,
                    denyCode: nil,
                    reasonCode: nil,
                    challenge: challenge
                ),
                nextAction: "授权已通过，可以继续执行受控动作"
            )
        }

        if result.ok {
            return SupervisorVoiceAuthorizationResolution(
                schemaVersion: SupervisorVoiceAuthorizationResolution.currentSchemaVersion,
                state: .denied,
                ok: true,
                requestId: requestId,
                projectId: normalized(request.projectId),
                templateId: normalized(request.templateId) ?? request.templateId,
                riskTier: request.riskTier.rawValue,
                challengeId: result.challengeId ?? challenge.challengeId,
                challenge: challenge,
                verified: false,
                requiresMobileConfirm: challenge.requiresMobileConfirm,
                allowVoiceOnly: challenge.allowVoiceOnly,
                denyCode: result.denyCode ?? "voice_grant_denied",
                reasonCode: nil,
                transcriptHash: result.transcriptHash,
                semanticMatchScore: result.semanticMatchScore,
                policyRef: policyRef(
                    state: .denied,
                    riskTier: request.riskTier,
                    denyCode: result.denyCode,
                    reasonCode: nil,
                    challenge: challenge
                ),
                nextAction: nextActionForDenyCode(result.denyCode)
            )
        }

        return failClosedResolution(
            requestId: requestId,
            projectId: request.projectId,
            templateId: request.templateId,
            riskTier: request.riskTier,
            reasonCode: result.reasonCode ?? "voice_grant_verify_failed",
            challenge: challenge,
            transcriptHash: result.transcriptHash,
            semanticMatchScore: result.semanticMatchScore
        )
    }

    static func makeDigests(
        actionText: String,
        scopeText: String,
        amountText: String?
    ) -> SupervisorVoiceAuthorizationDigests {
        SupervisorVoiceAuthorizationDigests(
            actionDigest: semanticDigest(prefix: "action", value: actionText),
            scopeDigest: semanticDigest(prefix: "scope", value: scopeText),
            amountDigest: normalized(amountText).map { semanticDigest(prefix: "amount", value: $0) }
        )
    }

    private func failClosedResolution(
        requestId: String,
        projectId: String?,
        templateId: String,
        riskTier: LaneRiskTier,
        reasonCode: String,
        challenge: HubIPCClient.VoiceGrantChallengeSnapshot? = nil,
        transcriptHash: String? = nil,
        semanticMatchScore: Double? = nil
    ) -> SupervisorVoiceAuthorizationResolution {
        SupervisorVoiceAuthorizationResolution(
            schemaVersion: SupervisorVoiceAuthorizationResolution.currentSchemaVersion,
            state: .failClosed,
            ok: false,
            requestId: requestId,
            projectId: normalized(projectId),
            templateId: normalized(templateId) ?? templateId,
            riskTier: riskTier.rawValue,
            challengeId: challenge?.challengeId,
            challenge: challenge,
            verified: false,
            requiresMobileConfirm: challenge?.requiresMobileConfirm ?? shouldRequireMobileConfirmation(for: riskTier),
            allowVoiceOnly: challenge?.allowVoiceOnly ?? shouldAllowVoiceOnly(for: riskTier),
            denyCode: nil,
            reasonCode: reasonCode,
            transcriptHash: normalized(transcriptHash),
            semanticMatchScore: semanticMatchScore,
            policyRef: policyRef(
                state: .failClosed,
                riskTier: riskTier,
                denyCode: nil,
                reasonCode: reasonCode,
                challenge: challenge
            ),
            nextAction: nextActionForFailClosed(reasonCode)
        )
    }

    private func hubRiskLevel(for riskTier: LaneRiskTier) -> String {
        switch riskTier {
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .critical:
            return "high"
        }
    }

    private func shouldAllowVoiceOnly(for riskTier: LaneRiskTier) -> Bool {
        riskTier < .high
    }

    private func shouldRequireMobileConfirmation(for riskTier: LaneRiskTier) -> Bool {
        riskTier >= .high
    }

    private func policyRef(
        state: SupervisorVoiceAuthorizationResolution.State,
        riskTier: LaneRiskTier,
        denyCode: String?,
        reasonCode: String?,
        challenge: HubIPCClient.VoiceGrantChallengeSnapshot?
    ) -> String {
        [
            "schema=\(SupervisorVoiceAuthorizationResolution.currentSchemaVersion)",
            "state=\(state.rawValue)",
            "risk_tier=\(riskTier.rawValue)",
            "requires_mobile_confirm=\((challenge?.requiresMobileConfirm ?? shouldRequireMobileConfirmation(for: riskTier)) ? "true" : "false")",
            "allow_voice_only=\((challenge?.allowVoiceOnly ?? shouldAllowVoiceOnly(for: riskTier)) ? "true" : "false")",
            denyCode.map { "deny_code=\($0)" },
            reasonCode.map { "reason_code=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ";")
    }

    private func nextActionForDenyCode(_ denyCode: String?) -> String {
        switch normalized(denyCode) {
        case "voice_only_forbidden":
            return "当前风险档禁止纯语音放行；先完成配对手机确认，再重新发起新的 challenge"
        case "mobile_confirmation_required":
            return "当前 challenge 要求先完成 mobile confirmation；先在配对手机确认，再重新发起新的 challenge"
        case "challenge_missing":
            return "这次 spoken response 没对上有效 challenge；请重新发起新的 challenge，不要复用旧口令"
        case "semantic_ambiguous":
            return "这次 challenge 已被拒绝；请更清楚地重复授权短语，并重新发起新的 challenge"
        case "device_not_bound":
            return "当前回复不是来自绑定设备；切回预期语音设备后，重新发起新的 challenge"
        case "challenge_expired":
            return "当前 challenge 已过期；请重新发起新的 challenge，不要复用旧口令"
        case "replay_detected":
            return "当前 challenge 已被视为 replay；请重新发起 challenge，并使用新的 verify nonce"
        default:
            return "这次授权已拒绝；先修复 deny_code 对应前置条件，再重新发起新的 challenge"
        }
    }

    private func nextActionForFailClosed(_ reasonCode: String?) -> String {
        switch normalized(reasonCode) {
        case "hub_env_missing":
            return "Hub pairing/runtime profile 缺失；先修复 Hub pairing，再重新发起 voice authorization"
        case "voice_grant_file_ipc_not_supported":
            return "当前 file IPC 不支持 voice authorization；先切到 remote/grpc Hub transport，再重新发起 challenge"
        case "node_missing":
            return "本地运行时依赖缺失；先修复客户端依赖，再重新发起 voice authorization"
        case "challenge_expired":
            return "旧 challenge 已过期并已清理；不要复用旧口令，请重新发起新的 challenge"
        case "challenge_missing":
            return "当前 challenge 不存在或上下文已失效；请重新发起新的 challenge"
        case "replay_detected":
            return "当前 challenge 已进入 replay/fail-closed 处理；请清理旧状态后，用新的 challenge 和 verify nonce 重新开始"
        case "mobile_confirmation_missing":
            return "当前 challenge 仍保留；先完成配对手机确认，再用当前 challenge 继续核验"
        case "voice_authorization_not_started":
            return "当前没有活动中的语音挑战；请先发起新的 voice authorization"
        case "request_id_empty", "template_id_empty", "challenge_id_empty", "verify_nonce_empty":
            return "语音授权上下文不完整；请清理当前状态并重新发起新的 challenge"
        case "user_cancelled":
            return "这次 challenge 已取消；如果还要继续，请重新发起新的 voice authorization"
        case "remote_voice_grant_challenge_failed", "remote_voice_grant_verify_failed":
            return "远端 Hub 语音授权路由失败；先修复 pairing/transport，再重新发起新的 challenge"
        default:
            return "先继续阻塞受控动作，并优先修复上游 voice authorization route"
        }
    }

    private static func semanticDigest(prefix: String, value: String) -> String {
        let normalized = canonicalSemanticText(value)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let token = digest.map { String(format: "%02x", $0) }.joined()
        return "\(prefix):sha256:\(token)"
    }

    private static func canonicalSemanticText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalized(_ text: String?) -> String? {
        Self.normalized(text)
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
