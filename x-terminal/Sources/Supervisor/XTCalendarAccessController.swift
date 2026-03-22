import Combine
import Foundation
@preconcurrency import EventKit

enum XTCalendarAuthorizationStatus: String, Codable, Equatable, Sendable {
    case notDetermined = "not_determined"
    case authorized
    case fullAccess = "full_access"
    case writeOnly = "write_only"
    case denied
    case restricted
    case unavailable

    var canReadEvents: Bool {
        self == .authorized || self == .fullAccess
    }

    var displayName: String {
        switch self {
        case .notDetermined:
            return "Not Granted"
        case .authorized:
            return "Authorized"
        case .fullAccess:
            return "Full Access"
        case .writeOnly:
            return "Write Only"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .unavailable:
            return "Unavailable"
        }
    }

    var guidanceText: String {
        switch self {
        case .notDetermined:
            return "Grant calendar access on this XT device before enabling Supervisor meeting reminders."
        case .authorized, .fullAccess:
            return "Calendar access is ready on this XT device."
        case .writeOnly:
            return "X-Terminal needs calendar read access for meeting reminders. Update the Calendar permission in System Settings."
        case .denied:
            return "Calendar access is denied. Open System Settings -> Privacy & Security -> Calendars and re-enable X-Terminal."
        case .restricted:
            return "Calendar access is restricted by the system. Check device policy before using Supervisor meeting reminders."
        case .unavailable:
            return "Calendar access is unavailable on this system."
        }
    }
}

protocol XTCalendarAuthorizationClient {
    func authorizationStatus() -> XTCalendarAuthorizationStatus
    func requestAccessIfNeeded() async -> XTCalendarAuthorizationStatus
}

private enum XTCalendarAuthorizationRequester {
    static func requestEventAccess(using store: EKEventStore) async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            } else {
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

struct XTEventKitCalendarAuthorizationClient: XTCalendarAuthorizationClient {
    func authorizationStatus() -> XTCalendarAuthorizationStatus {
        mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccessIfNeeded() async -> XTCalendarAuthorizationStatus {
        let current = authorizationStatus()
        if current.canReadEvents || current == .denied || current == .restricted {
            return current
        }

        let store = EKEventStore()
        _ = await XTCalendarAuthorizationRequester.requestEventAccess(using: store)
        for _ in 0..<12 {
            let refreshed = authorizationStatus()
            if refreshed.canReadEvents || refreshed == .denied || refreshed == .restricted || refreshed == .writeOnly {
                return refreshed
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return authorizationStatus()
    }

    private func mapAuthorizationStatus(_ status: EKAuthorizationStatus) -> XTCalendarAuthorizationStatus {
        if #available(macOS 14.0, *) {
            switch status {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .authorized:
                return .authorized
            case .fullAccess:
                return .fullAccess
            case .writeOnly:
                return .writeOnly
            @unknown default:
                return .unavailable
            }
        }

        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .fullAccess:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .unavailable
        }
    }
}

@MainActor
final class XTCalendarAccessController: ObservableObject {
    static let shared = XTCalendarAccessController()

    @Published private(set) var authorizationStatus: XTCalendarAuthorizationStatus
    @Published private(set) var lastErrorText: String = ""

    private let client: any XTCalendarAuthorizationClient
    private var authorizationStatusOverrideForTesting: XTCalendarAuthorizationStatus?

    init(client: any XTCalendarAuthorizationClient = XTEventKitCalendarAuthorizationClient()) {
        self.client = client
        self.authorizationStatus = client.authorizationStatus()
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = authorizationStatusOverrideForTesting ?? client.authorizationStatus()
        lastErrorText = authorizationStatus.canReadEvents ? "" : authorizationStatus.guidanceText
    }

    @discardableResult
    func requestAccessIfNeeded() async -> XTCalendarAuthorizationStatus {
        if let override = authorizationStatusOverrideForTesting {
            authorizationStatus = override
            lastErrorText = override.canReadEvents ? "" : override.guidanceText
            return override
        }
        let status = await client.requestAccessIfNeeded()
        authorizationStatus = status
        lastErrorText = status.canReadEvents ? "" : status.guidanceText
        return status
    }

    func installAuthorizationStatusOverrideForTesting(
        _ status: XTCalendarAuthorizationStatus?
    ) {
        authorizationStatusOverrideForTesting = status
        refreshAuthorizationStatus()
    }
}
