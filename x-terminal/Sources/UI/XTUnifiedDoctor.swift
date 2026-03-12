import Foundation
import SwiftUI

enum XTUnifiedDoctorSectionKind: String, CaseIterable, Codable, Sendable {
    case hubReachability = "hub_reachability"
    case pairingValidity = "pairing_validity"
    case modelRouteReadiness = "model_route_readiness"
    case bridgeToolReadiness = "bridge_tool_readiness"
    case sessionRuntimeReadiness = "session_runtime_readiness"
    case skillsCompatibilityReadiness = "skills_compatibility_readiness"

    var title: String {
        switch self {
        case .hubReachability:
            return "Hub Reachability"
        case .pairingValidity:
            return "Pairing Validity"
        case .modelRouteReadiness:
            return "Model Route Readiness"
        case .bridgeToolReadiness:
            return "Bridge / Tool Readiness"
        case .sessionRuntimeReadiness:
            return "Session Runtime Readiness"
        case .skillsCompatibilityReadiness:
            return "Skills Compatibility"
        }
    }
}

struct XTUnifiedDoctorRouteSnapshot: Codable, Equatable, Sendable {
    var transportMode: String
    var routeLabel: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String
}

struct XTUnifiedDoctorSection: Identifiable, Codable, Equatable, Sendable {
    var kind: XTUnifiedDoctorSectionKind
    var state: XTUISurfaceState
    var headline: String
    var summary: String
    var nextStep: String
    var repairEntry: UITroubleshootDestination
    var detailLines: [String]

    var id: String { kind.rawValue }
}

struct XTUnifiedDoctorReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.unified_doctor_report.v1"

    static let empty = XTUnifiedDoctorReport(
        schemaVersion: currentSchemaVersion,
        generatedAtMs: 0,
        overallState: .blockedWaitingUpstream,
        overallSummary: "doctor pending",
        readyForFirstTask: false,
        currentFailureCode: "",
        currentFailureIssue: nil,
        configuredModelRoles: 0,
        availableModelCount: 0,
        loadedModelCount: 0,
        currentSessionID: nil,
        currentRoute: XTUnifiedDoctorRouteSnapshot(
            transportMode: "disconnected",
            routeLabel: "disconnected",
            pairingPort: 50052,
            grpcPort: 50051,
            internetHost: ""
        ),
        sections: [],
        consumedContracts: [],
        reportPath: XTUnifiedDoctorStore.defaultReportURL().path
    )

    var schemaVersion: String
    var generatedAtMs: Int64
    var overallState: XTUISurfaceState
    var overallSummary: String
    var readyForFirstTask: Bool
    var currentFailureCode: String
    var currentFailureIssue: UITroubleshootIssue?
    var configuredModelRoles: Int
    var availableModelCount: Int
    var loadedModelCount: Int
    var currentSessionID: String?
    var currentRoute: XTUnifiedDoctorRouteSnapshot
    var sections: [XTUnifiedDoctorSection]
    var consumedContracts: [String]
    var reportPath: String

    func section(_ kind: XTUnifiedDoctorSectionKind) -> XTUnifiedDoctorSection? {
        sections.first { $0.kind == kind }
    }
}

struct XTUnifiedDoctorInput: Sendable {
    var generatedAt: Date
    var localConnected: Bool
    var remoteConnected: Bool
    var remoteRoute: HubRemoteRoute
    var linking: Bool
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String
    var configuredModelIDs: [String]
    var totalModelRoles: Int
    var failureCode: String
    var runtime: UIFailClosedRuntimeSnapshot
    var runtimeStatus: AIRuntimeStatus?
    var modelsState: ModelStateSnapshot
    var bridgeAlive: Bool
    var bridgeEnabled: Bool
    var sessionID: String?
    var sessionTitle: String?
    var sessionRuntime: AXSessionRuntimeSnapshot?
    var voiceRouteDecision: VoiceRouteDecision
    var voiceRuntimeState: SupervisorVoiceRuntimeState
    var voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus
    var voiceActiveHealthReasonCode: String
    var voiceSidecarHealth: VoiceSidecarHealthSnapshot?
    var wakeProfileSnapshot: VoiceWakeProfileSnapshot
    var conversationSession: SupervisorConversationSessionSnapshot
    var skillsSnapshot: AXSkillsDoctorSnapshot
    var reportPath: String

