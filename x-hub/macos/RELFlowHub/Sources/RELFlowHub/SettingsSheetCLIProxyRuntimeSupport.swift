import AppKit
import Foundation
import RELFlowHubCore

extension SettingsSheetView {
    func reloadCLIProxyRuntimeConfiguration() {
        cliproxyRuntimeSettings = CLIProxyRuntimeSupport.loadSettings()
        cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)
    }

    func persistCLIProxyRuntimeConfiguration() {
        cliproxyRuntimeSettings = cliproxyRuntimeSettings.normalized()
        _ = CLIProxyRuntimeSupport.saveSettings(cliproxyRuntimeSettings)
        cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)
    }

    func detectCLIProxyRuntimePackage() {
        if let detectedURL = CLIProxyRuntimeSupport.detectPackageDirectoryURL() {
            cliproxyRuntimeSettings.packageDirectoryPath = detectedURL.path
            cliproxyRuntimeSettings.preferDetectedPackage = true
            persistCLIProxyRuntimeConfiguration()
            cliproxyRuntimeActionText = "已自动定位 CLIProxy 发行包：\(settingsSummarySnippet(detectedURL.path, limit: 62))"
            cliproxyRuntimeErrorText = ""
            Task { await refreshCLIProxyRuntimeStatus(manual: false) }
            return
        }

        cliproxyRuntimeErrorText = "自动探测没有找到 CLIProxy 发行包。默认会查找 ~/Documents/AX/source/CLIProxyAPI-main。"
    }

    @MainActor
    func refreshCLIProxyRuntimeStatus(manual: Bool = false) async {
        guard !cliproxyRuntimeRefreshing else { return }

        cliproxyRuntimeRefreshing = true
        persistCLIProxyRuntimeConfiguration()
        if manual {
            cliproxyRuntimeActionText = "正在检查本地 CLIProxy 节点…"
            cliproxyRuntimeErrorText = ""
        }

        defer {
            cliproxyRuntimeRefreshing = false
        }

        let probe = await CLIProxyRuntimeSupport.probe(
            baseURL: cliproxyOAuthSettings.baseURL,
            managementKey: cliproxyOAuthManagementKey,
            settings: cliproxyRuntimeSettings
        )
        cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)
        cliproxyRuntimeProbe = probe
        cliproxyRuntimeLastProbeAtMs = probe.probedAtMs

        guard manual else { return }

        let trimmedSummary = cliproxyRuntimeSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch probe.packageStatus {
        case .notFound where !probe.serviceRunning:
            cliproxyRuntimeErrorText = "还没有发现 CLIProxy 发行包目录。可点“自动探测”，或手动填写发行包目录。"
            cliproxyRuntimeActionText = ""
        case .missingExecutable:
            cliproxyRuntimeErrorText = "选中的目录里缺少 cli-proxy-api 可执行文件。"
            cliproxyRuntimeActionText = ""
        case .missingConfig:
            cliproxyRuntimeErrorText = "选中的目录里缺少 config.yaml。"
            cliproxyRuntimeActionText = ""
        default:
            switch probe.managementStatus {
            case .keyInvalid:
                cliproxyRuntimeErrorText = "CLIProxy 已运行，但 management key 不正确。"
                cliproxyRuntimeActionText = ""
            case .unavailable:
                cliproxyRuntimeErrorText = "CLIProxy 服务已启动，但管理接口当前不可用。"
                cliproxyRuntimeActionText = ""
            case .error(let detail):
                cliproxyRuntimeErrorText = detail.isEmpty
                    ? "CLIProxy 管理接口检查失败。"
                    : "CLIProxy 管理接口检查失败：\(detail)"
                cliproxyRuntimeActionText = ""
            default:
                cliproxyRuntimeActionText = trimmedSummary
                cliproxyRuntimeErrorText = ""
            }
        }
    }

    @MainActor
    func maybeRefreshCLIProxyRuntimeStatus() async {
        guard selectedSettingsPage == .models else { return }
        guard !cliproxyRuntimeRefreshing, !cliproxyRuntimeLaunching, !cliproxyRuntimeKeyRotating else { return }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let intervalMs: Int64 = nowMs < cliproxyRuntimeFastProbeUntilMs ? 4_000 : 20_000
        guard cliproxyRuntimeLastProbeAtMs == 0 || nowMs - cliproxyRuntimeLastProbeAtMs >= intervalMs else {
            return
        }

        await refreshCLIProxyRuntimeStatus(manual: false)
    }

    @MainActor
    func startCLIProxyRuntime() async {
        guard !cliproxyRuntimeLaunching else { return }

        persistCLIProxyRuntimeConfiguration()
        persistCLIProxyOAuthConfiguration()
        cliproxyRuntimeLaunching = true
        cliproxyRuntimeActionText = "正在启动本地 CLIProxy 节点…"
        cliproxyRuntimeErrorText = ""

        defer {
            cliproxyRuntimeLaunching = false
        }

        do {
            let result = try await CLIProxyRuntimeSupport.startServer(
                baseURL: cliproxyOAuthSettings.baseURL,
                settings: cliproxyRuntimeSettings
            )
            cliproxyRuntimeFastProbeUntilMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) + 20_000
            await refreshCLIProxyRuntimeStatus(manual: false)

            if result.alreadyRunning {
                cliproxyRuntimeActionText = "CLIProxy 已在运行，Hub 已切换到托管检查模式。"
            } else if result.healthConfirmed {
                cliproxyRuntimeActionText = "本地 CLIProxy 已启动（pid \(result.pid)），Hub 已探测到服务。"
            } else {
                cliproxyRuntimeActionText = "CLIProxy 启动请求已发出（pid \(result.pid)），服务仍在预热，Hub 会继续探测。"
            }

            if !cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await refreshCLIProxyOAuthRemoteAuths(manual: false)
                if cliproxyOAuthSettings.autoSync {
                    await syncCLIProxyOAuthAccounts(manual: false)
                }
            }
        } catch {
            cliproxyRuntimeErrorText = error.localizedDescription
        }
    }

    @MainActor
    func applyCLIProxyRuntimeConfigRecommendations() async {
        guard !cliproxyRuntimeConfigApplying else { return }

        persistCLIProxyRuntimeConfiguration()
        cliproxyRuntimeConfigApplying = true
        cliproxyRuntimeActionText = "正在把推荐项写入 CLIProxy config.yaml…"
        cliproxyRuntimeErrorText = ""

        defer {
            cliproxyRuntimeConfigApplying = false
        }

        do {
            let result = try CLIProxyRuntimeSupport.applyRecommendedConfigFixes(settings: cliproxyRuntimeSettings)
            cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)

            if result.changedCount == 0 {
                cliproxyRuntimeActionText = "config.yaml 已经符合当前推荐项，没有额外改动。"
            } else {
                let updatedTitles = result.updatedKinds.map(\.title).joined(separator: "、")
                let restartHint = cliproxyRuntimeProbe.serviceRunning ? "CLIProxy 当前正在运行，重启后这些改动会完全生效。" : "下次从 Hub 启动本地节点时会直接按新配置运行。"
                let backupHint = result.backupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? ""
                    : " 已生成备份：\(settingsSummarySnippet(result.backupPath, limit: 54))。"
                cliproxyRuntimeActionText =
                    "已修正 \(result.changedCount) 项：\(updatedTitles)。\(restartHint)\(backupHint)"
            }

            await refreshCLIProxyRuntimeStatus(manual: false)
        } catch {
            cliproxyRuntimeErrorText = error.localizedDescription
        }
    }

    @MainActor
    func rotateCLIProxyRuntimeManagementKey() async {
        guard !cliproxyRuntimeKeyRotating else { return }

        persistCLIProxyRuntimeConfiguration()
        persistCLIProxyOAuthConfiguration()
        cliproxyRuntimeKeyRotating = true
        cliproxyRuntimeActionText = "正在轮换 CLIProxy management key…"
        cliproxyRuntimeErrorText = ""
        cliproxyOAuthErrorText = ""

        defer {
            cliproxyRuntimeKeyRotating = false
        }

        do {
            let result = try CLIProxyRuntimeSupport.rotateManagementKey(settings: cliproxyRuntimeSettings)
            cliproxyOAuthManagementKey = result.newKey
            persistCLIProxyOAuthConfiguration()
            cliproxyRuntimeFastProbeUntilMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) + 20_000
            cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)

            let backupHint = result.backupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ""
                : " 已生成备份：\(settingsSummarySnippet(result.backupPath, limit: 54))。"

            if cliproxyRuntimeProbe.serviceRunning {
                let activated = await waitForCLIProxyRuntimeManagementKeyActivation(result.newKey)
                if activated {
                    cliproxyRuntimeActionText =
                        "已轮换 management key，Hub 和运行中 CLIProxy 已完成切换。\(backupHint)"
                    await refreshCLIProxyOAuthRemoteAuths(manual: false)
                    if cliproxyOAuthSettings.autoSync {
                        await syncCLIProxyOAuthAccounts(manual: false)
                    }
                } else {
                    cliproxyRuntimeActionText =
                        "新 management key 已写入 config.yaml 并同步到 Hub keychain；运行中 CLIProxy 还在切换，若稍后仍未接通可重启本地节点。\(backupHint)"
                }
            } else {
                cliproxyRuntimeActionText =
                    "已轮换 management key。下次从 Hub 启动本地节点时会直接使用新 key。\(backupHint)"
                await refreshCLIProxyRuntimeStatus(manual: false)
            }
        } catch {
            cliproxyRuntimeErrorText = error.localizedDescription
        }
    }

    @MainActor
    private func waitForCLIProxyRuntimeManagementKeyActivation(
        _ managementKey: String,
        timeoutSec: Double = 8.0
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            let probe = await CLIProxyRuntimeSupport.probe(
                baseURL: cliproxyOAuthSettings.baseURL,
                managementKey: managementKey,
                settings: cliproxyRuntimeSettings
            )
            cliproxyRuntimeProbe = probe
            cliproxyRuntimeLastProbeAtMs = probe.probedAtMs
            cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)

            guard probe.serviceRunning else { return false }

            switch probe.managementStatus {
            case .keyValid:
                return true
            case .keyInvalid, .waitingForKey, .unavailable, .unknown, .error:
                break
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        return false
    }

    func openCLIProxyRuntimePackageDirectory() {
        let settings = cliproxyRuntimeSettings
        let packageURL = CLIProxyRuntimeSupport.packageDirectoryURL(for: settings)
        guard let packageURL else {
            cliproxyRuntimeErrorText = "还没有可打开的 CLIProxy 发行包目录。"
            return
        }
        _ = NSWorkspace.shared.open(packageURL)
    }

    func openCLIProxyRuntimeConfigFile() {
        let settings = cliproxyRuntimeSettings
        guard let configURL = CLIProxyRuntimeSupport.configURL(for: settings) else {
            cliproxyRuntimeErrorText = "还没有找到可打开的 CLIProxy config.yaml。"
            return
        }
        _ = NSWorkspace.shared.open(configURL)
    }

    func reloadCLIProxyOAuthConfiguration() {
        let settings = CLIProxyOAuthSourceSupport.loadSettings()
        cliproxyOAuthSettings = settings
        cliproxyOAuthManagementKey = CLIProxyOAuthSourceSupport.loadManagementKey(baseURL: settings.baseURL)
    }

    func persistCLIProxyOAuthConfiguration() {
        cliproxyOAuthSettings.baseURL = CLIProxyOAuthSourceSupport.normalizedBaseURLString(
            cliproxyOAuthSettings.baseURL
        )
        _ = CLIProxyOAuthSourceSupport.saveSettings(cliproxyOAuthSettings)
        _ = CLIProxyOAuthSourceSupport.saveManagementKey(
            cliproxyOAuthManagementKey,
            baseURL: cliproxyOAuthSettings.baseURL
        )
    }

    @MainActor
    func refreshCLIProxyOAuthRemoteAuths(manual: Bool = false) async {
        guard !cliproxyOAuthRefreshing, !cliproxyOAuthSyncing else { return }

        persistCLIProxyOAuthConfiguration()
        let managementKey = cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if managementKey.isEmpty {
            if manual {
                cliproxyOAuthErrorText = "请先填写 CLIProxy management key。"
            }
            return
        }

        cliproxyOAuthRefreshing = true
        if manual {
            cliproxyOAuthActionText = "正在读取 CLIProxy 已认证账号列表…"
            cliproxyOAuthErrorText = ""
        }

        defer {
            cliproxyOAuthRefreshing = false
        }

        do {
            let auths = try await CLIProxyOAuthSourceSupport.listRemoteAuths(
                baseURL: cliproxyOAuthSettings.baseURL,
                managementKey: managementKey
            )
            cliproxyOAuthRemoteAuths = auths
            cliproxyOAuthLastRemoteFetchAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            if manual {
                cliproxyOAuthActionText = auths.isEmpty
                    ? "CLIProxy 当前还没有已认证账号。"
                    : "已刷新 \(auths.count) 个 CLIProxy OAuth 账号。"
            }
        } catch {
            if manual || cliproxyOAuthRemoteAuths.isEmpty {
                cliproxyOAuthErrorText = error.localizedDescription
            }
        }
    }

    @MainActor
    func syncCLIProxyOAuthAccounts(manual: Bool = true) async {
        guard !cliproxyOAuthSyncing else { return }

        persistCLIProxyOAuthConfiguration()
        let managementKey = cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if managementKey.isEmpty {
            cliproxyOAuthErrorText = "请先填写 CLIProxy management key。"
            return
        }

        cliproxyOAuthSyncing = true
        cliproxyOAuthErrorText = ""
        cliproxyOAuthActionText = manual
            ? "正在把 CLIProxy OAuth 账号同步进 Hub 额度池…"
            : "CLIProxy OAuth 自动同步中…"

        defer {
            cliproxyOAuthSyncing = false
        }

        do {
            let summary = try await CLIProxyOAuthSourceSupport.syncAccounts(
                baseURL: cliproxyOAuthSettings.baseURL,
                managementKey: managementKey
            )
            cliproxyOAuthRemoteAuths = summary.remoteAuths
            cliproxyOAuthLastRemoteFetchAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            cliproxyOAuthLastAutoSyncAtMs = cliproxyOAuthLastRemoteFetchAtMs
            let snapshot = await Task.detached(priority: .utility) {
                await Self.loadProviderKeySnapshotWithBootstrapBackground()
            }.value
            providerKeySnapshot = snapshot
            lastProviderKeyPeriodicRefreshAt = Date()
            rebuildRemoteQuotaProjectionSnapshot()
            if summary.errorMessages.isEmpty {
                cliproxyOAuthSettings.lastSyncAtMs = CLIProxyOAuthSourceSupport.loadSettings().lastSyncAtMs
                cliproxyOAuthActionText = cliproxyOAuthSyncActionText(
                    summary: summary,
                    snapshot: snapshot,
                    partial: false
                )
            } else {
                cliproxyOAuthActionText = cliproxyOAuthSyncActionText(
                    summary: summary,
                    snapshot: snapshot,
                    partial: true
                )
                cliproxyOAuthErrorText = summary.errorMessages.prefix(3).joined(separator: " | ")
            }
        } catch {
            cliproxyOAuthErrorText = error.localizedDescription
        }
    }

    @MainActor
    func startCLIProxyOAuth(_ provider: HubProviderOAuthHTTPClient.Provider) async {
        guard cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cliproxyOAuthErrorText = "已有 Provider OAuth 登录在进行中。"
            return
        }

        cliproxyOAuthErrorText = ""
        cliproxyOAuthActionText = "正在向 Hub 发起 \(provider.title) OAuth…"

        do {
            let launch = try await HubProviderOAuthHTTPClient.startLogin(
                provider: provider,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            guard let authURL = URL(string: launch.authURL),
                  let redirectURL = URL(string: launch.redirectURI) else {
                throw HubProviderOAuthHTTPClient.ClientError.apiError("invalid_oauth_login_payload")
            }

            let callbackServer = try HubProviderOAuthLoopbackCallbackServer(redirectURI: redirectURL)
            cliproxyOAuthActiveState = launch.state
            cliproxyOAuthActiveProvider = provider
            cliproxyOAuthActionText = "\(provider.title) OAuth 已打开浏览器，等待登录回调…"

            async let callbackURL = callbackServer.waitForCallback(
                timeout: oauthCallbackTimeoutSeconds(launch.expiresAtMs)
            )
            guard NSWorkspace.shared.open(authURL) else {
                cliproxyOAuthActiveState = ""
                cliproxyOAuthActiveProvider = nil
                throw HubProviderOAuthHTTPClient.ClientError.apiError("failed_to_open_browser")
            }

            let returnedURL = try await callbackURL
            cliproxyOAuthActionText = "Hub 正在导入 \(provider.title) OAuth 凭证…"
            let submit = try await HubProviderOAuthHTTPClient.submitCallback(
                provider: launch.provider.isEmpty ? provider.rawValue : launch.provider,
                state: launch.state,
                redirectURL: returnedURL.absoluteString,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            guard submit.ok else {
                throw HubProviderOAuthHTTPClient.ClientError.apiError(submit.error)
            }
            await pollCLIProxyOAuthLogin()
        } catch {
            cliproxyOAuthErrorText = error.localizedDescription
            cliproxyOAuthActionText = ""
            cliproxyOAuthActiveState = ""
            cliproxyOAuthActiveProvider = nil
        }
    }

    @MainActor
    func pollCLIProxyOAuthLogin() async {
        let activeState = cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !activeState.isEmpty else { return }

        do {
            let status = try await HubProviderOAuthHTTPClient.status(
                state: activeState,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            switch status.status {
            case "pending", "processing":
                break
            case "ok":
                let providerTitle = cliproxyOAuthActiveProvider?.title ?? "Hub"
                cliproxyOAuthActiveState = ""
                cliproxyOAuthActiveProvider = nil
                let detail = [status.email, status.accountKey]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                cliproxyOAuthActionText = detail.isEmpty
                    ? "\(providerTitle) OAuth 已完成并导入 Hub 额度池。"
                    : "\(providerTitle) OAuth 已完成并导入 Hub 额度池：\(detail)"
                reloadProviderKeySnapshot()
            case "error", "expired", "unknown":
                let providerTitle = cliproxyOAuthActiveProvider?.title ?? "Hub"
                cliproxyOAuthActiveState = ""
                cliproxyOAuthActiveProvider = nil
                let message = status.error.isEmpty
                    ? (status.statusMessage.isEmpty ? status.status : status.statusMessage)
                    : status.error
                cliproxyOAuthErrorText = "\(providerTitle) OAuth 失败：\(message)"
            default:
                break
            }
        } catch {
            cliproxyOAuthErrorText = error.localizedDescription
            cliproxyOAuthActiveState = ""
            cliproxyOAuthActiveProvider = nil
        }
    }

    private func oauthCallbackTimeoutSeconds(_ expiresAtMs: Int64) -> TimeInterval {
        guard expiresAtMs > 0 else { return 300 }
        let remaining = max(15, (Double(expiresAtMs) / 1000.0) - Date().timeIntervalSince1970)
        return min(remaining, 600)
    }

    @MainActor
    func maybeAutoSyncCLIProxyOAuthAccounts() async {
        guard cliproxyOAuthSettings.autoSync else { return }
        guard cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !cliproxyOAuthSyncing, !cliproxyOAuthRefreshing else { return }
        guard !cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let baseline = max(cliproxyOAuthLastAutoSyncAtMs, cliproxyOAuthSettings.lastSyncAtMs)
        guard baseline == 0 || nowMs - baseline >= 60_000 else { return }
        cliproxyOAuthLastAutoSyncAtMs = nowMs
        await syncCLIProxyOAuthAccounts(manual: false)
    }

    func openCLIProxyOAuthManagementConsole() {
        persistCLIProxyOAuthConfiguration()
        guard cliproxyRuntimeProbe.serviceRunning else {
            cliproxyOAuthErrorText = "CLIProxy 管理页当前没有运行。Hub 原生 OAuth 可直接用“发起 OAuth”，不需要打开 CLIProxy 管理页；如果要维护旧 CLIProxy 账号，请先启动本地节点。"
            return
        }
        guard let url = CLIProxyOAuthSourceSupport.managementConsoleURL(
            baseURL: cliproxyOAuthSettings.baseURL
        ) else {
            cliproxyOAuthErrorText = "CLIProxy 地址无效。"
            return
        }
        _ = NSWorkspace.shared.open(url)
    }

}
