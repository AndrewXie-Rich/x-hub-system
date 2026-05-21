import SwiftUI

struct HubRemoteAccessGuidancePresentation: Equatable {
    let state: XTUISurfaceState
    let message: String
}

enum HubRemoteAccessGuidanceBuilder {
    static func formalEntry(internetHost: String) -> HubRemoteAccessGuidancePresentation {
        let classification = XTHubRemoteAccessHostClassification.classify(internetHost)

        switch classification.kind {
        case .missing:
            return HubRemoteAccessGuidancePresentation(
                state: .blockedWaitingUpstream,
                message: "未设置正式入口。异网推荐 Tailscale IP（高）、稳定域名/relay/Spectrum/VPS TCP（中高）；公网 IP 仅适合临时直连（低）。"
            )
        case .lanOnly:
            return HubRemoteAccessGuidancePresentation(
                state: .diagnosticRequired,
                message: "当前还是同网入口，只适合同 Wi-Fi / 同 LAN；要切网不断连，请改成 Tailscale IP、稳定域名、relay/Spectrum/VPS TCP 或临时公网 IP。"
            )
        case .rawIP(let scope):
            if scope.isFormalRemoteEntry {
                return HubRemoteAccessGuidancePresentation(
                    state: .ready,
                    message: "Tailscale IP 已作为正式入口；安全等级高，XT 需登录同一个 tailnet，切网重连会优先验证这条路径。"
                )
            }
            if scope == .publicInternet {
                return HubRemoteAccessGuidancePresentation(
                    state: .diagnosticRequired,
                    message: "公网 IP 可直连，安全/稳定等级低；需确保防火墙和端口转发只暴露必要端口，IP 变化后要重新更新。"
                )
            }
            return HubRemoteAccessGuidancePresentation(
                state: .diagnosticRequired,
                message: "当前仍是临时 raw IP（\(scope.doctorLabel)），只适合诊断 / 救火，不应作为正式入口。"
            )
        case .stableNamed:
            return HubRemoteAccessGuidancePresentation(
                state: .ready,
                message: "XT 会把该域名当作正式入口；切网、自愈和后台重连都会先验证这条路径。"
            )
        }
    }

    static func inviteToken(
        internetHost: String,
        inviteToken: String
    ) -> HubRemoteAccessGuidancePresentation {
        let trimmedToken = inviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            return HubRemoteAccessGuidancePresentation(
                state: .inProgress,
                message: "邀请令牌只用于正式首配；连接成功后会自动清空。"
            )
        }

        let classification = XTHubRemoteAccessHostClassification.classify(internetHost)
        if classification.isFormalRemoteEntry {
            return HubRemoteAccessGuidancePresentation(
                state: .ready,
                message: "长期连接靠已下发凭据，不靠 invite token。"
            )
        } else {
            return HubRemoteAccessGuidancePresentation(
                state: .blockedWaitingUpstream,
                message: "如果要异网正式首配，优先从 Hub 邀请链接自动带入 invite token，不要手填旧 token。"
            )
        }
    }
}
