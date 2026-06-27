import SwiftUI
import AppKit
import RELFlowHubCore

struct RemoteQuotaBudgetEditorSheet: View {
    let target: RemoteQuotaBudgetEditorTarget
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftLimit: Int

    init(target: RemoteQuotaBudgetEditorTarget, onSave: @escaping (Int) -> Void) {
        self.target = target
        self.onSave = onSave
        _draftLimit = State(initialValue: max(1, target.currentDailyTokenLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("精确设置日预算")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(target.title)
                    .font(.callout.weight(.semibold))
                if !target.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(target.subtitle)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                metricCard(
                    title: "当前额度",
                    value: Self.tokenFormatter.string(from: NSNumber(value: target.currentDailyTokenLimit)) ?? "\(target.currentDailyTokenLimit)",
                    tint: .purple
                )
                metricCard(
                    title: "今日已用",
                    value: Self.tokenFormatter.string(from: NSNumber(value: target.todayUsed)) ?? "\(target.todayUsed)",
                    tint: .teal
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("目标 daily budget")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "每日 token 额度",
                    value: $draftLimit,
                    formatter: Self.tokenFormatter
                )
                .textFieldStyle(.roundedBorder)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 72), spacing: 8),
                        GridItem(.flexible(minimum: 72), spacing: 8),
                        GridItem(.flexible(minimum: 72), spacing: 8),
                        GridItem(.flexible(minimum: 72), spacing: 8),
                    ],
                    spacing: 8
                ) {
                    presetButton(100_000, title: "100k")
                    presetButton(200_000, title: "200k")
                    presetButton(500_000, title: "500k")
                    presetButton(1_000_000, title: "1M")
                }
            }

            Text("保存后会立刻刷新 Hub 台账；XT 和普通 terminal 共用这套 daily budget 语义。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 10) {
                Button("取消") {
                    dismiss()
                }

                Spacer()

                Button("保存额度") {
                    onSave(max(1, draftLimit))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftLimit < 1 || draftLimit == target.currentDailyTokenLimit)
            }
        }
        .padding(16)
        .frame(width: 420, height: 300)
    }

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    @ViewBuilder
    private func metricCard(
        title: String,
        value: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func presetButton(_ value: Int, title: String) -> some View {
        Button(title) {
            draftLimit = value
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background((draftLimit == value ? Color.indigo : Color.gray).opacity(draftLimit == value ? 0.14 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
