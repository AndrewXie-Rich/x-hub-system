import SwiftUI

struct XTCompactStatusPill: View {
    let iconName: String
    let text: String
    let tint: Color
    var monospaced: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))

            Text(text)
                .font(monospaced ? UIThemeTokens.monoFont() : .caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
}
