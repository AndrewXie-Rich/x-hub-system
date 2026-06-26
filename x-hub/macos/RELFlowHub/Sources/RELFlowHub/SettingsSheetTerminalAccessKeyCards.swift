import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func terminalAccessLastSecretCard(_ secret: HubTerminalAccessKeySecretEnvelope) -> some View {
        let deliveryPack = secret.deliveryPack

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.teal, .green],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "key.radiowaves.forward")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text("最近签发 / 轮换")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(secret.accessKey.resolvedName)
                        .font(.subheadline.weight(.semibold))
                    if !secret.openAIBaseURL.isEmpty {
                        Text(secret.openAIBaseURL)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    terminalAccessStatusBadge(secret.accessKey)
                    terminalAccessBadge(title: "可即刻交付", tint: .teal)
                }
            }

            Text("这段 secret 只会在当前 Hub 界面里显示一次。确认目标 terminal 已保存后，再离开这一页。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                terminalAccessMiniPill(title: deliveryPack.authDisplayText, tint: .blue)
                terminalAccessMiniPill(title: deliveryPack.baseURLEnvKey, tint: .teal)
                terminalAccessMiniPill(title: deliveryPack.apiKeyEnvKey, tint: .orange)
                if !deliveryPack.responsesURL.isEmpty {
                    terminalAccessMiniPill(title: "/responses 已就绪", tint: .green)
                }
                Spacer()
            }

            if !deliveryPack.baseURL.isEmpty {
                Text(deliveryPack.baseURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button("复制接入包") {
                        terminalAccessCopyToPasteboard(
                            deliveryPack.setupPackText,
                            successText: "已复制 \(secret.accessKey.resolvedName) 的 terminal 接入包。"
                        )
                    }
                    .disabled(deliveryPack.setupPackText.isEmpty)

                    Button("复制 shell export") {
                        terminalAccessCopyToPasteboard(
                            deliveryPack.shellExports,
                            successText: "已复制 \(secret.accessKey.resolvedName) 的 shell export。"
                        )
                    }
                    .disabled(deliveryPack.shellExports.isEmpty)

                    Button("复制 API Key") {
                        terminalAccessCopyToPasteboard(
                            deliveryPack.apiKeyValue,
                            successText: "已复制 \(secret.accessKey.resolvedName) 的 OpenAI API key。"
                        )
                    }
                    .disabled(deliveryPack.apiKeyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                HStack(spacing: 10) {
                    Button("复制 URL") {
                        terminalAccessCopyToPasteboard(
                            secret.openAIBaseURL,
                            successText: "已复制普通 terminal OpenAI 入口 URL。"
                        )
                    }
                    .disabled(secret.openAIBaseURL.isEmpty)

                    Button("复制 smoke curl") {
                        terminalAccessCopyToPasteboard(
                            secret.smokeCurlCommand,
                            successText: "已复制普通 terminal smoke curl。"
                        )
                    }
                    .disabled(secret.smokeCurlCommand.isEmpty)

                    Spacer()
                }
            }
            .font(.caption)

            if !deliveryPack.shellExports.isEmpty {
                terminalAccessExportBlock(
                    title: "Shell Export",
                    text: deliveryPack.shellExports,
                    minHeight: 56,
                    maxHeight: 108
                )
            }

            if !deliveryPack.setupPackText.isEmpty {
                terminalAccessExportBlock(
                    title: "Terminal 接入包",
                    text: deliveryPack.setupPackText,
                    minHeight: 126,
                    maxHeight: 240
                )
            }

            terminalAccessExampleShowcase(deliveryPack: deliveryPack)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.86, green: 0.96, blue: 0.92),
                            Color(red: 0.88, green: 0.95, blue: 0.97),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
    }

    func terminalAccessKeyCard(_ accessKey: HubTerminalAccessKey) -> some View {
        let deviceStatus = terminalAccessDeviceStatus(for: accessKey)
        let hasSecret = terminalAccessSecretEnvelope(for: accessKey) != nil
        let baseURL = terminalAccessBaseURL(for: accessKey)
        let deliveryPack = terminalAccessDeliveryPack(for: accessKey)
        let quotaLimit = terminalAccessQuotaLimit(for: accessKey, deviceStatus: deviceStatus)
        let used = terminalAccessQuotaUsed(deviceStatus: deviceStatus)
        let remaining = terminalAccessQuotaRemaining(limit: quotaLimit, used: used, deviceStatus: deviceStatus)
        let statusTint = terminalAccessStatusTint(accessKey)
        let statusIcon = terminalAccessStatusIcon(accessKey)
        let detailBinding = expansionBinding(accessKey.accessKeyID, in: $expandedTerminalAccessKeyDetailIDs)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(statusTint.opacity(0.16))
                    Image(systemName: statusIcon)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(statusTint)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(accessKey.resolvedName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(accessKey.accessKeyID) • \(accessKey.appID.isEmpty ? "external_terminal" : accessKey.appID)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                terminalAccessStatusBadge(accessKey)
            }

            Text(terminalAccessSummaryLine(accessKey, quotaLimit: quotaLimit))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                terminalAccessMiniPill(
                    title: accessKey.paidModelSelectionMode == .off ? "付费模型关闭" : "付费模型开启",
                    tint: accessKey.paidModelSelectionMode == .off ? .gray : .orange
                )
                terminalAccessMiniPill(
                    title: accessKey.defaultWebFetchEnabled ? "web.fetch 开启" : "web.fetch 关闭",
                    tint: accessKey.defaultWebFetchEnabled ? .teal : .gray
                )
                terminalAccessMiniPill(
                    title: accessKey.expiresAtMs > 0 ? "会过期" : "不过期",
                    tint: accessKey.expiresAtMs > 0 ? .blue : .green
                )
                if hasSecret {
                    terminalAccessMiniPill(title: "持有最新 Secret", tint: .teal)
                }
                Spacer()
            }

            if !accessKey.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(accessKey.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !baseURL.isEmpty {
                Text(baseURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !accessKey.statusReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let statusReasonTint: Color = accessKey.status.lowercased() == "ready" ? .secondary : .orange
                Text("状态原因: \(accessKey.statusReason)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(statusReasonTint)
                    .textSelection(.enabled)
            }

            if quotaLimit > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("今日额度进度")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(terminalAccessIntText(used)) / \(terminalAccessIntText(quotaLimit))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    ProgressView(value: min(Double(max(0, used)), Double(max(1, quotaLimit))), total: Double(max(1, quotaLimit)))
                        .progressViewStyle(.linear)
                        .tint(remaining > 0 ? statusTint : .orange)
                    HStack(spacing: 8) {
                        terminalAccessMiniPill(title: "剩余 \(terminalAccessIntText(remaining))", tint: remaining > 0 ? .green : .orange)
                        if let deviceStatus {
                            terminalAccessMiniPill(title: "请求 \(deviceStatus.requestsToday)", tint: .blue)
                            terminalAccessMiniPill(title: "阻断 \(deviceStatus.blockedToday)", tint: deviceStatus.blockedToday > 0 ? .orange : .gray)
                        }
                        Spacer()
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if accessKey.supportsDirectBudgetAdjustment {
                HStack(spacing: 8) {
                    Text("预算快拨")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    terminalAccessQuickBudgetButton(accessKey, delta: -50_000, title: "-50k")
                    terminalAccessQuickBudgetButton(accessKey, delta: 50_000, title: "+50k")
                    terminalAccessQuickBudgetButton(accessKey, delta: 200_000, title: "+200k")
                    Button("精确设置") {
                        presentRemoteQuotaBudgetEditor(accessKey)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.indigo.opacity(0.08))
                    .clipShape(Capsule())
                    .disabled(terminalAccessMutationInFlight)
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Button("复制 URL") {
                    terminalAccessCopyToPasteboard(
                        baseURL,
                        successText: "已复制 \(accessKey.resolvedName) 的 OpenAI 入口 URL。"
                    )
                }
                .disabled(baseURL.isEmpty)

                Button(hasSecret ? "复制接入包" : "复制模板包") {
                    terminalAccessCopyToPasteboard(
                        deliveryPack.setupPackText,
                        successText: hasSecret
                            ? "已复制 \(accessKey.resolvedName) 的 terminal 接入包。"
                            : "已复制 \(accessKey.resolvedName) 的模板接入包。"
                    )
                }
                .disabled(deliveryPack.setupPackText.isEmpty)

                Button(terminalAccessMutationInFlight ? "轮换中..." : "轮换") {
                    Task { await rotateTerminalAccessKey(accessKey) }
                }
                .disabled(terminalAccessMutationInFlight || accessKey.status.lowercased() == "revoked")

                Button("撤销") {
                    terminalAccessPendingRevokeAccessKeyID = accessKey.accessKeyID
                }
                .disabled(terminalAccessMutationInFlight || accessKey.status.lowercased() == "revoked")

                Spacer()
            }
            .font(.caption)

            DisclosureGroup(isExpanded: detailBinding) {
                VStack(alignment: .leading, spacing: 10) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            terminalAccessFact(title: "每日额度", value: terminalAccessIntText(quotaLimit))
                            terminalAccessFact(title: "今日已用", value: terminalAccessIntText(used))
                        }
                        GridRow {
                            terminalAccessFact(title: "今日剩余", value: terminalAccessIntText(remaining))
                            terminalAccessFact(
                                title: "到期时间",
                                value: accessKey.expiresAtMs > 0 ? formatEpochMs(accessKey.expiresAtMs) : "不过期"
                            )
                        }
                        GridRow {
                            terminalAccessFact(
                                title: "上次使用",
                                value: accessKey.lastUsedAtMs > 0 ? formatEpochMs(accessKey.lastUsedAtMs) : "未记录"
                            )
                            terminalAccessFact(title: "轮换次数", value: terminalAccessIntText(Int64(accessKey.rotationCount)))
                        }
                    }
                    .font(.caption)

                    if let deviceStatus {
                        Text(terminalAccessLiveUsageLine(deviceStatus))
                            .font(.caption2.monospaced())
                            .foregroundStyle(remaining <= 0 ? .orange : .secondary)
                            .textSelection(.enabled)

                        if let lastActivity = deviceStatus.lastActivity, lastActivity.createdAtMs > 0 {
                            let modelID = lastActivity.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
                            let activitySuffix = modelID.isEmpty ? "" : " • \(modelID)"
                            Text("最近活动 \(formatEpochMs(lastActivity.createdAtMs))\(activitySuffix)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    if accessKey.status.lowercased() == "ready" && !hasSecret {
                        Text("Hub 现在只保留这把 key 的导出模板；如果要重新分发原始 `OPENAI_API_KEY`，请先轮换。")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !deliveryPack.baseURL.isEmpty || !deliveryPack.envBlock.isEmpty {
                        terminalAccessDeliveryPanel(
                            accessKey: accessKey,
                            deliveryPack: deliveryPack,
                            hasSecret: hasSecret
                        )
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("预算 / 活动 / 交付包")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(terminalAccessDetailSummary(accessKey, remaining: remaining, hasSecret: hasSecret))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            statusTint.opacity(0.10),
                            Color.white.opacity(0.92),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(statusTint.opacity(0.18), lineWidth: 1)
        )
    }
}
