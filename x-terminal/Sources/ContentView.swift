import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var navigationFocusStore: XTNavigationFocusStore
    @Environment(\.openWindow) private var openWindow

    @State private var selectedPrimarySurface: XTPrimarySurface = .work
    @State private var preferredControlSection: XTControlSurfaceView.Section = .overview
    @State private var selectedControlSection: XTControlSurfaceView.Section = .overview
    @State private var showMemoryInspector: Bool = false
    @State private var showProjectSettings: Bool = false
    @State private var showHistoryPanel: Bool = false
    @State private var showCreateProject: Bool = false
    @State private var projectSettingsProjectId: String? = nil
    @State private var projectSettingsDestination: XTProjectGovernanceDestination = .overview
    @State private var workSurfaceMounted: Bool = true
    @State private var workSurfaceMountTask: Task<Void, Never>? = nil
    @State private var supervisorSurfaceMounted: Bool = false
    @State private var supervisorManagerPrewarmTask: Task<Void, Never>? = nil
    @State private var supervisorSurfaceMountTask: Task<Void, Never>? = nil
    @State private var supervisorSurfacePrewarmTask: Task<Void, Never>? = nil
    @State private var reviewSurfaceMounted: Bool = false
    @State private var reviewSurfaceMountTask: Task<Void, Never>? = nil
    @State private var controlSurfaceMounted: Bool = false
    @State private var controlSurfaceMountTask: Task<Void, Never>? = nil
    @State private var retainedWorkSurfaceAfterPrimarySwitch: Bool = false
    @State private var workSurfaceReleaseTask: Task<Void, Never>? = nil
    @State private var retainedReviewSurfaceAfterPrimarySwitch: Bool = false
    @State private var reviewSurfaceReleaseTask: Task<Void, Never>? = nil
    @State private var retainedControlSurfaceAfterPrimarySwitch: Bool = false
    @State private var controlSurfaceReleaseTask: Task<Void, Never>? = nil

    private static let supervisorManagerPrewarmDelayNanoseconds: UInt64 = 220_000_000
    private static let supervisorSurfaceMountDelayNanoseconds: UInt64 = 48_000_000
    private static let supervisorSurfacePrewarmDelayNanoseconds: UInt64 = 420_000_000
    private static let secondarySurfaceMountDelayNanoseconds: UInt64 = 48_000_000
    private static let inactiveSurfaceReleaseDelayNanoseconds: UInt64 = 48_000_000

    var body: some View {
        HSplitView {
            XTPrimarySidebarView(selectedPrimarySurface: selectedPrimarySurfaceBinding)
                .environment(\.xtAppModelReference, appModel)
                .environmentObject(appModel.projectListStore)

            surfacePane
        }
        .toolbar {
            ContentToolbar(
                selectedPrimarySurface: selectedPrimarySurface,
                showMemoryInspector: $showMemoryInspector,
                showHistoryPanel: $showHistoryPanel,
                showCreateProject: $showCreateProject,
                showProjectSettings: $showProjectSettings,
                projectSettingsProjectId: $projectSettingsProjectId,
                selectPrimarySurface: selectPrimarySurface,
                openControl: { section, focusSectionId in
                    openControl(section: section, focusSectionId: focusSectionId)
                }
            )
        }
        .sheet(isPresented: $showProjectSettings) {
            if let ctx = projectSettingsSheetContext {
                ProjectSettingsView(
                    ctx: ctx,
                    initialGovernanceDestination: projectSettingsDestination
                )
            }
        }
        .sheet(isPresented: $showCreateProject) {
            CreateProjectSheet()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .xterminalOpenHubSetupWizard)) { _ in
            openWindow(id: "hub_setup")
        }
        .onReceive(NotificationCenter.default.publisher(for: .xterminalOpenSupervisorWindow)) { notification in
            handleSupervisorWindowOpen(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .xterminalOpenSupervisorToolWindow)) { notification in
            handleSupervisorToolWindowOpen(notification)
        }
        .onAppear {
            scheduleSupervisorManagerPrewarmIfNeeded()
            scheduleSupervisorSurfacePrewarmIfNeeded()
        }
        .onDisappear {
            workSurfaceMountTask?.cancel()
            workSurfaceMountTask = nil
            supervisorManagerPrewarmTask?.cancel()
            supervisorManagerPrewarmTask = nil
            supervisorSurfaceMountTask?.cancel()
            supervisorSurfaceMountTask = nil
            supervisorSurfacePrewarmTask?.cancel()
            supervisorSurfacePrewarmTask = nil
            reviewSurfaceMountTask?.cancel()
            reviewSurfaceMountTask = nil
            controlSurfaceMountTask?.cancel()
            controlSurfaceMountTask = nil
            workSurfaceReleaseTask?.cancel()
            workSurfaceReleaseTask = nil
            reviewSurfaceReleaseTask?.cancel()
            reviewSurfaceReleaseTask = nil
            controlSurfaceReleaseTask?.cancel()
            controlSurfaceReleaseTask = nil
        }
        .onChange(of: showProjectSettings) { presented in
            if !presented {
                projectSettingsProjectId = nil
                projectSettingsDestination = .overview
            }
        }
        .onChange(of: navigationFocusSnapshot.projectSettingsFocusRequest?.nonce) { _ in
            selectPrimarySurface(.work)
            processProjectSettingsFocusRequest()
        }
        .onChange(of: navigationFocusSnapshot.settingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            openControl(section: .hub)
        }
        .onChange(of: navigationFocusSnapshot.modelSettingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            openControl(section: .models)
        }
        .onChange(of: navigationFocusSnapshot.supervisorSettingsFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            openControl(section: .supervisor)
        }
        .onChange(of: navigationFocusSnapshot.supervisorFocusRequest?.nonce) { nonce in
            guard nonce != nil else { return }
            selectPrimarySurface(.supervisor)
        }
    }

    private var surfacePane: some View {
        ZStack {
            if shouldRenderWorkSurface {
                workSurface
                    .opacity(selectedPrimarySurface == .work ? 1 : 0)
                    .allowsHitTesting(selectedPrimarySurface == .work)
                    .accessibilityHidden(selectedPrimarySurface != .work)
                    .zIndex(selectedPrimarySurface == .work ? 2 : 0)
            }

            if shouldRenderSupervisorSurface {
                supervisorSurface
                    .opacity(selectedPrimarySurface == .supervisor ? 1 : 0)
                    .allowsHitTesting(selectedPrimarySurface == .supervisor)
                    .accessibilityHidden(selectedPrimarySurface != .supervisor)
                    .zIndex(selectedPrimarySurface == .supervisor ? 3 : 0)
            }

            if shouldRenderReviewSurface {
                reviewSurface
                    .opacity(selectedPrimarySurface == .review ? 1 : 0)
                    .allowsHitTesting(selectedPrimarySurface == .review)
                    .accessibilityHidden(selectedPrimarySurface != .review)
                    .zIndex(selectedPrimarySurface == .review ? 3 : 0)
            }

            if shouldRenderControlSurface {
                controlSurface
                    .opacity(selectedPrimarySurface == .control ? 1 : 0)
                    .allowsHitTesting(selectedPrimarySurface == .control)
                    .accessibilityHidden(selectedPrimarySurface != .control)
                    .zIndex(selectedPrimarySurface == .control ? 3 : 0)
            }

            if selectedPrimarySurface == .supervisor, !supervisorSurfaceMounted {
                SupervisorSurfaceWarmupView()
                    .onAppear {
                        scheduleSupervisorSurfaceMountIfNeeded()
                    }
                    .zIndex(3)
            } else if selectedPrimarySurface == .work, !workSurfaceMounted {
                PrimarySurfaceWarmupView(surface: .work)
                    .onAppear {
                        scheduleWorkSurfaceMountIfNeeded()
                    }
                    .zIndex(3)
            } else if selectedPrimarySurface == .review, !reviewSurfaceMounted {
                PrimarySurfaceWarmupView(surface: .review)
                    .onAppear {
                        scheduleReviewSurfaceMountIfNeeded()
                    }
                    .zIndex(3)
            } else if selectedPrimarySurface == .control, !controlSurfaceMounted {
                PrimarySurfaceWarmupView(surface: .control)
                    .onAppear {
                        scheduleControlSurfaceMountIfNeeded()
                    }
                    .zIndex(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldRenderWorkSurface: Bool {
        workSurfaceMounted || retainedWorkSurfaceAfterPrimarySwitch
    }

    private var shouldRenderSupervisorSurface: Bool {
        supervisorSurfaceMounted
    }

    private var shouldRenderReviewSurface: Bool {
        reviewSurfaceMounted || retainedReviewSurfaceAfterPrimarySwitch
    }

    private var shouldRenderControlSurface: Bool {
        controlSurfaceMounted || retainedControlSurfaceAfterPrimarySwitch
    }

    @ViewBuilder
    private var workSurface: some View {
        if (selectedPrimarySurface == .work && workSurfaceMounted) || retainedWorkSurfaceAfterPrimarySwitch {
            ContentWorkSurfaceHost(
                showHistoryPanel: showHistoryPanel,
                showMemoryInspector: showMemoryInspector
            )
        } else {
            XTInactiveWorkSurfacePlaceholder()
        }
    }

    private var supervisorSurface: some View {
        SupervisorView(isPrewarming: selectedPrimarySurface != .supervisor)
    }

    @ViewBuilder
    private var reviewSurface: some View {
        if (selectedPrimarySurface == .review && reviewSurfaceMounted) || retainedReviewSurfaceAfterPrimarySwitch {
            XTReviewSurfaceView(
                onOpenSupervisor: { selectPrimarySurface(.supervisor) },
                onOpenControl: { openControl(section: .hub) }
            )
        } else {
            XTInactiveReviewSurfacePlaceholder()
        }
    }

    @ViewBuilder
    private var controlSurface: some View {
        if (selectedPrimarySurface == .control && controlSurfaceMounted) || retainedControlSurfaceAfterPrimarySwitch {
            XTControlSurfaceView(
                preferredSection: preferredControlSection,
                selectedSection: $selectedControlSection
            )
        } else {
            XTInactiveControlSurfacePlaceholder()
        }
    }

    private var navigationFocusSnapshot: XTNavigationFocusSnapshot {
        navigationFocusStore.snapshot
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ContentView requires xtAppModelReference")
        }
        return appModelReference
    }

    private var selectedPrimarySurfaceBinding: Binding<XTPrimarySurface> {
        Binding(
            get: { selectedPrimarySurface },
            set: { selectPrimarySurface($0) }
        )
    }

    private func selectPrimarySurface(_ surface: XTPrimarySurface) {
        guard selectedPrimarySurface != surface else {
            if surface == .supervisor {
                XTPerformanceTrace.event(
                    "XT Surface Selection Reused",
                    surface.rawValue
                )
                scheduleSupervisorSurfaceMountIfNeeded()
            }
            return
        }
        let previous = selectedPrimarySurface
        XTPerformanceTrace.event(
            "XT Surface Selection Requested",
            "\(previous.rawValue)->\(surface.rawValue)"
        )
        retainPreviousSurfaceDuringPrimarySwitch(previous: previous, next: surface)

        selectedPrimarySurface = surface
        releaseRetainedSurfaceIfReturning(to: surface)
        XTPerformanceTrace.event(
            "XT Surface Selection Applied",
            surface.rawValue
        )

        if surface == .work {
            scheduleWorkSurfaceMountIfNeeded()
            cancelSupervisorSurfaceMount()
            cancelReviewSurfaceMount()
            cancelControlSurfaceMount()
        } else if surface == .supervisor {
            scheduleSupervisorSurfaceMountIfNeeded()
            cancelWorkSurfaceMount()
            cancelReviewSurfaceMount()
            cancelControlSurfaceMount()
        } else if surface == .review {
            scheduleReviewSurfaceMountIfNeeded()
            cancelWorkSurfaceMount()
            cancelSupervisorSurfaceMount()
            cancelControlSurfaceMount()
        } else if surface == .control {
            scheduleControlSurfaceMountIfNeeded()
            cancelWorkSurfaceMount()
            cancelSupervisorSurfaceMount()
            cancelReviewSurfaceMount()
        }
    }

    private func retainPreviousSurfaceDuringPrimarySwitch(
        previous: XTPrimarySurface,
        next: XTPrimarySurface
    ) {
        guard previous != next else { return }
        switch previous {
        case .work:
            retainWorkSurfaceDuringPrimarySwitch()
        case .review:
            retainReviewSurfaceDuringPrimarySwitch()
        case .control:
            retainControlSurfaceDuringPrimarySwitch()
        case .supervisor:
            break
        }
    }

    private func releaseRetainedSurfaceIfReturning(to surface: XTPrimarySurface) {
        switch surface {
        case .work:
            releaseRetainedWorkSurface(cancelOnly: true)
        case .review:
            releaseRetainedReviewSurface(cancelOnly: true)
        case .control:
            releaseRetainedControlSurface(cancelOnly: true)
        case .supervisor:
            break
        }
    }

    private func retainWorkSurfaceDuringPrimarySwitch() {
        guard workSurfaceMounted else { return }
        retainedWorkSurfaceAfterPrimarySwitch = true
        workSurfaceReleaseTask?.cancel()
        XTPerformanceTrace.event(
            "XT Work Surface Retain Scheduled",
            "delay_ms=48"
        )
        workSurfaceReleaseTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.inactiveSurfaceReleaseDelayNanoseconds)
            guard !Task.isCancelled else {
                workSurfaceReleaseTask = nil
                return
            }
            guard selectedPrimarySurface != .work else {
                releaseRetainedWorkSurface(cancelOnly: true)
                return
            }
            retainedWorkSurfaceAfterPrimarySwitch = false
            workSurfaceMounted = false
            workSurfaceReleaseTask = nil
            XTPerformanceTrace.event("XT Work Surface Retain Released")
        }
    }

    private func releaseRetainedWorkSurface(cancelOnly: Bool = false) {
        workSurfaceReleaseTask?.cancel()
        workSurfaceReleaseTask = nil
        if !cancelOnly {
            retainedWorkSurfaceAfterPrimarySwitch = false
            workSurfaceMounted = selectedPrimarySurface == .work
        } else if selectedPrimarySurface == .work {
            retainedWorkSurfaceAfterPrimarySwitch = false
        }
    }

    private func retainReviewSurfaceDuringPrimarySwitch() {
        guard reviewSurfaceMounted else { return }
        retainedReviewSurfaceAfterPrimarySwitch = true
        reviewSurfaceReleaseTask?.cancel()
        XTPerformanceTrace.event(
            "XT Review Surface Retain Scheduled",
            "delay_ms=48"
        )
        reviewSurfaceReleaseTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.inactiveSurfaceReleaseDelayNanoseconds)
            guard !Task.isCancelled else {
                reviewSurfaceReleaseTask = nil
                return
            }
            guard selectedPrimarySurface != .review else {
                releaseRetainedReviewSurface(cancelOnly: true)
                return
            }
            retainedReviewSurfaceAfterPrimarySwitch = false
            reviewSurfaceMounted = false
            reviewSurfaceReleaseTask = nil
            XTPerformanceTrace.event("XT Review Surface Retain Released")
        }
    }

    private func releaseRetainedReviewSurface(cancelOnly: Bool = false) {
        reviewSurfaceReleaseTask?.cancel()
        reviewSurfaceReleaseTask = nil
        if !cancelOnly {
            retainedReviewSurfaceAfterPrimarySwitch = false
            reviewSurfaceMounted = selectedPrimarySurface == .review
        } else if selectedPrimarySurface == .review {
            retainedReviewSurfaceAfterPrimarySwitch = false
        }
    }

    private func retainControlSurfaceDuringPrimarySwitch() {
        guard controlSurfaceMounted else { return }
        retainedControlSurfaceAfterPrimarySwitch = true
        controlSurfaceReleaseTask?.cancel()
        XTPerformanceTrace.event(
            "XT Control Surface Retain Scheduled",
            "delay_ms=48"
        )
        controlSurfaceReleaseTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.inactiveSurfaceReleaseDelayNanoseconds)
            guard !Task.isCancelled else {
                controlSurfaceReleaseTask = nil
                return
            }
            guard selectedPrimarySurface != .control else {
                releaseRetainedControlSurface(cancelOnly: true)
                return
            }
            retainedControlSurfaceAfterPrimarySwitch = false
            controlSurfaceMounted = false
            controlSurfaceReleaseTask = nil
            XTPerformanceTrace.event("XT Control Surface Retain Released")
        }
    }

    private func releaseRetainedControlSurface(cancelOnly: Bool = false) {
        controlSurfaceReleaseTask?.cancel()
        controlSurfaceReleaseTask = nil
        if !cancelOnly {
            retainedControlSurfaceAfterPrimarySwitch = false
            controlSurfaceMounted = selectedPrimarySurface == .control
        } else if selectedPrimarySurface == .control {
            retainedControlSurfaceAfterPrimarySwitch = false
        }
    }

    private func scheduleWorkSurfaceMountIfNeeded() {
        guard selectedPrimarySurface == .work,
              !workSurfaceMounted,
              workSurfaceMountTask == nil else {
            return
        }
        XTPerformanceTrace.event("XT Work Mount Scheduled", "delay_ms=48")
        workSurfaceMountTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.secondarySurfaceMountDelayNanoseconds)
            guard !Task.isCancelled,
                  selectedPrimarySurface == .work else {
                XTPerformanceTrace.event("XT Work Mount Cancelled")
                workSurfaceMountTask = nil
                return
            }
            workSurfaceMountTask = nil
            workSurfaceMounted = true
            XTPerformanceTrace.event("XT Work Mount Committed")
        }
    }

    private func cancelWorkSurfaceMount() {
        workSurfaceMountTask?.cancel()
        workSurfaceMountTask = nil
    }

    private func cancelSupervisorSurfaceMount() {
        supervisorSurfaceMountTask?.cancel()
        supervisorSurfaceMountTask = nil
    }

    private func cancelReviewSurfaceMount() {
        reviewSurfaceMountTask?.cancel()
        reviewSurfaceMountTask = nil
    }

    private func cancelControlSurfaceMount() {
        controlSurfaceMountTask?.cancel()
        controlSurfaceMountTask = nil
    }

    private func scheduleSupervisorManagerPrewarmIfNeeded() {
        guard supervisorManagerPrewarmTask == nil else {
            return
        }
        XTPerformanceTrace.event("XT Supervisor Manager Prewarm Scheduled", "delay_ms=220")
        supervisorManagerPrewarmTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.supervisorManagerPrewarmDelayNanoseconds)
            guard !Task.isCancelled else {
                supervisorManagerPrewarmTask = nil
                return
            }
            SupervisorManager.shared.setAppModel(appModel)
            supervisorManagerPrewarmTask = nil
            XTPerformanceTrace.event("XT Supervisor Manager Prewarm Committed")
        }
    }

    private func scheduleSupervisorSurfaceMountIfNeeded() {
        guard selectedPrimarySurface == .supervisor,
              !supervisorSurfaceMounted,
              supervisorSurfaceMountTask == nil else {
            return
        }
        XTPerformanceTrace.event("XT Supervisor Mount Needed", "surface=supervisor")
        scheduleSupervisorSurfaceMount()
    }

    private func scheduleSupervisorSurfaceMount() {
        supervisorSurfacePrewarmTask?.cancel()
        supervisorSurfacePrewarmTask = nil
        supervisorSurfaceMountTask?.cancel()
        supervisorSurfaceMounted = false
        XTPerformanceTrace.event("XT Supervisor Mount Scheduled", "delay_ms=48")
        supervisorSurfaceMountTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.supervisorSurfaceMountDelayNanoseconds)
            guard !Task.isCancelled,
                  selectedPrimarySurface == .supervisor else {
                XTPerformanceTrace.event("XT Supervisor Mount Cancelled")
                supervisorSurfaceMountTask = nil
                return
            }
            supervisorSurfaceMountTask = nil
            supervisorSurfaceMounted = true
            XTPerformanceTrace.event("XT Supervisor Mount Committed")
        }
    }

    private func scheduleReviewSurfaceMountIfNeeded() {
        guard selectedPrimarySurface == .review,
              !reviewSurfaceMounted,
              reviewSurfaceMountTask == nil else {
            return
        }
        XTPerformanceTrace.event("XT Review Mount Scheduled", "delay_ms=48")
        reviewSurfaceMountTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.secondarySurfaceMountDelayNanoseconds)
            guard !Task.isCancelled,
                  selectedPrimarySurface == .review else {
                XTPerformanceTrace.event("XT Review Mount Cancelled")
                reviewSurfaceMountTask = nil
                return
            }
            reviewSurfaceMountTask = nil
            reviewSurfaceMounted = true
            XTPerformanceTrace.event("XT Review Mount Committed")
        }
    }

    private func scheduleControlSurfaceMountIfNeeded() {
        guard selectedPrimarySurface == .control,
              !controlSurfaceMounted,
              controlSurfaceMountTask == nil else {
            return
        }
        XTPerformanceTrace.event("XT Control Mount Scheduled", "delay_ms=48")
        controlSurfaceMountTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.secondarySurfaceMountDelayNanoseconds)
            guard !Task.isCancelled,
                  selectedPrimarySurface == .control else {
                XTPerformanceTrace.event("XT Control Mount Cancelled")
                controlSurfaceMountTask = nil
                return
            }
            controlSurfaceMountTask = nil
            controlSurfaceMounted = true
            XTPerformanceTrace.event("XT Control Mount Committed")
        }
    }

    private func scheduleSupervisorSurfacePrewarmIfNeeded() {
        guard !supervisorSurfaceMounted,
              supervisorSurfaceMountTask == nil,
              supervisorSurfacePrewarmTask == nil else {
            return
        }
        XTPerformanceTrace.event("XT Supervisor Prewarm Scheduled", "delay_ms=420")
        supervisorSurfacePrewarmTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.supervisorSurfacePrewarmDelayNanoseconds)
            guard !Task.isCancelled else {
                supervisorSurfacePrewarmTask = nil
                return
            }
            supervisorSurfacePrewarmTask = nil
            guard !supervisorSurfaceMounted else { return }
            supervisorSurfaceMounted = true
            XTPerformanceTrace.event("XT Supervisor Prewarm Committed")
        }
    }

    private var projectSettingsSheetContext: AXProjectContext? {
        if let projectSettingsProjectId,
           let ctx = appModel.projectContext(for: projectSettingsProjectId) {
            return ctx
        }
        return appModel.workSurfaceStore.snapshot.projectContext
    }

    private func openControl(
        section: XTControlSurfaceView.Section,
        focusSectionId: String? = nil
    ) {
        preferredControlSection = section
        selectedControlSection = section
        selectPrimarySurface(.control)

        if let focusSectionId {
            appModel.requestSettingsFocus(sectionId: focusSectionId)
        }
    }

    private func processProjectSettingsFocusRequest() {
        guard let request = navigationFocusSnapshot.projectSettingsFocusRequest else { return }
        projectSettingsProjectId = request.projectId
        projectSettingsDestination = request.destination
        showProjectSettings = true
    }

    private func handleSupervisorWindowOpen(_ notification: Notification) {
        let request = SupervisorConversationWindowOpenRequest(notification: notification)
        let decision = XTSupervisorWindowPresentationPolicy.decision(
            for: request,
            isWindowVisible: XTSupervisorWindowVisibilityRegistry.shared.isWindowVisible
        )
        guard decision.shouldOpenWindow else { return }
        openWindow(id: "supervisor")
    }

    private func handleSupervisorToolWindowOpen(_ notification: Notification) {
        guard let rawValue = notification.userInfo?["sheet_id"] as? String,
              let sheet = SupervisorManager.SupervisorWindowSheet(rawValue: rawValue) else {
            return
        }
        openWindow(id: sheet.windowID)
    }

    private func handleDeepLink(_ url: URL) {
        guard let route = XTDeepLinkParser.parse(url) else { return }

        let openSupervisor: (XTSupervisorWindowOpenIntent) -> Void = { intent in
            SupervisorManager.shared.requestSupervisorWindow(
                reason: intent.reason,
                focusConversation: intent.focusConversation,
                startConversation: intent.startConversation
            )
        }
        let openSupervisorSettings: () -> Void = {
            openControl(section: .supervisor)
        }
        let openSupervisorModelSettings: (_ route: XTSupervisorModelSettingsRoute) -> Void = { route in
            appModel.requestModelSettingsFocus(
                title: route.title,
                detail: route.detail
            )
            openControl(section: .models)
        }

        switch route {
        case let .supervisor(supervisorRoute):
            applyDeepLinkActionPlan(
                XTDeepLinkActionPlanner.plan(for: supervisorRoute),
                openSupervisor: openSupervisor
            )
        case let .hubSetup(hubSetupRoute):
            if let pairingPrefill = hubSetupRoute.pairingPrefill {
                appModel.applyHubPairingInvitePrefill(pairingPrefill)
            }
            let hubSetupSectionId = hubSetupRoute.sectionId
                ?? (hubSetupRoute.pairingPrefill == nil ? nil : "pair_hub")
            if let sectionId = hubSetupRoute.sectionId {
                appModel.requestHubSetupFocus(
                    sectionId: sectionId,
                    title: resolvedHubSetupTitle(hubSetupRoute),
                    detail: resolvedHubSetupDetail(hubSetupRoute),
                    refreshAction: hubSetupRoute.refreshAction,
                    refreshReason: hubSetupRoute.refreshReason
                )
            } else if let sectionId = hubSetupSectionId {
                appModel.requestHubSetupFocus(
                    sectionId: sectionId,
                    title: resolvedHubSetupTitle(hubSetupRoute),
                    detail: resolvedHubSetupDetail(hubSetupRoute),
                    refreshAction: hubSetupRoute.refreshAction,
                    refreshReason: hubSetupRoute.refreshReason
                )
            }
            openWindow(id: "hub_setup")
        case let .settings(settingsRoute):
            if let sectionId = settingsRoute.sectionId {
                appModel.requestSettingsFocus(
                    sectionId: sectionId,
                    title: settingsRoute.title,
                    detail: settingsRoute.detail,
                    refreshAction: settingsRoute.refreshAction,
                    refreshReason: settingsRoute.refreshReason
                )
            }
            openControl(section: .hub)
        case .supervisorSettings:
            openSupervisorSettings()
        case let .supervisorModelSettings(route):
            openSupervisorModelSettings(route)
        case let .resume(projectId):
            selectPrimarySurface(.work)
            if let projectId {
                appModel.presentResumeBrief(projectId: projectId)
            } else {
                appModel.presentPreferredResumeBrief()
            }
        case let .project(projectRoute):
            selectPrimarySurface(.work)
            let actionPlan = XTDeepLinkActionPlanner.plan(for: projectRoute)
            let projectId = projectRoute.projectId ?? ""

            if projectRoute.resumeRequested {
                if !projectId.isEmpty {
                    appModel.presentResumeBrief(projectId: projectId)
                } else {
                    appModel.presentPreferredResumeBrief()
                }
            }

            applyDeepLinkActionPlan(actionPlan, openSupervisor: openSupervisor)

            if projectRoute.openTarget == .supervisorSettings {
                openSupervisorSettings()
            }

            if !projectId.isEmpty, let governanceDestination = projectRoute.governanceDestination {
                appModel.requestProjectSettingsFocus(
                    projectId: projectId,
                    destination: governanceDestination
                )
            }
        }
    }

    private func applyDeepLinkActionPlan(
        _ plan: XTDeepLinkActionPlan,
        openSupervisor: (XTSupervisorWindowOpenIntent) -> Void
    ) {
        XTDeepLinkActionExecutor.execute(
            plan,
            appModel: appModel,
            openSupervisor: openSupervisor
        )
    }

    private func resolvedHubSetupTitle(_ route: XTHubSetupRoute) -> String? {
        if let title = route.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        guard route.pairingPrefill != nil else { return nil }
        return "已载入 Hub 邀请"
    }

    private func resolvedHubSetupDetail(_ route: XTHubSetupRoute) -> String? {
        if let detail = route.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            return detail
        }
        guard let prefill = route.pairingPrefill else { return nil }
        let alias = prefill.hubAlias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let host = prefill.internetHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasInviteToken = prefill.inviteToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if !alias.isEmpty && !host.isEmpty {
            return "Hub alias: \(alias) · host: \(host)" + (hasInviteToken ? " · invite token ready" : "")
        }
        if !alias.isEmpty {
            return "Hub alias: \(alias)"
        }
        if !host.isEmpty {
            return "host: \(host)" + (hasInviteToken ? " · invite token ready" : "")
        }
        return "Pair Hub 参数已从邀请链接自动填入。"
    }
}

