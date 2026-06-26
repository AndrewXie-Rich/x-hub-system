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
                message: "未设置 Hub IP/域名。首次配对可手填 Hub IP/域名和端口，或粘贴 Hub 同 Wi-Fi 配对码；需要扫描时必须手动确认。异网安全路线用稳定域名 + relay/Spectrum/VPS TCP，便捷路线用公网 IP/DDNS 直连。"
            )
        case .lanOnly:
            return HubRemoteAccessGuidancePresentation(
                state: .diagnosticRequired,
                message: "当前还是同网入口，只适合同 Wi-Fi / 同 LAN；要切网不断连，请改成稳定域名、relay/Spectrum/VPS TCP、公网 IP/DDNS，或用户自选的私有网络入口。"
            )
        case .rawIP(let scope):
            if scope.isFormalRemoteEntry {
                return HubRemoteAccessGuidancePresentation(
                    state: .ready,
                    message: "私有网络 IP 已作为正式入口；安全等级高，XT 需加入同一个私有网络，切网重连会优先验证这条路径。"
                )
            }
            if scope == .publicInternet {
                return HubRemoteAccessGuidancePresentation(
                    state: .diagnosticRequired,
                    message: "公网 IP/DDNS 是便捷直连路线，安全/稳定等级低；需确保防火墙和端口转发只暴露必要端口，IP 变化后要重新更新。"
                )
            }
            return HubRemoteAccessGuidancePresentation(
                state: .diagnosticRequired,
                message: "当前仍是临时 raw IP（\(scope.doctorLabel)），只适合诊断 / 救火，不应作为正式入口。"
            )
        case .stableNamed:
            return HubRemoteAccessGuidancePresentation(
                state: .ready,
                message: "XT 会把该域名当作正式入口；推荐把域名指到 relay/Spectrum/VPS TCP 或其它 raw TCP 入口，切网、自愈和后台重连都会先验证这条路径。"
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
                message: "邀请令牌用于同 Wi-Fi 首配或正式入口换机配对；连接成功后会自动清空。"
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
                message: "首次配对必须同 Wi-Fi/LAN；邀请链接只负责带入参数，Hub 仍会拒绝异网首配。"
            )
        }
    }
}
