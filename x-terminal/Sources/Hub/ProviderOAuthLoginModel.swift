import Foundation

@MainActor
final class ProviderOAuthLoginModel: ObservableObject {
    enum Provider: String, CaseIterable, Identifiable, Sendable {
        case codex
        case claude
        case gemini
        case antigravity

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .codex:
                return "Codex"
            case .claude:
                return "Claude"
            case .gemini:
                return "Gemini"
            case .antigravity:
                return "Antigravity"
            }
        }
    }

    @Published private(set) var activeProvider: Provider?
    @Published private(set) var statusLine: String = ""
    @Published private(set) var detailLine: String = ""

    var isRunning: Bool {
        activeProvider != nil
    }

    func startLogin(
        provider: Provider,
        openBrowser: @escaping (URL) -> Bool,
        onSuccess: (() async -> Void)? = nil
    ) {
        guard activeProvider == nil else {
            statusLine = "已有 Provider 登录在进行中"
            return
        }

        activeProvider = provider
        statusLine = "正在启动 \(provider.displayName) 登录"
        detailLine = ""

        Task {
            await self.runLogin(
                provider: provider,
                openBrowser: openBrowser,
                onSuccess: onSuccess
            )
        }
    }

    private func runLogin(
        provider: Provider,
        openBrowser: @escaping (URL) -> Bool,
        onSuccess: (() async -> Void)?
    ) async {
        let start = await HubProviderKeysClient.startProviderOAuthLogin(provider: provider.rawValue)
        guard start.ok else {
            finishWithError(start.error.isEmpty ? "failed_to_start_oauth_login" : start.error)
            return
        }

        guard let authURL = URL(string: start.authURL),
              let redirectURL = URL(string: start.redirectURI) else {
            finishWithError("invalid_oauth_login_payload")
            return
        }

        let callbackServer: ProviderOAuthLoopbackCallbackServer
        do {
            callbackServer = try ProviderOAuthLoopbackCallbackServer(redirectURI: redirectURL)
        } catch {
            finishWithError(String(describing: error.localizedDescription))
            return
        }

        statusLine = "等待浏览器完成 \(provider.displayName) 登录"
        detailLine = redirectURL.absoluteString

        guard openBrowser(authURL) else {
            finishWithError("failed_to_open_browser")
            return
        }

        let callbackURL: URL
        do {
            let timeout = callbackTimeoutSeconds(start.expiresAtMs)
            callbackURL = try await callbackServer.waitForCallback(timeout: timeout)
        } catch {
            finishWithError(String(describing: error.localizedDescription))
            return
        }

        statusLine = "Hub 正在导入 \(provider.displayName) 凭证"
        detailLine = callbackURL.absoluteString

        let submit = await HubProviderKeysClient.submitProviderOAuthCallback(
            provider: start.provider.isEmpty ? provider.rawValue : start.provider,
            state: start.state,
            redirectURL: callbackURL.absoluteString
        )
        guard submit.ok else {
            finishWithError(submit.error.isEmpty ? "oauth_callback_submit_failed" : submit.error)
            return
        }

        guard let finalStatus = await pollForTerminalStatus(state: start.state) else {
            finishWithError("oauth_status_timeout")
            return
        }

        if finalStatus.status == "ok" {
            HubProviderKeysClient.invalidateCache()
            await onSuccess?()
            activeProvider = nil
            statusLine = "\(provider.displayName) 已登录并导入 Hub"
            detailLine = successDetail(finalStatus)
            return
        }

        finishWithError(
            finalStatus.error.isEmpty
                ? (finalStatus.statusMessage.isEmpty ? finalStatus.status : finalStatus.statusMessage)
                : finalStatus.error
        )
    }

    private func pollForTerminalStatus(state: String) async -> HubProviderKeysClient.OAuthLoginStatus? {
        for _ in 0..<160 {
            let status = await HubProviderKeysClient.getProviderOAuthLoginStatus(state: state)
            if status.isTerminal {
                return status
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return nil
    }

    private func callbackTimeoutSeconds(_ expiresAtMs: Double) -> TimeInterval {
        guard expiresAtMs > 0 else { return 300 }
        let remaining = max(15, (expiresAtMs / 1000.0) - Date().timeIntervalSince1970)
        return min(remaining, 600)
    }

    private func successDetail(_ status: HubProviderKeysClient.OAuthLoginStatus) -> String {
        var parts: [String] = []
        if !status.email.isEmpty {
            parts.append(status.email)
        }
        if !status.accountKey.isEmpty {
            parts.append(status.accountKey)
        }
        if !status.authFilePath.isEmpty {
            parts.append(status.authFilePath)
        }
        return parts.isEmpty ? "Provider key 池已刷新" : parts.joined(separator: " • ")
    }

    private func finishWithError(_ message: String) {
        activeProvider = nil
        statusLine = "Provider 登录失败"
        detailLine = message
    }
}
