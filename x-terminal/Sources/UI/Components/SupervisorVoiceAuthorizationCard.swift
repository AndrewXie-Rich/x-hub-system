import Foundation
import SwiftUI

struct SupervisorVoiceAuthorizationCard: View {
    @ObservedObject var supervisorManager: SupervisorManager

    @State private var transcriptDraft: String = ""
    @State private var verifyInFlight = false

    private var resolution: SupervisorVoiceAuthorizationResolution? {
        supervisorManager.voiceAuthorizationResolution
    }

    private var challenge: HubIPCClient.VoiceGrantChallengeSnapshot? {
        supervisorManager.activeVoiceChallenge ?? resolution?.challenge
    }

    private var hasActiveChallenge: Bool {
        supervisorManager.activeVoiceChallenge != nil
    }

    private var challengeKey: String {
        challenge?.challengeId ?? "none"
    }

    private var mobileConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                supervisorManager.voiceAuthorizationMobileConfirmationLatched
            },
            set: { confirmed in
                supervisorManager.setVoiceAuthorizationMobileConfirmed(
                    confirmed,
                    source: "voice_authorization_card",
                    emitSystemMessage: false
                )
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice Authorization")
                        .font(UIThemeTokens.sectionFont())
                    Text("High-risk actions remain fail-closed until Hub verifies the spoken challenge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if let resolution {
                    voiceStateBadge(for: resolution)
                }
            }

            if let explanation {
                StatusExplanationCard(explanation: explanation)
            }

            if let challenge {
                challengeDetails(challenge)
            }

            if hasActiveChallenge {
                verificationControls
            } else if resolution != nil {
                HStack {
                    Spacer()
                    Button("Clear voice auth state") {
                        supervisorManager.resetVoiceAuthorizationState()
                        resetDraftState()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .onAppear {
            syncDraftStateFromCurrentChallenge()
        }
        .onChange(of: challengeKey) { _ in
            syncDraftStateFromCurrentChallenge()
        }
    }

    private var explanation: StatusExplanation? {
        guard let resolution else { return nil }

        let highlights = [
            "risk_tier=\(resolution.riskTier)",
            resolution.challengeId.map { "challenge_id=\($0)" },
            resolution.denyCode.map { "deny_code=\($0)" },
            resolution.reasonCode.map { "reason_code=\($0)" },
            "requires_mobile_confirm=\(resolution.requiresMobileConfirm ? "true" : "false")",
            "allow_voice_only=\(resolution.allowVoiceOnly ? "true" : "false")",
            resolution.semanticMatchScore.map { "semantic_match_score=\(String(format: "%.2f", $0))" },
            resolution.transcriptHash.map { "transcript_hash=\($0)" }
        ]
        .compactMap { $0 }

        return StatusExplanation(
            state: uiState(for: resolution),
            headline: headline(for: resolution),
            whatHappened: whatHappened(for: resolution),
            whyItHappened: whyItHappened(for: resolution),
            userAction: resolution.nextAction,
            machineStatusRef: machineStatusRef(for: resolution),
            hardLine: hardLine(for: resolution),
            highlights: highlights
        )
    }

    @ViewBuilder
    private func voiceStateBadge(for resolution: SupervisorVoiceAuthorizationResolution) -> some View {
        let state = uiState(for: resolution)
        Label(state.label, systemImage: state.iconName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(UIThemeTokens.stateBackground(for: state))
            )
            .overlay(
                Capsule()
                    .stroke(state.tint.opacity(0.24), lineWidth: 1)
            )
            .foregroundStyle(state.tint)
    }

    @ViewBuilder
    private func challengeDetails(_ challenge: HubIPCClient.VoiceGrantChallengeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Challenge Details")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(minimum: 180), spacing: 12), GridItem(.flexible(minimum: 180), spacing: 12)], alignment: .leading, spacing: 8) {
                challengeDetailRow(title: "Challenge ID", value: challenge.challengeId)
                challengeDetailRow(title: "Risk level", value: challenge.riskLevel)
                challengeDetailRow(title: "Spoken code", value: challenge.challengeCode)
                challengeDetailRow(title: "Expires", value: expiryText(for: challenge.expiresAtMs))

                if !challenge.boundDeviceId.isEmpty {
                    challengeDetailRow(title: "Voice device", value: challenge.boundDeviceId)
                }
                if !challenge.mobileTerminalId.isEmpty {
                    challengeDetailRow(title: "Mobile terminal", value: challenge.mobileTerminalId)
                }
            }

            if let resolution {
                Text("policy_ref: \(resolution.policyRef)")
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.secondaryCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var verificationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verify Spoken Response")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Paste or dictate the spoken authorization phrase", text: $transcriptDraft)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                VoiceInputButton(text: $transcriptDraft, autoAppend: true)

                if let challengeCode = challenge?.challengeCode, !challengeCode.isEmpty {
                    Text("Target code: \(challengeCode)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if resolution?.requiresMobileConfirm == true {
                Toggle("Paired mobile confirmation already completed", isOn: mobileConfirmationBinding)
                    .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await submitVerification()
                    }
                } label: {
                    if verifyInFlight {
                        Label("Verifying...", systemImage: "waveform.badge.magnifyingglass")
                    } else {
                        Label("Retry Verify", systemImage: "waveform.badge.checkmark")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(verifyInFlight || transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel challenge") {
                    supervisorManager.cancelVoiceAuthorization()
                    resetDraftState()
                }
                .buttonStyle(.bordered)
                .disabled(verifyInFlight)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.secondaryCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func challengeDetailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func submitVerification() async {
        verifyInFlight = true
        defer { verifyInFlight = false }
        let trimmedTranscript = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = await supervisorManager.retryVoiceAuthorizationVerification(
            transcript: trimmedTranscript,
            semanticMatchScore: 0.99
        )
        if supervisorManager.activeVoiceChallenge == nil {
            resetDraftState()
        }
    }

    private func syncDraftStateFromCurrentChallenge() {
        if !hasActiveChallenge {
            transcriptDraft = ""
        }
    }

    private func resetDraftState() {
        transcriptDraft = ""
    }

    private func uiState(for resolution: SupervisorVoiceAuthorizationResolution) -> XTUISurfaceState {
        switch resolution.state {
        case .pending:
            return .inProgress
        case .verified:
            return .ready
        case .denied:
            return .permissionDenied
        case .escalatedToMobile:
            return .grantRequired
        case .failClosed:
            switch resolution.reasonCode {
            case "hub_env_missing", "voice_grant_file_ipc_not_supported", "node_missing":
                return .diagnosticRequired
            default:
                return .blockedWaitingUpstream
            }
        }
    }

    private func headline(for resolution: SupervisorVoiceAuthorizationResolution) -> String {
        switch resolution.state {
        case .pending:
            return "Voice challenge issued and waiting for spoken verification"
        case .verified:
            return "Voice authorization verified"
        case .denied:
            return "Voice authorization denied"
        case .escalatedToMobile:
            return "Voice authorization requires paired mobile confirmation"
        case .failClosed:
            return "Voice authorization remains fail-closed"
        }
    }

    private func whatHappened(for resolution: SupervisorVoiceAuthorizationResolution) -> String {
        switch resolution.state {
        case .pending:
            return "Hub issued a voice challenge. XT is holding the gated action until the spoken response is verified."
        case .verified:
            return "The paired Hub accepted the spoken response and marked the challenge as verified."
        case .denied:
            return "Hub received the verification attempt but denied it under the current voice-grant policy."
        case .escalatedToMobile:
            return "The current challenge was issued, but the selected risk tier requires an extra confirmation on the paired mobile terminal."
        case .failClosed:
            return "The voice authorization path could not finish safely, so the gated action remains blocked instead of pretending it can recover."
        }
    }

    private func whyItHappened(for resolution: SupervisorVoiceAuthorizationResolution) -> String {
        switch resolution.state {
        case .pending:
            return "High-risk actions only proceed after the spoken challenge proves intent and device binding."
        case .verified:
            return "The stored request digests, device binding, and spoken response all satisfied the Hub-side verifier."
        case .denied:
            return "A deny_code was returned by Hub, so XT keeps the decision explicit and does not auto-retry behind the user."
        case .escalatedToMobile:
            return "The risk tier or challenge contract requires a second factor on mobile before voice-only verification can pass."
        case .failClosed:
            return "Transport, runtime, or challenge prerequisites were incomplete, and the contract requires an explicit fail-closed state."
        }
    }

    private func hardLine(for resolution: SupervisorVoiceAuthorizationResolution) -> String {
        switch resolution.state {
        case .verified:
            return "gated action stays blocked until Hub verification passes"
        case .denied:
            return "denied voice challenge must remain visible"
        case .pending, .escalatedToMobile, .failClosed:
            return "voice authorization remains fail-closed until verified"
        }
    }

    private func machineStatusRef(for resolution: SupervisorVoiceAuthorizationResolution) -> String {
        [
            "request_id=\(resolution.requestId)",
            "state=\(resolution.state.rawValue)",
            "risk_tier=\(resolution.riskTier)",
            "challenge_id=\(resolution.challengeId ?? "none")",
            "requires_mobile_confirm=\(resolution.requiresMobileConfirm ? "true" : "false")",
            "allow_voice_only=\(resolution.allowVoiceOnly ? "true" : "false")",
            resolution.denyCode.map { "deny_code=\($0)" },
            resolution.reasonCode.map { "reason_code=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "; ")
    }

    private func expiryText(for expiresAtMs: Double) -> String {
        let remaining = Int((expiresAtMs / 1000.0) - Date().timeIntervalSince1970)
        if remaining <= 0 {
            return "expired"
        }
        if remaining < 60 {
            return "\(remaining)s remaining"
        }
        return "\(remaining / 60)m \(remaining % 60)s remaining"
    }
}
