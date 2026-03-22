import Testing
@testable import XTerminal

@MainActor
struct XTCalendarAccessControllerTests {

    @Test
    func refreshAuthorizationStatusReflectsClientState() {
        let client = MockXTCalendarAuthorizationClient(
            currentStatus: .notDetermined,
            requestedStatus: .authorized
        )
        let controller = XTCalendarAccessController(client: client)

        #expect(controller.authorizationStatus == .notDetermined)

        client.currentStatus = .fullAccess
        controller.refreshAuthorizationStatus()

        #expect(controller.authorizationStatus == .fullAccess)
        #expect(controller.lastErrorText.isEmpty)
    }

    @Test
    func requestAccessPublishesGuidanceWhenPermissionStaysBlocked() async {
        let client = MockXTCalendarAuthorizationClient(
            currentStatus: .notDetermined,
            requestedStatus: .denied
        )
        let controller = XTCalendarAccessController(client: client)

        let status = await controller.requestAccessIfNeeded()

        #expect(status == .denied)
        #expect(controller.authorizationStatus == .denied)
        #expect(controller.lastErrorText.contains("Calendar access is denied"))
        #expect(client.requestCount == 1)
    }
}

private final class MockXTCalendarAuthorizationClient: XTCalendarAuthorizationClient {
    var currentStatus: XTCalendarAuthorizationStatus
    var requestedStatus: XTCalendarAuthorizationStatus
    private(set) var requestCount: Int = 0

    init(
        currentStatus: XTCalendarAuthorizationStatus,
        requestedStatus: XTCalendarAuthorizationStatus
    ) {
        self.currentStatus = currentStatus
        self.requestedStatus = requestedStatus
    }

    func authorizationStatus() -> XTCalendarAuthorizationStatus {
        currentStatus
    }

    func requestAccessIfNeeded() async -> XTCalendarAuthorizationStatus {
        requestCount += 1
        currentStatus = requestedStatus
        return currentStatus
    }
}
