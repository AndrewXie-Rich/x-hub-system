import SwiftUI

extension SupervisorHeaderControlTone {
    var color: Color {
        switch self {
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

enum SupervisorSignalSummaryActionStyle {
    case standard
    case prominent
}

struct SupervisorSignalSummaryActionDescriptor {
    var label: String
    var tone: SupervisorHeaderControlTone
    var style: SupervisorSignalSummaryActionStyle
    var isEnabled: Bool
    var handler: () -> Void
}

struct SupervisorSignalSummaryCard: View {
    let badgeText: String
    let badgeTone: SupervisorHeaderControlTone
    let badgeEmphasized: Bool
    let eyebrowText: String
    let headlineText: String
    let headlineTone: SupervisorHeaderControlTone
    let headlineFont: Font
    let detailText: String
    let metadataText: String
    let backgroundColor: Color
    let borderColor: Color
    let actionDescriptor: SupervisorSignalSummaryActionDescriptor?

    init(
        badgeText: String,
        badgeTone: SupervisorHeaderControlTone,
        badgeEmphasized: Bool = true,
        eyebrowText: String,
        headlineText: String,
        headlineTone: SupervisorHeaderControlTone,
        headlineFont: Font = .headline,
        detailText: String,
        metadataText: String,
        backgroundColor: Color,
        borderColor: Color,
        actionDescriptor: SupervisorSignalSummaryActionDescriptor? = nil
    ) {
        self.badgeText = badgeText
        self.badgeTone = badgeTone
        self.badgeEmphasized = badgeEmphasized
        self.eyebrowText = eyebrowText
        self.headlineText = headlineText
        self.headlineTone = headlineTone
        self.headlineFont = headlineFont
        self.detailText = detailText
        self.metadataText = metadataText
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.actionDescriptor = actionDescriptor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                chip
                Text(eyebrowText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(headlineText)
                .font(headlineFont)
                .foregroundStyle(headlineTone.color)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailText)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 8) {
                Text(metadataText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                actionButton
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var chip: some View {
        Text(badgeText)
            .font(.caption2.weight(.semibold))
            .foregroundColor(badgeEmphasized ? badgeTone.color : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        badgeEmphasized
                            ? badgeTone.color.opacity(0.14)
                            : Color.secondary.opacity(0.08)
                    )
            )
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionDescriptor {
            if actionDescriptor.style == .prominent {
                Button(actionDescriptor.label) {
                    actionDescriptor.handler()
                }
                .buttonStyle(.borderedProminent)
                .tint(actionDescriptor.tone.color)
                .controlSize(.small)
                .disabled(!actionDescriptor.isEnabled)
            } else {
                Button(actionDescriptor.label) {
                    actionDescriptor.handler()
                }
                .buttonStyle(.bordered)
                .tint(actionDescriptor.tone.color)
                .controlSize(.small)
                .disabled(!actionDescriptor.isEnabled)
            }
        }
    }
}
