import SwiftUI

struct HubInviteStatusPresentation: Equatable {
    let state: XTUISurfaceState
    let title: String
    let summary: String
    let facts: [String]
    let nextAction: String
}

enum HubInviteStatusPlanner {
    static func build(
        inviteAlias: String,
        internetHost: String,
        pairingPort: Int,
        grpcPort: Int,
        inviteToken: String,
        hubInstanceID: String,
        connected: Bool,
        linking: Bool,
        failureCode: String
    ) -> HubInviteStatusPresentation? {
        let alias = normalized(inviteAlias)
        let host = normalized(internetHost)
        let token = normalized(inviteToken)
        let instanceID = normalized(hubInstanceID)
        let tokenRequired = UITroubleshootKnowledgeBase.isInviteTokenRequiredFailure(failureCode)
        let tokenInvalid = UITroubleshootKnowledgeBase.isInviteTokenInvalidFailure(failureCode)
        let tokenFailure = tokenRequired || tokenInvalid
        let hasInviteMetadata = !alias.isEmpty || !token.isEmpty || !instanceID.isEmpty
        let hasHost = !host.isEmpty

        guard hasInviteMetadata || hasHost || tokenFailure else { return nil }

        let state: XTUISurfaceState
        let title: String
        let summary: String
        let nextAction: String

        if tokenRequired {
            state = .diagnosticRequired
            title = "这次外网配对缺少邀请令牌"
            summary = "Hub 当前把外网 pairing 请求收敛到 invite token 门禁；这次连接没有带上有效令牌，所以不会进入 Pair Hub ready。"
            nextAction = "重新打开 Hub 发出的邀请链接，让 XT 自动带入 host / 端口 / token 后再点“一键连接”；不要手填旧 token。"
        } else if tokenInvalid {
            state = .diagnosticRequired
            title = "邀请令牌已失效或不匹配"
            summary = "这次外网连接带来的 token 已经过期、被轮换，或不属于当前这台 Hub；继续重试只会重复 invite_token_invalid。"
            nextAction = "让 Hub 重新复制或轮换邀请令牌，再重新打开邀请链接并点“一键连接”；不要继续复用旧 token。"
        } else if connected {
            state = .ready
            title = hasInviteMetadata ? "正式首配参数已载入并已连通" : "正式入口已就绪并已连通"
            summary = hasInviteMetadata
                ? "当前 XT 正在按这份邀请与 Hub 通信；如果后续重配，优先重新打开邀请链接，不要改回手填裸地址。"
                : "当前正式入口已经生效；长期连接会优先验证稳定域名，不依赖旧 invite token。"
            nextAction = "继续使用当前 Hub；如需重配，优先从 Hub 重新打开邀请链接或扫码。"
        } else if linking {
            state = .inProgress
            title = hasInviteMetadata ? "正式首配参数已载入，正在连接" : "正式入口已填入，正在连接"
            summary = "当前会按这组 host / 端口参数继续 bootstrap / connect；无需再手动猜测外网地址。"
            nextAction = "等待本轮连接完成；若失败，再按下方修复动作处理。"
        } else if hasInviteMetadata {
            state = .inProgress
            title = "正式首配参数已载入"
            summary = "XT 已拿到这台 Hub 的稳定 host、端口和邀请令牌；外网正式接入优先走这条路径，而不是暴露或手填裸 IP。"
            nextAction = "直接点“一键连接”；通常不需要再手动探测 host / 端口。"
        } else {
            state = .blockedWaitingUpstream
            title = "当前使用手填连接参数"
            summary = "手填 host / 端口可以临时排障，但正式异网接入更建议使用 Hub 邀请链接，这样 XT 会自动拿到稳定 host 和邀请令牌。"
            nextAction = "如果这是长期使用的外网设备，建议回 Hub 复制邀请链接或扫二维码后再连接。"
        }

        var facts: [String] = []
        if !alias.isEmpty {
            facts.append("Hub alias：\(alias)")
        }
        if !host.isEmpty {
            facts.append("正式入口：\(host)")
        }
        facts.append("配对端口：\(pairingPort) · gRPC 端口：\(grpcPort)")
        facts.append("邀请令牌：\(token.isEmpty ? "未载入" : "首配令牌已载入")")
        if !instanceID.isEmpty {
            facts.append("Hub 实例：\(instanceID)")
        }

        return HubInviteStatusPresentation(
            state: state,
            title: title,
            summary: summary,
            facts: facts,
            nextAction: nextAction
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HubInviteStatusCard: View {
    let presentation: HubInviteStatusPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.state.iconName)
                    .foregroundStyle(presentation.state.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                    Text(presentation.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            Text(presentation.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(presentation.facts, id: \.self) { fact in
                Text("• \(fact)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("下一步：\(presentation.nextAction)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(presentation.state.tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(UIThemeTokens.stateBackground(for: presentation.state))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(presentation.state.tint.opacity(0.2), lineWidth: 1)
        )
    }
}
