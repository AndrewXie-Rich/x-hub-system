import Foundation

enum XTSectionRefreshAction: String, Equatable {
    case recheckOfficialSkills = "recheck_official_skills"
}

struct XTSectionFocusContext: Equatable {
    var title: String
    var detail: String?
    var refreshAction: XTSectionRefreshAction? = nil
    var refreshReason: String? = nil
}
