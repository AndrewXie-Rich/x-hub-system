import Foundation

extension ChatSessionModel {
    func memoryModeDisplayText(prefersHubMemory: Bool) -> String {
        prefersHubMemory ? "优先使用 Hub Memory" : "仅使用本地 Memory"
    }

    func handleSlashMemory(args: [String], ctx: AXProjectContext, config: AXProjectConfig?) -> String {
        guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
            return projectConfigUpdateUnavailableText()
        }

        let lowered = args.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let first = lowered.first ?? "status"
        let command: String
        if first == "hub" {
            command = lowered.dropFirst().first ?? "status"
        } else {
            command = first
        }

        switch command {
        case "status", "show", "list":
            return slashMemoryText(config: cfg)
        case "on", "enable", "preferred", "prefer":
            cfg = cfg.settingHubMemoryPreference(enabled: true)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已将当前项目的 Memory 切到“优先使用 Hub Memory”。\n\n" + slashMemoryText(config: cfg)
        case "off", "disable", "local", "local-only", "local_only":
            cfg = cfg.settingHubMemoryPreference(enabled: false)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已将当前项目的 Memory 切到“只使用本地 Memory”。\n\n" + slashMemoryText(config: cfg)
        case "default", "reset":
            cfg = cfg.settingHubMemoryPreference(enabled: true)
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已将当前项目的 Memory 恢复为默认设置（优先使用 Hub Memory）。\n\n" + slashMemoryText(config: cfg)
        default:
            return slashMemoryUsageText()
        }
    }

    func slashMemoryText(config: AXProjectConfig?) -> String {
        let preferHubMemory = XTProjectMemoryGovernance.prefersHubMemory(config)
        let localBehavior = preferHubMemory
            ? "先使用 Hub Memory；如果 Hub 当前不可用，会自动回退到本地 `.xterminal/AX_MEMORY.md` 和 `recent_context.json`。"
            : "只使用本地 `.xterminal/AX_MEMORY.md` 和 `recent_context.json`，这次不会读取 Hub Memory。"

        return """
Memory 使用方式：
- 当前设置：\(memoryModeDisplayText(prefersHubMemory: preferHubMemory))
- 默认设置：\(memoryModeDisplayText(prefersHubMemory: true))
- 使用 Hub Memory：\(yesNoText(preferHubMemory))
- 本地文件：`.xterminal/AX_MEMORY.md`、`.xterminal/recent_context.json`
- 当前行为：\(localBehavior)
- 生效约束：受 Hub X-宪章、远端导出闸门、技能信任/撤销、高风险授权与 kill switch 共同约束

\(slashMemoryUsageText())
"""
    }

    func slashMemoryUsageText() -> String {
        """
命令：
- /memory                  查看当前项目的 Memory 使用方式
- /memory on               优先使用 Hub Memory
- /memory off              只使用本地 Memory
- /memory default          恢复默认使用方式（优先使用 Hub Memory）
"""
    }
}
