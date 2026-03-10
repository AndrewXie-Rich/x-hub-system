import SwiftUI

enum PrimaryActionRailActionStyle: String, Codable, Equatable {
    case primary
    case secondary
    case diagnostic
}

struct PrimaryActionRailAction: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let style: PrimaryActionRailActionStyle
}

struct PrimaryActionRail: View {
    let title: String?
    let actions: [PrimaryActionRailAction]
    let onTap: (PrimaryActionRailAction) -> Void

    private var primaryActions: [PrimaryActionRailAction] {
        actions.filter { $0.style == .primary }
    }

    private var supportingActions: [PrimaryActionRailAction] {
        actions.filter { $0.style != .primary }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(UIThemeTokens.sectionFont())
            }

            ForEach(primaryActions) { action in
                Button(action: { onTap(action) }) {
                    actionLabel(for: action)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if !supportingActions.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(supportingActions) { action in
                        supportingActionButton(action)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func supportingActionButton(_ action: PrimaryActionRailAction) -> some View {
        Button(action: { onTap(action) }) {
            actionLabel(for: action)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(action.style == .diagnostic ? UIThemeTokens.color(for: .releaseFrozen) : UIThemeTokens.color(for: .inProgress))
    }

    private func actionLabel(for action: PrimaryActionRailAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(action.title, systemImage: action.systemImage)
                .font(.headline)
            if let subtitle = action.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
