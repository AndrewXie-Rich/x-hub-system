import SwiftUI

struct XTExternalTerminalAccessDoctorFocusPresentation: Equatable {
    let state: XTUISurfaceState
    let headline: String
    let summary: String
    let detailLines: [String]

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func build(
        projection: XTUnifiedDoctorExternalTerminalAccessProjection,
        now: Date = Date()
    ) -> Self? {
        let snapshotLine = [
            "当前快照 \(projection.blockedKeyCount) 个受阻",
            "\(projection.readyKeyCount) 个可用",
            "\(projection.totalKeyCount) 个总计"
        ].joined(separator: " · ")
        let observedLine = "快照时间：\(timestampSummaryText(ms: projection.observedAtMs, now: now, fallback: "未知"))"

        if let blockedKey = projection.primaryBlockedKey {
            let keyLabel = blockedKey.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? blockedKey.accessKeyID
                : blockedKey.name
            var detailLines = [snapshotLine, observedLine]
            if let statusReasonSummary = blockedKey.statusReasonSummary, !statusReasonSummary.isEmpty {
                detailLines.append(statusReasonSummary)
            }
            if let recoverySummary = blockedKey.recoverySummary, !recoverySummary.isEmpty {
                detailLines.append(recoverySummary)
            }
            if blockedKey.expiresAtMs > 0 {
                detailLines.append(
                    "到期时间：\(timestampSummaryText(ms: blockedKey.expiresAtMs, now: now, fallback: "未知"))"
                )
            }
            if projection.sourceStatus != "ready" {
                detailLines.append(fetchFailureLine(projection: projection))
            }
            return XTExternalTerminalAccessDoctorFocusPresentation(
                state: .diagnosticRequired,
                headline: "Doctor 快照：\(keyLabel) 当前受阻",
                summary: "状态 \(blockedKey.status)\(blockedKey.statusReason.isEmpty ? "" : " · reason=\(blockedKey.statusReason)")",
                detailLines: detailLines
            )
        }

        guard projection.sourceStatus != "ready" else { return nil }
        return XTExternalTerminalAccessDoctorFocusPresentation(
            state: .diagnosticRequired,
            headline: "Doctor 快照：外部 terminal access 状态刷新失败",
            summary: "XT 这次没有拿到新的 Hub access key 生命周期回包，当前先按最近一次缓存快照展示。",
            detailLines: [
                snapshotLine,
                observedLine,
                fetchFailureLine(projection: projection)
            ]
        )
    }

    private static func fetchFailureLine(
        projection: XTUnifiedDoctorExternalTerminalAccessProjection
    ) -> String {
        let errorCode = (projection.errorCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let errorMessage = (projection.errorMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !errorCode.isEmpty && !errorMessage.isEmpty {
            return "最近刷新失败：\(errorCode) · \(errorMessage)"
        }
        if !errorCode.isEmpty {
            return "最近刷新失败：\(errorCode)"
        }
        if !errorMessage.isEmpty {
            return "最近刷新失败：\(errorMessage)"
        }
        return "最近刷新失败：未知原因"
    }

    private static func timestampSummaryText(
        ms: Int64,
        now: Date,
        fallback: String
    ) -> String {
        guard ms > 0 else { return fallback }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let relative = relativeFormatter.localizedString(for: date, relativeTo: now)
        return "\(timestampFormatter.string(from: date)) (\(relative))"
    }
}

struct XTExternalTerminalAccessDoctorFocusCard: View {
    let presentation: XTExternalTerminalAccessDoctorFocusPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.headline)
                .font(.subheadline.weight(.semibold))
            Text(presentation.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(presentation.detailLines, id: \.self) { line in
                    Text("• \(line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(UIThemeTokens.stateBackground(for: presentation.state))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(UIThemeTokens.color(for: presentation.state).opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
