import SwiftUI

struct XTFocusContextCard: View {
    let context: XTSectionFocusContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(context.title)
                .font(.subheadline.weight(.semibold))
            if let detail = normalizedDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var normalizedDetail: String? {
        let trimmed = (context.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
