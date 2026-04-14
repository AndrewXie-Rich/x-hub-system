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
                message: "未设置正式入口。首次可同网发现；要异网无感切换，请填写稳定域名。"
            )
        case .lanOnly:
            return HubRemoteAccessGuidancePresentation(
                state: .diagnosticRequired,
                message: "当前还是同网入口，只适合同 Wi-Fi / 同 VPN，不适合作为长期异网入口。"
            )
        case .rawIP(let scope):
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
        switch classification.kind {
        case .stableNamed:
            return HubRemoteAccessGuidancePresentation(
                state: .ready,
                message: "长期连接靠已下发凭据，不靠 invite token。"
            )
        case .missing, .lanOnly, .rawIP:
            return HubRemoteAccessGuidancePresentation(
                state: .blockedWaitingUpstream,
                message: "如果要异网正式首配，优先从 Hub 邀请链接自动带入 invite token，不要手填旧 token。"
            )
        }
    }
}
