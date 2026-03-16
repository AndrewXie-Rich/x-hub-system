import SwiftUI

struct ProjectUIReviewDiffSummaryView: View {
    let diff: XTUIReviewDiffPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近两次差异")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if diff.isEmpty {
                Text("最近两次 review 没有发现结构化变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !diff.addedIssueLabels.isEmpty {
                    tagRow(
                        title: "新增问题",
                        labels: diff.addedIssueLabels,
                        tint: .orange
                    )
                }

                if !diff.resolvedIssueLabels.isEmpty {
                    tagRow(
                        title: "已解决",
                        labels: diff.resolvedIssueLabels,
                        tint: .green
                    )
                }

                ForEach(diff.metrics) { metric in
                    metricRow(metric)
                }
            }
        }
    }

    private func tagRow(title: String, labels: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            FlexibleTagWrapView(labels: labels, tint: tint)
        }
    }

    private func metricRow(_ metric: XTUIReviewDiffMetricPresentation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(metric.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(metric.detail)
                .font(.caption)
                .foregroundStyle(metricTint(metric.tone))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func metricTint(_ tone: XTUIReviewDiffTone) -> Color {
        switch tone {
        case .improved:
            return .green
        case .stable:
            return .secondary
        case .regressed:
            return .orange
        }
    }
}

private struct FlexibleTagWrapView: View {
    let labels: [String]
    let tint: Color

    var body: some View {
        ViewThatFits(in: .vertical) {
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    tag(label)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    tag(label)
                }
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