private struct ContentToolbar: ToolbarContent {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var projectListStore: XTProjectListStore

    let selectedPrimarySurface: XTPrimarySurface
    @Binding var showMemoryInspector: Bool
    @Binding var showHistoryPanel: Bool
    @Binding var showCreateProject: Bool
    @Binding var showProjectSettings: Bool
    @Binding var projectSettingsProjectId: String?
    let selectPrimarySurface: (XTPrimarySurface) -> Void
    let openControl: (XTControlSurfaceView.Section, String?) -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                performOpenProjectToolbarAction()
            } label: {
                Label(openProjectToolbarTitle, systemImage: openProjectToolbarSystemImage)
            }
            .help(openProjectToolbarHelp)
        }

        ContentResumeToolbarItems(selectPrimarySurface: selectPrimarySurface)

        ContentWorkToolbarItems(
            selectedPrimarySurface: selectedPrimarySurface,
            showMemoryInspector: $showMemoryInspector,
            showHistoryPanel: $showHistoryPanel,
            showCreateProject: $showCreateProject,
            showProjectSettings: $showProjectSettings,
            projectSettingsProjectId: $projectSettingsProjectId
        )

        ContentControlToolbarItems(openControl: openControl)
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ContentToolbar requires xtAppModelReference")
        }
        return appModelReference
    }

    private var openProjectToolbarTitle: String {
        hasCurrentConcreteProject ? "Open Project Folder" : "Open Project..."
    }

    private var openProjectToolbarSystemImage: String {
        hasCurrentConcreteProject ? "folder" : "folder.badge.plus"
    }

    private var openProjectToolbarHelp: String {
        hasCurrentConcreteProject
            ? "Open the current project folder in Finder"
            : "Choose an existing folder and add it as an XT project"
    }

    private var hasCurrentConcreteProject: Bool {
        (concreteProjectId(appModel.selectedProjectId) ?? concreteProjectId(projectListStore.snapshot.selectedProjectId)) != nil
            && appModel.currentProjectFolderURLForOpening() != nil
    }

    private func performOpenProjectToolbarAction() {
        if hasCurrentConcreteProject {
            appModel.openCurrentProjectFolder()
            return
        }

        selectPrimarySurface(.work)
        appModel.openProjectPicker()
    }

    private func concreteProjectId(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return trimmed
    }
}

