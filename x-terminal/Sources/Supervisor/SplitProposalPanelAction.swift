import Foundation

enum SplitProposalPanelAction: Equatable {
    case generateProposal
    case clearFocusedLane
    case toggleLaneFocus(SplitLaneProposal)
    case toggleLaneMaterialization(SplitLaneProposal)
    case confirmHighRiskSoftOverride(SplitLaneProposal)
    case confirmProposal
    case executeProposal
    case rejectProposal
    case replayCheck
    case reset
}

struct SplitProposalPanelActionDescriptor: Equatable, Identifiable {
    enum Style: Equatable {
        case prominent
        case bordered
        case borderless
    }

    var action: SplitProposalPanelAction
    var label: String
    var style: Style
    var isEnabled: Bool

    var id: String {
        "\(label)|\(style)|\(isEnabled)|\(action)"
    }
}

struct SplitProposalPanelLanePresentation: Equatable {
    var isFocused: Bool
    var overrideLabel: String
    var focusLabel: String
    var needsHighRiskSoftConfirmation: Bool
}

enum SplitProposalPanelActionResolver {
    struct Context: Equatable {
        var draftTaskDescription: String
        var focusedLaneID: String?
        var hasActiveProposal: Bool
        var hasBaseSnapshot: Bool
    }

    enum Effect: Equatable {
        case proposeSplit(String)
        case confirmProposal(String)
        case executeProposal
        case rejectProposal(String)
        case replayCheck
        case reset
        case setFocusedLane(String?)
        case showHighRiskSoftOverrideConfirmation(SplitLaneProposal)
        case applyOverride(SplitLaneOverride, reason: String)
    }

    struct Plan: Equatable {
        var effects: [Effect]
    }

    static func generateDescriptor(
        context: Context
    ) -> SplitProposalPanelActionDescriptor {
        SplitProposalPanelActionDescriptor(
            action: .generateProposal,
            label: "生成提案",
            style: .bordered,
            isEnabled: normalizedDraft(context.draftTaskDescription) != nil
        )
    }

    static func footerDescriptors(
        context: Context
    ) -> [SplitProposalPanelActionDescriptor] {
        [
            SplitProposalPanelActionDescriptor(
                action: .confirmProposal,
                label: "确认方案",
                style: .prominent,
                isEnabled: context.hasActiveProposal
            ),
            SplitProposalPanelActionDescriptor(
                action: .executeProposal,
                label: "启动多泳道",
                style: .prominent,
                isEnabled: context.hasActiveProposal
            ),
            SplitProposalPanelActionDescriptor(
                action: .rejectProposal,
                label: "放弃方案",
                style: .bordered,
                isEnabled: context.hasActiveProposal
            ),
            SplitProposalPanelActionDescriptor(
                action: .replayCheck,
                label: "回放校验",
                style: .borderless,
                isEnabled: context.hasBaseSnapshot
            ),
            SplitProposalPanelActionDescriptor(
                action: .reset,
                label: "重置",
                style: .borderless,
                isEnabled: context.hasActiveProposal || context.hasBaseSnapshot
            )
        ]
    }

    static func clearFocusedLaneDescriptor(
        focusedLaneID: String?
    ) -> SplitProposalPanelActionDescriptor? {
        guard normalizedScalar(focusedLaneID) != nil else { return nil }
        return SplitProposalPanelActionDescriptor(
            action: .clearFocusedLane,
            label: "清除定位",
            style: .borderless,
            isEnabled: true
        )
    }

    static func lanePresentation(
        for lane: SplitLaneProposal,
        focusedLaneID: String?
    ) -> SplitProposalPanelLanePresentation {
        let isFocused = lane.laneId == normalizedScalar(focusedLaneID)
        return SplitProposalPanelLanePresentation(
            isFocused: isFocused,
            overrideLabel: lane.createChildProject ? "改为轻执行" : "升级为独立项目",
            focusLabel: isFocused ? "取消定位" : "定位",
            needsHighRiskSoftConfirmation: lane.createChildProject && lane.isHighRisk
        )
    }

    static func displayLanes(
        from proposal: SplitProposal,
        focusedLaneID: String?
    ) -> [SplitLaneProposal] {
        guard let focusedLaneID = normalizedScalar(focusedLaneID),
              let focusedIndex = proposal.lanes.firstIndex(where: { $0.laneId == focusedLaneID }) else {
            return proposal.lanes
        }

        var lanes = proposal.lanes
        let focusedLane = lanes.remove(at: focusedIndex)
        lanes.insert(focusedLane, at: 0)
        return lanes
    }

    static func resolve(
        _ action: SplitProposalPanelAction,
        context: Context
    ) -> Plan? {
        switch action {
        case .generateProposal:
            guard let draft = normalizedDraft(context.draftTaskDescription) else {
                return nil
            }
            return Plan(effects: [.proposeSplit(draft)])
        case .clearFocusedLane:
            return Plan(effects: [.setFocusedLane(nil)])
        case .toggleLaneFocus(let lane):
            let nextFocusedLane = lane.laneId == normalizedScalar(context.focusedLaneID)
                ? nil
                : lane.laneId
            return Plan(effects: [.setFocusedLane(nextFocusedLane)])
        case .toggleLaneMaterialization(let lane):
            if lane.createChildProject && lane.isHighRisk {
                return Plan(effects: [.showHighRiskSoftOverrideConfirmation(lane)])
            }
            return Plan(
                effects: [
                    .applyOverride(
                        SplitLaneOverride(
                            laneId: lane.laneId,
                            createChildProject: !lane.createChildProject,
                            note: "ui_toggle_materialization"
                        ),
                        reason: "ui_lane_materialization_override"
                    )
                ]
            )
        case .confirmHighRiskSoftOverride(let lane):
            return Plan(
                effects: [
                    .applyOverride(
                        SplitLaneOverride(
                            laneId: lane.laneId,
                            createChildProject: false,
                            note: "ui_confirmed_high_risk_hard_to_soft",
                            confirmHighRiskHardToSoft: true
                        ),
                        reason: "ui_lane_materialization_override"
                    )
                ]
            )
        case .confirmProposal:
            return Plan(
                effects: [
                    .confirmProposal(
                        normalizedDraft(context.draftTaskDescription) ?? ""
                    )
                ]
            )
        case .executeProposal:
            guard context.hasActiveProposal else { return nil }
            return Plan(effects: [.executeProposal])
        case .rejectProposal:
            guard context.hasActiveProposal else { return nil }
            return Plan(effects: [.rejectProposal("user_rejected_from_supervisor_view")])
        case .replayCheck:
            guard context.hasBaseSnapshot else { return nil }
            return Plan(effects: [.replayCheck])
        case .reset:
            guard context.hasActiveProposal || context.hasBaseSnapshot else { return nil }
            return Plan(effects: [.reset])
        }
    }

    private static func normalizedDraft(_ raw: String) -> String? {
        normalizedScalar(raw)
    }

    private static func normalizedScalar(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
