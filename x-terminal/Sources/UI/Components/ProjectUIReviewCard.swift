import AppKit
import SwiftUI

struct ProjectUIReviewCard: View {
    let review: XTUIReviewPresentation
    var onShowHistory: (() -> Void)? = nil
    var onResampleSnapshot: (() -> Void)? = nil
    var isResampling: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: verdictIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(verdictColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(review.verdictLabel)
                        .font(.headline)
                    Text(review.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(review.updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 8) {
                badge(review.confidenceLabel, tint: .blue)
                badge(review.evidenceLabel, tint: review.sufficientEvidence ? .green : .orange)
                badge(review.objectiveLabel, tint: review.objectiveReady ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                row(label: "问题摘要", value: review.issueSummary)
                row(label: "交互性", value: review.interactiveTargetSummary)
                row(label: "关键动作", value: review.criticalActionSummary)
                row(label: "Review Ref", value: review.reviewRef, monospaced: true)
            }

            if let trend = review.trend {
                trendRow(trend)
            }

            if let comparison = review.comparison {
                ProjectUIReviewDiffSummaryView(diff: comparison)
            }

            if !review.checks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关键检查")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(review.checks.prefix(4), id: \.code) { check in
                        checkRow(check)
                    }
                }
            }

            if !review.recentHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近几次")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(review.recentHistory, id: \.reviewID) { item in
                        historyRow(item)
                    }
                }
            }

            if review.hasAnyOpenableArtifact {
                HStack(spacing: 8) {
                    artifactButton("Open Review", url: review.reviewFileURL)
                    artifactButton("Open Bundle", url: review.bundleFileURL)
                    artifactButton("Open Screenshot", url: review.screenshotFileURL)
                    artifactButton("Open Text", url: review.visibleTextFileURL)
                }
            }

            HStack(spacing: 8) {
                if let onShowHistory {
                    Button("History") {
                        onShowHistory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let onResampleSnapshot {
                    Button {
                        onResampleSnapshot()
                    } label: {
                        if isResampling {
                            Label("Sampling…", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Re-run Snapshot", systemImage: "camera.viewfinder")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isResampling)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(verdictColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(verdictColor.opacity(0.2), lineWidth: 1)
        )
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

    private var verdictIcon: String {
        switch review.verdict {
        case .ready:
            return "checkmark.shield.fill"
        case .attentionNeeded:
            return "exclamationmark.triangle.fill"
        case .insufficientEvidence:
            return "eye.slash.fill"
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func row(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            Group {
                if monospaced {
                    Text(value)
                        .font(.caption.monospaced())
                } else {
                    Text(value)
                        .font(.caption)
                }
            }
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func checkRow(_ check: XTUIReviewCheckPresentation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            badge(check.statusLabel, tint: checkTint(check.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(check.codeLabel)
                    .font(.caption.weight(.semibold))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func checkTint(_ status: XTUIReviewCheckStatus) -> Color {
        switch status {
        case .pass:
            return .green
        case .warning:
            return .orange
        case .fail:
            return .red
        case .notApplicable:
            return .secondary
        }
    }

    private func artifactButton(_ title: String, url: URL?) -> some View {
        Button(title) {
            guard let url else { return }
            NSWorkspace.shared.open(url)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(url == nil)
    }

    private func trendRow(_ trend: XTUIReviewTrendPresentation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            badge(trend.headline, tint: trendTint(trend.status))
            Text(trend.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func historyRow(_ item: XTUIReviewHistoryItemPresentation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            badge(item.verdictLabel, tint: historyTint(item.verdict))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.summary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.relativeUpdatedText()) · \(item.reviewRef)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button("Open") {
                    guard let url = item.reviewFileURL else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(item.reviewFileURL == nil)

                if item.hasAnyOpenableArtifact {
                    Menu("Artifacts") {
                        artifactMenuButton("Open Review", url: item.reviewFileURL)
                        artifactMenuButton("Open Bundle", url: item.bundleFileURL)
                        artifactMenuButton("Open Screenshot", url: item.screenshotFileURL)
                        artifactMenuButton("Open Text", url: item.visibleTextFileURL)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func artifactMenuButton(_ title: String, url: URL?) -> some View {
        if let url {
            Button(title) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func trendTint(_ status: XTUIReviewTrendStatus) -> Color {
        switch status {
        case .improved:
            return .green
        case .stable:
            return .secondary
        case .regressed:
            return .orange
        }
    }

    private func historyTint(_ verdict: XTUIReviewVerdict) -> Color {
        switch verdict {
        case .ready:
            return .green
        case .attentionNeeded:
            return .orange
        case .insufficientEvidence:
            return .red
        }
    }
}