private struct ContentResumeToolbarItems: ToolbarContent {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var globalHomeStore: XTGlobalHomeStore

    let selectPrimarySurface: (XTPrimarySurface) -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                selectPrimarySurface(.work)
                if let target = toolbarResumeTarget {
                    appModel.presentResumeBrief(projectId: target.projectId)
                }
            } label: {
                Label("接上次进度", systemImage: "arrow.clockwise.circle")
            }
            .help(toolbarResumeHelp)
            .disabled(toolbarResumeTarget == nil)
        }
    }

    private var toolbarResumeTarget: AXResumeReminderProjectPresentation? {
        globalHomeStore.snapshot.preferredResumeProject
    }

    private var toolbarResumeHelp: String {
        guard let target = toolbarResumeTarget else {
            return "当前没有可恢复的交接摘要"
        }
        return "接上次进度：\(target.projectDisplayName) · \(target.summary.detailText)。只会在你点击后展开，不会自动塞进当前 prompt。"
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ContentResumeToolbarItems requires xtAppModelReference")
        }
        return appModelReference
    }
}

private struct ContentWorkToolbarItems: ToolbarContent {
    let selectedPrimarySurface: XTPrimarySurface
    @Binding var showMemoryInspector: Bool
    @Binding var showHistoryPanel: Bool
    @Binding var showCreateProject: Bool
    @Binding var showProjectSettings: Bool
    @Binding var projectSettingsProjectId: String?

