import SwiftUI

struct ProjectGovernanceQuickAccessStrip: View {
    enum DisplayStyle {
        case regular
        case compact
    }

    struct Item: Identifiable {
        let destination: XTProjectGovernanceDestination
        let title: String
        let compactTitle: String
        let detail: String
        let iconName: String

        var id: String { destination.rawValue }
    }

    var selectedDestination: XTProjectGovernanceDestination?
    var governancePresentation: ProjectGovernancePresentation? = nil
    var enabled: Bool = true
    var displayStyle: DisplayStyle = .regular
    var onSelect: (XTProjectGovernanceDestination) -> Void

    private let items: [Item] = [
        Item(
            destination: .executionTier,
            title: "A-Tier",
            compactTitle: "A-Tier",
            detail: "决定 Project AI 最多能做到哪一步",
            iconName: "figure.run"
        ),
        Item(
            destination: .supervisorTier,
            title: "S-Tier",
            compactTitle: "S-Tier",
            detail: "决定 Supervisor 会盯多深、介入多积极",
            iconName: "person.crop.circle.badge.checkmark"
        ),
        Item(
            destination: .heartbeatReview,
            title: "Heartbeat / Review",
            compactTitle: "HB/Review",
            detail: "决定多久看一次、什么事件会触发 review / guidance",
            iconName: "waveform.path.ecg"
        )
    ]

    var body: some View {
        Group {
            switch displayStyle {
            case .regular:
                VStack(alignment: .leading, spacing: 10) {
                    Text("治理快捷入口")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 10) {
                        ForEach(items) { item in
                            quickAccessButton(item)
                        }
                    }

                    Text("A-Tier、S-Tier 和 Heartbeat / Review 是三根独立拨盘；overview 里另外会展示 role-aware memory、双环治理和 hard boundaries。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .compact:
                ViewThatFits(in: .horizontal) {
                    compactButtonsRow(items)

                    VStack(alignment: .leading, spacing: 8) {
                        compactButtonsRow(Array(items.prefix(2)))
                        compactButtonsRow(Array(items.suffix(from: 2)))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func compactButtonsRow(_ rowItems: [Item]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(rowItems) { item in
                compactQuickAccessButton(item)
            }
        }
    }

    private func quickAccessButton(_ item: Item) -> some View {
        let isSelected = selectedDestination == item.destination
        let tint = accentColor(for: item.destination)

        return Button {
            onSelect(item.destination)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: item.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? tint : Color.primary)

                    Spacer(minLength: 0)

                    Text(item.destination.localizedDisplayTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? tint : .secondary)
                }

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? tint.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? tint.opacity(0.45) : Color.secondary.opacity(0.14),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .help(
            enabled
                ? helpText(for: item.destination)
                : "当前项目未绑定可编辑的治理上下文"
        )
    }

    private func compactQuickAccessButton(_ item: Item) -> some View {
        let isSelected = selectedDestination == item.destination
        let tint = accentColor(for: item.destination)

        return Button {
            onSelect(item.destination)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.iconName)
                    .font(.system(size: 11, weight: .semibold))

                Text(item.compactTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
            }
            .foregroundStyle(isSelected ? tint : Color.primary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? tint.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? tint.opacity(0.42) : Color.secondary.opacity(0.14),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .help(
            enabled
                ? helpText(for: item.destination)
                : "当前项目未绑定可编辑的治理上下文"
        )
    }

    private func accentColor(for destination: XTProjectGovernanceDestination) -> Color {
        switch destination {
        case .executionTier:
            return governancePresentation.map {
                ProjectGovernanceComposerAccentTone.forExecutionTier($0.executionTier).color
            } ?? ProjectGovernanceComposerAccentTone.blue.color
        case .supervisorTier:
            return governancePresentation.map {
                ProjectGovernanceComposerAccentTone.forSupervisorTier($0.supervisorInterventionTier).color
            } ?? ProjectGovernanceComposerAccentTone.green.color
        case .heartbeatReview:
            return governancePresentation.map {
                ProjectGovernanceComposerAccentTone.forReviewPolicy($0.reviewPolicyMode).color
            } ?? ProjectGovernanceComposerAccentTone.teal.color
        case .overview:
            return ProjectGovernanceComposerAccentTone.blue.color
        case .uiReview:
            return ProjectGovernanceComposerAccentTone.teal.color
        }
    }

    private func helpText(for destination: XTProjectGovernanceDestination) -> String {
        switch destination {
        case .executionTier:
            return "打开 A-Tier 设置"
        case .supervisorTier:
            return "打开 S-Tier 设置"
        case .heartbeatReview:
            return "打开 Heartbeat / Review 设置"
        case .overview:
            return "打开治理概览"
        case .uiReview:
            return "打开 UI 审查"
        }
    }
}
