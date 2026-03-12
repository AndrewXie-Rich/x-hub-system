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
            ? "complete mobile confirmation, then verify the spoken challenge"
            : "capture the spoken response and verify the challenge"

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
                nextAction: "authorization verified; proceed with the gated action"
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
            return "complete the required mobile confirmation before retrying verify"
        case "mobile_confirmation_required":
            return "confirm on the paired mobile terminal, then retry verify"
        case "challenge_missing":
            return "issue a new challenge and retry verification"
        case "semantic_ambiguous":
            return "repeat the authorization phrase more clearly and retry verify"
        case "device_not_bound":
            return "re-bind the expected voice device before retrying"
        case "challenge_expired":
            return "issue a new challenge because the current one expired"
        case "replay_detected":
            return "issue a fresh challenge and use a new verify nonce"
        default:
            return "authorization denied; inspect deny_code and retry only after the prerequisite is satisfied"
        }
    }

    private func nextActionForFailClosed(_ reasonCode: String?) -> String {
        switch normalized(reasonCode) {
        case "hub_env_missing":
            return "repair Hub pairing/runtime profile before retrying voice authorization"
        case "voice_grant_file_ipc_not_supported":
            return "switch XT to remote/grpc Hub transport; file IPC cannot service voice authorization"
        case "node_missing":
            return "repair the client runtime dependency before retrying voice authorization"
        default:
            return "hold the gated action and repair the upstream voice authorization route first"
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