    var body: some ToolbarContent {
        if selectedPrimarySurface == .work {
            ContentActiveWorkToolbarItems(
                showMemoryInspector: $showMemoryInspector,
                showHistoryPanel: $showHistoryPanel,
                showCreateProject: $showCreateProject,
                showProjectSettings: $showProjectSettings,
                projectSettingsProjectId: $projectSettingsProjectId
            )
        }
    }
}

private struct ContentActiveWorkToolbarItems: ToolbarContent {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @EnvironmentObject private var workSurfaceStore: XTWorkSurfaceStore
    @EnvironmentObject private var projectListStore: XTProjectListStore

    @Binding var showMemoryInspector: Bool
    @Binding var showHistoryPanel: Bool
    @Binding var showCreateProject: Bool
    @Binding var showProjectSettings: Bool
    @Binding var projectSettingsProjectId: String?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if hubConnectionSnapshot.interactive {
                Divider()

                Button {
                    appModel.toggleMultiProjectView()
                } label: {
                    Image(systemName: workSurfaceSnapshot.isMultiProjectViewEnabled ? "square.grid.2x2" : "square")
                }
                .help(workSurfaceSnapshot.isMultiProjectViewEnabled ? "Switch to Single Project View" : "Switch to Multi-Project View")

                if workSurfaceSnapshot.isMultiProjectViewEnabled {
                    Button {
                        showCreateProject = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .help("Create New Project")
                }
            }

            if shouldShowWorkToolbarTools {
                Divider()

                Button {
                    showHistoryPanel.toggle()
                } label: {
                    Image(systemName: "clock")
                }
                .help("Toggle History Panel")

                Button {
                    showMemoryInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Memory Inspector")

                Button {
                    projectSettingsProjectId = workSurfaceSnapshot.selectedProjectId
                    showProjectSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Project Settings")
                .disabled(!canOpenProjectSettings)

                if let pid = currentWorkProjectId {
                    Picker(
                        "",
                        selection: Binding(
                            get: {
                                workSurfaceSnapshot.selectedProjectId == pid
                                    ? workSurfaceSnapshot.selectedPane
                                    : appModel.pane(for: pid)
                            },
                            set: { appModel.setPane($0, for: pid) }
                        )
                    ) {
                        Text("Chat").tag(AXProjectPane.chat)
                        Text("Terminal").tag(AXProjectPane.terminal)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .help("Project Pane")
                }
            }
        }
    }

    private var shouldShowWorkToolbarTools: Bool {
        currentWorkProjectId != nil
    }

    private var canOpenProjectSettings: Bool {
        currentWorkProjectId != nil
    }

    private var currentWorkProjectId: String? {
        concreteProjectId(workSurfaceSnapshot.selectedProjectId)
            ?? concreteProjectId(projectListStore.snapshot.selectedProjectId)
    }

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var workSurfaceSnapshot: XTWorkSurfaceSnapshot {
        workSurfaceStore.snapshot
    }

    private func concreteProjectId(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return trimmed
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ContentActiveWorkToolbarItems requires xtAppModelReference")
        }
        return appModelReference
    }
}

private struct ContentControlToolbarItems: ToolbarContent {
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore

