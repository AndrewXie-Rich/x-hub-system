import SwiftUI

struct ProjectWorkEmptyStateAction {
    let title: String
    var subtitle: String? = nil
    var style: ProjectWorkHeaderActionStyle = .secondary
    let action: () -> Void
}

struct ProjectWorkEmptyStateView: View {
    let title: String
    let summaryText: String
    var detailText: String? = nil
    var actions: [ProjectWorkEmptyStateAction] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)

                    Image(systemName: "hammer.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 18, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))

                    Text(summaryText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let detailText = sanitized(detailText) {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !actions.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        actionRow(action)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 760, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func actionRow(_ action: ProjectWorkEmptyStateAction) -> some View {
        Button(action: action.action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(actionForegroundColor(action.style))

                    if let subtitle = sanitized(action.subtitle) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(actionSubtitleColor(action.style))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(actionForegroundColor(action.style))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(actionBackground(action.style))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(actionBorderColor(action.style), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func actionBackground(_ style: ProjectWorkHeaderActionStyle) -> Color {
        switch style {
        case .prominent:
            return Color.accentColor.opacity(0.14)
        case .secondary:
            return Color.secondary.opacity(0.08)
        case .plain:
            return Color.clear
        }
    }

    private func actionBorderColor(_ style: ProjectWorkHeaderActionStyle) -> Color {
        switch style {
        case .prominent:
            return Color.accentColor.opacity(0.18)
        case .secondary:
            return Color.secondary.opacity(0.12)
        case .plain:
            return Color.secondary.opacity(0.08)
        }
    }

    private func actionForegroundColor(_ style: ProjectWorkHeaderActionStyle) -> Color {
        switch style {
        case .prominent:
            return Color.accentColor
        case .secondary, .plain:
            return .primary
        }
    }

    private func actionSubtitleColor(_ style: ProjectWorkHeaderActionStyle) -> Color {
        switch style {
        case .prominent:
            return Color.accentColor.opacity(0.85)
        case .secondary, .plain:
            return .secondary
        }
    }

    private func sanitized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
