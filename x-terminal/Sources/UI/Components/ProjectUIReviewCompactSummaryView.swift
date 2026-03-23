import SwiftUI

struct ProjectUIReviewCompactSummaryView: View {
    let review: XTUIReviewPresentation
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var lastObservedReviewSignature: String?

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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: updateFeedback.isHighlighted,
            focusTint: verdictColor,
            updateTint: verdictColor,
            baseBackground: .clear,
            baseBorder: .clear,
            updateBackgroundOpacity: 0.04,
            updateBorderOpacity: 0.2,
            updateShadowOpacity: 0.08,
            shadowRadius: 4,
            shadowYOffset: 1
        )
        .overlay(alignment: .topTrailing) {
            if updateFeedback.showsBadge {
                XTTransientUpdateBadge(
                    tint: verdictColor,
                    horizontalPadding: 5,
                    verticalPadding: 2
                )
                .padding(.top, 4)
                .padding(.trailing, 4)
            }
        }
        .onAppear {
            lastObservedReviewSignature = observedReviewSignature
        }
        .onChange(of: observedReviewSignature) { newValue in
            defer { lastObservedReviewSignature = newValue }
            guard let lastObservedReviewSignature, lastObservedReviewSignature != newValue else {
                return
            }
            updateFeedback.trigger()
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
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

    private var observedReviewSignature: String {
        review.transientUpdateSignature
    }
}
