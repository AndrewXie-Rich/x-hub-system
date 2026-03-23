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
                    Text("语音授权")
                        .font(UIThemeTokens.sectionFont())
                    Text("高风险动作会保持 fail-closed，直到 Hub 完成口令核验。")
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
                    Button("清空语音授权状态") {
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
            Text("挑战详情")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(minimum: 180), spacing: 12), GridItem(.flexible(minimum: 180), spacing: 12)], alignment: .leading, spacing: 8) {
                challengeDetailRow(title: "挑战 ID", value: challenge.challengeId)
                challengeDetailRow(title: "风险等级", value: challenge.riskLevel)
                challengeDetailRow(title: "口令", value: challenge.challengeCode)
                challengeDetailRow(title: "过期时间", value: expiryText(for: challenge.expiresAtMs))

                if !challenge.boundDeviceId.isEmpty {
                    challengeDetailRow(title: "语音设备", value: challenge.boundDeviceId)
                }
                if !challenge.mobileTerminalId.isEmpty {
                    challengeDetailRow(title: "移动端终端", value: challenge.mobileTerminalId)
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
            Text("核验口令回复")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("粘贴或输入你刚才说出的授权短语", text: $transcriptDraft)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                VoiceInputButton(text: $transcriptDraft, autoAppend: true)

                if let challengeCode = challenge?.challengeCode, !challengeCode.isEmpty {
                    Text("目标口令: \(challengeCode)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if resolution?.requiresMobileConfirm == true {
                Toggle("已在配对手机上完成确认", isOn: mobileConfirmationBinding)
                    .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await submitVerification()
                    }
                } label: {
                    if verifyInFlight {
                        Label("核验中...", systemImage: "waveform.badge.magnifyingglass")
                    } else {
                        Label("重新核验", systemImage: "waveform.badge.checkmark")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(verifyInFlight || transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("取消挑战") {
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
            return "语音挑战已发出，等待口令核验"
        case .verified:
            return "语音授权已通过"
        case .denied:
            return "语音授权被拒绝"
        case .escalatedToMobile:
            return "语音授权需要配对手机确认"
        case .failClosed:
            return "语音授权仍保持 fail-closed"
        }
    }

    private func whatHappened(for resolution: SupervisorVoiceAuthorizationResolution) -> String {
        switch resolution.state {
        case .pending:
            return "Hub 已发出语音挑战。在口令核验通过前，XT 会继续拦住这次受控动作。"
        case .verified:
            return "配对的 Hub 已接受这次口令回复，并把挑战标记为已验证。"
        case .denied:
            return "Hub 已收到这次核验尝试，但按当前语音授权策略拒绝了它。"
        case .escalatedToMobile:
            return "当前挑战已经发出，但所选风险等级要求在配对移动端再做一次确认。"
        case .failClosed:
            return "这条语音授权链路没能安全完成，所以受控动作会继续保持阻塞，而不是假装已经恢复。"
        }
    }

    private func whyItHappened(for resolution: SupervisorVoiceAuthorizationResolution) -> String {
        switch resolution.state {
        case .pending:
            return "高风险动作只有在口令确认了用户意图和设备绑定之后才会继续。"
        case .verified:
            return "请求摘要、设备绑定和口令回复都通过了 Hub 侧校验器。"
        case .denied:
            return "Hub 返回了 deny_code，所以 XT 会把这次拒绝明确展示出来，不会在背后悄悄重试。"
        case .escalatedToMobile:
            return "当前风险等级或挑战契约要求先完成移动端二次确认，纯语音核验才可能通过。"
        case .failClosed:
            return "传输、运行时或挑战前置条件不完整，而当前契约要求显式保持 fail-closed。"
        }
    }

    private func hardLine(for resolution: SupervisorVoiceAuthorizationResolution) -> String {
        switch resolution.state {
        case .verified:
            return "Hub 完成核验前，受控动作不会放行"
        case .denied:
            return "被拒绝的语音挑战必须保持可见"
        case .pending, .escalatedToMobile, .failClosed:
            return "语音授权在核验完成前都保持 fail-closed"
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
            return "已过期"
        }
        if remaining < 60 {
            return "\(remaining) 秒后过期"
        }
        return "\(remaining / 60) 分 \(remaining % 60) 秒后过期"
    }
}
