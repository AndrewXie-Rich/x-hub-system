import SwiftUI

enum SupervisorRuntimeStageProgress: String, Codable, Equatable {
    case pending = "pending"
    case active = "active"
    case completed = "completed"
    case blocked = "blocked"

    var label: String {
        switch self {
        case .pending:
            return "Pending"
        case .active:
            return "Live"
        case .completed:
            return "Done"
        case .blocked:
            return "Blocked"
        }
    }

    var iconName: String {
        switch self {
        case .pending:
            return "circle"
        case .active:
            return "record.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .blocked:
            return "exclamationmark.octagon.fill"
        }
    }
}

struct SupervisorRuntimeStageItemPresentation: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String?
    let progress: SupervisorRuntimeStageProgress
    let surfaceState: XTUISurfaceState
    let actionID: String?
    let actionLabel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case progress
        case surfaceState = "surface_state"
        case actionID = "action_id"
        case actionLabel = "action_label"
    }
}

struct SupervisorRuntimeStageRailPresentation: Codable, Equatable {
    let headline: String
    let summary: String
    let items: [SupervisorRuntimeStageItemPresentation]
    let machineStatusRef: String

    enum CodingKeys: String, CodingKey {
        case headline
        case summary
        case items
        case machineStatusRef = "machine_status_ref"
    }
}

struct OneShotRuntimeStageRail: View {
    let presentation: SupervisorRuntimeStageRailPresentation
    let onTap: ((SupervisorRuntimeStageItemPresentation) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "timeline.selection")
                    .font(.title3)
                    .foregroundStyle(UIThemeTokens.color(for: .inProgress))

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.headline)
                        .font(UIThemeTokens.sectionFont())
                    Text(presentation.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(presentation.items) { item in
                    stageItemContainer(item)
                }
            }

            Text("machine_status_ref: \(presentation.machineStatusRef)")
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
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
    private func stageItemContainer(_ item: SupervisorRuntimeStageItemPresentation) -> some View {
        if item.actionID != nil, let onTap {
            Button(action: { onTap(item) }) {
                stageItem(item)
            }
            .buttonStyle(.plain)
        } else {
            stageItem(item)
        }
    }

    @ViewBuilder
    private func stageItem(_ item: SupervisorRuntimeStageItemPresentation) -> some View {
        let tint = progressTint(for: item)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.progress.iconName)
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    Text(item.progress.label)
                        .font(.caption2)
                        .foregroundStyle(tint)
                }

                Spacer(minLength: 8)
            }

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let actionLabel = item.actionLabel, !actionLabel.isEmpty, item.actionID != nil {
                Text(actionLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(progressBackground(for: item))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }

    private func progressTint(for item: SupervisorRuntimeStageItemPresentation) -> Color {
        switch item.progress {
        case .pending:
            return .secondary
        case .completed:
            return UIThemeTokens.color(for: .ready)
        case .active, .blocked:
            return UIThemeTokens.color(for: item.surfaceState)
        }
    }

    private func progressBackground(for item: SupervisorRuntimeStageItemPresentation) -> Color {
        switch item.progress {
        case .pending:
            return Color.secondary.opacity(0.06)
        case .completed:
            return UIThemeTokens.stateBackground(for: .ready)
        case .active, .blocked:
            return UIThemeTokens.stateBackground(for: item.surfaceState)
        }
    }
}
