import SwiftUI

enum ProjectWorkHeaderActionStyle {
    case prominent
    case secondary
    case plain
}

struct ProjectWorkHeaderAction {
    let title: String
    var helpText: String? = nil
    var style: ProjectWorkHeaderActionStyle = .secondary
    var disabled: Bool = false
    let action: () -> Void
}

enum ProjectWorkHeaderText {
    static func firstLine(_ raw: String?) -> String? {
        raw?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

struct ProjectWorkHeaderCard: View {
    let icon: String
    let title: String
    let readinessText: String
    let readinessTone: ProjectCoderExecutionStatusTone
    let nextStepText: String
    var badgeText: String? = nil
    var detailText: String? = nil
    var statusPresentation: ProjectCoderExecutionStatusPresentation? = nil
    var primaryAction: ProjectWorkHeaderAction? = nil
    var secondaryAction: ProjectWorkHeaderAction? = nil
    var tertiaryAction: ProjectWorkHeaderAction? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let badgeText = sanitized(badgeText) {
                    Text(badgeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Text(readinessText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readinessTone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(readinessTone.color.opacity(0.12))
                    .clipShape(Capsule())

                Text(nextStepText)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            if let detailText = sanitized(detailText) {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statusPresentation {
                ProjectCoderExecutionStatusBar(
                    presentation: statusPresentation,
                    style: .inline
                )
            }

            if primaryAction != nil || secondaryAction != nil || tertiaryAction != nil {
                HStack(spacing: 8) {
                    if let primaryAction {
                        actionButton(primaryAction)
                    }

                    if let secondaryAction {
                        actionButton(secondaryAction)
                    }

                    if let tertiaryAction {
                        actionButton(tertiaryAction)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.secondary.opacity(0.18)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func actionButton(_ action: ProjectWorkHeaderAction) -> some View {
        switch action.style {
        case .prominent:
            Button(action.title, action: action.action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(action.disabled)
                .help(action.helpText ?? "")
        case .secondary:
            Button(action.title, action: action.action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(action.disabled)
                .help(action.helpText ?? "")
        case .plain:
            Button(action.title, action: action.action)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(action.disabled)
                .help(action.helpText ?? "")
        }
    }

    private func sanitized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
