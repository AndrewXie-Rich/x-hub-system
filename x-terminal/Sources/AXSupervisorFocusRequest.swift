import Foundation

struct AXSupervisorFocusRequest: Equatable {
    enum Subject: Equatable {
        case board(anchorID: String)
        case grant(grantRequestId: String?, capability: String?)
        case approval(requestId: String)
        case candidateReview(requestId: String)
        case skillRecord(requestId: String)
    }

    var nonce: Int
    var projectId: String?
    var subject: Subject
}