    let openControl: (XTControlSurfaceView.Section, String?) -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Divider()

            Button {
                if hubConnectionSnapshot.interactive {
                    openControl(.hub, nil)
                } else {
                    openControl(.hub, "pair_hub")
                }
            } label: {
                Label(controlButtonTitle, systemImage: controlButtonIconName)
            }
            .keyboardShortcut("x", modifiers: [.command, .option])
            .help(controlButtonHelp)
        }
    }

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var controlButtonIconName: String {
        XTHubConnectionPresentation.controlButtonIconName(for: hubConnectionSnapshot)
    }

    private var controlButtonTitle: String {
        XTHubConnectionPresentation.controlButtonTitle(for: hubConnectionSnapshot)
    }

    private var controlButtonHelp: String {
        XTHubConnectionPresentation.controlButtonHelp(for: hubConnectionSnapshot)
    }
}

private struct ContentWorkSurfaceHost: View {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @EnvironmentObject private var workSurfaceStore: XTWorkSurfaceStore
    @EnvironmentObject private var projectListStore: XTProjectListStore

    let showHistoryPanel: Bool
    let showMemoryInspector: Bool

    var body: some View {
        HSplitView {
            workMainPane

            if shouldShowHistoryPanel, let ctx = effectiveProjectContext {
                HistoryPanelView(ctx: ctx, session: appModel.session(for: ctx))
                    .frame(minWidth: 300, maxWidth: 400)
            }

            if shouldShowMemoryInspector, let ctx = effectiveProjectContext {
                MemoryInspectorView(ctx: ctx, memory: effectiveProjectMemory)
            }
        }
    }

