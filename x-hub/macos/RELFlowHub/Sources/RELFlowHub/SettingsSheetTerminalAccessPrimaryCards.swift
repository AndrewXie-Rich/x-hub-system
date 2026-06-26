import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    var terminalAccessOverviewHero: some View {
        let quotaTotal = terminalAccessOverviewQuotaTotal
        let usedTotal = terminalAccessOverviewUsedTotal
        let remainingTotal = terminalAccessOverviewRemainingTotal
        let usageTotal = max(1, quotaTotal)
        let usageValue = min(Double(max(0, usedTotal)), Double(usageTotal))
        let summaryTint: Color = terminalAccessReadyCount == terminalAccessKeys.count && !terminalAccessKeys.isEmpty ? .green : .blue

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.13, green: 0.40, blue: 0.66),
                                    Color(red: 0.07, green: 0.62, blue: 0.57),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "terminal.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("普通 Terminal Gateway")
                        .font(.headline)
                    Text("Hub 常驻时，可以持续给普通 terminal 发放独立的 OpenAI-compatible access key，并按 key / user / device 记账。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(terminalAccessSectionSummaryText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    terminalAccessBadge(
                        title: terminalAccessKeys.isEmpty ? "尚未签发" : "\(terminalAccessReadyCount)/\(terminalAccessKeys.count) 可用",
                        tint: summaryTint
                    )
                    if terminalAccessLastSecret != nil {
                        terminalAccessBadge(title: "待分发 Secret", tint: .teal)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(terminalAccessCurrentBaseURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                    Spacer()
                }

                HStack(spacing: 8) {
                    terminalAccessMiniPill(title: "GET /v1/models", tint: .blue)
                    terminalAccessMiniPill(title: "POST /v1/chat/completions", tint: .teal)
                    terminalAccessMiniPill(title: "POST /v1/responses", tint: .orange)
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                terminalAccessOverviewMetric(
                    title: "已签发",
                    value: terminalAccessIntText(Int64(terminalAccessKeys.count)),
                    subtitle: "所有外部 terminal key",
                    tint: .blue
                )
                terminalAccessOverviewMetric(
                    title: "今日已用",
                    value: terminalAccessIntText(usedTotal),
                    subtitle: "按已上报 usage 汇总",
                    tint: .teal
                )
                terminalAccessOverviewMetric(
                    title: "今日剩余",
                    value: terminalAccessIntText(remainingTotal),
                    subtitle: "可继续分配的预算",
                    tint: remainingTotal > 0 ? .green : .orange
                )
            }

            if quotaTotal > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("外部 Terminal 总额度")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(terminalAccessIntText(usedTotal)) / \(terminalAccessIntText(quotaTotal))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    ProgressView(value: usageValue, total: Double(usageTotal))
                        .progressViewStyle(.linear)
                        .tint(remainingTotal > 0 ? .teal : .orange)
                }
            }

            HStack(spacing: 10) {
                Button(terminalAccessReloadInFlight ? "刷新中..." : "刷新视图") {
                    Task { await reloadTerminalAccessKeys(forceMessage: true) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(terminalAccessReloadInFlight || terminalAccessMutationInFlight)

                Button("复制 Gateway URL") {
                    terminalAccessCopyToPasteboard(
                        terminalAccessCurrentBaseURL,
                        successText: "已复制普通 terminal OpenAI 入口 URL。"
                    )
                }
                .disabled(terminalAccessCurrentBaseURL.isEmpty || terminalAccessMutationInFlight)

                Spacer()
            }
            .font(.caption)
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.97, green: 0.92, blue: 0.84),
                                Color(red: 0.87, green: 0.93, blue: 0.97),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.35))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
    }

    var terminalAccessIssueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("签发给普通 terminal")
                        .font(.headline)
                    Text("每把 key 都绑定独立 `user_id / app_id / 每日额度 / paid policy`，方便你分配给不同机器、脚本或团队成员。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                terminalAccessBadge(title: "Issue", tint: .orange)
            }

            HStack(spacing: 8) {
                TextField("名称", text: $terminalAccessDraft.name)
                    .textFieldStyle(.roundedBorder)
                TextField("user_id", text: $terminalAccessDraft.userID)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                TextField("app_id", text: $terminalAccessDraft.appID)
                    .textFieldStyle(.roundedBorder)
                TextField("备注", text: $terminalAccessDraft.note)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                TextField(
                    "每日 token 额度",
                    value: $terminalAccessDraft.dailyTokenLimit,
                    formatter: terminalAccessIntegerFormatter(minimum: 1, maximum: 1_000_000_000)
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "TTL 小时，0=不过期",
                    value: $terminalAccessDraft.ttlHours,
                    formatter: terminalAccessIntegerFormatter(minimum: 0, maximum: 24 * 365 * 10)
                )
                .textFieldStyle(.roundedBorder)
            }
            .font(.caption)

            Toggle("允许付费模型", isOn: $terminalAccessDraft.allowPaidModels)
                .toggleStyle(.checkbox)
                .font(.caption)

            Toggle("默认允许 web.fetch", isOn: $terminalAccessDraft.defaultWebFetchEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)

            HStack(spacing: 8) {
                terminalAccessMiniPill(
                    title: terminalAccessDraft.allowPaidModels ? "付费模型已开启" : "仅按默认 paid policy",
                    tint: terminalAccessDraft.allowPaidModels ? .orange : .gray
                )
                terminalAccessMiniPill(
                    title: terminalAccessDraft.defaultWebFetchEnabled ? "web.fetch 默认开启" : "web.fetch 默认关闭",
                    tint: terminalAccessDraft.defaultWebFetchEnabled ? .teal : .gray
                )
                terminalAccessMiniPill(
                    title: "TTL \(terminalAccessDraft.ttlHours == 0 ? "无限" : "\(terminalAccessDraft.ttlHours)h")",
                    tint: .blue
                )
                Spacer()
            }

            HStack(spacing: 10) {
                Button(terminalAccessMutationInFlight ? "签发中..." : "签发并返回 Key + URL") {
                    Task { await issueTerminalAccessKey() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(terminalAccessMutationInFlight || terminalAccessReloadInFlight)

                Button("复制当前 URL") {
                    terminalAccessCopyToPasteboard(
                        terminalAccessCurrentBaseURL,
                        successText: "已复制普通 terminal OpenAI 入口 URL。"
                    )
                }
                .disabled(terminalAccessCurrentBaseURL.isEmpty || terminalAccessMutationInFlight)

                Spacer()
            }
            .font(.caption)

            Text("普通 terminal 直接拿 `OPENAI_BASE_URL` + `OPENAI_API_KEY` 即可；Hub 内部仍按独立 device/user/account 记账。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.95, blue: 0.90),
                            Color(red: 0.95, green: 0.97, blue: 0.99),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}
