import Foundation

enum AXProjectContextAssemblyPresentationSourceKind: String, Codable, Equatable, Sendable {
    case latestCoderUsage = "latest_coder_usage"
    case configOnly = "config_only"
    case unknown
}

struct AXProjectContextAssemblyPresentation: Codable, Equatable, Sendable {
    var sourceKind: AXProjectContextAssemblyPresentationSourceKind
    var projectLabel: String?
    var sourceBadge: String
    var statusLine: String
    var recentDialogueSource: String? = nil
    var recentDialogueSourceLabel: String? = nil
    var recentDialogueSourceClass: String? = nil
    var memorySource: String? = nil
    var memorySourceLabel: String? = nil
    var memorySourceClass: String? = nil
    var dialogueMetric: String
    var depthMetric: String
    var dialogueLine: String
    var depthLine: String
    var coverageMetric: String?
    var coverageLine: String?
    var boundaryMetric: String?
    var boundaryLine: String?
    var userSourceBadge: String
    var userStatusLine: String
    var userDialogueMetric: String
    var userDepthMetric: String
    var userCoverageSummary: String?
    var userBoundarySummary: String?
    var userDialogueLine: String
    var userDepthLine: String

    static func from(summary: AXProjectContextAssemblyDiagnosticsSummary) -> AXProjectContextAssemblyPresentation? {
        from(detailLines: summary.detailLines)
    }

    static func from(detailLines: [String]) -> AXProjectContextAssemblyPresentation? {
        let values = keyValueMap(detailLines)
        let sourceRaw = values["project_context_diagnostics_source"]?.lowercased() ?? ""
        let sourceKind = AXProjectContextAssemblyPresentationSourceKind(rawValue: sourceRaw) ?? .unknown

        let hasLatestUsage = !values["recent_project_dialogue_profile", default: ""].isEmpty
            || !values["project_context_depth", default: ""].isEmpty
        let hasConfigOnly = !values["configured_recent_project_dialogue_profile", default: ""].isEmpty
            || !values["configured_project_context_depth", default: ""].isEmpty
        guard sourceKind != .unknown || hasLatestUsage || hasConfigOnly else { return nil }

        let projectLabel = trimmed(values["project_context_project"])
        switch sourceKind {
        case .latestCoderUsage:
            return latestUsagePresentation(values: values, projectLabel: projectLabel)
        case .configOnly:
            return configOnlyPresentation(values: values, projectLabel: projectLabel)
        case .unknown:
            if hasLatestUsage {
                return latestUsagePresentation(values: values, projectLabel: projectLabel)
            }
            if hasConfigOnly {
                return configOnlyPresentation(values: values, projectLabel: projectLabel)
            }
            return nil
        }
    }

