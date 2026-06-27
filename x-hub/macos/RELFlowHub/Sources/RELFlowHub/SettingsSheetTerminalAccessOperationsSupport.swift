import Foundation
import RELFlowHubCore

extension SettingsSheetView {
    @MainActor
    private func ensureTerminalAccessGatewayReady() async throws {
        let firstHealth = await TerminalAccessKeyHTTPClient.gatewayHealth(grpcPort: grpc.port)
        if firstHealth?.isPairingGateway == true {
            return
        }
        if let firstHealth {
            let endpoint = TerminalAccessKeyHTTPClient.gatewayBaseURLText(grpcPort: grpc.port)
            throw TerminalAccessKeyHTTPClient.ClientError.gatewayUnavailable(
                message: "普通 Terminal Gateway 端口不正确：\(endpoint)/health 返回 \(firstHealth.diagnosticSummary)，不是 service=pairing。请不要把普通 terminal URL 指到 Rust kernel 的 HTTP 端口。"
            )
        }

        grpc.restart()
        var lastHealth: TerminalAccessGatewayHealth? = nil
        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 350_000_000)
            let health = await TerminalAccessKeyHTTPClient.gatewayHealth(grpcPort: grpc.port)
            lastHealth = health
            if health?.isPairingGateway == true {
                return
            }
        }

        let endpoint = TerminalAccessKeyHTTPClient.gatewayBaseURLText(grpcPort: grpc.port)
        let observed = lastHealth?.diagnosticSummary ?? "no response"
        let message = """
        普通 Terminal Gateway 还没有就绪：\(endpoint)/health 返回 \(observed)。这通常说明 Node pairing gateway 没启动，或当前端口指到了 Rust kernel。请先在 Hub 设置里重启 gRPC/Pairing sidecar，再重新签发；系统不会返回一个会 404/not_found 的 Key + URL。
        """
        throw TerminalAccessKeyHTTPClient.ClientError.gatewayUnavailable(message: message)
    }

    @MainActor
    func reloadTerminalAccessKeys(forceMessage: Bool = false) async {
        if terminalAccessReloadInFlight { return }
        terminalAccessReloadInFlight = true
        defer { terminalAccessReloadInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            let rows = try await TerminalAccessKeyHTTPClient.list(
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            terminalAccessKeys = rows
            rebuildRemoteQuotaProjectionSnapshot()
            terminalAccessErrorText = ""
            if forceMessage {
                terminalAccessActionText = "已刷新普通 terminal access key 列表。"
            }
        } catch {
            terminalAccessErrorText = error.localizedDescription
            if forceMessage {
                terminalAccessActionText = ""
            }
        }
    }

    @MainActor
    func issueTerminalAccessKey() async {
        if terminalAccessMutationInFlight { return }
        terminalAccessMutationInFlight = true
        defer { terminalAccessMutationInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            let secret = try await TerminalAccessKeyHTTPClient.issue(
                draft: terminalAccessDraft,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            terminalAccessLastSecret = secret
            terminalAccessIssueExpanded = false
            terminalAccessLastSecretExpanded = true
            terminalAccessErrorText = ""
            terminalAccessActionText = "已签发 \(secret.accessKey.resolvedName)，已返回普通 terminal 的 URL + API key。"
            await reloadTerminalAccessKeys(forceMessage: false)
        } catch {
            terminalAccessErrorText = error.localizedDescription
        }
    }

    @MainActor
    func rotateTerminalAccessKey(_ accessKey: HubTerminalAccessKey) async {
        if terminalAccessMutationInFlight { return }
        terminalAccessMutationInFlight = true
        defer { terminalAccessMutationInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            let secret = try await TerminalAccessKeyHTTPClient.rotate(
                accessKeyID: accessKey.accessKeyID,
                note: accessKey.note,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            terminalAccessLastSecret = secret
            terminalAccessLastSecretExpanded = true
            terminalAccessErrorText = ""
            terminalAccessActionText = "已轮换 \(secret.accessKey.resolvedName)，新的普通 terminal API key 已返回。"
            await reloadTerminalAccessKeys(forceMessage: false)
        } catch {
            terminalAccessErrorText = error.localizedDescription
        }
    }

    @MainActor
    private func setTerminalAccessKeyDailyBudget(
        _ accessKey: HubTerminalAccessKey,
        dailyTokenLimit: Int
    ) async {
        guard accessKey.supportsDirectBudgetAdjustment else {
            let message = "普通 terminal 预算设定只支持启用新策略档案且未撤销的 access key。"
            terminalAccessActionText = ""
            terminalAccessErrorText = message
            remoteQuotaActionText = ""
            remoteQuotaErrorText = message
            return
        }
        if terminalAccessMutationInFlight { return }

        let updatedLimit = max(1, dailyTokenLimit)

        terminalAccessMutationInFlight = true
        defer { terminalAccessMutationInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            let updated = try await TerminalAccessKeyHTTPClient.updateDailyBudget(
                accessKeyID: accessKey.accessKeyID,
                dailyTokenLimit: updatedLimit,
                note: accessKey.note,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )

            if let index = terminalAccessKeys.firstIndex(where: { $0.accessKeyID == updated.accessKeyID }) {
                terminalAccessKeys[index] = updated
            }
            if let secret = terminalAccessLastSecret,
               secret.accessKey.accessKeyID == updated.accessKeyID {
                terminalAccessLastSecret = HubTerminalAccessKeySecretEnvelope(
                    clientToken: secret.clientToken,
                    accessKey: updated
                )
            }

            let actionText = "\(updated.resolvedName) 日预算已调整为 \(terminalAccessIntText(Int64(updated.dailyTokenLimit))) tokens。"
            terminalAccessErrorText = ""
            terminalAccessActionText = actionText
            remoteQuotaErrorText = ""
            remoteQuotaActionText = actionText
            await reloadTerminalAccessKeys(forceMessage: false)
        } catch {
            let message = error.localizedDescription
            terminalAccessActionText = ""
            terminalAccessErrorText = message
            remoteQuotaActionText = ""
            remoteQuotaErrorText = message
        }
    }

    @MainActor
    func adjustTerminalAccessKeyDailyBudget(
        _ accessKey: HubTerminalAccessKey,
        delta: Int
    ) async {
        let currentLimit = max(1, accessKey.dailyTokenLimit)
        let updatedLimit = max(1, currentLimit + delta)
        guard updatedLimit != currentLimit else { return }
        await setTerminalAccessKeyDailyBudget(accessKey, dailyTokenLimit: updatedLimit)
    }

    func presentRemoteQuotaBudgetEditor(
        _ consumer: RemoteQuotaCenterClientProjection
    ) {
        guard providerKeyCanQuickAdjustBudget(consumer) else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "当前消费者还不支持精确设预算。"
            return
        }
        remoteQuotaBudgetEditorTarget = RemoteQuotaBudgetEditorTarget(
            consumerKind: consumer.consumerKind,
            referenceID: consumer.referenceID,
            title: consumer.name,
            subtitle: providerKeyBudgetClientReferenceSummary(consumer),
            currentDailyTokenLimit: max(1, Int(consumer.dailyTokenLimit)),
            todayUsed: consumer.dailyTokenUsed
        )
    }

    func presentRemoteQuotaBudgetEditor(
        _ accessKey: HubTerminalAccessKey
    ) {
        guard accessKey.supportsDirectBudgetAdjustment else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "当前 terminal access key 还不支持精确设预算。"
            return
        }
        let subtitle = [
            "key \(accessKey.accessKeyID)",
            accessKey.userID.isEmpty ? "" : "user \(accessKey.userID)",
            accessKey.appID.isEmpty ? "" : "app \(accessKey.appID)",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
        remoteQuotaBudgetEditorTarget = RemoteQuotaBudgetEditorTarget(
            consumerKind: .terminalAccess,
            referenceID: accessKey.accessKeyID,
            title: accessKey.resolvedName,
            subtitle: subtitle,
            currentDailyTokenLimit: max(1, accessKey.dailyTokenLimit),
            todayUsed: Int64(max(0, terminalAccessQuotaUsed(deviceStatus: terminalAccessDeviceStatus(for: accessKey))))
        )
    }

    func applyRemoteQuotaBudgetEdit(
        _ target: RemoteQuotaBudgetEditorTarget,
        dailyTokenLimit: Int
    ) {
        let updatedLimit = max(1, dailyTokenLimit)
        guard let consumer = remoteQuotaProjection.consumers.first(where: {
            $0.consumerKind == target.consumerKind && $0.referenceID == target.referenceID
        }) else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "目标消费者已刷新，请重新打开预算设置。"
            return
        }

        if let client = consumer.grpcClient {
            grpcSetDailyBudget(client, dailyTokenLimit: updatedLimit)
            return
        }
        guard let accessKey = consumer.terminalAccessKey else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "当前 terminal access key 无法定位，请刷新后重试。"
            return
        }
        Task { await setTerminalAccessKeyDailyBudget(accessKey, dailyTokenLimit: updatedLimit) }
    }

    @MainActor
    func revokeTerminalAccessKey(_ accessKey: HubTerminalAccessKey) async {
        if terminalAccessMutationInFlight { return }
        terminalAccessMutationInFlight = true
        defer { terminalAccessMutationInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            _ = try await TerminalAccessKeyHTTPClient.revoke(
                accessKeyID: accessKey.accessKeyID,
                note: "revoked from hub settings",
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            if terminalAccessLastSecret?.accessKey.accessKeyID == accessKey.accessKeyID {
                terminalAccessLastSecret = nil
                terminalAccessLastSecretExpanded = false
            }
            terminalAccessPendingRevokeAccessKeyID = ""
            terminalAccessErrorText = ""
            terminalAccessActionText = "已撤销 \(accessKey.resolvedName)。"
            await reloadTerminalAccessKeys(forceMessage: false)
        } catch {
            terminalAccessPendingRevokeAccessKeyID = ""
            terminalAccessErrorText = error.localizedDescription
        }
    }

}