    init(
        generatedAt: Date = Date(),
        localConnected: Bool,
        remoteConnected: Bool,
        remoteRoute: HubRemoteRoute,
        linking: Bool,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String,
        configuredModelIDs: [String],
        totalModelRoles: Int,
        failureCode: String,
        runtime: UIFailClosedRuntimeSnapshot,
        runtimeStatus: AIRuntimeStatus?,
        modelsState: ModelStateSnapshot,
        bridgeAlive: Bool,
        bridgeEnabled: Bool,
        sessionID: String?,
        sessionTitle: String?,
        sessionRuntime: AXSessionRuntimeSnapshot?,
        voiceRouteDecision: VoiceRouteDecision = .unavailable,
        voiceRuntimeState: SupervisorVoiceRuntimeState = .idle,
        voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus = .undetermined,
        voiceActiveHealthReasonCode: String = "",
        voiceSidecarHealth: VoiceSidecarHealthSnapshot? = nil,
        wakeProfileSnapshot: VoiceWakeProfileSnapshot = .empty,
        conversationSession: SupervisorConversationSessionSnapshot = .idle(
            policy: .default(),
            wakeMode: .pushToTalk,
            route: .manualText
        ),
        skillsSnapshot: AXSkillsDoctorSnapshot,
        reportPath: String = XTUnifiedDoctorStore.defaultReportURL().path
    ) {
        self.generatedAt = generatedAt
        self.localConnected = localConnected
        self.remoteConnected = remoteConnected
        self.remoteRoute = remoteRoute
        self.linking = linking
        self.pairingPort = pairingPort
        self.grpcPort = grpcPort
        self.internetHost = internetHost
        self.configuredModelIDs = configuredModelIDs
        self.totalModelRoles = totalModelRoles
        self.failureCode = failureCode
        self.runtime = runtime
        self.runtimeStatus = runtimeStatus
        self.modelsState = modelsState
        self.bridgeAlive = bridgeAlive
        self.bridgeEnabled = bridgeEnabled
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.sessionRuntime = sessionRuntime
        self.voiceRouteDecision = voiceRouteDecision
        self.voiceRuntimeState = voiceRuntimeState
        self.voiceAuthorizationStatus = voiceAuthorizationStatus
        self.voiceActiveHealthReasonCode = voiceActiveHealthReasonCode
        self.voiceSidecarHealth = voiceSidecarHealth
        self.wakeProfileSnapshot = wakeProfileSnapshot
        self.conversationSession = conversationSession
        self.skillsSnapshot = skillsSnapshot
        self.reportPath = reportPath
    }
}

