import SwiftUI

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyBudgetClientRow(_ clientProjection: RemoteQuotaCenterClientProjection) -> some View {
        let status = clientProjection.deviceStatus
        let kindTint = providerKeyConsumerKindColor(clientProjection.consumerKind)
        let usageTint = providerKeyConsumerAtRisk(clientProjection) ? Color.orange : kindTint
        let remainingTint = clientProjection.dailyTokenLimit > 0 && clientProjection.remainingDailyTokenBudget <= 0
            ? Color.orange
            : Color.green

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(grpcClientPresencePillColor(status))
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(clientProjection.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)

                        Text(clientProjection.kindTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(kindTint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(kindTint.opacity(0.12))
                            .clipShape(Capsule())

                        Text(grpcClientPresencePillTitle(status))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(grpcClientPresencePillColor(status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(grpcClientPresencePillColor(status).opacity(0.12))
                            .clipShape(Capsule())

                        Text(clientProjection.paidPolicyTitle)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())

                        if clientProjection.defaultWebFetchEnabled {
                            Text("Web")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.teal.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    let referenceSummary = providerKeyBudgetClientReferenceSummary(clientProjection)
                    if !referenceSummary.isEmpty {
                        Text(referenceSummary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Text(providerKeyBudgetClientScopeSummary(clientProjection))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(clientProjection.managementTitle) {
                    presentRemoteQuotaConsumerManager(clientProjection)
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }

            HStack(spacing: 8) {
                providerKeyLedgerMetricTile(
                    title: "预算",
                    value: clientProjection.dailyTokenLimit > 0
                        ? HubUIStrings.Settings.ProviderKeys.tokenCount(clientProjection.dailyTokenLimit)
                        : "不限",
                    detail: clientProjection.dailyTokenLimit > 0 ? "每日硬上限" : "由上游库存约束",
                    tint: .purple
                )
                providerKeyLedgerMetricTile(
                    title: "已用",
                    value: HubUIStrings.Settings.ProviderKeys.tokenCount(clientProjection.dailyTokenUsed),
                    detail: status != nil ? "今日实时账本" : "已记录 usage",
                    tint: usageTint
                )
                providerKeyLedgerMetricTile(
                    title: "剩余",
                    value: clientProjection.dailyTokenLimit > 0
                        ? HubUIStrings.Settings.ProviderKeys.tokenCount(clientProjection.remainingDailyTokenBudget)
                        : "上游池",
                    detail: clientProjection.dailyTokenLimit > 0 ? "今日还能分配" : "无固定硬上限",
                    tint: remainingTint
                )
            }

            if clientProjection.dailyTokenLimit > 0 {
                ProgressView(
                    value: Double(clientProjection.dailyTokenUsed),
                    total: Double(clientProjection.dailyTokenLimit)
                )
                .progressViewStyle(.linear)
                .tint(usageTint)

                Text(
                    HubUIStrings.Settings.GRPC.DeviceList.dailyTokenUsage(
                        day: status?.quotaDay ?? "unknown",
                        used: Int(clientProjection.dailyTokenUsed),
                        cap: Int(clientProjection.dailyTokenLimit),
                        remaining: Int(clientProjection.remainingDailyTokenBudget)
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text(
                    clientProjection.dailyTokenUsed > 0
                        ? "今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(clientProjection.dailyTokenUsed)) tokens，当前没有单独硬上限。"
                        : "当前没有单独硬上限，主要受上游家族池库存约束。"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            let activitySummary = providerKeyBudgetClientActivitySummary(clientProjection)
            if !activitySummary.isEmpty {
                Text(activitySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if providerKeyCanQuickAdjustBudget(clientProjection) {
                HStack(spacing: 8) {
                    Text("快速调预算")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    providerKeyQuickBudgetButton(clientProjection, delta: -50_000, title: "-50k")
                    providerKeyQuickBudgetButton(clientProjection, delta: 50_000, title: "+50k")
                    providerKeyQuickBudgetButton(clientProjection, delta: 200_000, title: "+200k")
                    Button("精确设置") {
                        presentRemoteQuotaBudgetEditor(clientProjection)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.08))
                    .clipShape(Capsule())
                    .disabled((clientProjection.isTerminalAccess && terminalAccessMutationInFlight) || !providerKeyCanQuickAdjustBudget(clientProjection))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background((providerKeyConsumerAtRisk(clientProjection) ? Color.orange : kindTint).opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((providerKeyConsumerAtRisk(clientProjection) ? Color.orange : kindTint).opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func providerKeyBudgetUserRow(_ userProjection: RemoteQuotaCenterUserProjection) -> some View {
        let userTint = providerKeyUserTint(userProjection)
        let usageTint = providerKeyUserAtRisk(userProjection) ? Color.orange : userTint
        let remainingValue: String = {
            if userProjection.allocatedDailyTokenBudget > 0 {
                let base = HubUIStrings.Settings.ProviderKeys.tokenCount(userProjection.remainingDailyTokenBudget)
                return userProjection.hasUnlimitedBudget ? "\(base) +" : base
            }
            return userProjection.hasUnlimitedBudget ? "弹性" : "0"
        }()
        let remainingDetail: String = {
            if userProjection.hasUnlimitedBudget && userProjection.allocatedDailyTokenBudget > 0 {
                return "固定预算剩余 + 弹性"
            }
            if userProjection.hasUnlimitedBudget {
                return "由上游库存约束"
            }
            return "今日还能分配"
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(userTint.opacity(0.12))
                    Image(systemName: userProjection.isStandaloneConsumer ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(userTint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(userProjection.displayName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)

                        Text(userProjection.groupingKind.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(userTint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(userTint.opacity(0.12))
                            .clipShape(Capsule())

                        if userProjection.hasUnlimitedBudget {
                            Text("含弹性额度")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        if userProjection.connectedConsumerCount > 0 {
                            Text("\(userProjection.connectedConsumerCount) 在线")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Text(providerKeyBudgetUserIdentitySummary(userProjection))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(providerKeyBudgetUserScopeSummary(userProjection))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(userProjection.consumerCount == 1 ? userProjection.consumers[0].managementTitle : "查看消费者") {
                    presentRemoteQuotaUserManager(userProjection)
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }

            HStack(spacing: 8) {
                providerKeyLedgerMetricTile(
                    title: "分配预算",
                    value: userProjection.allocatedDailyTokenBudget > 0
                        ? HubUIStrings.Settings.ProviderKeys.tokenCount(userProjection.allocatedDailyTokenBudget)
                        : (userProjection.hasUnlimitedBudget ? "不限" : "0"),
                    detail: "\(userProjection.consumerCount) 个消费者 · XT \(userProjection.xtConsumerCount) · Terminal \(userProjection.terminalConsumerCount)",
                    tint: .purple
                )
                providerKeyLedgerMetricTile(
                    title: "今日已用",
                    value: HubUIStrings.Settings.ProviderKeys.tokenCount(userProjection.observedDailyTokensUsed),
                    detail: "该用户名下所有 consumer 合计",
                    tint: usageTint
                )
                providerKeyLedgerMetricTile(
                    title: "今日剩余",
                    value: remainingValue,
                    detail: remainingDetail,
                    tint: providerKeyUserAtRisk(userProjection) ? .orange : .green
                )
            }

            if userProjection.allocatedDailyTokenBudget > 0 {
                ProgressView(
                    value: Double(userProjection.observedDailyTokensUsed),
                    total: Double(max(Int64(1), userProjection.allocatedDailyTokenBudget))
                )
                .progressViewStyle(.linear)
                .tint(usageTint)
            }

            let consumerPreview = providerKeyBudgetUserConsumerPreview(userProjection)
            if !consumerPreview.isEmpty {
                Text(consumerPreview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if userProjection.consumers.count == 1, let consumer = userProjection.consumers.first, providerKeyCanQuickAdjustBudget(consumer) {
                HStack(spacing: 8) {
                    Text("快速调预算")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    providerKeyQuickBudgetButton(consumer, delta: -50_000, title: "-50k")
                    providerKeyQuickBudgetButton(consumer, delta: 50_000, title: "+50k")
                    providerKeyQuickBudgetButton(consumer, delta: 200_000, title: "+200k")
                    Button("精确设置") {
                        presentRemoteQuotaBudgetEditor(consumer)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.08))
                    .clipShape(Capsule())
                    .disabled((consumer.isTerminalAccess && terminalAccessMutationInFlight) || !providerKeyCanQuickAdjustBudget(consumer))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background((providerKeyUserAtRisk(userProjection) ? Color.orange : userTint).opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((providerKeyUserAtRisk(userProjection) ? Color.orange : userTint).opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func providerKeyQuickBudgetButton(
        _ consumer: RemoteQuotaCenterClientProjection,
        delta: Int,
        title: String
    ) -> some View {
        Button(title) {
            if let client = consumer.grpcClient {
                grpcAdjustDailyBudget(client, delta: delta)
                return
            }
            guard let accessKey = consumer.terminalAccessKey else { return }
            Task { await adjustTerminalAccessKeyDailyBudget(accessKey, delta: delta) }
        }
        .buttonStyle(.borderless)
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.indigo.opacity(0.10))
        .clipShape(Capsule())
        .disabled((consumer.isTerminalAccess && terminalAccessMutationInFlight) || !providerKeyCanQuickAdjustBudget(consumer))
    }

    func providerKeyCanQuickAdjustBudget(
        _ consumer: RemoteQuotaCenterClientProjection
    ) -> Bool {
        if let client = consumer.grpcClient {
            return client.policyMode == .newProfile && client.approvedTrustProfile != nil
        }
        if let accessKey = consumer.terminalAccessKey {
            return accessKey.supportsDirectBudgetAdjustment
        }
        return false
    }
}
