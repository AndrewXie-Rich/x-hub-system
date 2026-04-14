import SwiftUI

enum HubActionChipMetrics {
    static let regularHeight: CGFloat = 36
}

struct HubActionChipContent: View {
    let title: String
    let systemName: String
    let foreground: Color
    let background: Color
    let border: Color
    let width: CGFloat?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.88)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(foreground)
        .frame(maxWidth: width == nil ? nil : .infinity, maxHeight: .infinity)
        .padding(.horizontal, 11)
        .frame(width: width, height: HubActionChipMetrics.regularHeight)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct HubFilledActionChipButton: View {
    let title: String
    let systemName: String
    let tint: Color
    let disabled: Bool
    let width: CGFloat?
    let help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HubActionChipContent(
                title: title,
                systemName: systemName,
                foreground: disabled ? .secondary : .white,
                background: disabled ? Color.white.opacity(0.06) : tint.opacity(0.92),
                border: disabled ? Color.white.opacity(0.08) : tint.opacity(0.98),
                width: width
            )
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(Text(title))
        .disabled(disabled)
    }
}

struct HubTonedActionChip: View {
    let title: String
    let systemName: String
    let tint: Color
    let width: CGFloat?
    let help: String?

    var body: some View {
        HubActionChipContent(
            title: title,
            systemName: systemName,
            foreground: tint,
            background: tint.opacity(0.14),
            border: tint.opacity(0.28),
            width: width
        )
        .help(help ?? title)
        .accessibilityLabel(Text(title))
    }
}

struct HubNeutralActionChipButton: View {
    let title: String
    let systemName: String
    let width: CGFloat?
    let help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HubNeutralActionChipLabel(
                title: title,
                systemName: systemName,
                width: width
            )
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(Text(title))
    }
}

struct HubNeutralActionChipLabel: View {
    let title: String
    let systemName: String
    let width: CGFloat?

    var body: some View {
        HubActionChipContent(
            title: title,
            systemName: systemName,
            foreground: .primary,
            background: Color.white.opacity(0.06),
            border: Color.white.opacity(0.08),
            width: width
        )
    }
}
