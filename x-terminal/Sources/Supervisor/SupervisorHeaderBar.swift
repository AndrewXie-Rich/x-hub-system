import SwiftUI

struct SupervisorHeaderBar: View {
    let configuredModelId: String
    let snapshot: AXRoleExecutionSnapshot
    let hubInteractive: Bool
    let latestRuntimeActivityText: String?
    let context: SupervisorHeaderControls.Context
    let isProcessing: Bool
    let detectedBigTaskCandidate: SupervisorBigTaskCandidate?
    let heartbeatIconScale: CGFloat
    let onTriggerBigTask: (SupervisorBigTaskCandidate) -> Void
    let onAction: (SupervisorHeaderAction) -> Void

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

    private var signalAction: SupervisorHeaderControls.SignalActionPresentation? {
        SupervisorHeaderControls.signalAction(context: context)
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
                Text(headerStatus.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(statusColor(for: headerStatus.tone))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(for: headerStatus.tone).opacity(0.12))
                    .clipShape(Capsule())
                    .help(tooltip)
                if let routeDetailBadge {
                    Text(routeDetailBadge.text)
                        .font(.caption)
                        .foregroundStyle(routeDetailBadge.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(routeDetailBadge.color.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .help(tooltip)
                }
                if let detailBadge = headerStatus.detailBadge {
                    Text(detailBadge.text)
                        .font(.caption)
                        .foregroundStyle(statusColor(for: detailBadge.tone))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(for: detailBadge.tone).opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .help(detailBadge.helpText ?? tooltip)
                }
            }

            if let candidate = detectedBigTaskCandidate {
                Button(action: { onTriggerBigTask(candidate) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("检测到大任务")
                                .font(.caption.weight(.semibold))
                            Text("自动建任务与初始计划")
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
                .help(candidate.goal)
            }

            if let signalAction {
                Button(
                    action: {
                        onAction(.focusSignalCenterOverview(signalAction.action))
                    }
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                        Text(signalAction.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(signalAction.tone.color)
                    .background(signalAction.tone.color.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(signalAction.helpText)
            }

            Spacer()

            if isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("处理中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
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
