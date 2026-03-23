import Foundation

enum XTProjectDetailSection: String, CaseIterable, Codable, Sendable {
    case overview = "overview"
    case status = "status"
    case uiReview = "ui_review"
    case model = "model"
    case governanceActivity = "governance_activity"
    case cost = "cost"
    case collaboration = "collaboration"
    case timeline = "timeline"
    case dangerZone = "danger_zone"

    var displayTitle: String {
        switch self {
        case .overview:
            return "概览"
        case .status:
            return "状态"
        case .uiReview:
            return "UI Review"
        case .model:
            return "模型治理"
        case .governanceActivity:
            return "治理活动"
        case .cost:
            return "成本预算"
        case .collaboration:
            return "协作"
        case .timeline:
            return "时间线"
        case .dangerZone:
            return "危险操作"
        }
    }

    var focusContext: XTSectionFocusContext {
        switch self {
        case .overview:
            return XTSectionFocusContext(
                title: "Project Detail",
                detail: "Overview"
            )
        case .status:
            return XTSectionFocusContext(
                title: "Project Detail",
                detail: "Status & Progress"
            )
        case .uiReview:
            return XTSectionFocusContext(
                title: "Project Detail",
                detail: "Latest UI Review"
            )
        case .model:
            return XTSectionFocusContext(
                title: "Project Detail",
                detail: "Model & Governance"
            )
        case .governanceActivity:
            return XTSectionFocusContext(
                title: "Project Detail",
                detail: "Governance Activity"
            )
        case .cost:
            return XTSectionFocusContext(
                title: "Project Detail",
                detail: "Cost & Budget"
            )
        case .collaboration:
            return XTSectionFocusContext(
                title: "Project Detail",
                detail: "Collaboration"
            )
        case .timeline:
            return XTSectionFocusContext(
                title: "Project Detail",
                detail: "Timeline"
            )
        case .dangerZone:
            return XTSectionFocusContext(
                title: "Project Detail",
                detail: "Danger Zone"
            )
        }
    }
}

struct XTProjectDetailFocusRequest: Equatable {
    var nonce: Int
    var projectId: String
    var section: XTProjectDetailSection
    var context: XTSectionFocusContext?
}
