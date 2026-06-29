import Foundation

extension SupervisorManager {
    func looksLikeAutomationRuntimeCommand(_ text: String) -> Bool {
        let head = text
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased() ?? ""
        return head == "/automation" || head == "automation"
    }

    func parseAutomationRuntimeCommand(_ text: String) -> ParsedAutomationRuntimeCommand? {
        let tokens = text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let head = tokens.first?.lowercased(),
              head == "/automation" || head == "automation" else {
            return nil
        }
        guard tokens.count >= 2 else {
            return ParsedAutomationRuntimeCommand(action: .help, projectRef: nil)
        }

        let actionToken = normalizedAutomationCommandToken(tokens[1])
        switch actionToken {
        case "help":
            return ParsedAutomationRuntimeCommand(action: .help, projectRef: nil)
        case "status":
            return ParsedAutomationRuntimeCommand(
                action: .status,
                projectRef: automationProjectRef(from: tokens, startingAt: 2)
            )
        case "start":
            return ParsedAutomationRuntimeCommand(
                action: .start,
                projectRef: automationProjectRef(from: tokens, startingAt: 2)
            )
        case "recover":
            return ParsedAutomationRuntimeCommand(
                action: .recover,
                projectRef: automationProjectRef(from: tokens, startingAt: 2)
            )
        case "cancel":
            return ParsedAutomationRuntimeCommand(
                action: .cancel,
                projectRef: automationProjectRef(from: tokens, startingAt: 2)
            )
        case "advance":
            guard tokens.count >= 3,
                  let nextState = automationRunState(from: tokens[2]) else {
                return nil
            }
            return ParsedAutomationRuntimeCommand(
                action: .advance(nextState),
                projectRef: automationProjectRef(from: tokens, startingAt: 3)
            )
        case "self_iterate":
            let modeToken = normalizedAutomationSelfIterateCommandToken(tokens.count > 2 ? tokens[2] : "")
            switch modeToken {
            case "", "status":
                return ParsedAutomationRuntimeCommand(
                    action: .selfIterateStatus,
                    projectRef: automationProjectRef(from: tokens, startingAt: modeToken.isEmpty ? 2 : 3)
                )
            case "on":
                return ParsedAutomationRuntimeCommand(
                    action: .selfIterateSet(true),
                    projectRef: automationProjectRef(from: tokens, startingAt: 3)
                )
            case "off":
                return ParsedAutomationRuntimeCommand(
                    action: .selfIterateSet(false),
                    projectRef: automationProjectRef(from: tokens, startingAt: 3)
                )
            case "max":
                guard tokens.count >= 4,
                      let depth = Int(tokens[3].trimmingCharacters(in: .whitespacesAndNewlines)),
                      depth >= 1 else {
                    return nil
                }
                return ParsedAutomationRuntimeCommand(
                    action: .selfIterateMax(depth),
                    projectRef: automationProjectRef(from: tokens, startingAt: 4)
                )
            default:
                return nil
            }
        default:
            return nil
        }
    }

    func normalizedAutomationCommandToken(_ token: String) -> String {
        let lowered = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "help", "帮助":
            return "help"
        case "status", "状态":
            return "status"
        case "start", "启动", "开始":
            return "start"
        case "recover", "恢复":
            return "recover"
        case "cancel", "取消", "停止":
            return "cancel"
        case "advance", "推进", "更新":
            return "advance"
        case "self-iterate", "self_iterate", "selfiterate", "自迭代":
            return "self_iterate"
        default:
            return lowered
        }
    }

    func normalizedAutomationSelfIterateCommandToken(_ token: String) -> String {
        let lowered = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "", "status", "状态":
            return lowered.isEmpty ? "" : "status"
        case "on", "enable", "enabled", "开启", "打开", "启用":
            return "on"
        case "off", "disable", "disabled", "关闭", "关掉", "停用":
            return "off"
        case "max", "depth", "最大", "深度":
            return "max"
        default:
            return lowered
        }
    }

    func automationProjectRef(from tokens: [String], startingAt index: Int) -> String? {
        guard index < tokens.count else { return nil }
        let raw = tokens[index...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let sanitized = sanitizeProjectReference(raw)
        return sanitized.isEmpty ? nil : sanitized
    }

    func automationRunState(from raw: String) -> XTAutomationRunState? {
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch token {
        case "queued", "queue", "排队", "排队中":
            return .queued
        case "running", "run", "运行", "运行中":
            return .running
        case "blocked", "block", "阻塞", "卡住":
            return .blocked
        case "takeover", "接管":
            return .takeover
        case "delivered", "deliver", "交付", "已交付":
            return .delivered
        case "failed", "fail", "失败":
            return .failed
        case "downgraded", "downgrade", "degraded", "降级":
            return .downgraded
        default:
            return nil
        }
    }

    func automationRuntimeCommandHelpText() -> String {
        """
🤖 自动化执行命令
- /automation status [projectRef]
- /automation start [projectRef]
- /automation recover [projectRef]
- /automation cancel [projectRef]
- /automation advance <queued|running|blocked|takeover|delivered|failed|downgraded> [projectRef]
- /automation self-iterate status [projectRef]
- /automation self-iterate on [projectRef]
- /automation self-iterate off [projectRef]
- /automation self-iterate max <depth> [projectRef]

如果不传 projectRef，默认使用当前选中的项目；若当前未选中且存在多个项目，请显式指定项目名或 project_id。
"""
    }
}
