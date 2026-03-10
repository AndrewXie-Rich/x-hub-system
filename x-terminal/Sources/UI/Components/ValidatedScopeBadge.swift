import SwiftUI

struct ValidatedScopeBadge: View {
    let presentation: ValidatedScopePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(UIThemeTokens.color(for: .releaseFrozen))
                Text(presentation.badgeText)
                    .font(.headline)
            }

            Text(presentation.currentReleaseScope)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)

            Text(presentation.validatedPaths.joined(separator: " → "))
                .font(.caption)
                .foregroundStyle(.primary)

            Text(presentation.hardLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.stateBackground(for: .releaseFrozen))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.color(for: .releaseFrozen).opacity(0.24), lineWidth: 1)
        )
    }
}
