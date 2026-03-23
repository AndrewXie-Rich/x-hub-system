import Foundation

struct SupervisorAuditDrillDownPresentation: Equatable, Identifiable {
    enum Tone: String, Equatable {
        case neutral
        case attention
        case critical
        case success
    }

    struct ActionLink: Identifiable, Equatable {
        var label: String
        var url: String

        var id: String { "\(label)|\(url)" }
    }

    struct Field: Identifiable, Equatable {
        var id: String { label }
        var label: String
        var value: String
    }

    struct Section: Identifiable, Equatable {
        var id: String { title }
        var title: String
        var fields: [Field]
    }

    var id: String
    var iconName: String
    var title: String
    var statusLabel: String
    var tone: Tone
    var summary: String
    var detail: String
    var sections: [Section]
    var requestId: String?
    var actionLabel: String?
    var actionURL: String?
    var secondaryActions: [ActionLink] = []
    var includesEmbeddedSkillRecord: Bool

    static func officialSkillsChannel(
        statusLine: String,
        transitionLine: String,
        detailLine: String,
        blockerSummaries: [AXOfficialSkillBlockerSummaryItem] = [],
        eventLoopStatusLine: String
    ) -> SupervisorAuditDrillDownPresentation {
        let normalizedStatus = normalizedScalar(statusLine)
        let normalizedTransition = normalizedScalar(transitionLine)
        let normalizedDetail = normalizedScalar(detailLine)
        let normalizedLoop = normalizedScalar(eventLoopStatusLine)
        let normalizedBlockers = XTOfficialSkillsBlockerActionSupport.rankedBlockers(blockerSummaries)
        let primaryBlocker = SupervisorOfficialSkillsChannelActionSupport.primaryBlocker(
            from: normalizedBlockers
        )
        let action = SupervisorOfficialSkillsChannelActionSupport.readinessAction(
            statusLine: normalizedStatus,
            transitionLine: normalizedTransition,
            detailLine: normalizedDetail,
            blockerSummaries: normalizedBlockers
        )

        return SupervisorAuditDrillDownPresentation(
            id: "official-skills-channel",
            iconName: officialTone(for: normalizedStatus) == .critical ? "shippingbox.fill" : "shippingbox",
            title: "官方技能通道",
            statusLabel: officialBadge(for: normalizedStatus),
            tone: officialTone(for: normalizedStatus),
            summary: normalizedStatus.isEmpty ? "当前还没有官方技能状态快照。" : normalizedStatus,
            detail: firstMeaningfulScalar([
                normalizedTransition,
                normalizedLoop
            ]),
            sections: [
                compactSection(
                    title: "通道快照",
                    fields: [
                        ("状态", normalizedStatus),
                        ("最近切换", normalizedTransition),
                        ("包就绪度", normalizedDetail),
                        ("事件循环", normalizedLoop)
                    ]
                ),
                compactSection(
                    title: "运行说明",
                    fields: [
                        ("模式", "由 Hub 托管的官方技能目录"),
                        ("安全边界", "服务端审核与审批链仍保持最终权威")
                    ]
                ),
                officialTopBlockersSection(normalizedBlockers)
            ].compactMap { $0 },
            requestId: nil,
            actionLabel: action?.label,
            actionURL: action?.url,
            secondaryActions: officialTopBlockerActions(
                normalizedBlockers,
                excluding: primaryBlocker?.id
            ),
            includesEmbeddedSkillRecord: false
        )
    }

