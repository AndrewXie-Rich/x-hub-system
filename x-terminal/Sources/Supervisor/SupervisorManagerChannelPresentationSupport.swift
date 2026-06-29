import Foundation

extension SupervisorManager {
    func hubConnectorIngressDisplayName(
        _ receipt: HubIPCClient.ConnectorIngressReceipt,
        triggerType: XTAutomationTriggerType
    ) -> String {
        switch triggerType {
        case .webhook:
            return "webhook"
        default:
            switch normalizedLookupKey(receipt.channelScope) {
            case "dm":
                return "私聊消息入口"
            case "group":
                return "群聊消息入口"
            case "channel":
                return "频道消息入口"
            case "repo":
                return "仓库入口"
            default:
                return "消息入口"
            }
        }
    }

    func hubConnectorIngressVoiceAliasTerms(
        _ receipt: HubIPCClient.ConnectorIngressReceipt,
        triggerType: XTAutomationTriggerType
    ) -> [String] {
        switch triggerType {
        case .webhook:
            return ["webhook", "web hook", "回调"]
        default:
            switch normalizedLookupKey(receipt.channelScope) {
            case "dm":
                return ["私聊消息入口", "私聊", "私信", "dm", "direct message"]
            case "group":
                return ["群聊消息入口", "群聊", "群组", "group"]
            case "channel":
                return ["频道消息入口", "频道", "channel"]
            case "repo":
                return ["仓库入口", "仓库", "repo"]
            default:
                return []
            }
        }
    }

    func hubConnectorIngressReasonDisplayName(_ token: String) -> String {
        switch normalizedLookupKey(token) {
        case "hubingresssourceunsupported":
            return "该远程来源暂未接入 XT"
        case "hubingressrecipeunavailable":
            return "项目缺少可运行的自动化配方"
        case "hubingresstriggerunresolved":
            return "入口未映射到已声明 trigger"
        case "automationactiverunpresent":
            return "项目已有进行中的 automation"
        case "triggercooldownactive":
            return "该入口仍在冷却窗口内"
        case "externaltriggerreplaydetected":
            return "重复入口已被抑制"
        case "triggeridmissing":
            return "trigger 标识缺失"
        case "externaltriggerdedupekeymissing":
            return "dedupe key 缺失"
        case "triggeringressnotallowed":
            return "该入口未被允许"
        default:
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "未知原因" }
            return trimmed.replacingOccurrences(of: "_", with: " ")
        }
    }

    func remoteChannelProviderDisplayName(_ provider: String) -> String {
        switch normalizedLookupKey(provider) {
        case "slack":
            return "Slack"
        case "telegram":
            return "Telegram"
        case "feishu":
            return "Feishu"
        case "github":
            return "GitHub"
        case "discord":
            return "Discord"
        case "whatsappcloudapi":
            return "WhatsApp Cloud"
        case "whatsapppersonalqr", "whatsapppersonalrunner":
            return "WhatsApp Personal"
        default:
            let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Hub" : trimmed
        }
    }

    func remoteChannelProviderVoiceAliasTerms(_ provider: String) -> [String] {
        switch normalizedLookupKey(provider) {
        case "slack":
            return ["Slack", "slack"]
        case "telegram":
            return ["Telegram", "telegram", "tg", "电报"]
        case "feishu":
            return ["Feishu", "feishu", "Lark", "lark", "飞书"]
        case "github":
            return ["GitHub", "github"]
        case "discord":
            return ["Discord", "discord"]
        case "whatsappcloudapi":
            return ["WhatsApp Cloud", "whatsapp cloud", "whatsapp"]
        case "whatsapppersonalqr", "whatsapppersonalrunner":
            return ["WhatsApp Personal", "whatsapp personal", "whatsapp"]
        default:
            let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
    }

    func operatorChannelProviderDisplayName(_ provider: String) -> String {
        remoteChannelProviderDisplayName(provider)
    }

    func operatorChannelActionDisplayName(_ actionName: String) -> String {
        switch normalizedLookupKey(actionName) {
        case "deployplan":
            return "部署计划"
        default:
            let trimmed = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "XT 指令" : trimmed
        }
    }

    func operatorChannelProjectDisplayName(
        _ projectName: String?,
        projectID: String
    ) -> String {
        let name = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            return name
        }
        let projectToken = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        return projectToken.isEmpty ? "当前项目" : projectToken
    }

    func operatorChannelXTCommandReasonDisplayName(_ token: String) -> String {
        switch normalizedLookupKey(token) {
        case "trustedautomationprojectnotbound":
            return "项目未绑定到当前设备"
        case "projectcontextmissing":
            return "项目上下文缺失"
        case "xtcommandactionnotsupportedyet":
            return "该动作尚未支持"
        case "activerecipemissing":
            return "项目缺少可执行自动化配方"
        case "triggeringressnotallowed":
            return "该入口未被允许"
        default:
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "未知原因" }
            return trimmed.replacingOccurrences(of: "_", with: " ")
        }
    }
}
