import Foundation

struct HubMeeting: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var startAt: Double
    var endAt: Double
    var location: String?
    var joinURL: String?
    var isMeeting: Bool

    var startDate: Date { Date(timeIntervalSince1970: startAt) }
    var endDate: Date { Date(timeIntervalSince1970: endAt) }
}
