import AppKit
import SwiftUI

struct ProjectUIReviewHistorySheet: View {
    let ctx: AXProjectContext

    @Environment(\.dismiss) private var dismiss

    private var items: [XTUIReviewHistoryItemPresentation] {
        XTUIReviewPresentation.loadHistory(for: ctx, limit: 24)
    }

    private var trend: XTUIReviewTrendPresentation? {
        guard items.count >= 2 else { return nil }
        return XTUIReviewTrendPresentation.compare(latest: items[0], previous: items[1])
    }

    private var comparison: XTUIReviewDiffPresentation? {
        guard items.count >= 2 else { return nil }
        return XTUIReviewDiffPresentation.compare(latest: items[0], previous: items[1])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UI Review History")
                        .font(.headline)
                    Text(ctx.displayName())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }

            if items.isEmpty {
                Text("当前项目还没有 UI review 历史。先运行一次 browser snapshot。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let trend {
                            trendBanner(trend)
                        }
                        if let comparison {
                            diffBanner(comparison)
                        }
                        ForEach(items, id: \.reviewID) { item in
                            historyRow(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 520)
    }

    private func historyRow(_ item: XTUIReviewHistoryItemPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.verdictLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(verdictColor(item.verdict))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(verdictColor(item.verdict).opacity(0.12))
                    .clipShape(Capsule())

                Text(item.confidence.rawValue)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                Text(item.relativeUpdatedText())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.summary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.reviewRef)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(item.issueSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                artifactButton("Open Review", url: item.reviewFileURL)
                artifactButton("Open Bundle", url: item.bundleFileURL)
                artifactButton("Open Screenshot", url: item.screenshotFileURL)
                artifactButton("Open Text", url: item.visibleTextFileURL)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func verdictColor(_ verdict: XTUIReviewVerdict) -> Color {
        switch verdict {
        case .ready:
            return .green
        case .attentionNeeded:
            return .orange
        case .insufficientEvidence:
            return .red
        }
    }

    private func trendBanner(_ trend: XTUIReviewTrendPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trend.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(trendColor(trend.status))
            Text(trend.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(trendColor(trend.status).opacity(0.08))
        )
    }

    private func trendColor(_ status: XTUIReviewTrendStatus) -> Color {
        switch status {
        case .improved:
            return .green
        case .stable:
            return .secondary
        case .regressed:
            return .orange
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

    private func diffBanner(_ diff: XTUIReviewDiffPresentation) -> some View {
        ProjectUIReviewDiffSummaryView(diff: diff)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}