    private var workMainPane: some View {
        VStack(spacing: 0) {
            if shouldShowMultiProjectGrid {
                ProjectsGridView(projectsManager: appModel.legacyMultiProjectManager)
            } else if isEffectiveGlobalHomeSelected {
                GlobalHomeView()
            } else if let ctx = effectiveProjectContext {
                if effectiveSelectedPane == .terminal {
                    ProjectTerminalView(ctx: ctx, session: appModel.terminalSession(for: ctx))
                } else {
                    ModernChatView(
                        ctx: ctx,
                        memory: effectiveProjectMemory,
                        config: effectiveProjectConfig,
                        hubConnected: hubConnectionSnapshot.interactive,
                        session: appModel.session(for: ctx)
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Work")
                        .font(.title2)
                    Text("从左侧项目列表进入工作台；系统级设置和审查入口已经移到其它一级面。")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var shouldShowHistoryPanel: Bool {
        showHistoryPanel &&
            effectiveProjectContext != nil &&
            !shouldShowMultiProjectGrid
    }

    private var shouldShowMemoryInspector: Bool {
        showMemoryInspector &&
            effectiveProjectContext != nil &&
            !shouldShowMultiProjectGrid
    }

    private var shouldShowMultiProjectGrid: Bool {
        workSurfaceSnapshot.isMultiProjectViewEnabled &&
            hubConnectionSnapshot.interactive &&
            effectiveSelectedConcreteProjectId == nil
    }

    private var isEffectiveGlobalHomeSelected: Bool {
        effectiveSelectedConcreteProjectId == nil &&
            (
                workSurfaceSnapshot.selectedProjectId == AXProjectRegistry.globalHomeId ||
                projectListStore.snapshot.selectedProjectId == AXProjectRegistry.globalHomeId
            )
    }

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var workSurfaceSnapshot: XTWorkSurfaceSnapshot {
        workSurfaceStore.snapshot
    }

    private var effectiveProjectContext: AXProjectContext? {
        guard let selectedProjectId = effectiveSelectedConcreteProjectId else {
            return nil
        }
        if let projectContext = workSurfaceSnapshot.projectContext,
           projectId(for: projectContext) == selectedProjectId {
            return projectContext
        }
        return appModel.projectContext(for: selectedProjectId)
    }

    private var effectiveProjectMemory: AXMemory? {
        guard let ctx = effectiveProjectContext,
              let snapshotContext = workSurfaceSnapshot.projectContext,
              snapshotContext.root.standardizedFileURL.path == ctx.root.standardizedFileURL.path else {
            return nil
        }
        return workSurfaceSnapshot.memory
    }

    private var effectiveProjectConfig: AXProjectConfig? {
        guard let ctx = effectiveProjectContext,
              let snapshotContext = workSurfaceSnapshot.projectContext,
              snapshotContext.root.standardizedFileURL.path == ctx.root.standardizedFileURL.path else {
            return nil
        }
        return workSurfaceSnapshot.projectConfig
    }

    private var effectiveSelectedPane: AXProjectPane {
        guard let selectedProjectId = effectiveSelectedConcreteProjectId else {
            return .chat
        }
        if workSurfaceSnapshot.selectedProjectId == selectedProjectId {
            return workSurfaceSnapshot.selectedPane
        }
        return appModel.pane(for: selectedProjectId)
    }

    private var effectiveSelectedConcreteProjectId: String? {
        concreteProjectId(workSurfaceSnapshot.selectedProjectId)
            ?? concreteProjectId(projectListStore.snapshot.selectedProjectId)
            ?? concreteProjectId(appModel.selectedProjectId)
    }

    private func concreteProjectId(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return trimmed
    }

    private func projectId(for ctx: AXProjectContext) -> String {
        AXProjectRegistryStore.projectId(forRoot: ctx.root)
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ContentWorkSurfaceHost requires xtAppModelReference")
        }
        return appModelReference
    }
}

private struct XTInactiveWorkSurfacePlaceholder: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 720, minHeight: 520)
    }
}

private struct XTInactiveReviewSurfacePlaceholder: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 820, minHeight: 620)
    }
}

private struct XTInactiveControlSurfacePlaceholder: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 900, minHeight: 700)
    }
}

private struct SupervisorSurfaceWarmupView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("正在打开 Supervisor")
                .font(.headline)
            Text("先切换导航，再挂载总控面板。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            XTPerformanceTrace.event("XT Supervisor Warmup Appeared")
        }
    }
}

private struct PrimarySurfaceWarmupView: View {
    let surface: XTPrimarySurface

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("正在打开 \(surface.title)")
                .font(.headline)
            Text("先响应导航，再挂载面板。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            XTPerformanceTrace.event(
                "XT Primary Surface Warmup Appeared",
                surface.rawValue
            )
        }
    }
}
