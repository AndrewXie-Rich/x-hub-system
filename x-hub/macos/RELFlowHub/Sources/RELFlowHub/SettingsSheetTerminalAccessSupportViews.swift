import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
    var terminalAccessSortedKeys: [HubTerminalAccessKey] {
        terminalAccessKeys.sorted { left, right in
            if left.updatedAtMs != right.updatedAtMs {
                return left.updatedAtMs > right.updatedAtMs
            }
            if left.createdAtMs != right.createdAtMs {
                return left.createdAtMs > right.createdAtMs
            }
            return left.resolvedName.localizedCaseInsensitiveCompare(right.resolvedName) == .orderedAscending
        }
    }

    var terminalAccessReadyCount: Int {
        terminalAccessKeys.filter { $0.status.lowercased() == "ready" }.count
    }

    var terminalAccessCurrentBaseURL: String {
        if let resolved = terminalAccessKeys
            .compactMap({ $0.openAICompat?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return resolved
        }
        let host = (grpc.xtTerminalInternetHost ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHost = host.isEmpty ? "127.0.0.1" : host
        let pairingPort = TerminalAccessKeyHTTPClient.pairingPort(grpcPort: grpc.port)
        if resolvedHost.contains(":") {
            return "http://\(resolvedHost)/v1"
        }
        return "http://\(resolvedHost):\(pairingPort)/v1"
    }

    var terminalAccessSectionSummaryText: String {
        let blocked = max(0, terminalAccessKeys.count - terminalAccessReadyCount)
        let baseURL = terminalAccessCurrentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return "keys \(terminalAccessKeys.count) • ready \(terminalAccessReadyCount) • blocked \(blocked) • daily quota \(terminalAccessIntText(terminalAccessOverviewQuotaTotal)) • \(baseURL)"
    }

    var terminalAccessOverviewQuotaTotal: Int64 {
        terminalAccessSortedKeys.reduce(Int64(0)) { partialResult, item in
            partialResult + terminalAccessQuotaLimit(for: item, deviceStatus: terminalAccessDeviceStatus(for: item))
        }
    }

    var terminalAccessOverviewUsedTotal: Int64 {
        terminalAccessSortedKeys.reduce(Int64(0)) { partialResult, item in
            partialResult + terminalAccessQuotaUsed(deviceStatus: terminalAccessDeviceStatus(for: item))
        }
    }

    var terminalAccessOverviewRemainingTotal: Int64 {
        terminalAccessSortedKeys.reduce(Int64(0)) { partialResult, item in
            let status = terminalAccessDeviceStatus(for: item)
            let limit = terminalAccessQuotaLimit(for: item, deviceStatus: status)
            let used = terminalAccessQuotaUsed(deviceStatus: status)
            return partialResult + terminalAccessQuotaRemaining(limit: limit, used: used, deviceStatus: status)
        }
    }

    var terminalAccessPendingRevokeAccessKey: HubTerminalAccessKey? {
        terminalAccessKeys.first { $0.accessKeyID == terminalAccessPendingRevokeAccessKeyID }
    }

    var terminalAccessRevokeDialogPresented: Binding<Bool> {
        Binding(
            get: { !terminalAccessPendingRevokeAccessKeyID.isEmpty },
            set: { presented in
                if !presented {
                    terminalAccessPendingRevokeAccessKeyID = ""
                }
            }
        )
    }

    func terminalAccessBaseURL(for accessKey: HubTerminalAccessKey) -> String {
        accessKey.openAICompat?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func terminalAccessStatusTint(_ accessKey: HubTerminalAccessKey) -> Color {
        switch accessKey.status.lowercased() {
        case "ready":
            return .green
        case "revoked":
            return .red
        case "expired", "disabled":
            return .orange
        default:
            return .blue
        }
    }

    func terminalAccessStatusIcon(_ accessKey: HubTerminalAccessKey) -> String {
        switch accessKey.status.lowercased() {
        case "ready":
            return "checkmark.shield.fill"
        case "revoked":
            return "xmark.shield.fill"
        case "expired":
            return "clock.badge.exclamationmark.fill"
        case "disabled":
            return "pause.circle.fill"
        default:
            return "key.fill"
        }
    }

    func terminalAccessSecretEnvelope(for accessKey: HubTerminalAccessKey) -> HubTerminalAccessKeySecretEnvelope? {
        guard let lastSecret = terminalAccessLastSecret else { return nil }
        return lastSecret.accessKey.accessKeyID == accessKey.accessKeyID ? lastSecret : nil
    }

    func terminalAccessDeliveryPack(for accessKey: HubTerminalAccessKey) -> HubTerminalAccessDeliveryPack {
        if let secret = terminalAccessSecretEnvelope(for: accessKey) {
            return secret.deliveryPack
        }
        return accessKey.deliveryPack()
    }

    func terminalAccessExampleText(for deliveryPack: HubTerminalAccessDeliveryPack) -> String {
        switch terminalAccessExampleKind {
        case .shell:
            return deliveryPack.shellExports
        case .python:
            return deliveryPack.pythonSnippet
        case .node:
            return deliveryPack.nodeSnippet
        case .curl:
            return deliveryPack.curlCommand
        }
    }

    func terminalAccessDeviceStatus(for accessKey: HubTerminalAccessKey) -> GRPCDeviceStatusEntry? {
        grpcDevicesStatus.devices.first { row in
            row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines) == accessKey.deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func terminalAccessQuotaLimit(
        for accessKey: HubTerminalAccessKey,
        deviceStatus: GRPCDeviceStatusEntry?
    ) -> Int64 {
        let snapshotLimit = max(0, deviceStatus?.dailyTokenLimit ?? 0)
        if snapshotLimit > 0 {
            return snapshotLimit
        }
        return Int64(max(0, accessKey.dailyTokenLimit))
    }

    func terminalAccessQuotaUsed(deviceStatus: GRPCDeviceStatusEntry?) -> Int64 {
        max(0, deviceStatus?.dailyTokenUsed ?? 0)
    }

    func terminalAccessQuotaRemaining(
        limit: Int64,
        used: Int64,
        deviceStatus: GRPCDeviceStatusEntry?
    ) -> Int64 {
        let explicitRemaining = max(
            max(0, deviceStatus?.remainingDailyTokenBudget ?? 0),
            max(0, deviceStatus?.dailyTokenRemaining ?? 0)
        )
        if explicitRemaining > 0 || (deviceStatus != nil && used > 0) {
            return explicitRemaining
        }
        if limit <= 0 {
            return 0
        }
        return max(0, limit - used)
    }

    func terminalAccessSummaryLine(_ accessKey: HubTerminalAccessKey, quotaLimit: Int64) -> String {
        let paidModelText = accessKey.paidModelSelectionMode == .off ? "paid off" : "paid on"
        let webFetchText = accessKey.defaultWebFetchEnabled ? "web.fetch on" : "web.fetch off"
        let userText = accessKey.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "anonymous" : accessKey.userID
        return [
            "user \(userText)",
            "quota \(terminalAccessIntText(quotaLimit))/day",
            paidModelText,
            webFetchText,
            accessKey.tokenRedacted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : accessKey.tokenRedacted,
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    func terminalAccessLiveUsageLine(_ deviceStatus: GRPCDeviceStatusEntry) -> String {
        let topModel = deviceStatus.topModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let topModelSuffix = topModel.isEmpty ? "" : " • top \(topModel)"
        return [
            deviceStatus.connected ? "connected" : "offline",
            "requests \(deviceStatus.requestsToday)",
            "blocked \(deviceStatus.blockedToday)",
            "remaining \(terminalAccessIntText(max(0, deviceStatus.remainingDailyTokenBudget)))",
        ].joined(separator: " • ") + topModelSuffix
    }

    func terminalAccessIntText(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: max(0, value))) ?? String(max(0, value))
    }

    func terminalAccessIntegerFormatter(minimum: Int, maximum: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximum = NSNumber(value: maximum)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    func terminalAccessCopyToPasteboard(_ text: String, successText: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        terminalAccessErrorText = ""
        terminalAccessActionText = successText
    }

    func terminalAccessFeedbackBanner(text: String, tint: Color, systemName: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func terminalAccessStatusBadge(_ accessKey: HubTerminalAccessKey) -> some View {
        let label: String
        let tint: Color
        switch accessKey.status.lowercased() {
        case "ready":
            label = "可用"
            tint = .green
        case "revoked":
            label = "已撤销"
            tint = .red
        case "expired":
            label = "已过期"
            tint = .orange
        case "disabled":
            label = "已禁用"
            tint = .orange
        case "invalid":
            label = "无效"
            tint = .red
        default:
            label = accessKey.status.isEmpty ? "未知" : accessKey.status
            tint = .secondary
        }

        return Text(label)
            .font(.caption.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    func terminalAccessQuickBudgetButton(
        _ accessKey: HubTerminalAccessKey,
        delta: Int,
        title: String
    ) -> some View {
        let tint: Color = delta < 0 ? .orange : .indigo
        Button(title) {
            Task { await adjustTerminalAccessKeyDailyBudget(accessKey, delta: delta) }
        }
        .buttonStyle(.borderless)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
        .disabled(terminalAccessMutationInFlight || !accessKey.supportsDirectBudgetAdjustment)
    }

    func terminalAccessFact(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func terminalAccessExportBlock(
        title: String,
        text: String,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .padding(10)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    func terminalAccessDeliveryPanel(
        accessKey: HubTerminalAccessKey,
        deliveryPack: HubTerminalAccessDeliveryPack,
        hasSecret: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasSecret ? "当前可直接下发" : "当前交付模板")
                        .font(.caption.weight(.semibold))
                    Text(
                        hasSecret
                            ? "这把 key 的最新 secret 还在当前页面，可直接把 URL + API key + shell export 发给目标 terminal。"
                            : "Hub 目前只保留这把 key 的 URL 与模板。需要重新分发原始 secret 时，请先轮换。"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                terminalAccessBadge(
                    title: hasSecret ? "Secret 已就绪" : "仅模板",
                    tint: hasSecret ? .teal : .orange
                )
            }

            HStack(spacing: 8) {
                terminalAccessMiniPill(title: deliveryPack.authDisplayText, tint: .blue)
                terminalAccessMiniPill(title: deliveryPack.baseURLEnvKey, tint: .teal)
                terminalAccessMiniPill(
                    title: deliveryPack.apiKeyEnvKey,
                    tint: hasSecret ? .orange : .gray
                )
                terminalAccessMiniPill(
                    title: "示例 \(terminalAccessExampleKind.title)",
                    tint: terminalAccessExampleKind.tint
                )
                if !deliveryPack.responsesURL.isEmpty {
                    terminalAccessMiniPill(title: "/responses", tint: .green)
                }
                Spacer()
            }

            if !deliveryPack.baseURL.isEmpty {
                Text(deliveryPack.baseURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button(hasSecret ? "复制接入包" : "复制模板包") {
                    terminalAccessCopyToPasteboard(
                        deliveryPack.setupPackText,
                        successText: hasSecret
                            ? "已复制 \(accessKey.resolvedName) 的 terminal 接入包。"
                            : "已复制 \(accessKey.resolvedName) 的模板接入包。"
                    )
                }
                .disabled(deliveryPack.setupPackText.isEmpty)

                Button(hasSecret ? "复制 shell export" : "复制 shell 模板") {
                    terminalAccessCopyToPasteboard(
                        deliveryPack.shellExports,
                        successText: hasSecret
                            ? "已复制 \(accessKey.resolvedName) 的 shell export。"
                            : "已复制 \(accessKey.resolvedName) 的 shell 模板。"
                    )
                }
                .disabled(deliveryPack.shellExports.isEmpty)

                Button(terminalAccessExampleKind.copyButtonTitle) {
                    terminalAccessCopyToPasteboard(
                        terminalAccessExampleText(for: deliveryPack),
                        successText: "已复制 \(accessKey.resolvedName) 的 \(terminalAccessExampleKind.title) 示例。"
                    )
                }
                .disabled(terminalAccessExampleText(for: deliveryPack).isEmpty)

                if hasSecret {
                    Button("复制 API Key") {
                        terminalAccessCopyToPasteboard(
                            deliveryPack.apiKeyValue,
                            successText: "已复制 \(accessKey.resolvedName) 的 OpenAI API key。"
                        )
                    }
                    .disabled(deliveryPack.apiKeyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: hasSecret
                            ? [
                                Color(red: 0.87, green: 0.96, blue: 0.93),
                                Color(red: 0.92, green: 0.97, blue: 0.98),
                            ]
                            : [
                                Color(red: 0.98, green: 0.94, blue: 0.88),
                                Color(red: 0.96, green: 0.97, blue: 0.99),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    (hasSecret ? Color.teal : Color.orange).opacity(0.18),
                    lineWidth: 1
                )
        )
    }

    func terminalAccessExampleShowcase(deliveryPack: HubTerminalAccessDeliveryPack) -> some View {
        let snippet = terminalAccessExampleText(for: deliveryPack)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SDK / CLI 快速接入")
                        .font(.caption.weight(.semibold))
                    Text("切换示例类型后，可直接复制给普通 terminal 用户。示例默认用 `MODEL_ID_HERE`，先看 `/v1/models` 再替换。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                terminalAccessBadge(
                    title: terminalAccessExampleKind.title,
                    tint: terminalAccessExampleKind.tint
                )
            }

            Picker("接入示例", selection: $terminalAccessExampleKind) {
                ForEach(TerminalAccessExampleKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button(terminalAccessExampleKind.copyButtonTitle) {
                    terminalAccessCopyToPasteboard(
                        snippet,
                        successText: "已复制普通 terminal 的 \(terminalAccessExampleKind.title) 示例。"
                    )
                }
                .disabled(snippet.isEmpty)

                Spacer()
            }
            .font(.caption)

            if !snippet.isEmpty {
                terminalAccessExportBlock(
                    title: terminalAccessExampleKind.blockTitle,
                    text: snippet,
                    minHeight: 104,
                    maxHeight: 220
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.60))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(terminalAccessExampleKind.tint.opacity(0.16), lineWidth: 1)
        )
    }

    func terminalAccessBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    func terminalAccessMiniPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }

    func terminalAccessOverviewMetric(
        title: String,
        value: String,
        subtitle: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
