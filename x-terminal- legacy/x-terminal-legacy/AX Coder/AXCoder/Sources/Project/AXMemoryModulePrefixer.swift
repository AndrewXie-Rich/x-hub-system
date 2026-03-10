import Foundation

// Deterministic post-processing for monorepo/multi-module projects.
// Purpose: retrofit historical AX_MEMORY list items with module prefixes so the memory stays scannable.
enum AXMemoryModulePrefixer {
    enum Module: String {
        case hub = "Hub"
        case coder = "Coder"
        case system = "System"
        case shared = "Shared"

        var prefix: String { "\(rawValue): " }
    }

    private static let knownModules: [Module] = [.hub, .coder, .system, .shared]

    static func normalizeIfNeeded(_ mem: AXMemory, projectRoot: URL) -> AXMemory {
        guard shouldApply(mem: mem, projectRoot: projectRoot) else { return mem }

        var out = mem
        out.requirements = normalizeList(mem.requirements)
        out.currentState = normalizeList(mem.currentState)
        out.decisions = normalizeList(mem.decisions)
        out.nextSteps = normalizeList(mem.nextSteps)
        out.openQuestions = normalizeList(mem.openQuestions)
        out.risks = normalizeList(mem.risks)
        out.recommendations = normalizeList(mem.recommendations)
        return out
    }

    // MARK: - Gating

    private static func shouldApply(mem: AXMemory, projectRoot: URL) -> Bool {
        // If any item already has a known prefix, we treat this as a multi-module memory and normalize the rest.
        if containsAnyKnownPrefix(mem) { return true }

        // Heuristic for this monorepo: presence of multiple top-level module dirs.
        // Keep conservative to avoid polluting normal single-module projects.
        let markers: [String] = [
            "RELFlowHub",
            "AX Coder",
            "X-Terminal",
            "XTerminal",
            "protocol",
        ]
        var hits = 0
        for m in markers {
            if FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent(m).path) {
                hits += 1
            }
        }
        return hits >= 2
    }

    private static func containsAnyKnownPrefix(_ mem: AXMemory) -> Bool {
        let lists = [
            mem.requirements,
            mem.currentState,
            mem.decisions,
            mem.nextSteps,
            mem.openQuestions,
            mem.risks,
            mem.recommendations,
        ]
        for list in lists {
            for item in list {
                if modulePrefix(in: item) != nil {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Normalization

    private static func normalizeList(_ items: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let normalized = normalizeItem(trimmed)
            let key = normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty || seen.contains(key) { continue }
            seen.insert(key)
            out.append(normalized)
        }
        return out
    }

    private static func normalizeItem(_ s: String) -> String {
        if let _ = modulePrefix(in: s) {
            return s
        }
        let m = classifyModule(s)
        return m.prefix + s
    }

    private static func modulePrefix(in s: String) -> Module? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        // Accept both ASCII ':' and Chinese '：'.
        for m in knownModules {
            if t.hasPrefix("\(m.rawValue):") || t.hasPrefix("\(m.rawValue)：") {
                return m
            }
        }
        return nil
    }

    // MARK: - Classification (heuristic)

    private static func classifyModule(_ s: String) -> Module {
        let lower = s.lowercased()

        var hub = 0
        var coder = 0
        var shared = 0
        var system = 0

        // Path / directory hints.
        if lower.contains("relflowhub") || lower.contains("flow hub") { hub += 4 }
        if lower.contains("relflowhubbridge") || lower.contains("bridge") { hub += 2 }
        if lower.contains("models_state") || lower.contains("modelsstate") { hub += 2 }
        if lower.contains("inbox") { hub += 1 }

        if lower.contains("ax coder") || lower.contains("axcoder") || lower.contains("x-terminal") || lower.contains("xterminal") { coder += 4 }
        if lower.contains("projectsidebar") || lower.contains("globalhome") { coder += 2 }
        if lower.contains("memorypipeline") || lower.contains("forgotten-vault") { coder += 2 }
        if lower.contains("chat") || lower.contains("terminal") || lower.contains("pty") { coder += 1 }

        if lower.contains("protocol/") || lower.contains("protocol") { shared += 4 }
        if lower.contains("sdk") || lower.contains("hublink") { shared += 2 }

        // System / cross-module keywords.
        let systemKeywords = [
            "唯一", "provider", "边界", "契约", "协议", "ipc", "调度", "并发", "ttl",
            "权限", "审批", "网络", "路由", "安全", "policy", "策略", "汇总", "butler", "resident",
        ]
        for k in systemKeywords where lower.contains(k) {
            system += 1
        }

        // Chinese/English product terms often indicate system-level constraints.
        if lower.contains("hub 是唯一") || lower.contains("hub为唯一") || lower.contains("hub 为唯一") { system += 3 }
        if lower.contains("不可直接联网") || lower.contains("只能向 hub") { system += 2 }

        // Choose the best; default to System to avoid accidental mis-bucketing.
        let scored: [(Module, Int)] = [(.hub, hub), (.coder, coder), (.shared, shared), (.system, system)]
        let best = scored.max { $0.1 < $1.1 }
        if let best, best.1 > 0 { return best.0 }
        return .system
    }
}
