import Foundation

struct XTHubSetupFocusRequest: Equatable {
    var nonce: Int
    var sectionId: String
    var context: XTSectionFocusContext?
}
