import Foundation

struct XTModelSettingsFocusRequest: Equatable {
    var nonce: Int
    var role: AXRole?
    var context: XTSectionFocusContext?
}