    private static func latestUsagePresentation(
        values: [String: String],
        projectLabel: String?
    ) -> AXProjectContextAssemblyPresentation {
        let recentProfile = AXProjectRecentDialogueProfile(rawValue: values["recent_project_dialogue_profile"] ?? "")
        let selectedPairs = int(values["recent_project_dialogue_selected_pairs"])
        let floorPairs = max(AXProjectRecentDialogueProfile.hardFloorPairs, int(values["recent_project_dialogue_floor_pairs"]))
        let floorSatisfied = bool(values["recent_project_dialogue_floor_satisfied"])
        let lowSignalDropped = int(values["recent_project_dialogue_low_signal_dropped"])
        let recentSource = trimmed(values["recent_project_dialogue_source"]) ?? "unknown"
        let recentSourceLabel = XTMemorySourceTruthPresentation.label(recentSource)
        let depthProfile = AXProjectContextDepthProfile(rawValue: values["project_context_depth"] ?? "")
        let servingProfile = XTMemoryServingProfile.parse(values["effective_project_serving_profile"])
        let workflowPresent = bool(values["workflow_present"])
        let evidencePresent = bool(values["execution_evidence_present"])
        let guidancePresent = bool(values["review_guidance_present"])
        let crossLinks = int(values["cross_link_hints_selected"])
        let memorySource = trimmed(values["project_memory_v1_source"]) ?? "unknown"
        let memorySourceLabel = XTMemorySourceTruthPresentation.label(memorySource)
        let boundaryReason = trimmed(values["personal_memory_excluded_reason"])

        let dialogueMetric = [
            recentProfile.map { "\($0.displayName) · \($0.shortLabel)" } ?? fallbackDialogueProfile(values["recent_project_dialogue_profile"]),
            selectedPairs > 0 ? "selected \(selectedPairs)p" : "selected 0p"
        ]
        .joined(separator: " · ")

        let depthMetric = [
            depthProfile?.displayName ?? fallbackDepthProfile(values["project_context_depth"]),
            servingProfile?.rawValue ?? trimmed(values["effective_project_serving_profile"]) ?? "unknown",
            memorySourceLabel
        ]
        .joined(separator: " · ")

        let dialogueLine = [
            "Recent Project Dialogue：\(recentProfile.map { "\($0.displayName) · \($0.shortLabel)" } ?? fallbackDialogueProfile(values["recent_project_dialogue_profile"]))",
            "本轮选中 \(selectedPairs) pairs",
            "floor \(floorPairs) \(floorSatisfied ? "已满足" : "未满足")",
            "source \(recentSourceLabel)",
            "low-signal drop \(lowSignalDropped)"
        ]
        .joined(separator: " · ")

        let depthLine = [
            "Project Context Depth：\(depthProfile?.displayName ?? fallbackDepthProfile(values["project_context_depth"]))",
            "serving \(servingProfile?.rawValue ?? trimmed(values["effective_project_serving_profile"]) ?? "unknown")",
            "memory \(memorySourceLabel)"
        ]
        .joined(separator: " · ")

        let coverageMetric = "wf \(yesNo(workflowPresent)) · ev \(yesNo(evidencePresent)) · gd \(yesNo(guidancePresent)) · xlink \(crossLinks)"
        let coverageLine = "Coverage：workflow \(yesNoWord(workflowPresent)) · evidence \(yesNoWord(evidencePresent)) · guidance \(yesNoWord(guidancePresent)) · cross-link hints \(crossLinks)"
        let boundaryMetric = boundaryReason == nil ? nil : "personal excluded"
        let boundaryLine = boundaryReason.map {
            "Boundary：personal memory excluded · \($0)"
        }
        let userCoverageSummary = userCoverageSummary(
            workflowPresent: workflowPresent,
            evidencePresent: evidencePresent,
            guidancePresent: guidancePresent,
            crossLinks: crossLinks
        )

        return AXProjectContextAssemblyPresentation(
            sourceKind: .latestCoderUsage,
            projectLabel: projectLabel,
            sourceBadge: "Latest Usage",
            statusLine: "最近一次 coder context assembly 已被捕获，Doctor 现在显示的是 runtime 实际喂给 project AI 的背景，而不只是静态配置。",
            recentDialogueSource: recentSource,
            recentDialogueSourceLabel: recentSourceLabel,
            recentDialogueSourceClass: XTMemorySourceTruthPresentation.sourceClass(recentSource),
            memorySource: memorySource,
            memorySourceLabel: memorySourceLabel,
            memorySourceClass: XTMemorySourceTruthPresentation.sourceClass(memorySource),
            dialogueMetric: dialogueMetric,
            depthMetric: depthMetric,
            dialogueLine: dialogueLine,
            depthLine: depthLine,
            coverageMetric: coverageMetric,
            coverageLine: coverageLine,
            boundaryMetric: boundaryMetric,
            boundaryLine: boundaryLine,
            userSourceBadge: "实际运行",
            userStatusLine: "这里显示的是最近一次真正喂给 project AI 的背景，不是静态配置。",
            userDialogueMetric: recentProfile.map { "\($0.displayName) · \($0.shortLabel)" }
                ?? fallbackDialogueProfile(values["recent_project_dialogue_profile"]),
            userDepthMetric: depthProfile?.displayName
                ?? fallbackDepthProfile(values["project_context_depth"]),
            userCoverageSummary: userCoverageSummary,
            userBoundarySummary: boundaryReason == nil ? nil : "默认不读取你的个人记忆",
            userDialogueLine: "这轮保留了 \(recentProfile.map { "\($0.shortLabel)" } ?? "recent project dialogue") 的最近项目对话窗口，本轮实际选中 \(selectedPairs) 组对话。",
            userDepthLine: userDepthLine(depthProfile: depthProfile)
        )
    }

