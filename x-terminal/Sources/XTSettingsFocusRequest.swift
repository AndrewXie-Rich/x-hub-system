import Foundation

struct XTSettingsFocusRequest: Equatable {
    var nonce: Int
    var sectionId: String
    var context: XTSectionFocusContext?
}
