import SwiftUI

struct SupervisorHeaderBar: View {
    let configuredModelId: String
    let snapshot: AXRoleExecutionSnapshot
    let hubInteractive: Bool
    let latestRuntimeActivityText: String?
    let context: SupervisorHeaderControls.Context
    let voiceStatus: SupervisorHeaderVoiceStatusPresentation
    let isProcessing: Bool
    let processingStatusText: String?
    let detectedBigTaskCandidate: SupervisorBigTaskCandidate?
    let bigTaskSceneHint: SupervisorBigTaskSceneHint?
    let heartbeatIconScale: CGFloat
    let onTriggerBigTask: (SupervisorBigTaskCandidate) -> Void
    let onDismissBigTask: (SupervisorBigTaskCandidate) -> Void
    let onVoiceCallAction: () -> Void
    let onAction: (SupervisorHeaderAction) -> Void

    @State private var voiceStatusPopoverPresented = false

    private var headerStatus: SupervisorHeaderStatusPresentation {
        SupervisorHeaderStatusResolver.map(
            snapshot: snapshot,
            hubInteractive: hubInteractive,
            latestRuntimeActivityText: latestRuntimeActivityText
        )
    }

    private var tooltip: String {
        ExecutionRoutePresentation.tooltip(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
    }

    private var modelLabel: String {
        ExecutionRoutePresentation.configuredModelLabel(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
    }

    private var routeDetailBadge: ExecutionRouteBadgePresentation? {
        ExecutionRoutePresentation.detailBadge(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
    }

    private var heartbeatButton: SupervisorHeaderButtonPresentation {
        SupervisorHeaderControls.presentation(
            for: .heartbeat,
            context: context
        )
    }

    private var operationsButton: SupervisorHeaderButtonPresentation {
        SupervisorHeaderControls.presentation(
            for: .operations,
            context: context
        )
    }

    private var supervisorSettingsButton: SupervisorHeaderButtonPresentation {
        SupervisorHeaderControls.presentation(
            for: .supervisorSettings,
            context: context
        )
    }

    private var clearConversationButton: SupervisorHeaderButtonPresentation {
        SupervisorHeaderControls.presentation(
            for: .clearConversation,
            context: context
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.accentColor)
                Text("Supervisor · \(modelLabel)")
                    .font(.headline)
                    .help(tooltip)
                XTCompactStatusPill(
                    iconName: statusIconName(for: headerStatus.tone),
                    text: headerStatus.text,
                    tint: statusColor(for: headerStatus.tone),
                    monospaced: true
                )
                    .help(tooltip)
                if let routeDetailBadge {
                    XTCompactStatusPill(
                        iconName: "point.3.connected.trianglepath.dotted",
                        text: routeDetailBadge.text,
                        tint: routeDetailBadge.color
                    )
                        .help(tooltip)
                }
                if let detailBadge = headerStatus.detailBadge {
                    XTCompactStatusPill(
                        iconName: statusIconName(for: detailBadge.tone),
                        text: detailBadge.text,
                        tint: statusColor(for: detailBadge.tone)
                    )
                        .help(detailBadge.helpText ?? tooltip)
                }
            }

            if let candidate = detectedBigTaskCandidate {
                HStack(spacing: 8) {
                    Button(action: { onTriggerBigTask(candidate) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("检测到大任务")
                                    .font(.caption.weight(.semibold))
                                Text(bigTaskSceneHint?.quickAccessLine ?? "一键建 job + initial plan")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(bigTaskHelpText(candidate: candidate))

                    Button {
                        onDismissBigTask(candidate)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.secondary.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("忽略这次大任务侦测")
                }
            }

            Spacer()

            if isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(processingStatusText ?? "处理中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                voiceIconButton
                    .help(voiceStatus.helpText)
                    .popover(isPresented: $voiceStatusPopoverPresented, arrowEdge: .bottom) {
                        SupervisorHeaderVoiceStatusPopover(
                            presentation: voiceStatus,
                            onPrimaryAction: {
                                voiceStatusPopoverPresented = false
                                onVoiceCallAction()
                            }
                        )
                    }

                iconButton(
                    operationsButton,
                    fallbackIconName: "square.grid.2x2"
                ) {
                    onAction(.operationsButtonTapped)
                }
                .help(operationsButton.helpText)

                iconButton(
                    heartbeatButton,
                    fallbackIconName: "heart",
                    scale: heartbeatIconScale
                ) {
                    onAction(.heartbeatButtonTapped)
                }
                .help(heartbeatButton.helpText)

                iconButton(
                    supervisorSettingsButton,
                    fallbackIconName: "slider.horizontal.3"
                ) {
                    onAction(.supervisorSettingsTapped)
                }
                .help(supervisorSettingsButton.helpText)

                Button(clearConversationButton.label ?? "清空") {
                    onAction(.clearConversationTapped)
                }
                .buttonStyle(.borderless)
                .help(clearConversationButton.helpText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var voiceIconButton: some View {
        let chromeColor = color(for: voiceStatus.chrome.tone)

        return Button {
            voiceStatusPopoverPresented.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(chromeColor.opacity(voiceStatus.chrome.fillOpacity))
                Circle()
                    .strokeBorder(
                        chromeColor.opacity(voiceStatus.chrome.strokeOpacity),
                        lineWidth: voiceStatus.chrome.strokeOpacity > 0 ? 1 : 0
                    )
                Image(systemName: voiceStatus.iconName)
                    .font(.system(size: 13, weight: voiceStatus.tone == .neutral ? .regular : .semibold))
                    .foregroundStyle(color(for: voiceStatus.tone))
            }
            .frame(width: 28, height: 28)
            .shadow(
                color: chromeColor.opacity(voiceStatus.chrome.shadowOpacity),
                radius: voiceStatus.chrome.shadowOpacity > 0 ? 6 : 0
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(
        _ presentation: SupervisorHeaderButtonPresentation,
        fallbackIconName: String,
        scale: CGFloat = 1.0,
        action: @escaping () -> Void
    ) -> some View {
        let chromeColor = color(for: presentation.chrome.tone)

        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(chromeColor.opacity(presentation.chrome.fillOpacity))
                Circle()
                    .strokeBorder(
                        chromeColor.opacity(presentation.chrome.strokeOpacity),
                        lineWidth: presentation.chrome.strokeOpacity > 0 ? 1 : 0
                    )
                Image(systemName: presentation.iconName ?? fallbackIconName)
                    .font(
                        .system(
                            size: 13,
                            weight: presentation.chrome.fillOpacity > 0 ? .semibold : .regular
                        )
                    )
                    .foregroundStyle(color(for: presentation.tone))
            }
            .frame(width: 28, height: 28)
            .shadow(
                color: chromeColor.opacity(presentation.chrome.shadowOpacity),
                radius: presentation.chrome.shadowOpacity > 0 ? 6 : 0
            )
            .scaleEffect(scale)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func color(for tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }

    private func statusIconName(for tone: SupervisorHeaderStatusTone) -> String {
        switch tone {
        case .neutral:
            return "circle"
        case .success:
            return "checkmark.circle.fill"
        case .caution:
            return "exclamationmark.circle"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .danger:
            return "xmark.octagon.fill"
        }
    }

    private func bigTaskHelpText(candidate: SupervisorBigTaskCandidate) -> String {
        guard let bigTaskSceneHint else {
            return candidate.goal
        }
        return """
\(candidate.goal)

\(bigTaskSceneHint.quickAccessLine)
\(bigTaskSceneHint.reason)
"""
    }

    private func statusColor(for tone: SupervisorHeaderStatusTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .caution:
            return .yellow
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

private struct SupervisorHeaderVoiceStatusPopover: View {
    let presentation: SupervisorHeaderVoiceStatusPresentation
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Label("语音", systemImage: presentation.iconName)
                    .font(.headline)
                    .foregroundStyle(color(for: presentation.tone))
                Spacer(minLength: 0)
            }

            voiceCallStatusBlock

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("核对证据")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(presentation.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if presentation.items.isEmpty {
                Text("还没有回放核对或安全约束证据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(presentation.items) { item in
                        SupervisorVoiceEvidenceSummaryRowView(
                            title: item.title,
                            state: item.state,
                            headline: item.headline,
                            summary: item.summary,
                            detail: item.detail
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
    }

    private var voiceCallStatusBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                statusBadge(
                    text: presentation.call.statusText,
                    tone: presentation.call.statusTone
                )

                Spacer(minLength: 8)

                Button(action: onPrimaryAction) {
                    Label(
                        presentation.call.buttonTitle,
                        systemImage: presentation.call.buttonIconName
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(color(for: presentation.call.buttonTone))
                .help(presentation.call.actionHelpText)
            }

            Text(presentation.call.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(presentation.call.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(color(for: presentation.call.statusTone).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusBadge(
        text: String,
        tone: SupervisorHeaderControlTone
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: tone))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color(for: tone))
        }
    }

    private func color(for tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}
