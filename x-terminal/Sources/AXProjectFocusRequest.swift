import Foundation

struct AXProjectFocusRequest: Equatable {
    enum Subject: Equatable {
        case toolApproval(requestId: String?)
        case routeDiagnose
    }

    var nonce: Int
    var projectId: String
    var subject: Subject
}
