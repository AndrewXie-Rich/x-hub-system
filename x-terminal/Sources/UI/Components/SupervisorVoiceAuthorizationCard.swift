import Foundation
import SwiftUI

struct SupervisorVoiceAuthorizationCard: View {
    @ObservedObject var supervisorManager: SupervisorManager

    @State private var transcriptDraft: String = ""
    @State private var verifyInFlight = false
    @State private var restartInFlight = false
    @State private var challengeDiagnosticsExpanded = false

    private var resolution: SupervisorVoiceAuthorizationResolution? {
        supervisorManager.voiceAuthorizationResolution
    }

    private var challenge: HubIPCClient.VoiceGrantChallengeSnapshot? {
        supervisorManager.activeVoiceChallenge ?? resolution?.challenge
    }

    private var hasActiveChallenge: Bool {
        supervisorManager.activeVoiceChallenge != nil
    }

    private var canRestartChallenge: Bool {
        supervisorManager.canRestartLastVoiceAuthorizationChallengeFromUI()
    }

    private var guidance: SupervisorVoiceAuthorizationGuidancePresentation? {
        guard let resolution else { return nil }
        return SupervisorVoiceAuthorizationGuidancePresentationBuilder.build(
            resolution: resolution,
            challenge: challenge
        )
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
                    Text("高风险动作会先暂停，等 Hub 完成口令核验后再继续。")
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

            if let guidance {
                guidanceDetails(guidance)
            }

            if let challenge {
                challengeDetails(challenge)
            }

            if shouldShowVoiceSafetyEvidence {
                voiceSafetyEvidenceDetails
            }

            if hasActiveChallenge {
                verificationControls
            } else if resolution != nil {
                HStack(spacing: 10) {
                    Spacer()

                    if canRestartChallenge {
                        Button {
                            Task {
                                await restartChallenge()
                            }
                        } label: {
                            if restartInFlight {
                                Label("重发中...", systemImage: "arrow.trianglehead.clockwise")
                            } else {
                                Label("重新发起挑战", systemImage: "arrow.trianglehead.clockwise")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(restartInFlight)
                    }

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

    private var shouldShowVoiceSafetyEvidence: Bool {
        !supervisorManager.voiceReplaySummary.isEmpty
            || supervisorManager.voiceSafetyInvariantReport.updatedAt > 0
    }

    @ViewBuilder
    private func voiceStateBadge(for resolution: SupervisorVoiceAuthorizationResolution) -> some View {
        let state = uiState(for: resolution)
        Label(surfaceLabel(for: state), systemImage: state.iconName)
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
            Text("挑战信息")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(minimum: 180), spacing: 12), GridItem(.flexible(minimum: 180), spacing: 12)], alignment: .leading, spacing: 8) {
                challengeDetailRow(title: "挑战 ID", value: challenge.challengeId)
                challengeDetailRow(title: "风险等级", value: voiceRiskLevelLabel(challenge.riskLevel))
                challengeDetailRow(title: "当前口令", value: challenge.challengeCode)
                challengeDetailRow(title: "过期时间", value: expiryText(for: challenge.expiresAtMs))

                if !challenge.boundDeviceId.isEmpty {
                    challengeDetailRow(title: "语音设备", value: challenge.boundDeviceId)
                }
                if !challenge.mobileTerminalId.isEmpty {
                    challengeDetailRow(title: "移动端终端", value: challenge.mobileTerminalId)
                }
            }

            if let resolution, !resolution.policyRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup(isExpanded: $challengeDiagnosticsExpanded) {
                    Text("策略引用：\(resolution.policyRef)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                } label: {
                    HStack {
                        Text("原始诊断")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(challengeDiagnosticsExpanded ? "展开中" : "已折叠")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
    private func guidanceDetails(_ guidance: SupervisorVoiceAuthorizationGuidancePresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("恢复指引")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(guidance.summary)
                .font(UIThemeTokens.bodyFont())
                .foregroundStyle(.primary)

            ForEach(Array(guidance.instructions.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(line)
                        .font(UIThemeTokens.bodyFont())
                        .foregroundStyle(.primary)
                }
            }

            if let caution = guidance.caution, !caution.isEmpty {
                Label(caution, systemImage: "exclamationmark.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
    private var voiceSafetyEvidenceDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("回放与安全")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !supervisorManager.voiceReplaySummary.isEmpty {
                SupervisorVoiceEvidenceSummaryRowView(
                    title: "回放核对",
                    state: supervisorManager.voiceReplaySummary.overallState.surfaceState,
                    headline: supervisorManager.voiceReplaySummary.headline,
                    summary: supervisorManager.voiceReplaySummary.summaryLine,
                    detail: supervisorManager.voiceReplaySummary.compactTimelineText
                )
            }

            if supervisorManager.voiceSafetyInvariantReport.updatedAt > 0 {
                SupervisorVoiceEvidenceSummaryRowView(
                    title: "安全约束",
                    state: supervisorManager.voiceSafetyInvariantReport.overallState.surfaceState,
                    headline: supervisorManager.voiceSafetyInvariantReport.headline,
                    summary: supervisorManager.voiceSafetyInvariantReport.summaryLine,
                    detail: nil
                )

                ForEach(supervisorManager.voiceSafetyInvariantReport.checks) { check in
                    SupervisorVoiceInvariantCheckRowView(check: check)
                }
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
                    Text("当前口令：\(challengeCode)")
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
                    _ = supervisorManager.repeatActiveVoiceAuthorizationPromptFromUI()
                } label: {
                    Label("重读挑战", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
                .disabled(verifyInFlight)

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

    private func restartChallenge() async {
        restartInFlight = true
        defer { restartInFlight = false }
        resetDraftState()
        _ = await supervisorManager.restartLastVoiceAuthorizationChallengeFromUI()
        syncDraftStateFromCurrentChallenge()
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
            return "语音授权暂时没走通"
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
            return "这条语音授权链路没能完整走通，所以这次受控动作会继续暂停，而不是假装已经恢复。"
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
            return "传输、运行时或挑战前置条件还不完整，系统会先停在安全状态，而不是假装已经恢复。"
        }
    }

    private func hardLine(for resolution: SupervisorVoiceAuthorizationResolution) -> String {
        switch resolution.state {
        case .verified:
            return "只有核验通过后，受控动作才会放行"
        case .denied:
            return "被拒绝的授权不会自动重试"
        case .pending, .escalatedToMobile, .failClosed:
            return "核验完成前，受控动作保持暂停"
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

    private func voiceRiskLevelLabel(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low":
            return "低风险"
        case "medium", "moderate":
            return "中风险"
        case "high":
            return "高风险"
        case "critical":
            return "关键风险"
        default:
            return raw
        }
    }

    private func surfaceLabel(for state: XTUISurfaceState) -> String {
        switch state {
        case .ready:
            return "已就绪"
        case .inProgress:
            return "处理中"
        case .grantRequired:
            return "待授权"
        case .permissionDenied:
            return "权限被拒"
        case .blockedWaitingUpstream:
            return "被上游阻塞"
        case .releaseFrozen:
            return "已冻结"
        case .diagnosticRequired:
            return "需要排查"
        }
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

private struct SupervisorVoiceInvariantCheckRowView: View {
    let check: VoiceSafetyInvariantCheck

    @State private var diagnosticsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Label(check.kind.title, systemImage: check.status.surfaceState.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(check.status.surfaceState.tint)
                Spacer(minLength: 0)
                Text(check.status.localizedLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(check.status.surfaceState.tint)
            }

            Text(check.summary)
                .font(.caption)
                .foregroundStyle(.primary)

            Text(check.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let evidenceLine {
                DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                    Text(evidenceLine)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 6)
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
        .padding(.vertical, 4)
    }

    private var evidenceLine: String? {
        let trimmed = check.evidence.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
