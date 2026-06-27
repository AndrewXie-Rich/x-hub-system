import SwiftUI
import RELFlowHubCore

struct ModelsDrawerUsageWindowDisplay: Identifiable {
    var id: String
    var title: String
    var percentText: String
    var resetText: String
    var progress: Double
    var tint: Color
}

struct ModelsDrawerPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelsDrawerStatusPill: View {
    var title: String
    var systemName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
}

struct ModelsDrawerIconOnlyButton: View {
    var title: String
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.medium)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(title)
        .accessibilityLabel(Text(title))
    }
}

struct ModelsDrawerActionChip: View {
    var title: String
    var systemName: String
    var tint: Color
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ModelsDrawerActionChipLabel(
                title: title,
                systemName: systemName,
                tint: tint,
                disabled: disabled
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct ModelsDrawerActionChipLabel: View {
    var title: String
    var systemName: String
    var tint: Color
    var disabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(disabled ? .secondary : tint)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(tint.opacity(disabled ? 0.05 : 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tint.opacity(disabled ? 0.10 : 0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct ModelsDrawerNoticeLine: View {
    var systemName: String
    var text: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemName)
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.caption2)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ModelsDrawerSectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ModelsDrawerIconButton: View {
    var title: String
    var systemName: String
    var disabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.small)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(title)
        .accessibilityLabel(Text(title))
        .disabled(disabled)
    }
}

struct ModelsDrawerMetricPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelsDrawerPortfolioSignalCell: View {
    var title: String
    var value: String
    var systemName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .imageScale(.small)
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelsDrawerUsageWindowMiniBar: View {
    var window: ModelsDrawerUsageWindowDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(window.percentText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(window.tint)
            }
            ProgressView(value: window.progress)
                .tint(window.tint)
            if !window.resetText.isEmpty {
                Text(window.resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ModelsDrawerChipList: View {
    var chips: [String]
    var tint: Color

    var body: some View {
        if chips.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(Array(chips.prefix(4)), id: \.self) { chip in
                    Text(chip)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.10))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct ModelsDrawerEmptyStateLine: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dashed")
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
