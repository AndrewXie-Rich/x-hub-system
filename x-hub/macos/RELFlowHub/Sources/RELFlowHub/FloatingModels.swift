import Foundation
import SwiftUI

enum FloatingMode: String, Codable, CaseIterable {
    case orb
    case card

    var title: String {
        switch self {
        case .orb: return HubUIStrings.Settings.FloatingMode.orb
        case .card: return HubUIStrings.Settings.FloatingMode.card
        }
    }

    var panelSize: CGSize {
        switch self {
        case .orb: return CGSize(width: 396, height: 396)
        // Fixed-size card: closer to a square widget footprint.
        case .card: return CGSize(width: 176, height: 176)
        }
    }
}

enum TopAlertKind: String, Codable {
    case meetingSoon
    case meetingHot
    case meetingUrgent
    case radar
    case message
    case mail
    case slack
    case task
    case idle

    var baseColor: Color {
        switch self {
        // Meetings live in the "red" family so they are distinct from radars.
        case .meetingSoon: return Color(red: 1.0, green: 0.64, blue: 0.64) // soft coral
        case .meetingHot: return Color(red: 1.0, green: 0.48, blue: 0.34) // orange-red
        case .meetingUrgent: return Color(red: 1.0, green: 0.32, blue: 0.32) // red
        // FA Tracker radars (new) live in the "yellow" family.
        case .radar: return Color(red: 1.0, green: 0.784, blue: 0.341) // #FFC857
        // Other sources get distinct families.
        case .message: return Color(red: 0.62, green: 0.90, blue: 0.62) // light green
        case .mail: return Color(red: 0.35, green: 0.66, blue: 1.00) // sky blue
        case .slack: return Color(red: 0.55, green: 0.45, blue: 1.0) // pale purple
        case .task: return Color(red: 0.30, green: 0.58, blue: 1.0) // blue
        case .idle: return Color(red: 0.00, green: 0.78, blue: 0.59) // green-teal
        }
    }
}

struct TopAlert: Equatable {
    var kind: TopAlertKind
    var count: Int
    var urgentSecondsToMeeting: Int?
    // When kind is `.meetingUrgent`, this is the window (in seconds) that defines how
    // "urgent" we consider it. The orb animation uses it to scale speed/pulse smoothly.
    var urgentWindowSeconds: Int?
}