    static func pendingHubGrant(
        _ grant: SupervisorManager.SupervisorPendingGrant
    ) -> SupervisorAuditDrillDownPresentation {
        let capabilityLabel = XTHubGrantPresentation.capabilityLabel(
            capability: grant.capability,
            modelId: grant.modelId
        )
        let summary = XTHubGrantPresentation.awaitingSummary(
            capability: grant.capability,
            modelId: grant.modelId
        )
        let reason = XTHubGrantPresentation.supplementaryReason(
            grant.reason,
            capability: grant.capability,
            modelId: grant.modelId
        ) ?? normalizedScalar(grant.reason)
        let scope = XTHubGrantPresentation.scopeSummary(
            requestedTtlSec: grant.requestedTtlSec,
            requestedTokenCap: grant.requestedTokenCap
        ) ?? ""

        return SupervisorAuditDrillDownPresentation(
            id: "pending-grant:\(grant.id)",
            iconName: "checkmark.shield.trianglebadge.exclamationmark",
            title: "Hub 授权待处理",
            statusLabel: "待处理",
            tone: .attention,
            summary: summary,
            detail: firstMeaningfulScalar([
                normalizedScalar(grant.nextAction),
                reason,
                scope
            ]),
            sections: [
                compactSection(
                    title: "请求",
                    fields: [
                        ("项目", normalizedScalar(grant.projectName)),
                        ("能力", capabilityLabel),
                        ("模型", normalizedScalar(grant.modelId)),
                        ("授权请求", normalizedScalar(grant.grantRequestId)),
                        ("请求", normalizedScalar(grant.requestId))
                    ]
                ),
                compactSection(
                    title: "范围",
                    fields: [
                        ("请求时长", durationLabel(seconds: grant.requestedTtlSec)),
                        ("Token 上限", tokenCapLabel(grant.requestedTokenCap)),
                        ("优先级", "P\(grant.priorityRank)"),
                        ("优先原因", normalizedScalar(grant.priorityReason))
                    ]
                ),
                compactSection(
                    title: "决策上下文",
                    fields: [
                        ("原因", reason),
                        ("下一步", normalizedScalar(grant.nextAction)),
                        ("去重键", normalizedScalar(grant.dedupeKey))
                    ]
                )
            ].compactMap { $0 },
            requestId: normalizedOptionalScalar(grant.requestId),
            actionLabel: normalizedOptionalScalar(grant.actionURL) == nil ? nil : "打开授权",
            actionURL: normalizedOptionalScalar(grant.actionURL),
            includesEmbeddedSkillRecord: false
        )
    }

