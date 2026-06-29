import Foundation

struct EffectiveToolPolicy {
    var profile: ToolProfile
    var allowTokens: [String]
    var denyTokens: [String]
    var allowed: Set<ToolName>
}

extension ChatSessionModel {
    func effectiveToolPolicy(config: AXProjectConfig?) -> EffectiveToolPolicy {
        let profileRaw = config?.toolProfile ?? ToolPolicy.defaultProfile.rawValue
        let allow = ToolPolicy.normalizePolicyTokens(config?.toolAllow ?? [])
        let deny = ToolPolicy.normalizePolicyTokens(config?.toolDeny ?? [])
        let profile = ToolPolicy.parseProfile(profileRaw)
        let allowed = ToolPolicy.effectiveAllowedTools(profileRaw: profile.rawValue, allowTokens: allow, denyTokens: deny)
        return EffectiveToolPolicy(profile: profile, allowTokens: allow, denyTokens: deny, allowed: allowed)
    }

    func toolProfileDisplayText(_ profile: ToolProfile) -> String {
        switch profile {
        case .minimal:
            return "最小（minimal）"
        case .coding:
            return "开发（coding）"
        case .full:
            return "全量（full）"
        }
    }

    func toolPolicyTokenDisplayText(_ token: String) -> String {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return token }

        switch normalized {
        case "*", "all":
            return "全部工具（\(normalized)）"
        case "group:readonly":
            return "只读工具（group:readonly）"
        case "group:fs":
            return "文件与搜索（group:fs）"
        case "group:runtime":
            return "运行与会话（group:runtime）"
        case "group:git":
            return "Git（group:git）"
        case "group:delivery":
            return "交付发布（group:delivery）"
        case "group:network":
            return "联网（group:network）"
        case "group:device_automation":
            return "设备自动化（group:device_automation）"
        case "group:minimal":
            return "最小档（group:minimal）"
        case "group:coding":
            return "开发档（group:coding）"
        case "group:full":
            return "全量档（group:full）"
        default:
            if let tool = ToolName(rawValue: normalized) {
                return "\(XTPendingApprovalPresentation.displayToolName(for: tool))（\(normalized)）"
            }
            return token
        }
    }

    func toolPolicyTokensDisplayText(_ tokens: [String]) -> String {
        let values = tokens.map(toolPolicyTokenDisplayText).filter { !$0.isEmpty }
        return values.isEmpty ? "无" : values.joined(separator: "、")
    }

    func toolPolicyAllowedToolsDisplayText(_ tools: [ToolName]) -> String {
        let values = tools.map(XTPendingApprovalPresentation.displayToolName(for:)).filter { !$0.isEmpty }
        return values.isEmpty ? "无" : values.joined(separator: "、")
    }

    func slashToolsUsageText() -> String {
        """
命令：
- /tools
- /tools profile <minimal|coding|full>
- /tools allow <token...>        token 支持工具名或 group:*
- /tools deny <token...>
- /tools reset
"""
    }

    func handleSlashTools(args: [String], ctx: AXProjectContext, config: AXProjectConfig?) -> String {
        guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
            return projectConfigUpdateUnavailableText()
        }

        guard let headRaw = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !headRaw.isEmpty else {
            return slashToolsText(config: cfg)
        }

        switch headRaw {
        case "show", "status", "list":
            return slashToolsText(config: cfg)
        case "reset":
            cfg = cfg.settingToolPolicy(profile: ToolPolicy.defaultProfile.rawValue, allow: [], deny: [])
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已将当前项目的工具策略恢复为默认档位（\(toolProfileDisplayText(ToolPolicy.defaultProfile))）。\n\n" + slashToolsText(config: cfg)
        case "profile":
            guard args.count >= 2 else {
                return "用法：/tools profile <\(ToolPolicy.profileOptionsText())>"
            }
            let raw = args[1]
            let profile = ToolPolicy.parseProfile(raw)
            if profile.rawValue != raw.lowercased() {
                return "未知工具档位：\(raw)\n可选：\(ToolPolicy.profileOptionsText())"
            }
            cfg = cfg.settingToolPolicy(profile: profile.rawValue)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已将当前项目的工具档位切到“\(toolProfileDisplayText(profile))”。\n\n" + slashToolsText(config: cfg)
        case "allow":
            let tokens = normalizedToolPolicyTokens(from: Array(args.dropFirst()))
            cfg = cfg.settingToolPolicy(allow: tokens)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已更新当前项目的额外放行规则。\n\n" + slashToolsText(config: cfg)
        case "deny":
            let tokens = normalizedToolPolicyTokens(from: Array(args.dropFirst()))
            cfg = cfg.settingToolPolicy(deny: tokens)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已更新当前项目的额外禁用规则。\n\n" + slashToolsText(config: cfg)
        default:
            return slashToolsUsageText()
        }
    }

    func normalizedToolPolicyTokens(from args: [String]) -> [String] {
        let raw = args.joined(separator: " ")
        let parsed = ToolPolicy.parsePolicyTokens(raw)
        return ToolPolicy.normalizePolicyTokens(parsed)
    }

    func slashToolsText(config: AXProjectConfig?) -> String {
        let policy = effectiveToolPolicy(config: config)
        let allowedTools = ToolPolicy.sortedTools(policy.allowed)
        let allowedText = toolPolicyAllowedToolsDisplayText(allowedTools)
        let allowText = toolPolicyTokensDisplayText(policy.allowTokens)
        let denyText = toolPolicyTokensDisplayText(policy.denyTokens)

        return """
工具策略：
- 当前档位：\(toolProfileDisplayText(policy.profile))
- 额外放行：\(allowText)
- 额外禁用：\(denyText)
- 当前可直接调用：\(allowedText)

常用 token：
- 文件与搜索：group:fs
- 运行与会话：group:runtime
- Git：group:git
- 联网：group:network
- 最小 / 开发 / 全量：group:minimal / group:coding / group:full
- 设备自动化：group:device_automation
- 全部工具：all 或 *

\(slashToolsUsageText())
"""
    }
}
