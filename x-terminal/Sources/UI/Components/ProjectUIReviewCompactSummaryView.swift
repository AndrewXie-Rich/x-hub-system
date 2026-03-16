import SwiftUI

struct ProjectUIReviewCompactSummaryView: View {
    let review: XTUIReviewPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                compactBadge(review.verdictLabel, tint: verdictColor)
                compactBadge(review.confidenceLabel, tint: .blue)
                if !review.objectiveReady {
                    compactBadge("需复核", tint: .orange)
                }
            }

            Text(review.compactStatusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var verdictColor: Color {
        switch review.verdict {
        case .ready:
            return .green
        case .attentionNeeded:
            return .orange
        case .insufficientEvidence:
            return .red
        }
    }

    private func compactBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
