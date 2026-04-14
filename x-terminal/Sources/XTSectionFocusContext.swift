import Foundation

enum XTSectionRefreshAction: String, Equatable {
    case recheckOfficialSkills = "recheck_official_skills"
    case repairHistoricalProjectBoundaries = "repair_historical_project_boundaries"
}

struct XTSectionFocusContext: Equatable {
    var title: String
    var detail: String?
    var refreshAction: XTSectionRefreshAction? = nil
    var refreshReason: String? = nil
}