    private static func configOnlyPresentation(
        values: [String: String],
        projectLabel: String?
    ) -> AXProjectContextAssemblyPresentation {
        let recentProfile = AXProjectRecentDialogueProfile(rawValue: values["configured_recent_project_dialogue_profile"] ?? "")
        let depthProfile = AXProjectContextDepthProfile(rawValue: values["configured_project_context_depth"] ?? "")
        let dialogueMetric = recentProfile.map { "\($0.displayName) · \($0.shortLabel)" }
            ?? fallbackDialogueProfile(values["configured_recent_project_dialogue_profile"])
        let depthMetric = depthProfile?.displayName
            ?? fallbackDepthProfile(values["configured_project_context_depth"])
        return AXProjectContextAssemblyPresentation(
            sourceKind: .configOnly,
            projectLabel: projectLabel,
            sourceBadge: "Config Only",
            statusLine: "当前还没有 recent coder usage explainability，所以这里只显示配置基线；等 project AI 真正跑过一轮后，这里会切到实际 runtime assembly。",
            dialogueMetric: dialogueMetric,
            depthMetric: depthMetric,
            dialogueLine: "Recent Project Dialogue：\(dialogueMetric)",
            depthLine: "Project Context Depth：\(depthMetric)",
            coverageMetric: nil,
            coverageLine: nil,
            boundaryMetric: nil,
            boundaryLine: nil,
            userSourceBadge: "配置基线",
            userStatusLine: "项目还没有实际运行记录，这里先显示当前配置会怎样喂给 project AI。",
            userDialogueMetric: dialogueMetric,
            userDepthMetric: depthMetric,
            userCoverageSummary: nil,
            userBoundarySummary: nil,
            userDialogueLine: "如果现在开始执行，会按这个最近项目对话窗口来组装当前项目对话。",
            userDepthLine: "如果现在开始执行，会按这个背景深度准备项目上下文。"
        )
    }

    private static func keyValueMap(_ detailLines: [String]) -> [String: String] {
        detailLines.reduce(into: [String: String]()) { partial, line in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmedLine.firstIndex(of: "=") else { return }
            let key = String(trimmedLine[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = trimmedLine.index(after: separator)
            let value = String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            partial[key] = value
        }
    }

    private static func trimmed(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func int(_ raw: String?) -> Int {
        guard let raw = trimmed(raw), let value = Int(raw) else { return 0 }
        return value
    }

    private static func bool(_ raw: String?) -> Bool {
        switch trimmed(raw)?.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func yesNoWord(_ value: Bool) -> String {
        value ? "present" : "absent"
    }

    private static func fallbackDialogueProfile(_ raw: String?) -> String {
        trimmed(raw) ?? "unknown"
    }

    private static func fallbackDepthProfile(_ raw: String?) -> String {
        trimmed(raw) ?? "unknown"
    }

    private static func userCoverageSummary(
        workflowPresent: Bool,
        evidencePresent: Bool,
        guidancePresent: Bool,
        crossLinks: Int
    ) -> String? {
        var parts: [String] = []
        if workflowPresent {
            parts.append("工作流")
        }
        if evidencePresent {
            parts.append("执行证据")
        }
        if guidancePresent {
            parts.append("review 提醒")
        }
        if crossLinks > 0 {
            parts.append("关联线索")
        }
        guard !parts.isEmpty else { return nil }
        return "已带" + localizedList(parts)
    }

    private static func userDepthLine(depthProfile: AXProjectContextDepthProfile?) -> String {
        let label = depthProfile?.displayName ?? "当前配置"
        return "\(label) 背景深度会决定这轮带入多少项目工作流、review 和执行证据。"
    }

    private static func localizedList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0])和\(items[1])"
        default:
            return items.dropLast().joined(separator: "、") + "和" + items.last!
        }
    }
}
