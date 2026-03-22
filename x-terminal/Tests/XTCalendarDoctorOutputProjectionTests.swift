import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTCalendarDoctorOutputProjectionTests {
    @Test
    func projectsCalendarPermissionDeniedAsCriticalPermissionRepair() {
        let report = sampleCalendarDoctorReport(
            state: .permissionDenied,
            headline: "Calendar reminders cannot read meetings with the current permission state",
            summary: "Calendar access is denied. Open System Settings -> Privacy & Security -> Calendars and re-enable X-Terminal.",
            nextStep: "Restore Calendar read access in macOS Settings, then rerun Refresh Meetings and one live reminder smoke.",
            repairEntry: .systemPermissions,
            detailLines: [
                "calendar_permission_owner=xt_device_local",
                "hub_calendar_permission=request_blocked",
                "calendar_reminders_enabled=true",
                "calendar_authorization=denied",
                "calendar_authorization_can_read=false"
            ],
            overallState: .permissionDenied,
            overallSummary: "first task ready, but calendar reminder readiness still needs repair: Calendar reminders cannot read meetings with the current permission state",
            readyForFirstTask: true
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: report)
        let check = bundle.checks.first {
            $0.checkID == XTUnifiedDoctorSectionKind.calendarReminderReadiness.rawValue
        }
        let nextStep = bundle.nextSteps.first {
            $0.stepID == XTUnifiedDoctorSectionKind.calendarReminderReadiness.rawValue
        }

        #expect(bundle.readyForFirstTask == true)
        #expect(bundle.overallState == .blocked)
        #expect(check?.status == .fail)
        #expect(check?.severity == .critical)
        #expect(check?.blocking == true)
        #expect(check?.repairDestinationRef == UITroubleshootDestination.systemPermissions.rawValue)
        #expect(check?.detailLines.contains("calendar_permission_owner=xt_device_local") == true)
        #expect(check?.detailLines.contains("hub_calendar_permission=request_blocked") == true)
        #expect(nextStep?.kind == .reviewPermissions)
        #expect(nextStep?.owner == .user)
        #expect(nextStep?.destinationRef == UITroubleshootDestination.systemPermissions.rawValue)
    }

    @Test
    func keepsCalendarOffByChoiceAsPassWithoutExtraNextStep() {
        let report = sampleCalendarDoctorReport(
            state: .ready,
            headline: "XT-owned calendar reminder path is currently off by preference",
            summary: "Hub no longer requests Calendar permission. Personal meeting reminders remain device-local on this X-Terminal, and the feature is simply disabled right now instead of being broken.",
            nextStep: "If you want meeting reminders on this device, open Supervisor Settings -> Calendar Reminders and run the local smoke actions there.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "calendar_permission_owner=xt_device_local",
                "hub_calendar_permission=request_blocked",
                "calendar_reminders_enabled=false",
                "calendar_authorization=not_determined"
            ],
            overallState: .ready,
            overallSummary: "pairing, model route, tools, and session runtime are verified on one path",
            readyForFirstTask: true
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: report)
        let check = bundle.checks.first {
            $0.checkID == XTUnifiedDoctorSectionKind.calendarReminderReadiness.rawValue
        }
        let nextStep = bundle.nextSteps.first {
            $0.stepID == XTUnifiedDoctorSectionKind.calendarReminderReadiness.rawValue
        }

        #expect(bundle.readyForFirstTask == true)
        #expect(bundle.overallState == .ready)
        #expect(check?.status == .pass)
        #expect(check?.severity == .info)
        #expect(check?.blocking == false)
        #expect(check?.repairDestinationRef == UITroubleshootDestination.xtDiagnostics.rawValue)
        #expect(nextStep == nil)
    }
}

private func sampleCalendarDoctorReport(
    state: XTUISurfaceState,
    headline: String,
    summary: String,
    nextStep: String,
    repairEntry: UITroubleshootDestination,
    detailLines: [String],
    overallState: XTUISurfaceState,
    overallSummary: String,
    readyForFirstTask: Bool
) -> XTUnifiedDoctorReport {
    XTUnifiedDoctorReport(
        schemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
        generatedAtMs: 1_741_300_000,
        overallState: overallState,
        overallSummary: overallSummary,
        readyForFirstTask: readyForFirstTask,
        currentFailureCode: "",
        currentFailureIssue: nil,
        configuredModelRoles: 4,
        availableModelCount: 1,
        loadedModelCount: 1,
        currentSessionID: "session-1",
        currentRoute: XTUnifiedDoctorRouteSnapshot(
            transportMode: "local_fileipc",
            routeLabel: "local fileIPC",
            pairingPort: 50052,
            grpcPort: 50051,
            internetHost: "127.0.0.1"
        ),
        sections: [
            XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: state,
                headline: headline,
                summary: summary,
                nextStep: nextStep,
                repairEntry: repairEntry,
                detailLines: detailLines
            )
        ],
        consumedContracts: [],
        reportPath: "/tmp/xt_unified_doctor_report.json"
    )
}
