import Foundation

extension SupervisorAuditDrillDownPresentation {
    static func xtBuiltinGovernedSkills(
        items: [AXBuiltinGovernedSkillSummary],
        managedStatusLine: String
    ) -> SupervisorAuditDrillDownPresentation {
        let normalizedManagedStatus = normalizedScalarForBuiltinSkills(managedStatusLine)
        let preferredIDs = ["guarded-automation", "supervisor-voice"]
        let preferredItems = preferredIDs.compactMap { skillID in
            items.first(where: {
                normalizedScalarForBuiltinSkills($0.skillID).caseInsensitiveCompare(skillID) == .orderedSame
            })
        }
        let highlightItems = preferredItems.isEmpty ? Array(items.prefix(5)) : preferredItems
        let actionURL = XTDeepLinkURLBuilder.settingsURL(
            sectionId: "diagnostics",
            title: "XT 内建受治理技能",
            detail: "在诊断页查看 XT 内建受治理技能与 managed skills 的兼容状态。"
        )?.absoluteString

        return SupervisorAuditDrillDownPresentation(
            id: "xt-builtin-governed-skills",
            iconName: "bolt.shield",
            title: "XT 内建受治理技能",
            statusLabel: "内建",
            tone: .success,
            summary: "已登记 \(items.count) 个 XT 本地受治理技能，可直接供 Supervisor 使用，不依赖 Hub 包生命周期。",
            detail: firstMeaningfulBuiltinSkillsScalar([
                normalizedManagedStatus.isEmpty ? "" : "托管技能：\(normalizedManagedStatus)",
                "仅限 XT 本地能力；不能通过 Hub 安装或移除。"
            ]),
            sections: [
                builtinSkillsSection(
                    title: "可用性",
                    fields: [
                        builtinSkillsField("内建数量", "\(items.count)"),
                        builtinSkillsField("托管技能", normalizedManagedStatus),
                        builtinSkillsField("生命周期", "XT 本地能力；不能通过 Hub 安装或移除"),
                        builtinSkillsField("发现方式", "Supervisor 可直接从 XT 内建注册表发现这些技能")
                    ]
                ),
                builtinSkillsSection(
                    title: "重点技能",
                    fields: highlightItems.map { item in
                        let capabilityLine = item.capabilitiesRequired
                            .map { normalizedScalarForBuiltinSkills($0) }
                            .filter { !$0.isEmpty }
                            .joined(separator: ",")
                        let value = [
                            normalizedScalarForBuiltinSkills(item.skillID),
                            "风险=\(normalizedScalarForBuiltinSkills(item.riskLevel).lowercased())",
                            capabilityLine.isEmpty ? "" : "能力=\(capabilityLine)"
                        ]
                        .filter { !$0.isEmpty }
                        .joined(separator: " | ")
                        return builtinSkillsField(
                            normalizedScalarForBuiltinSkills(item.displayName),
                            value
                        )
                    }
                ),
                builtinSkillsSection(
                    title: "运行说明",
                    fields: [
                        builtinSkillsField("Guarded Automation", "先检查可信自动化是否就绪，再让显式浏览器自动化通过 XT 治理门控。"),
                        builtinSkillsField("Supervisor Voice", "可检查、预览、播报或停止本地 Supervisor 播放链路。")
                    ]
                )
            ].compactMap { $0 },
            requestId: nil,
            actionLabel: normalizedOptionalBuiltinSkillsScalar(actionURL) == nil ? nil : "打开诊断",
            actionURL: normalizedOptionalBuiltinSkillsScalar(actionURL),
            includesEmbeddedSkillRecord: false
        )
    }

    private static func builtinSkillsSection(
        title: String,
        fields: [Field?]
    ) -> Section? {
        let compactFields = fields.compactMap { $0 }
        guard !compactFields.isEmpty else { return nil }
        return Section(title: title, fields: compactFields)
    }

    private static func builtinSkillsField(
        _ label: String,
        _ value: String
    ) -> Field? {
        let normalizedLabel = normalizedScalarForBuiltinSkills(label)
        let normalizedValue = normalizedScalarForBuiltinSkills(value)
        guard !normalizedLabel.isEmpty, !normalizedValue.isEmpty else { return nil }
        return Field(label: normalizedLabel, value: normalizedValue)
    }

    private static func firstMeaningfulBuiltinSkillsScalar(
        _ values: [String]
    ) -> String {
        values.first(where: { !normalizedScalarForBuiltinSkills($0).isEmpty }) ?? ""
    }

    private static func normalizedScalarForBuiltinSkills(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedOptionalBuiltinSkillsScalar(_ raw: String?) -> String? {
        let trimmed = normalizedScalarForBuiltinSkills(raw)
        return trimmed.isEmpty ? nil : trimmed
    }
}