    static func pendingSkillApproval(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> SupervisorAuditDrillDownPresentation {
        let message = XTPendingApprovalPresentation.approvalMessage(
            toolName: approval.toolName,
            tool: approval.tool,
            toolSummary: approval.toolSummary
        )
        let reason = XTPendingApprovalPresentation.supplementaryReason(
            approval.reason,
            primaryMessage: message
        ) ?? normalizedScalar(approval.reason)
        let routingSummary = SupervisorSkillActivityPresentation.routingSummary(
            requestedSkillId: approval.requestedSkillId,
            effectiveSkillId: approval.skillId,
            routingReasonCode: approval.routingReasonCode,
            routingExplanation: approval.routingExplanation
        ) ?? ""
        let routingNarrative = SupervisorSkillActivityPresentation.routingNarrative(
            requestedSkillId: approval.requestedSkillId,
            effectiveSkillId: approval.skillId,
            routingReasonCode: approval.routingReasonCode,
            routingExplanation: approval.routingExplanation
        ) ?? ""
        let skillFields = skillIdentityFields(
            requestedSkillId: approval.requestedSkillIdText,
            effectiveSkillId: approval.skillId
        )

        return SupervisorAuditDrillDownPresentation(
            id: "pending-approval:\(approval.id)",
            iconName: iconName(for: approval.tool),
            title: "本地技能审批待处理",
            statusLabel: "待处理",
            tone: .attention,
            summary: normalizedScalar(message.summary),
            detail: firstMeaningfulScalar([
                normalizedScalar(message.nextStep ?? ""),
                reason
            ]),
            sections: [
                compactSection(
                    title: "请求",
                    fields: [
                        ("项目", normalizedScalar(approval.projectName)),
                    ] + skillFields + [
                        ("请求", normalizedScalar(approval.requestId)),
                        ("任务", normalizedScalar(approval.jobId)),
                        ("计划", normalizedScalar(approval.planId)),
                        ("步骤", normalizedScalar(approval.stepId))
                    ]
                ),
                compactSection(
                    title: "工具意图",
                    fields: [
                        ("工具", displayToolName(approval.toolName, tool: approval.tool)),
                        ("路由", routingSummary),
                        ("路由说明", routingNarrative),
                        ("路由判定", normalizedScalar(
                            SupervisorSkillActivityPresentation.routingReasonText(
                                approval.routingReasonCode
                            ) ?? ""
                        )),
                        ("路由代码", normalizedScalar(approval.routingReasonCode ?? "")),
                        ("路由原文", normalizedScalar(approval.routingExplanation ?? "")),
                        ("摘要", normalizedScalar(approval.toolSummary)),
                        ("原因", reason)
                    ]
                )
            ].compactMap { $0 },
            requestId: normalizedOptionalScalar(approval.requestId),
            actionLabel: normalizedOptionalScalar(approval.actionURL) == nil ? nil : "打开审批",
            actionURL: normalizedOptionalScalar(approval.actionURL),
            includesEmbeddedSkillRecord: false
        )
    }

    static func recentSkillActivity(
        _ item: SupervisorManager.SupervisorRecentSkillActivity,
        fullRecord: SupervisorSkillFullRecord?
    ) -> SupervisorAuditDrillDownPresentation {
        let defaultAction = actionLink(
            label: SupervisorSkillActivityPresentation.actionButtonTitle(for: item),
            url: item.actionURL
        )
        let preferredAction = preferredUIReviewAction(
            projectId: item.projectId,
            fallbackAction: defaultAction,
            fullRecord: fullRecord
        )
        let secondaryActions = dedupedActionLinks(
            preferredAction?.url,
            candidates: [defaultAction]
        )

        var governanceFields: [(String, String)] = []
        if let governance = item.governance {
            governanceFields.append(("跟进节奏", normalizedScalar(governance.followUpRhythmSummary)))
            if let verdict = governance.latestReviewVerdict?.displayName {
                governanceFields.append(("最近审查", verdict))
            }
            if let level = governance.latestReviewLevel?.displayName {
                governanceFields.append(("审查级别", level))
            }
            if let tier = governance.effectiveSupervisorTier?.displayName {
                governanceFields.append(("Supervisor 档位", tier))
            }
            if let depth = governance.effectiveWorkOrderDepth?.displayName {
                governanceFields.append(("工单深度", depth))
            }
            governanceFields.append(("工单", normalizedScalar(governance.workOrderRef)))
            if let ackStatus = governance.pendingGuidanceAckStatus?.displayName {
                governanceFields.append(("指导确认", ackStatus))
            }
            governanceFields.append(("指导引用", firstMeaningfulScalar([
                normalizedScalar(governance.pendingGuidanceId),
                normalizedScalar(governance.latestGuidanceId)
            ])))
        }
        governanceFields.append(contentsOf: guidanceContractFields(fullRecord?.guidanceContract))
        let skillFields = skillIdentityFields(
            requestedSkillId: item.requestedSkillId,
            effectiveSkillId: item.skillId
        )
        let blockedSummary = firstMeaningfulScalar([
            fullRecordFieldValue("blocked_summary", in: fullRecord?.approvalFields ?? []),
            XTGuardrailMessagePresentation.blockedSummary(
                tool: item.tool,
                toolLabel: displayToolName(item.toolName, tool: item.tool),
                denyCode: item.denyCode,
                policySource: item.policySource,
                policyReason: item.policyReason,
                fallbackSummary: item.resultSummary,
                fallbackDetail: ""
            ) ?? ""
        ])
        let governanceTruth = firstMeaningfulScalar([
            fullRecordFieldValue("governance_truth", in: fullRecord?.governanceFields ?? []),
            fullRecordFieldValue("governance_truth", in: fullRecord?.approvalFields ?? [])
        ])
        let routingNarrative = SupervisorSkillActivityPresentation.routingNarrative(
            requestedSkillId: item.requestedSkillId,
            effectiveSkillId: item.skillId,
            payload: item.record.payload,
            routingReasonCode: item.record.routingReasonCode,
            routingExplanation: item.record.routingExplanation
        ) ?? ""

        return SupervisorAuditDrillDownPresentation(
            id: item.id,
            iconName: SupervisorSkillActivityPresentation.iconName(for: item),
            title: SupervisorSkillActivityPresentation.title(for: item),
            statusLabel: SupervisorSkillActivityPresentation.statusLabel(for: item),
            tone: tone(forSkillStatus: item.status, requiredCapability: item.requiredCapability),
            summary: SupervisorSkillActivityPresentation.body(for: item),
            detail: firstMeaningfulScalar([
                normalizedScalar(item.toolSummary),
                normalizedScalar(item.resultSummary)
            ]),
            sections: [
                compactSection(
                    title: "请求",
                    fields: [
                        ("项目", normalizedScalar(item.projectName)),
                        ("请求", normalizedScalar(item.requestId)),
                    ] + skillFields + [
                        ("工具", SupervisorSkillActivityPresentation.toolBadge(for: item)),
                        ("状态", normalizedScalar(item.status))
                    ]
                ),
                compactSection(
                    title: "工作流",
                    fields: [
                        ("任务", normalizedScalar(item.record.jobId)),
                        ("计划", normalizedScalar(item.record.planId)),
                        ("步骤", normalizedScalar(item.record.stepId)),
                        ("负责人", normalizedScalar(item.record.currentOwner))
                    ]
                ),
                compactSection(
                    title: "执行",
                    fields: [
                        ("路由", normalizedScalar(SupervisorSkillActivityPresentation.routingLine(for: item) ?? "")),
                        ("路由说明", routingNarrative),
                        ("路由判定", normalizedScalar(
                            SupervisorSkillActivityPresentation.routingReasonText(
                                item.record.routingReasonCode
                            ) ?? ""
                        )),
                        ("路由代码", normalizedScalar(item.record.routingReasonCode ?? "")),
                        ("路由原文", normalizedScalar(item.record.routingExplanation ?? "")),
                        ("所需能力", normalizedScalar(item.requiredCapability)),
                        ("授权请求", normalizedScalar(item.grantRequestId)),
                        ("授权", normalizedScalar(item.grantId)),
                        ("结果", normalizedScalar(item.resultSummary)),
                        ("拒绝码", normalizedScalar(item.denyCode)),
                        ("策略来源", normalizedScalar(item.policySource)),
                        ("策略原因", normalizedScalar(item.policyReason)),
                        ("阻塞说明", blockedSummary),
                        ("证据引用", normalizedScalar(item.resultEvidenceRef))
                    ]
                ),
                compactSection(
                    title: "治理",
                    fields: [("治理真相", governanceTruth)] + governanceFields
                ),
                uiReviewEvidenceSection(fullRecord)
            ].compactMap { $0 },
            requestId: normalizedOptionalScalar(item.requestId),
            actionLabel: preferredAction?.label,
            actionURL: preferredAction?.url,
            secondaryActions: secondaryActions,
            includesEmbeddedSkillRecord: fullRecord != nil
        )
    }

    static func fullRecordFallback(
        projectId: String,
        projectName: String,
        record: SupervisorSkillFullRecord
    ) -> SupervisorAuditDrillDownPresentation {
        let requestSummary = record.requestMetadata.first?.value ?? ""
        let resultSummary = record.resultFields.first?.value ?? ""
        let governanceTruth = firstMeaningfulScalar([
            fullRecordFieldValue("governance_truth", in: record.governanceFields),
            fullRecordFieldValue("governance_truth", in: record.approvalFields)
        ])
        let blockedSummary = fullRecordFieldValue("blocked_summary", in: record.approvalFields)
        let policyReason = fullRecordFieldValue("policy_reason", in: record.approvalFields)
        let preferredAction = preferredUIReviewAction(
            projectId: projectId,
            fallbackAction: nil,
            fullRecord: record
        )

        return SupervisorAuditDrillDownPresentation(
            id: "skill-record-fallback:\(projectId):\(record.requestID)",
            iconName: "doc.text.magnifyingglass",
            title: record.title,
            statusLabel: record.latestStatusLabel,
            tone: tone(forSkillStatus: record.latestStatus, requiredCapability: ""),
            summary: firstMeaningfulScalar([
                resultSummary,
                requestSummary,
                "已从项目审计历史载入技能记录。"
            ]),
            detail: firstMeaningfulScalar([
                normalizedScalar(projectName),
                normalizedScalar(projectId)
            ]),
            sections: [
                compactSection(
                    title: "请求",
                    fields: [
                        ("项目", normalizedScalar(projectName)),
                        ("项目 ID", normalizedScalar(projectId)),
                        ("请求", normalizedScalar(record.requestID)),
                        ("状态", normalizedScalar(record.latestStatus))
                    ]
                ),
                compactSection(
                    title: "治理",
                    fields: [
                        ("治理真相", governanceTruth),
                        ("阻塞说明", blockedSummary),
                        ("策略原因", policyReason)
                    ]
                )
            ].compactMap { $0 },
            requestId: normalizedOptionalScalar(record.requestID),
            actionLabel: preferredAction?.label,
            actionURL: preferredAction?.url,
            includesEmbeddedSkillRecord: true
        )
    }

    static func eventLoopActivity(
        _ activity: SupervisorManager.SupervisorEventLoopActivity,
        relatedSkillActivity: SupervisorManager.SupervisorRecentSkillActivity?,
        fullRecord: SupervisorSkillFullRecord?
    ) -> SupervisorAuditDrillDownPresentation {
        let defaultAction = SupervisorEventLoopActionPresentation.action(for: activity).map {
            ActionLink(label: $0.label, url: $0.url)
        }
        let requestId = SupervisorEventLoopActionPresentation.requestId(for: activity)
        let preferredAction = preferredUIReviewAction(
            projectId: activity.projectId,
            fallbackAction: defaultAction,
            fullRecord: fullRecord,
            policySummary: activity.policySummary
        )
        let secondaryActions = dedupedActionLinks(
            preferredAction?.url,
            candidates: [
                defaultAction,
                eventLoopRecordAction(
                    projectId: activity.projectId,
                    requestId: requestId
                )
            ]
        )
        let relatedSkillLabel = relatedSkillActivity.map {
            let skillLabel = firstMeaningfulScalar([
                SupervisorSkillActivityPresentation.routingSummary(
                    requestedSkillId: $0.requestedSkillId,
                    effectiveSkillId: $0.skillId,
                    payload: $0.record.payload,
                    routingReasonCode: $0.record.routingReasonCode,
                    routingExplanation: $0.record.routingExplanation
                ) ?? "",
                normalizedScalar($0.skillId)
            ])
            return [
                skillLabel,
                SupervisorSkillActivityPresentation.statusLabel(for: $0)
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        } ?? ""
        let blockedSummary = firstMeaningfulScalar([
            fullRecordFieldValue("blocked_summary", in: fullRecord?.approvalFields ?? []),
            relatedSkillActivity.flatMap {
                XTGuardrailMessagePresentation.blockedSummary(
                    tool: $0.tool,
                    toolLabel: displayToolName($0.toolName, tool: $0.tool),
                    denyCode: $0.denyCode,
                    policySource: $0.policySource,
                    policyReason: $0.policyReason,
                    fallbackSummary: $0.resultSummary,
                    fallbackDetail: ""
                )
            } ?? ""
        ])
        let governanceTruth = firstMeaningfulScalar([
            fullRecordFieldValue("governance_truth", in: fullRecord?.governanceFields ?? []),
            fullRecordFieldValue("governance_truth", in: fullRecord?.approvalFields ?? [])
        ])
        let policyReason = firstMeaningfulScalar([
            fullRecordFieldValue("policy_reason", in: fullRecord?.approvalFields ?? []),
            relatedSkillActivity?.policyReason ?? ""
        ])

        return SupervisorAuditDrillDownPresentation(
            id: "event-loop:\(activity.id)",
            iconName: iconName(forEventTrigger: activity.triggerSource),
            title: title(forEventTrigger: activity.triggerSource),
            statusLabel: eventStatusLabel(activity.status),
            tone: tone(forEventStatus: activity.status),
            summary: firstMeaningfulScalar([
                normalizedScalar(activity.triggerSummary),
                normalizedScalar(activity.resultSummary),
                normalizedScalar(activity.reasonCode)
            ]),
            detail: firstMeaningfulScalar([
                normalizedScalar(activity.resultSummary),
                normalizedScalar(activity.policySummary)
            ]),
            sections: [
                compactSection(
                    title: "事件",
                    fields: [
                        ("项目", firstMeaningfulScalar([
                            normalizedScalar(activity.projectName),
                            normalizedScalar(activity.projectId)
                        ])),
                        ("触发源", normalizedScalar(activity.triggerSource)),
                        ("原因", normalizedScalar(activity.reasonCode)),
                        ("去重键", normalizedScalar(activity.dedupeKey)),
                        ("请求", normalizedScalar(requestId ?? ""))
                    ]
                ),
                compactSection(
                    title: "结果",
                    fields: [
                        ("触发摘要", normalizedScalar(activity.triggerSummary)),
                        ("结果摘要", normalizedScalar(activity.resultSummary)),
                        ("策略", normalizedScalar(activity.policySummary)),
                        ("关联技能", relatedSkillLabel),
                        ("阻塞说明", blockedSummary),
                        ("治理真相", governanceTruth),
                        ("策略原因", policyReason)
                    ]
                ),
                uiReviewEvidenceSection(fullRecord)
            ].compactMap { $0 },
            requestId: normalizedOptionalScalar(requestId),
            actionLabel: preferredAction?.label,
            actionURL: preferredAction?.url,
            secondaryActions: secondaryActions,
            includesEmbeddedSkillRecord: fullRecord != nil
        )
    }

    private static func compactSection(
        title: String,
        fields: [(String, String)]
    ) -> Section? {
        let filtered = fields.compactMap { label, value -> Field? in
            let normalized = normalizedScalar(value)
            guard !normalized.isEmpty else { return nil }
            return Field(label: label, value: normalized)
        }
        guard !filtered.isEmpty else { return nil }
        return Section(title: title, fields: filtered)
    }

    private static func fullRecordFieldValue(
        _ label: String,
        in fields: [ProjectSkillRecordField]
    ) -> String {
        fields.first(where: {
            $0.label.caseInsensitiveCompare(label) == .orderedSame
        })?.value ?? ""
    }

    private static func skillIdentityFields(
        requestedSkillId: String,
        effectiveSkillId: String
    ) -> [(String, String)] {
        let requested = normalizedScalar(requestedSkillId)
        let effective = normalizedScalar(effectiveSkillId)
        if requested.isEmpty {
            return effective.isEmpty ? [] : [("技能", effective)]
        }
        if effective.isEmpty {
            return [("请求技能", requested)]
        }
        if requested.caseInsensitiveCompare(effective) == .orderedSame {
            return [("技能", effective)]
        }
        return [
            ("请求技能", requested),
            ("生效技能", effective)
        ]
    }

    private static func officialTopBlockersSection(
        _ blockers: [AXOfficialSkillBlockerSummaryItem]
    ) -> Section? {
        guard !blockers.isEmpty else { return nil }
        let fields = blockers.prefix(5).compactMap { blocker -> (String, String)? in
            let label = normalizedScalar(officialBlockerFieldLabel(blocker))
            let value = normalizedScalar(officialBlockerFieldValue(blocker))
            guard !label.isEmpty, !value.isEmpty else { return nil }
            return (label, value)
        }
        return compactSection(title: "重点包问题", fields: fields)
    }

    private static func uiReviewEvidenceSection(
        _ fullRecord: SupervisorSkillFullRecord?
    ) -> Section? {
        guard let fullRecord else { return nil }
        let valueByLabel = Dictionary(
            uniqueKeysWithValues: fullRecord.uiReviewAgentEvidenceFields.map { ($0.label, $0.value) }
        )
        let repairGuidance = uiReviewRepairGuidance(for: fullRecord)
        return compactSection(
            title: "UI 审查证据",
            fields: [
                ("摘要", valueByLabel["summary"] ?? ""),
                ("结论", valueByLabel["verdict"] ?? ""),
                ("置信度", valueByLabel["confidence"] ?? ""),
                ("目标就绪", valueByLabel["objective_ready"] ?? ""),
                ("问题码", valueByLabel["issue_codes"] ?? ""),
                ("建议修复", repairGuidance?.summary ?? ""),
                ("证据引用", valueByLabel["ui_review_agent_evidence_ref"] ?? "")
            ]
        )
    }

    private static func guidanceContractFields(
        _ contract: SupervisorGuidanceContractSummary?
    ) -> [(String, String)] {
        guard let contract else { return [] }

        var fields: [(String, String)] = [
            ("指导合同", contract.kindText),
            ("指导摘要", contract.summaryText),
            ("安全下一步", contract.nextSafeActionText)
        ]

        if let uiReview = contract.uiReviewRepair {
            fields.append((
                "修复动作",
                firstMeaningfulScalar([
                    normalizedScalar(uiReview.repairAction),
                    normalizedScalar(uiReview.repairFocus)
                ])
            ))
        } else {
            fields.append(("主要阻塞", normalizedScalar(contract.primaryBlocker)))
        }

        if let actions = normalizedOptionalScalar(contract.recommendedActionsText) {
            fields.append(("建议动作", actions))
        }

        return fields
    }

    private static func preferredUIReviewAction(
        projectId: String,
        fallbackAction: ActionLink?,
        fullRecord: SupervisorSkillFullRecord?,
        policySummary: String = ""
    ) -> ActionLink? {
        if let fallbackAction,
           actionURLGovernanceDestination(fallbackAction.url) == .uiReview {
            return fallbackAction
        }
        guard uiReviewNeedsAttention(
            fullRecord: fullRecord,
            policySummary: policySummary
        ),
        let url = uiReviewActionURL(projectId: projectId) else {
            return fallbackAction
        }
        return ActionLink(label: "打开 UI 审查", url: url)
    }

    private static func uiReviewNeedsAttention(
        fullRecord: SupervisorSkillFullRecord?,
        policySummary: String
    ) -> Bool {
        if normalizedScalar(policySummary)
            .lowercased()
            .contains("next=open_ui_review") {
            return true
        }
        guard let fullRecord else { return false }
        return uiReviewRepairGuidance(for: fullRecord) != nil
    }

    private static func uiReviewEvidenceFieldValue(
        _ label: String,
        in fullRecord: SupervisorSkillFullRecord
    ) -> String {
        fullRecord.uiReviewAgentEvidenceFields.first(where: {
            $0.label.caseInsensitiveCompare(label) == .orderedSame
        })?.value ?? ""
    }

    private static func uiReviewEvidenceBoolValue(
        _ label: String,
        in fullRecord: SupervisorSkillFullRecord
    ) -> Bool? {
        switch uiReviewEvidenceFieldValue(label, in: fullRecord).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func uiReviewRepairGuidance(
        for fullRecord: SupervisorSkillFullRecord
    ) -> SupervisorUIReviewRepairGuidance? {
        let verdict = XTUIReviewVerdict(
            rawValue: uiReviewEvidenceFieldValue("verdict", in: fullRecord).lowercased()
        )
        let sufficientEvidence = uiReviewEvidenceBoolValue("sufficient_evidence", in: fullRecord)
        let objectiveReady = uiReviewEvidenceBoolValue("objective_ready", in: fullRecord)
        let issueCodes = uiReviewEvidenceFieldValue("issue_codes", in: fullRecord)
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let trend: [String] = normalizedScalar(fullRecord.uiReviewAgentEvidenceText ?? "")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        return SupervisorUIReviewRepairPlanner.guidance(
            verdict: verdict,
            sufficientEvidence: sufficientEvidence,
            objectiveReady: objectiveReady,
            issueCodes: issueCodes,
            trend: trend
        )
    }

    private static func uiReviewActionURL(
        projectId: String
    ) -> String? {
        XTDeepLinkURLBuilder.projectURL(
            projectId: projectId,
            pane: .chat,
            governanceDestination: .uiReview
        )?.absoluteString
    }

    private static func eventLoopRecordAction(
        projectId: String,
        requestId: String?
    ) -> ActionLink? {
        guard let requestId = normalizedOptionalScalar(requestId) else { return nil }
        if let projectId = normalizedOptionalScalar(projectId),
           let url = XTDeepLinkURLBuilder.projectURL(
                projectId: projectId,
                pane: .chat,
                openTarget: .supervisor,
                focusTarget: .skillRecord,
                requestId: requestId
           )?.absoluteString {
            return ActionLink(label: "打开记录", url: url)
        }
        guard let url = XTDeepLinkURLBuilder.supervisorURL(
            focusTarget: .skillRecord,
            requestId: requestId
        )?.absoluteString else {
            return nil
        }
        return ActionLink(label: "打开记录", url: url)
    }

    private static func dedupedActionLinks(
        _ primaryURL: String?,
        candidates: [ActionLink?]
    ) -> [ActionLink] {
        var seen = Set<String>()
        if let primaryURL = normalizedOptionalScalar(primaryURL) {
            seen.insert(primaryURL)
        }

        var actions: [ActionLink] = []
        for candidate in candidates {
            guard let candidate = actionLink(label: candidate?.label, url: candidate?.url),
                  !seen.contains(candidate.url) else {
                continue
            }
            seen.insert(candidate.url)
            actions.append(candidate)
        }
        return actions
    }

    private static func actionLink(
        label: String?,
        url: String?
    ) -> ActionLink? {
        guard let label = normalizedOptionalScalar(label),
              let url = normalizedOptionalScalar(url) else {
            return nil
        }
        return ActionLink(label: label, url: url)
    }

    private static func actionURLGovernanceDestination(
        _ raw: String
    ) -> XTProjectGovernanceDestination? {
        guard let components = URLComponents(string: raw),
              let destination = components.queryItems?.first(where: {
                  $0.name == "governance_destination"
              })?.value else {
            return nil
        }
        return XTProjectGovernanceDestination.parse(destination)
    }

    private static func officialTopBlockerActions(
        _ blockers: [AXOfficialSkillBlockerSummaryItem],
        excluding excludedID: String?
    ) -> [ActionLink] {
        blockers.prefix(3).compactMap { blocker in
            if let excludedID, blocker.id == excludedID {
                return nil
            }
            guard let action = XTOfficialSkillsBlockerActionSupport.action(for: blocker) else {
                return nil
            }
            return ActionLink(
                label: officialBlockerActionLabel(blocker),
                url: action.url
            )
        }
    }

    private static func officialBlockerActionLabel(
        _ blocker: AXOfficialSkillBlockerSummaryItem
    ) -> String {
        let subject = firstMeaningfulScalar([
            normalizedScalar(blocker.title),
            normalizedScalar(blocker.subtitle),
            normalizedScalar(blocker.packageSHA256)
        ])
        guard !subject.isEmpty else { return "查看阻塞项" }
        return "查看 \(subject)"
    }

    private static func officialBlockerFieldLabel(
        _ blocker: AXOfficialSkillBlockerSummaryItem
    ) -> String {
        firstMeaningfulScalar([
            normalizedScalar(blocker.title),
            normalizedScalar(blocker.subtitle),
            normalizedScalar(blocker.packageSHA256)
        ])
    }

    private static func officialBlockerFieldValue(
        _ blocker: AXOfficialSkillBlockerSummaryItem
    ) -> String {
        let state = normalizedScalar(blocker.stateLabel)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
        let subtitle = normalizedScalar(blocker.subtitle)
        let summary = normalizedScalar(blocker.summaryLine)
        let timeline = normalizedScalar(blocker.timelineLine)

        var parts: [String] = []
        if !state.isEmpty {
            parts.append("状态=\(state)")
        }
        if !subtitle.isEmpty,
           subtitle.caseInsensitiveCompare(normalizedScalar(blocker.title)) != .orderedSame {
            parts.append("技能=\(subtitle)")
        }
        if !summary.isEmpty {
            parts.append(summary)
        }
        if !timeline.isEmpty {
            parts.append(timeline)
        }
        return parts.joined(separator: " | ")
    }

    private static func officialTone(for statusLine: String) -> Tone {
        let normalized = statusLine.lowercased()
        if normalized.contains("official failed") || normalized.contains("official missing") {
            return .critical
        }
        if normalized.contains("official healthy") {
            return .success
        }
        return .neutral
    }

    private static func officialBadge(for statusLine: String) -> String {
        switch officialTone(for: statusLine) {
        case .critical:
            return "降级"
        case .success:
            return "健康"
        case .attention:
            return "关注"
        case .neutral:
            return "观察"
        }
    }

    private static func tone(
        forSkillStatus rawStatus: String,
        requiredCapability: String
    ) -> Tone {
        switch normalizedScalar(rawStatus).lowercased() {
        case "completed":
            return .success
        case "failed", "blocked":
            return .critical
        case "awaiting_authorization":
            return normalizedScalar(requiredCapability).isEmpty ? .attention : .critical
        case "running", "queued", "canceled":
            return .attention
        default:
            return .neutral
        }
    }

    private static func tone(forEventStatus rawStatus: String) -> Tone {
        switch normalizedScalar(rawStatus).lowercased() {
        case "completed":
            return .success
        case "failed":
            return .critical
        case "queued", "running":
            return .attention
        default:
            return .neutral
        }
    }

    private static func title(forEventTrigger raw: String) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "official_skills_channel":
            return "官方技能跟进"
        case "grant_resolution":
            return "授权处理"
        case "approval_resolution":
            return "审批处理"
        case "incident":
            return "异常事件跟进"
        case "heartbeat":
            return "心跳跟进"
        default:
            return "基础设施事件"
        }
    }

    private static func iconName(forEventTrigger raw: String) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "official_skills_channel":
            return "shippingbox.fill"
        case "grant_resolution":
            return "checkmark.shield"
        case "approval_resolution":
            return "hand.raised.fill"
        case "incident":
            return "exclamationmark.triangle.fill"
        case "heartbeat":
            return "heart.text.square.fill"
        default:
            return "waveform.path.ecg"
        }
    }

    private static func eventStatusLabel(_ raw: String) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "completed":
            return "已完成"
        case "completed_empty":
            return "无动作"
        case "running":
            return "进行中"
        case "queued":
            return "排队中"
        case "failed":
            return "失败"
        case "deduped":
            return "已去重"
        default:
            return normalizedScalar(raw).isEmpty ? "事件" : normalizedScalar(raw)
        }
    }

    private static func iconName(for tool: ToolName?) -> String {
        switch tool {
        case .some(.read_file):
            return "doc.text"
        case .some(.write_file):
            return "pencil"
        case .some(.search):
            return "magnifyingglass"
        case .some(.run_command):
            return "terminal"
        case .some(.deviceBrowserControl):
            return "safari"
        case .some(.web_fetch), .some(.web_search), .some(.browser_read):
            return "network"
        case .some(.project_snapshot):
            return "folder.badge.gearshape"
        case .some(.agentImportRecord):
            return "checklist"
        case .some(.memory_snapshot):
            return "memorychip"
        default:
            return "hand.raised.fill"
        }
    }

    private static func displayToolName(
        _ raw: String,
        tool: ToolName?
    ) -> String {
        let resolvedTool = tool ?? ToolName(rawValue: raw)
        guard let resolvedTool else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "工具运行时" : raw
        }

        switch resolvedTool {
        case .read_file:
            return "读取文件"
        case .write_file:
            return "写入文件"
        case .delete_path:
            return "删除路径"
        case .move_path:
            return "移动路径"
        case .run_command:
            return "运行命令"
        case .process_start:
            return "启动进程"
        case .process_status:
            return "进程状态"
        case .process_logs:
            return "进程日志"
        case .process_stop:
            return "停止进程"
        case .git_commit:
            return "Git 提交"
        case .git_push:
            return "Git 推送"
        case .pr_create:
            return "创建 Pull Request"
        case .ci_read:
            return "读取 CI"
        case .ci_trigger:
            return "触发 CI"
        case .search:
            return "搜索"
        case .skills_search:
            return "搜索技能"
        case .summarize:
            return "总结内容"
        case .supervisorVoicePlayback:
            return "Supervisor 语音"
        case .web_fetch:
            return "抓取网页"
        case .web_search:
            return "网页搜索"
        case .browser_read:
            return "浏览器读取"
        case .deviceBrowserControl:
            return "浏览器控制"
        case .agentImportRecord:
            return "导入代理记录"
        default:
            return resolvedTool.rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func durationLabel(seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        if seconds % 3600 == 0 {
            return "\(seconds / 3600)h"
        }
        if seconds % 60 == 0 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }

    private static func tokenCapLabel(_ tokenCap: Int) -> String {
        guard tokenCap > 0 else { return "" }
        return "\(tokenCap)"
    }

    private static func firstMeaningfulScalar(_ values: [String]) -> String {
        values.first { !normalizedScalar($0).isEmpty } ?? ""
    }

    private static func normalizedOptionalScalar(_ value: String?) -> String? {
        let normalized = normalizedScalar(value ?? "")
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedScalar(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