enum XTUnifiedDoctorBuilder {
    static func build(input: XTUnifiedDoctorInput) -> XTUnifiedDoctorReport {
        let failureCode = input.failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureIssue = UITroubleshootKnowledgeBase.issue(forFailureCode: failureCode) ?? input.runtime.primaryIssue
        let route = routeSnapshot(for: input)
        let availableModels = input.modelsState.models
        let availableModelCount = availableModels.count
        let loadedModelCount = availableModels.filter { $0.state == .loaded }.count
        let configuredModelIDs = orderedUnique(input.configuredModelIDs)
        let configuredModelCount = configuredModelIDs.count
        let availableModelIDs = Set(availableModels.map(\.id))
        let missingAssignedModels = configuredModelIDs.filter { !availableModelIDs.contains($0) }
        let hubInteractive = input.localConnected || input.remoteConnected
        let runtimeAlive = input.runtimeStatus?.isAlive(ttl: 3.0) == true
        let toolRouteExecutable = hubInteractive && input.bridgeAlive && input.bridgeEnabled
        let trimmedHost = input.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceReadiness = VoiceReadinessAggregator.build(
            input: VoiceReadinessAggregatorInput.fromDoctorInput(input)
        )

        let hubReachability = buildHubReachabilitySection(
            hubInteractive: hubInteractive,
            runtimeAlive: runtimeAlive,
            failureCode: failureCode,
            route: route,
            input: input
        )
        let pairingValidity = voiceReadiness.check(.pairingValidity)?.asDoctorSection()
            ?? buildPairingValidityFallback(
                localConnected: input.localConnected,
                remoteConnected: input.remoteConnected,
                linking: input.linking,
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                internetHost: trimmedHost,
                route: route
            )
        let modelRoute = voiceReadiness.check(.modelRouteReadiness)?.asDoctorSection()
            ?? buildModelRouteFallback(
                hubInteractive: hubInteractive,
                runtimeAlive: runtimeAlive,
                availableModelCount: availableModelCount,
                loadedModelCount: loadedModelCount,
                configuredModelCount: configuredModelCount,
                totalModelRoles: input.totalModelRoles,
                missingAssignedModels: missingAssignedModels,
                configuredModelIDs: configuredModelIDs
            )
        let bridgeTool = voiceReadiness.check(.bridgeToolReadiness)?.asDoctorSection()
            ?? buildBridgeToolFallback(
                hubInteractive: hubInteractive,
                modelRouteReady: modelRoute.state == .ready,
                bridgeAlive: input.bridgeAlive,
                bridgeEnabled: input.bridgeEnabled,
                route: route
            )
        let sessionRuntime = voiceReadiness.check(.sessionRuntimeReadiness)?.asDoctorSection()
            ?? buildSessionRuntimeFallback(
                toolRouteExecutable: toolRouteExecutable,
                sessionID: input.sessionID,
                sessionTitle: input.sessionTitle,
                runtime: input.sessionRuntime
            )
        let skillsCompatibility = buildSkillsCompatibilitySection(
            hubInteractive: hubInteractive,
            snapshot: input.skillsSnapshot
        )

        let sections = [
            hubReachability,
            pairingValidity,
            modelRoute,
            bridgeTool,
            sessionRuntime,
            skillsCompatibility
        ]
        let readyForFirstTask = hubReachability.state == .ready
            && modelRoute.state == .ready
            && bridgeTool.state == .ready
            && sessionRuntime.state == .ready
        let overallState = overallState(for: sections)
        let overallSummary = overallSummary(
            overallState: overallState,
            readyForFirstTask: readyForFirstTask,
            sections: sections
        )
        let consumedContracts = orderedUnique(
            input.runtime.consumedContracts + [
                XTUIInformationArchitectureContract.frozen.schemaVersion,
                XTUISurfaceStateContract.frozen.schemaVersion,
                XTUIDesignTokenBundleContract.frozen.schemaVersion,
                XTUIReleaseScopeBadgeContract.frozen.schemaVersion,
                VoiceReadinessSnapshot.currentSchemaVersion,
                XTUnifiedDoctorReport.currentSchemaVersion
            ]
        )

        return XTUnifiedDoctorReport(
            schemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
            generatedAtMs: Int64(input.generatedAt.timeIntervalSince1970 * 1000),
            overallState: overallState,
            overallSummary: overallSummary,
            readyForFirstTask: readyForFirstTask,
            currentFailureCode: failureCode,
            currentFailureIssue: failureIssue,
            configuredModelRoles: configuredModelCount,
            availableModelCount: availableModelCount,
            loadedModelCount: loadedModelCount,
            currentSessionID: input.sessionID,
            currentRoute: route,
            sections: sections,
            consumedContracts: consumedContracts,
            reportPath: input.reportPath
        )
    }

