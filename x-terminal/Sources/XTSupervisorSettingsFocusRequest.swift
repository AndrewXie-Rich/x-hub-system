import Foundation

enum XTSupervisorSettingsFocusSection: String, CaseIterable, Codable, Sendable {
    case recentRawContext = "recent_raw_context"
    case reviewMemoryDepth = "review_memory_depth"

    var focusContext: XTSectionFocusContext {
        switch self {
        case .recentRawContext:
            return XTSectionFocusContext(
                title: "Supervisor Settings",
                detail: "Recent Raw Context"
            )
        case .reviewMemoryDepth:
            return XTSectionFocusContext(
                title: "Supervisor Settings",
                detail: "Review Memory Depth"
            )
        }
    }
}

struct XTSupervisorSettingsFocusRequest: Equatable {
    var nonce: Int
    var section: XTSupervisorSettingsFocusSection
    var context: XTSectionFocusContext?
}