    private static func buildHubReachabilitySection(
        hubInteractive: Bool,
        runtimeAlive: Bool,
        failureCode: String,
        route: XTUnifiedDoctorRouteSnapshot,
        input: XTUnifiedDoctorInput
    ) -> XTUnifiedDoctorSection {
        if input.localConnected {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .ready,
                headline: "Hub reachable via local fileIPC",
                summary: "X-Terminal is reading the Hub truth source directly from the same Mac. This is the clearest path for first-run verification.",
                nextStep: "Continue with model route, tool route, and session runtime verification in the same wizard.",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=local_fileipc",
                    "route=local:fileipc",
                    "runtime_alive=\(runtimeAlive)",
                    failureCode.isEmpty ? "failure_code=none" : "failure_code=\(failureCode)"
                ]
            )
        }

        if input.remoteConnected {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .ready,
                headline: "Hub reachable via \(route.routeLabel)",
                summary: "X-Terminal already has a working remote gRPC route. Pairing and bootstrap do not need a second page to explain the active transport.",
                nextStep: "Keep verifying model route and tools on the same active route.",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=\(route.transportMode)",
                    "route=\(route.routeLabel)",
                    "runtime_alive=\(runtimeAlive)",
                    failureCode.isEmpty ? "failure_code=none" : "failure_code=\(failureCode)"
                ]
            )
        }

        if input.linking {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .inProgress,
                headline: "Hub pairing bootstrap is still running",
                summary: "Discovery, bootstrap, or reconnect is still in flight. Until that finishes, all downstream verification remains fail-closed.",
                nextStep: "Wait for Pair Hub to finish, then re-check the active route in Verify.",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=\(route.transportMode)",
                    "route=\(route.routeLabel)",
                    "runtime_alive=\(runtimeAlive)",
                    failureCode.isEmpty ? "failure_code=none" : "failure_code=\(failureCode)"
                ]
            )
        }

        return XTUnifiedDoctorSection(
            kind: .hubReachability,
            state: .diagnosticRequired,
            headline: "Hub is not reachable yet",
            summary: "No local fileIPC and no remote gRPC route are interactive. The first-run path must stop here instead of guessing which transport should work.",
            nextStep: "Open Pair Hub and explicitly verify Pairing Port, gRPC Port, Internet Host, and reconnect smoke before continuing.",
            repairEntry: .xtPairHub,
            detailLines: [
                "transport=\(route.transportMode)",
                "route=\(route.routeLabel)",
                "runtime_alive=\(runtimeAlive)",
                failureCode.isEmpty ? "failure_code=hub_unreachable" : "failure_code=\(failureCode)"
            ]
        )
    }

    private static func buildPairingValidityFallback(
        localConnected: Bool,
        remoteConnected: Bool,
        linking: Bool,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String,
        route: XTUnifiedDoctorRouteSnapshot
    ) -> XTUnifiedDoctorSection {
        let pairingLooksValid = portLooksValid(pairingPort) && portLooksValid(grpcPort) && pairingPort != grpcPort
        let pairingMatchesConvention = pairingPort == max(1, min(65_535, grpcPort + 1))
        let hostLabel = internetHost.isEmpty ? "missing" : internetHost
        let details = [
            "pairing_port=\(pairingPort)",
            "grpc_port=\(grpcPort)",
            "internet_host=\(hostLabel)",
            "pairing_equals_grpc_plus_one=\(pairingMatchesConvention)",
            "active_route=\(route.routeLabel)"
        ]

        if !pairingLooksValid {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .diagnosticRequired,
                headline: "Pairing values are not valid yet",
                summary: "Pairing Port and gRPC Port must be explicit, distinct values. The setup path should never force the user to guess those numbers.",
                nextStep: "Copy Pairing Port and gRPC Port from REL Flow Hub -> Settings -> LAN (gRPC), then retry Pair Hub.",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if remoteConnected {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .ready,
                headline: "Pairing values match an active remote route",
                summary: "The same Pairing Port / gRPC Port / Internet Host values already produced a working remote connection.",
                nextStep: "Keep these exact values for future reconnects. No second source of truth is needed.",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if !internetHost.isEmpty {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .ready,
                headline: "Pairing values are explicit and ready to reuse",
                summary: "X-Terminal has all user-visible pairing fields it needs: Pairing Port, gRPC Port, and Internet Host.",
                nextStep: "Use the same values for LAN, VPN, or tunnel pairing without re-discovering them elsewhere.",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if localConnected || linking {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .inProgress,
                headline: "Local route works, but remote bootstrap values are still incomplete",
                summary: "Same-Mac verification can continue, but Internet Host is still empty, so a second device would not know what to enter yet.",
                nextStep: "Open REL Flow Hub -> Settings -> LAN (gRPC) and copy Internet Host into X-Terminal before remote pairing.",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .pairingValidity,
            state: .diagnosticRequired,
            headline: "Pairing values are not complete enough for bootstrap",
            summary: "Without an explicit Internet Host, the pairing path is incomplete for LAN/VPN/tunnel devices.",
            nextStep: "Copy Internet Host from REL Flow Hub -> Settings -> LAN (gRPC), then rerun one-click setup.",
            repairEntry: .xtPairHub,
            detailLines: details
        )
    }

    private static func buildModelRouteFallback(
        hubInteractive: Bool,
        runtimeAlive: Bool,
        availableModelCount: Int,
        loadedModelCount: Int,
        configuredModelCount: Int,
        totalModelRoles: Int,
        missingAssignedModels: [String],
        configuredModelIDs: [String]
    ) -> XTUnifiedDoctorSection {
        var details = [
            "runtime_alive=\(runtimeAlive)",
            "available_models=\(availableModelCount)",
            "loaded_models=\(loadedModelCount)",
            "configured_roles=\(configuredModelCount)/\(totalModelRoles)",
            configuredModelIDs.isEmpty ? "configured_model_ids=none" : "configured_model_ids=\(configuredModelIDs.joined(separator: ","))"
        ]

        if !missingAssignedModels.isEmpty {
            details.append("missing_assigned_models=\(missingAssignedModels.joined(separator: ","))")
        }

        if !hubInteractive {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .blockedWaitingUpstream,
                headline: "Model route waits for a live Hub route",
                summary: "Until Hub reachability becomes interactive, XT cannot verify which models are actually available.",
                nextStep: "Finish Pair Hub first, then return to Choose Model.",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if availableModelCount == 0 {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                headline: "Pairing ok, but model route is unavailable",
                summary: "Hub is reachable, but XT cannot see any usable models yet. This must stay distinct from pairing and grant failures.",
                nextStep: "Open Choose Model or REL Flow Hub -> Models & Paid Access, confirm at least one active model, then re-run Verify.",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if configuredModelCount == 0 {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .inProgress,
                headline: "Hub models are visible, but XT role assignment is still empty",
                summary: "The model route exists, but X-Terminal has not bound any role to a Hub model yet.",
                nextStep: "Assign at least the coder and supervisor roles in Choose Model.",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if !missingAssignedModels.isEmpty {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                headline: "XT role assignment points to models that are not currently exposed",
                summary: "Pairing succeeded, but at least one assigned model ID is missing from the current Hub model inventory.",
                nextStep: "Replace stale model IDs in Choose Model or re-enable those models in Hub.",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .modelRouteReadiness,
            state: .ready,
            headline: "Model route is ready",
            summary: "XT can see available Hub models and the current role assignments map to visible model IDs.",
            nextStep: "Continue into bridge/tool verification without leaving this screen.",
            repairEntry: .xtChooseModel,
            detailLines: details
        )
    }

    private static func buildBridgeToolFallback(
        hubInteractive: Bool,
        modelRouteReady: Bool,
        bridgeAlive: Bool,
        bridgeEnabled: Bool,
        route: XTUnifiedDoctorRouteSnapshot
    ) -> XTUnifiedDoctorSection {
        let toolRouteExecutable = hubInteractive && bridgeAlive && bridgeEnabled
        let details = [
            "bridge_alive=\(bridgeAlive)",
            "bridge_enabled=\(bridgeEnabled)",
            "tool_route_executable=\(toolRouteExecutable)",
            "active_route=\(route.routeLabel)"
        ]

        if !hubInteractive {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .blockedWaitingUpstream,
                headline: "Tool route waits for Hub reachability",
                summary: "Bridge and tool execution cannot be verified before X-Terminal has a live Hub route.",
                nextStep: "Finish Pair Hub first, then re-run Verify.",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeAlive {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                headline: modelRouteReady ? "Model route ok, but bridge / tool route is unavailable" : "Bridge / tool route is unavailable",
                summary: "Hub is reachable, but the bridge heartbeat is missing, so tool calls must remain fail-closed.",
                nextStep: "Open Hub Diagnostics & Recovery, relaunch the bridge if needed, then rerun Verify.",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeEnabled {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                headline: "Bridge is alive, but tool execution is not enabled",
                summary: "The bridge process exists, but the current execution window is not active, so tools are not yet executable.",
                nextStep: "Run reconnect smoke or re-enable the bridge window, then verify tools again.",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .bridgeToolReadiness,
            state: .ready,
            headline: "Bridge / tool route is ready",
            summary: "The bridge heartbeat is alive and the execution window is enabled, so tool calls can run through the current Hub route.",
            nextStep: "Continue to session runtime verification on the same route.",
            repairEntry: .hubDiagnostics,
            detailLines: details
        )
    }

    private static func buildSessionRuntimeFallback(
        toolRouteExecutable: Bool,
        sessionID: String?,
        sessionTitle: String?,
        runtime: AXSessionRuntimeSnapshot?
    ) -> XTUnifiedDoctorSection {
        let snapshot = runtime ?? AXSessionRuntimeSnapshot.idle()
        let details = [
            sessionID == nil ? "session_id=none" : "session_id=\(sessionID!)",
            sessionTitle == nil ? "session_title=none" : "session_title=\(sessionTitle!)",
            "state=\(snapshot.state.rawValue)",
            "recoverable=\(snapshot.recoverable)",
            "pending_tool_calls=\(snapshot.pendingToolCallCount)",
            snapshot.lastFailureCode?.isEmpty == false ? "last_failure_code=\(snapshot.lastFailureCode!)" : "last_failure_code=none",
            snapshot.resumeToken?.isEmpty == false ? "resume_token_present=true" : "resume_token_present=false"
        ]

        if !toolRouteExecutable {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .blockedWaitingUpstream,
                headline: "Session runtime waits for the tool route to become executable",
                summary: "Until the bridge / tool layer is ready, runtime verification remains blocked instead of pretending the session can recover.",
                nextStep: "Repair bridge / tool readiness first, then come back to Verify.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.state == .failed_recoverable && !snapshot.recoverable {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .diagnosticRequired,
                headline: "Bridge ok, but session runtime is not recoverable",
                summary: "The runtime reached a failure state without a valid recovery path. This must stay separate from bridge and model routing issues.",
                nextStep: "Open XT Diagnostics, inspect the last failure code, then recreate or repair the affected session before continuing.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.state == .failed_recoverable {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                headline: "Session runtime has a recoverable failure path",
                summary: "The current session is paused behind a recoverable failure. A resume path exists, but verification is not complete yet.",
                nextStep: "Use the resume path or rerun the blocked request, then verify the runtime returns to idle or completed.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.pendingToolCallCount > 0 || runtimeBusy(snapshot.state) {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                headline: "Session runtime is active",
                summary: "The runtime is currently processing or waiting on a step. Verification should wait until it returns to a stable state.",
                nextStep: "Wait for the current session activity to finish, then re-open Verify.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if sessionID == nil {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .ready,
                headline: "Session runtime foundation is ready",
                summary: "No primary session exists yet, but the runtime foundation is idle and ready to materialize one on the first task.",
                nextStep: "Start the first task to create the primary session on top of the verified route.",
                repairEntry: .homeSupervisor,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "The current session is in a stable state and can resume normal work on the verified route.",
            nextStep: "You can continue into the first task without switching pages.",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func buildSkillsCompatibilitySection(
        hubInteractive: Bool,
        snapshot: AXSkillsDoctorSnapshot
    ) -> XTUnifiedDoctorSection {
        let projectRefs = snapshot.projectIndexEntries.map(\.path)
        let globalRefs = snapshot.globalIndexEntries.map(\.path)
        let details = [
            "hub_index_available=\(snapshot.hubIndexAvailable)",
            "installed_skills=\(snapshot.installedSkillCount)",
            "compatible_skills=\(snapshot.compatibleSkillCount)",
            "partial_skills=\(snapshot.partialCompatibilityCount)",
            "revoked_matches=\(snapshot.revokedMatchCount)",
            "trusted_publishers=\(snapshot.trustEnabledPublisherCount)",
            projectRefs.isEmpty ? "project_indexes=none" : "project_indexes=\(projectRefs.joined(separator: ","))",
            globalRefs.isEmpty ? "global_indexes=none" : "global_indexes=\(globalRefs.joined(separator: ","))"
        ]

        if !snapshot.hubIndexAvailable {
            return XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: hubInteractive ? .diagnosticRequired : .blockedWaitingUpstream,
                headline: hubInteractive ? "Hub skills index is unavailable" : "Skills compatibility waits for Hub reachability",
                summary: hubInteractive
                    ? "The Hub control plane is reachable, but the skills store index is not readable yet, so compatibility stays fail-closed."
                    : "Until Hub reachability is restored, XT cannot verify managed skills compatibility.",
                nextStep: "Refresh the Hub skills store and reopen the current project / global skills index before relying on managed skills.",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.revokedMatchCount > 0 {
            return XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: .diagnosticRequired,
                headline: "Installed skills include revoked matches",
                summary: "At least one installed or pinned skill matches a revoked package or publisher, so compatibility cannot be treated as ready.",
                nextStep: "Remove or repin revoked skills, then reopen the skills index and rerun Verify.",
                repairEntry: .xtDiagnostics,
                detailLines: details + Array(snapshot.conflictWarnings.prefix(3))
            )
        }

        if snapshot.partialCompatibilityCount > 0 || !snapshot.conflictWarnings.isEmpty {
            return XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: .inProgress,
                headline: "Skills compatibility is partially ready",
                summary: "Managed skills are present, but at least one package still needs compatibility cleanup or pin conflict resolution.",
                nextStep: "Review the project / global skills index before assuming every managed skill can run cleanly.",
                repairEntry: .xtDiagnostics,
                detailLines: details + Array(snapshot.conflictWarnings.prefix(3))
            )
        }

        return XTUnifiedDoctorSection(
            kind: .skillsCompatibilityReadiness,
            state: .ready,
            headline: snapshot.installedSkillCount == 0 ? "Skills compatibility is clear (no managed skills installed)" : "Skills compatibility is ready",
            summary: snapshot.installedSkillCount == 0
                ? "No managed skills are installed, so compatibility does not block assistant runtime readiness."
                : "Installed skills are compatible enough for XT consumption, with no revoked matches or pin conflicts.",
            nextStep: snapshot.installedSkillCount == 0
                ? "Continue with core runtime verification; managed skills are optional for the first task."
                : "Use the current project / global skills index as the single compatibility reference.",
            repairEntry: .xtDiagnostics,
            detailLines: details
        )
    }

    private static func routeSnapshot(for input: XTUnifiedDoctorInput) -> XTUnifiedDoctorRouteSnapshot {
        let host = input.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.localConnected {
            return XTUnifiedDoctorRouteSnapshot(
                transportMode: "local_fileipc",
                routeLabel: "local fileIPC",
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                internetHost: host
            )
        }
        if input.remoteConnected {
            switch input.remoteRoute {
            case .lan:
                return XTUnifiedDoctorRouteSnapshot(
                    transportMode: "remote_grpc_lan",
                    routeLabel: "remote gRPC (LAN)",
                    pairingPort: input.pairingPort,
                    grpcPort: input.grpcPort,
                    internetHost: host
                )
            case .internet:
                return XTUnifiedDoctorRouteSnapshot(
                    transportMode: "remote_grpc_internet",
                    routeLabel: "remote gRPC (internet)",
                    pairingPort: input.pairingPort,
                    grpcPort: input.grpcPort,
                    internetHost: host
                )
            case .internetTunnel:
                return XTUnifiedDoctorRouteSnapshot(
                    transportMode: "remote_grpc_tunnel",
                    routeLabel: "remote gRPC (tunnel)",
                    pairingPort: input.pairingPort,
                    grpcPort: input.grpcPort,
                    internetHost: host
                )
            case .none:
                return XTUnifiedDoctorRouteSnapshot(
                    transportMode: "remote_grpc",
                    routeLabel: "remote gRPC",
                    pairingPort: input.pairingPort,
                    grpcPort: input.grpcPort,
                    internetHost: host
                )
            }
        }
        if input.linking {
            return XTUnifiedDoctorRouteSnapshot(
                transportMode: "pairing_bootstrap",
                routeLabel: "pairing bootstrap",
                pairingPort: input.pairingPort,
                grpcPort: input.grpcPort,
                internetHost: host
            )
        }
        return XTUnifiedDoctorRouteSnapshot(
            transportMode: "disconnected",
            routeLabel: "disconnected",
            pairingPort: input.pairingPort,
            grpcPort: input.grpcPort,
            internetHost: host
        )
    }

    private static func overallState(for sections: [XTUnifiedDoctorSection]) -> XTUISurfaceState {
        if sections.contains(where: { $0.state == .permissionDenied }) {
            return .permissionDenied
        }
        if sections.contains(where: { $0.state == .grantRequired }) {
            return .grantRequired
        }
        if sections.contains(where: { $0.state == .diagnosticRequired }) {
            return .diagnosticRequired
        }
        if sections.contains(where: { $0.state == .blockedWaitingUpstream }) {
            return .blockedWaitingUpstream
        }
        if sections.contains(where: { $0.state == .inProgress }) {
            return .inProgress
        }
        return .ready
    }

    private static func overallSummary(
        overallState: XTUISurfaceState,
        readyForFirstTask: Bool,
        sections: [XTUnifiedDoctorSection]
    ) -> String {
        if readyForFirstTask {
            return "pairing, model route, tools, and session runtime are verified on one path"
        }
        if let firstBlocking = sections.first(where: { $0.state != .ready }) {
            return "fail-closed on \(firstBlocking.kind.title.lowercased()): \(firstBlocking.headline)"
        }
        return "doctor still collecting readiness signals"
    }

    private static func runtimeBusy(_ state: AXSessionRuntimeState) -> Bool {
        switch state {
        case .planning, .awaiting_model, .awaiting_tool_approval, .running_tools, .awaiting_hub:
            return true
        case .idle, .failed_recoverable, .completed:
            return false
        }
    }

    private static func portLooksValid(_ port: Int) -> Bool {
        (1...65_535).contains(port)
    }

    private static func orderedUnique(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if seen.insert(line).inserted {
                ordered.append(line)
            }
        }
        return ordered
    }
}

enum XTUnifiedDoctorStore {
    static func workspaceRootFromEnvOrCWD() -> URL {
        let env = (ProcessInfo.processInfo.environment["XTERMINAL_WORKSPACE_ROOT"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            return URL(fileURLWithPath: NSString(string: env).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    static func defaultReportURL(workspaceRoot: URL = workspaceRootFromEnvOrCWD()) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent("xt_unified_doctor_report.json")
    }

    static func writeReport(_ report: XTUnifiedDoctorReport, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            print("XTUnifiedDoctor write report failed: \(error)")
        }
    }
}

struct XTUnifiedDoctorSummaryView: View {
    let report: XTUnifiedDoctorReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(report.overallSummary, systemImage: report.overallState.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(report.overallState.tint)
                Spacer()
                Text(report.overallState.rawValue)
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(report.overallState.tint)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Current Route")
                        .foregroundStyle(.secondary)
                    Text(report.currentRoute.routeLabel)
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Transport")
                        .foregroundStyle(.secondary)
                    Text(report.currentRoute.transportMode)
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Pairing Port")
                        .foregroundStyle(.secondary)
                    Text("\(report.currentRoute.pairingPort)")
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("gRPC Port")
                        .foregroundStyle(.secondary)
                    Text("\(report.currentRoute.grpcPort)")
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Internet Host")
                        .foregroundStyle(.secondary)
                    Text(report.currentRoute.internetHost.isEmpty ? "missing" : report.currentRoute.internetHost)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(report.currentRoute.internetHost.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Models")
                        .foregroundStyle(.secondary)
                    Text("configured=\(report.configuredModelRoles) available=\(report.availableModelCount) loaded=\(report.loadedModelCount)")
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("First Task")
                        .foregroundStyle(.secondary)
                    Text(report.readyForFirstTask ? "ready" : "hold")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(report.readyForFirstTask ? UIThemeTokens.color(for: .ready) : UIThemeTokens.color(for: .diagnosticRequired))
                }
            }
            .font(.caption)

            ForEach(report.sections) { section in
                XTUnifiedDoctorSectionCard(section: section)
            }

            if !report.reportPath.isEmpty {
                Text("machine_report=\(report.reportPath)")
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct XTUnifiedDoctorSectionCard: View {
    let section: XTUnifiedDoctorSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(section.kind.title, systemImage: section.state.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(section.state.tint)
                Spacer()
                Text(section.state.rawValue)
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(section.state.tint)
            }

            Text(section.headline)
                .font(.caption.weight(.semibold))
            Text(section.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Next: \(section.nextStep)")
                .font(.caption)
            Text("Repair: \(section.repairEntry.label)")
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)

            if !section.detailLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(section.detailLines, id: \.self) { line in
                        Text("• \(line)")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UIThemeTokens.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }
}
