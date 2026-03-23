import Foundation
import SwiftUI

enum XTUnifiedDoctorSectionKind: String, CaseIterable, Codable, Sendable {
    case hubReachability = "hub_reachability"
    case pairingValidity = "pairing_validity"
    case modelRouteReadiness = "model_route_readiness"
    case bridgeToolReadiness = "bridge_tool_readiness"
    case sessionRuntimeReadiness = "session_runtime_readiness"
    case wakeProfileReadiness = "wake_profile_readiness"
    case talkLoopReadiness = "talk_loop_readiness"
    case voicePlaybackReadiness = "voice_playback_readiness"
    case calendarReminderReadiness = "calendar_reminder_readiness"
    case skillsCompatibilityReadiness = "skills_compatibility_readiness"

    var title: String {
        switch self {
        case .hubReachability:
            return "Hub 可达性"
        case .pairingValidity:
            return "配对有效性"
        case .modelRouteReadiness:
            return "模型路由就绪"
        case .bridgeToolReadiness:
            return "桥接 / 工具就绪"
        case .sessionRuntimeReadiness:
            return "会话运行时就绪"
        case .wakeProfileReadiness:
            return "唤醒配置就绪"
        case .talkLoopReadiness:
            return "对话链路就绪"
        case .voicePlaybackReadiness:
            return "语音播放就绪"
        case .calendarReminderReadiness:
            return "日历提醒就绪"
        case .skillsCompatibilityReadiness:
            return "技能兼容性"
        }
    }

    var contributesToFirstTaskReadiness: Bool {
        switch self {
        case .hubReachability, .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness:
            return true
        case .pairingValidity, .wakeProfileReadiness, .talkLoopReadiness, .voicePlaybackReadiness, .calendarReminderReadiness, .skillsCompatibilityReadiness:
            return false
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

struct XTUnifiedDoctorDurableCandidateMirrorProjection: Codable, Equatable, Sendable {
    var status: SupervisorDurableCandidateMirrorStatus
    var target: String
    var attempted: Bool
    var errorCode: String?
    var localStoreRole: String

    var detailLine: String {
        var parts = [
            "durable_candidate_mirror",
            "status=\(status.rawValue)",
            "target=\(target)",
            "attempted=\(attempted)"
        ]
        if let errorCode, !errorCode.isEmpty {
            parts.append("reason=\(errorCode)")
        }
        if !localStoreRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("local_store_role=\(localStoreRole)")
        }
        return parts.joined(separator: " ")
    }

    static func from(detailLines: [String]) -> XTUnifiedDoctorDurableCandidateMirrorProjection? {
        guard let line = detailLines.first(where: { $0.hasPrefix("durable_candidate_mirror ") }) else {
            return nil
        }
        let rawFields = line.dropFirst("durable_candidate_mirror ".count)
        var fields: [String: String] = [:]
        for token in rawFields.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        guard let rawStatus = fields["status"],
              let status = SupervisorDurableCandidateMirrorStatus(rawValue: rawStatus) else {
            return nil
        }
        return XTUnifiedDoctorDurableCandidateMirrorProjection(
            status: status,
            target: normalizedDoctorField(
                fields["target"],
                fallback: XTSupervisorDurableCandidateMirror.mirrorTarget
            ),
            attempted: fields["attempted"].map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            } ?? (status != .notNeeded),
            errorCode: normalizedOptionalDoctorField(fields["reason"] ?? fields["error_code"]),
            localStoreRole: normalizedDoctorField(
                fields["local_store_role"],
                fallback: XTSupervisorDurableCandidateMirror.localStoreRole
            )
        )
    }
}

struct XTUnifiedDoctorLocalStoreWriteProjection: Codable, Equatable, Sendable {
    var personalMemoryIntent: String?
    var crossLinkIntent: String?
    var personalReviewIntent: String?

    var detailLine: String {
        let parts = [
            "xt_local_store_writes",
            personalMemoryIntent.map { "personal_memory=\($0)" },
            crossLinkIntent.map { "cross_link=\($0)" },
            personalReviewIntent.map { "personal_review=\($0)" }
        ].compactMap { $0 }
        return parts.joined(separator: " ")
    }

    var hasAnyIntent: Bool {
        personalMemoryIntent != nil
            || crossLinkIntent != nil
            || personalReviewIntent != nil
    }

    static func from(detailLines: [String]) -> XTUnifiedDoctorLocalStoreWriteProjection? {
        guard let line = detailLines.first(where: { $0.hasPrefix("xt_local_store_writes ") }) else {
            return nil
        }
        let rawFields = line.dropFirst("xt_local_store_writes ".count)
        var fields: [String: String] = [:]
        for token in rawFields.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        let projection = XTUnifiedDoctorLocalStoreWriteProjection(
            personalMemoryIntent: normalizedOptionalDoctorField(fields["personal_memory"]),
            crossLinkIntent: normalizedOptionalDoctorField(fields["cross_link"]),
            personalReviewIntent: normalizedOptionalDoctorField(fields["personal_review"])
        )
        return projection.hasAnyIntent ? projection : nil
    }
}

struct XTUnifiedDoctorSection: Identifiable, Codable, Equatable, Sendable {
    var kind: XTUnifiedDoctorSectionKind
    var state: XTUISurfaceState
    var headline: String
    var summary: String
    var nextStep: String
    var repairEntry: UITroubleshootDestination
    var detailLines: [String]
    var projectContextPresentation: AXProjectContextAssemblyPresentation? = nil
    var memoryRouteTruthProjection: AXModelRouteTruthProjection? = nil
    var durableCandidateMirrorProjection: XTUnifiedDoctorDurableCandidateMirrorProjection? = nil
    var localStoreWriteProjection: XTUnifiedDoctorLocalStoreWriteProjection? = nil

    var id: String { kind.rawValue }
}

struct XTUnifiedDoctorReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.unified_doctor_report.v1"

    static let empty = XTUnifiedDoctorReport(
        schemaVersion: currentSchemaVersion,
        generatedAtMs: 0,
        overallState: .blockedWaitingUpstream,
        overallSummary: "Doctor 正在等待就绪信号",
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

struct XTUnifiedDoctorReportContract: Codable, Equatable {
    let schemaVersion: String
    let reportSchemaVersion: String
    let sectionKinds: [XTUnifiedDoctorSectionKind]
    let structuredProjectionFields: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case reportSchemaVersion = "report_schema_version"
        case sectionKinds = "section_kinds"
        case structuredProjectionFields = "structured_projection_fields"
        case auditRef = "audit_ref"
    }

    static let frozen = XTUnifiedDoctorReportContract(
        schemaVersion: "xt.unified_doctor_report_contract.v1",
        reportSchemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
        sectionKinds: XTUnifiedDoctorSectionKind.allCases,
        structuredProjectionFields: [
            "projectContextPresentation",
            "memoryRouteTruthProjection",
            "durableCandidateMirrorProjection",
            "localStoreWriteProjection"
        ],
        auditRef: "audit-xt-unified-doctor-contract-v1"
    )
}

struct XTUnifiedDoctorCalendarReminderSnapshot: Codable, Equatable, Sendable {
    static let empty = XTUnifiedDoctorCalendarReminderSnapshot(
        enabled: false,
        headsUpMinutes: 15,
        finalCallMinutes: 3,
        notificationFallbackEnabled: true,
        authorizationStatus: .notDetermined,
        authorizationGuidanceText: XTCalendarAuthorizationStatus.notDetermined.guidanceText,
        schedulerStatusLine: "Calendar reminders are off",
        schedulerLastRunAtMs: 0,
        eventStoreStatusLine: "Calendar reminders are off",
        eventStoreLastRefreshedAtMs: 0,
        upcomingMeetingCount: 0,
        upcomingMeetingPreviewLines: []
    )

    var enabled: Bool
    var headsUpMinutes: Int
    var finalCallMinutes: Int
    var notificationFallbackEnabled: Bool
    var authorizationStatus: XTCalendarAuthorizationStatus
    var authorizationGuidanceText: String
    var schedulerStatusLine: String
    var schedulerLastRunAtMs: Int64
    var eventStoreStatusLine: String
    var eventStoreLastRefreshedAtMs: Int64
    var upcomingMeetingCount: Int
    var upcomingMeetingPreviewLines: [String]
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
    var bridgeLastError: String
    var sessionID: String?
    var sessionTitle: String?
    var sessionRuntime: AXSessionRuntimeSnapshot?
    var voiceRouteDecision: VoiceRouteDecision
    var voiceRuntimeState: SupervisorVoiceRuntimeState
    var voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus
    var voicePermissionSnapshot: VoicePermissionSnapshot
    var voiceActiveHealthReasonCode: String
    var voiceSidecarHealth: VoiceSidecarHealthSnapshot?
    var wakeProfileSnapshot: VoiceWakeProfileSnapshot
    var conversationSession: SupervisorConversationSessionSnapshot
    var voicePreferences: VoiceRuntimePreferences
    var calendarReminderSnapshot: XTUnifiedDoctorCalendarReminderSnapshot
    var skillsSnapshot: AXSkillsDoctorSnapshot
    var reportPath: String
    var modelRouteDiagnostics: AXModelRouteDiagnosticsSummary
    var projectContextDiagnostics: AXProjectContextAssemblyDiagnosticsSummary
    var supervisorMemoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot?

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
        bridgeLastError: String = "",
        sessionID: String?,
        sessionTitle: String?,
        sessionRuntime: AXSessionRuntimeSnapshot?,
        voiceRouteDecision: VoiceRouteDecision = .unavailable,
        voiceRuntimeState: SupervisorVoiceRuntimeState = .idle,
        voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus = .undetermined,
        voicePermissionSnapshot: VoicePermissionSnapshot = .unknown,
        voiceActiveHealthReasonCode: String = "",
        voiceSidecarHealth: VoiceSidecarHealthSnapshot? = nil,
        wakeProfileSnapshot: VoiceWakeProfileSnapshot = .empty,
        conversationSession: SupervisorConversationSessionSnapshot = .idle(
            policy: .default(),
            wakeMode: .pushToTalk,
            route: .manualText
        ),
        voicePreferences: VoiceRuntimePreferences = .default(),
        calendarReminderSnapshot: XTUnifiedDoctorCalendarReminderSnapshot = .empty,
        skillsSnapshot: AXSkillsDoctorSnapshot,
        reportPath: String = XTUnifiedDoctorStore.defaultReportURL().path,
        modelRouteDiagnostics: AXModelRouteDiagnosticsSummary = .empty,
        projectContextDiagnostics: AXProjectContextAssemblyDiagnosticsSummary = .empty,
        supervisorMemoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot? = nil
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
        self.bridgeLastError = bridgeLastError
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.sessionRuntime = sessionRuntime
        self.voiceRouteDecision = voiceRouteDecision
        self.voiceRuntimeState = voiceRuntimeState
        self.voiceAuthorizationStatus = voiceAuthorizationStatus
        self.voicePermissionSnapshot = voicePermissionSnapshot
        self.voiceActiveHealthReasonCode = voiceActiveHealthReasonCode
        self.voiceSidecarHealth = voiceSidecarHealth
        self.wakeProfileSnapshot = wakeProfileSnapshot
        self.conversationSession = conversationSession
        self.voicePreferences = voicePreferences
        self.calendarReminderSnapshot = calendarReminderSnapshot
        self.skillsSnapshot = skillsSnapshot
        self.reportPath = reportPath
        self.modelRouteDiagnostics = modelRouteDiagnostics
        self.projectContextDiagnostics = projectContextDiagnostics
        self.supervisorMemoryAssemblySnapshot = supervisorMemoryAssemblySnapshot
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
        let modelRoute = enrichModelRouteSection(
            voiceReadiness.check(.modelRouteReadiness)?.asDoctorSection()
                ?? buildModelRouteFallback(
                hubInteractive: hubInteractive,
                runtimeAlive: runtimeAlive,
                availableModelCount: availableModelCount,
                loadedModelCount: loadedModelCount,
                configuredModelCount: configuredModelCount,
                totalModelRoles: input.totalModelRoles,
                missingAssignedModels: missingAssignedModels,
                configuredModelIDs: configuredModelIDs
                ),
            diagnostics: input.modelRouteDiagnostics
        )
        let bridgeTool = voiceReadiness.check(.bridgeToolReadiness)?.asDoctorSection()
            ?? buildBridgeToolFallback(
                hubInteractive: hubInteractive,
                modelRouteReady: modelRoute.state == .ready,
                bridgeAlive: input.bridgeAlive,
                bridgeEnabled: input.bridgeEnabled,
                bridgeLastError: input.bridgeLastError,
                route: route
            )
        let sessionRuntime = enrichSessionRuntimeSection(
            voiceReadiness.check(.sessionRuntimeReadiness)?.asDoctorSection()
                ?? buildSessionRuntimeFallback(
                    toolRouteExecutable: toolRouteExecutable,
                    sessionID: input.sessionID,
                    sessionTitle: input.sessionTitle,
                    runtime: input.sessionRuntime
                ),
            diagnostics: input.projectContextDiagnostics,
            memoryAssemblySnapshot: input.supervisorMemoryAssemblySnapshot
        )
        let wakeProfile = voiceReadiness.check(.wakeProfileReadiness)?.asDoctorSection()
        let talkLoop = voiceReadiness.check(.talkLoopReadiness)?.asDoctorSection()
        let voicePlayback = voiceReadiness.check(.ttsReadiness)?.asDoctorSection()
        let calendarReminder = buildCalendarReminderSection(
            snapshot: input.calendarReminderSnapshot
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
            wakeProfile,
            talkLoop,
            voicePlayback,
            calendarReminder,
            skillsCompatibility
        ].compactMap { $0 }
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
                XTUnifiedDoctorReportContract.frozen.schemaVersion
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
        let normalizedFailureCode = failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureIssue = UITroubleshootKnowledgeBase.issue(forFailureCode: normalizedFailureCode)

        if input.localConnected {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .ready,
                headline: "Hub 已通过本机 fileIPC 可达",
                summary: "X-Terminal 正在直接读取这台 Mac 上的 Hub 真值源。对首次验证来说，这是最直接、最清晰的一条路径。",
                nextStep: "留在当前向导里，继续检查模型路由、工具链路和会话运行时。",
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
                headline: "Hub 已通过 \(route.routeLabel) 可达",
                summary: "X-Terminal 已经拿到一条可用的远端 gRPC 路由。既然当前传输已经跑通，就不需要再开第二套说明。",
                nextStep: "继续沿着当前这条有效链路检查模型路由和工具链路。",
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
                headline: "Hub 配对引导仍在进行中",
                summary: "发现、引导或重连流程还没结束。在它真正完成之前，后续验证都必须保持 fail-closed。",
                nextStep: "等 Pair Hub 完成后，再回到 Verify 检查当前有效链路。",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=\(route.transportMode)",
                    "route=\(route.routeLabel)",
                    "runtime_alive=\(runtimeAlive)",
                    failureCode.isEmpty ? "failure_code=none" : "failure_code=\(failureCode)"
                ]
            )
        }

        if failureIssue == .pairingRepairRequired {
            return XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .diagnosticRequired,
                headline: "现有配对档案已失效，需要清理并重配",
                summary: "当前不是单纯的 Hub 不可达，更像是本地缓存的 token、client cert 或旧 pairing profile 已经失效；继续拿旧档案 reconnect 只会反复失败。",
                nextStep: "先在 XT Pair Hub 执行“清除配对后重连”，再到 Hub Pairing & Device Trust 清理旧设备条目并重新批准。",
                repairEntry: .xtPairHub,
                detailLines: [
                    "transport=\(route.transportMode)",
                    "route=\(route.routeLabel)",
                    "runtime_alive=\(runtimeAlive)",
                    normalizedFailureCode.isEmpty ? "failure_code=pairing_repair_required" : "failure_code=\(normalizedFailureCode)"
                ]
            )
        }

        return XTUnifiedDoctorSection(
            kind: .hubReachability,
            state: .diagnosticRequired,
            headline: "Hub 暂时还不可达",
            summary: "当前既没有可交互的本机 fileIPC，也没有可交互的远端 gRPC 路由。首次引导必须先停在这里，不能靠猜来判断该走哪条链路。",
            nextStep: "先打开 Pair Hub，明确核对 Pairing Port、gRPC Port、Internet Host 和 reconnect smoke，再继续。",
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
                headline: "配对参数暂时无效",
                summary: "在继续引导之前，Pairing Port 和 gRPC Port 必须是明确且彼此不同的值，不能让用户靠猜。",
                nextStep: "去 REL Flow Hub -> Settings -> LAN (gRPC) 复制 Pairing Port 和 gRPC Port，然后重新执行 Pair Hub。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if remoteConnected {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .ready,
                headline: "配对参数已匹配当前远端链路",
                summary: "同一组 Pairing Port / gRPC Port / Internet Host 已经成功建立过可用的远端连接。",
                nextStep: "后续重连时继续保留这组值即可，不需要再找第二个真值来源。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if !internetHost.isEmpty {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .ready,
                headline: "配对参数已明确，可重复复用",
                summary: "X-Terminal 已经拿到了用户可见的全部配对字段：Pairing Port、gRPC Port 和 Internet Host。",
                nextStep: "后续做 LAN、VPN 或隧道配对时，直接复用这组值即可，不需要重新到别处查找。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        if localConnected || linking {
            return XTUnifiedDoctorSection(
                kind: .pairingValidity,
                state: .inProgress,
                headline: "本机链路可用，但远端引导参数还不完整",
                summary: "同机验证可以继续，但 Internet Host 仍为空，所以第二台设备还不知道该填什么。",
                nextStep: "先去 REL Flow Hub -> Settings -> LAN (gRPC) 复制 Internet Host 到 X-Terminal，再做远端配对。",
                repairEntry: .xtPairHub,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .pairingValidity,
            state: .diagnosticRequired,
            headline: "配对参数不足以完成引导",
            summary: "如果没有明确的 Internet Host，面向 LAN / VPN / 隧道设备的配对路径就是不完整的。",
            nextStep: "去 REL Flow Hub -> Settings -> LAN (gRPC) 复制 Internet Host，然后重新执行一键设置。",
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
                headline: "模型路由正在等待可用的 Hub 链路",
                summary: "在 Hub 可达性真正进入 interactive 之前，XT 无法确认哪些模型实际可用。",
                nextStep: "先完成 Pair Hub，再回到 Choose Model。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if availableModelCount == 0 {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                headline: "配对已通，但模型路由不可用",
                summary: "Hub 已可达，但 XT 还看不到任何可用模型。这个问题需要和配对失败、授权失败区分开。",
                nextStep: "打开 Choose Model 或 REL Flow Hub -> Models & Paid Access，确认至少有一个激活模型，再重新执行 Verify。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if configuredModelCount == 0 {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .inProgress,
                headline: "Hub 模型可见，但 XT 的角色分配还是空的",
                summary: "模型路由已经存在，但 X-Terminal 还没有把任何角色绑定到具体的 Hub 模型上。",
                nextStep: "至少先在 Choose Model 里给 coder 和 supervisor 分配模型。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        if !missingAssignedModels.isEmpty {
            return XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                headline: "XT 的角色分配指向了当前未暴露的模型",
                summary: "虽然配对成功，但至少有一个已分配的模型 ID 不在当前的 Hub 模型清单里。",
                nextStep: "去 Choose Model 替换过期模型 ID，或者回到 Hub 重新启用这些模型。",
                repairEntry: .xtChooseModel,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .modelRouteReadiness,
            state: .ready,
            headline: "模型路由已就绪",
            summary: "XT 已经能看到可用的 Hub 模型，当前角色分配也都映射到了可见模型 ID。",
            nextStep: "不用离开当前页面，直接继续做桥接 / 工具链验证。",
            repairEntry: .xtChooseModel,
            detailLines: details
        )
    }

    private static func enrichModelRouteSection(
        _ base: XTUnifiedDoctorSection,
        diagnostics: AXModelRouteDiagnosticsSummary
    ) -> XTUnifiedDoctorSection {
        var section = base
        section.memoryRouteTruthProjection = diagnostics.truthProjection

        guard diagnostics.recentEventCount > 0 else {
            return section
        }

        section.detailLines = orderedUnique(base.detailLines + diagnostics.detailLines)

        guard base.state == .ready,
              diagnostics.recentFailureCount > 0 else {
            return section
        }

        section.headline = "Model route is ready, but recent project routes degraded"
        section.summary = "XT 当前能看到可分配模型，但最近仍有项目请求在执行时降到本地或远端失败；这通常不是“完全没连上 Hub”，而是具体项目选中的远端没有稳定命中。"
        section.nextStep = "打开受影响项目后运行 `/route diagnose`；如果诊断里已经提示 XT 会自动改试上次稳定远端，就直接继续。只有你想把模型固定下来时，再到 Choose Model 手动切。"
        return section
    }

    private static func buildBridgeToolFallback(
        hubInteractive: Bool,
        modelRouteReady: Bool,
        bridgeAlive: Bool,
        bridgeEnabled: Bool,
        bridgeLastError: String,
        route: XTUnifiedDoctorRouteSnapshot
    ) -> XTUnifiedDoctorSection {
        let toolRouteExecutable = hubInteractive && bridgeAlive && bridgeEnabled
        let normalizedBridgeLastError = bridgeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = [
            "bridge_alive=\(bridgeAlive)",
            "bridge_enabled=\(bridgeEnabled)",
            "tool_route_executable=\(toolRouteExecutable)",
            "active_route=\(route.routeLabel)"
        ] + (normalizedBridgeLastError.isEmpty ? [] : ["bridge_last_error=\(normalizedBridgeLastError)"])

        if !hubInteractive {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .blockedWaitingUpstream,
                headline: "工具链路正在等待 Hub 可达",
                summary: "在 X-Terminal 建立 live Hub 路由之前，桥接和工具执行都无法被验证。",
                nextStep: "先完成 Pair Hub，再重新执行 Verify。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeAlive {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                headline: modelRouteReady ? "模型路由已通，但桥接 / 工具链路不可用" : "桥接 / 工具链路不可用",
                summary: normalizedBridgeLastError.isEmpty
                    ? "Hub 已可达，但 bridge heartbeat 缺失，所以工具调用必须继续保持 fail-closed。"
                    : "Hub 已可达，但 bridge heartbeat 缺失，而且上一次 bridge enable 请求也在链路恢复前失败了，所以工具调用必须继续保持 fail-closed。",
                nextStep: normalizedBridgeLastError.isEmpty
                    ? "打开 Hub Diagnostics & Recovery，必要时重启 bridge，然后重新执行 Verify。"
                    : "打开 Hub Diagnostics & Recovery，先修 bridge 请求链路，必要时重启 bridge，然后重新执行 Verify。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        if !bridgeEnabled {
            return XTUnifiedDoctorSection(
                kind: .bridgeToolReadiness,
                state: .diagnosticRequired,
                headline: "Bridge 存活，但工具执行窗口未启用",
                summary: normalizedBridgeLastError.isEmpty
                    ? "Bridge 进程已经存在，但当前执行窗口没有激活，所以工具还不能真正执行。"
                    : "Bridge 进程已经存在，但当前执行窗口没有激活，而且上一次 bridge enable 请求还报告了投递失败。",
                nextStep: normalizedBridgeLastError.isEmpty
                    ? "执行 reconnect smoke，或重新启用 bridge 窗口，然后再验证工具。"
                    : "先修 bridge 命令投递链路，再重新启用 bridge 窗口并重新验证工具。",
                repairEntry: .hubDiagnostics,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .bridgeToolReadiness,
            state: .ready,
            headline: "桥接 / 工具链路已就绪",
            summary: "Bridge heartbeat 正常，执行窗口也已启用，因此工具调用可以通过当前 Hub 链路执行。",
            nextStep: "继续在同一路径上做会话运行时验证。",
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
                headline: "会话运行时正在等待工具链路变为可执行",
                summary: "在 bridge / 工具层准备好之前，运行时验证必须保持阻塞，而不是假装会话已经能自行恢复。",
                nextStep: "先修复桥接 / 工具就绪状态，再回来执行 Verify。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.state == .failed_recoverable && !snapshot.recoverable {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .diagnosticRequired,
                headline: "Bridge 已通，但会话运行时不可恢复",
                summary: "运行时进入了失败状态，但没有有效恢复路径。这个问题必须与 bridge 或模型路由问题分开看待。",
                nextStep: "打开 XT Diagnostics，检查最后一次失败代码，然后先重建或修复受影响会话，再继续。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.state == .failed_recoverable {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                headline: "会话运行时存在可恢复失败路径",
                summary: "当前会话暂停在一个可恢复失败之后。虽然存在恢复路径，但整体验证还没有完成。",
                nextStep: "走恢复路径或重跑被阻塞的请求，然后确认运行时是否回到 idle 或 completed。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.pendingToolCallCount > 0 || runtimeBusy(snapshot.state) {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                headline: "会话运行时当前处于活动中",
                summary: "运行时当前正在处理或等待某一步完成。验证应当等它回到稳定状态后再做。",
                nextStep: "等当前会话活动结束，再重新打开 Verify。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if sessionID == nil {
            return XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .ready,
                headline: "会话运行时基础已就绪",
                summary: "当前还没有主会话，但运行时基础处于 idle，已经可以在第一个任务到来时创建主会话。",
                nextStep: "直接开始第一个任务，在已验证的路由上创建主会话。",
                repairEntry: .homeSupervisor,
                detailLines: details
            )
        }

        return XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "会话运行时已就绪",
            summary: "当前会话处于稳定状态，可以在已验证的路由上恢复正常工作。",
            nextStep: "不用切页，直接继续进入首个任务即可。",
            repairEntry: .homeSupervisor,
            detailLines: details
        )
    }

    private static func enrichSessionRuntimeSection(
        _ base: XTUnifiedDoctorSection,
        diagnostics: AXProjectContextAssemblyDiagnosticsSummary,
        memoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot?
    ) -> XTUnifiedDoctorSection {
        var section = base
        var detailLines = base.detailLines

        if !diagnostics.detailLines.isEmpty {
            section.projectContextPresentation = diagnostics.presentation
            detailLines += diagnostics.detailLines
        }
        if let memoryAssemblySnapshot {
            detailLines += memoryAssemblySnapshot.continuityDrillDownLines
        }
        if let mirrorProjection = durableCandidateMirrorProjection(from: memoryAssemblySnapshot) {
            section.durableCandidateMirrorProjection = mirrorProjection
            detailLines.append(mirrorProjection.detailLine)
        }
        if let localStoreWriteProjection = localStoreWriteProjection(from: memoryAssemblySnapshot) {
            section.localStoreWriteProjection = localStoreWriteProjection
            detailLines.append(localStoreWriteProjection.detailLine)
        }
        guard detailLines != base.detailLines
                || section.projectContextPresentation != nil
                || section.durableCandidateMirrorProjection != nil
                || section.localStoreWriteProjection != nil else {
            return base
        }
        section.detailLines = orderedUnique(detailLines)
        return section
    }

    private static func durableCandidateMirrorProjection(
        from snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> XTUnifiedDoctorDurableCandidateMirrorProjection? {
        guard let snapshot else { return nil }
        let status = snapshot.durableCandidateMirrorStatus
        guard snapshot.durableCandidateMirrorAttempted || status != .notNeeded else {
            return nil
        }
        return XTUnifiedDoctorDurableCandidateMirrorProjection(
            status: status,
            target: normalizedDoctorField(
                snapshot.durableCandidateMirrorTarget,
                fallback: XTSupervisorDurableCandidateMirror.mirrorTarget
            ),
            attempted: snapshot.durableCandidateMirrorAttempted,
            errorCode: normalizedOptionalDoctorField(snapshot.durableCandidateMirrorErrorCode),
            localStoreRole: normalizedDoctorField(
                snapshot.durableCandidateLocalStoreRole,
                fallback: XTSupervisorDurableCandidateMirror.localStoreRole
            )
        )
    }

    private static func localStoreWriteProjection(
        from snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> XTUnifiedDoctorLocalStoreWriteProjection? {
        guard let snapshot else { return nil }
        let projection = XTUnifiedDoctorLocalStoreWriteProjection(
            personalMemoryIntent: normalizedOptionalDoctorField(snapshot.localPersonalMemoryWriteIntent),
            crossLinkIntent: normalizedOptionalDoctorField(snapshot.localCrossLinkWriteIntent),
            personalReviewIntent: normalizedOptionalDoctorField(snapshot.localPersonalReviewWriteIntent)
        )
        return projection.hasAnyIntent ? projection : nil
    }

    private static func buildCalendarReminderSection(
        snapshot: XTUnifiedDoctorCalendarReminderSnapshot
    ) -> XTUnifiedDoctorSection {
        let guidance = snapshot.authorizationGuidanceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let schedulerStatus = snapshot.schedulerStatusLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let eventStoreStatus = snapshot.eventStoreStatusLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let previewLines = snapshot.upcomingMeetingPreviewLines.enumerated().map { index, line in
            "calendar_meeting_\(index + 1)=\(line)"
        }
        let details = orderedUnique(
            [
                "calendar_permission_owner=xt_device_local",
                "hub_calendar_permission=request_blocked",
                "raw_calendar_event_visibility=device_local_only",
                "calendar_reminders_enabled=\(snapshot.enabled)",
                "calendar_authorization=\(snapshot.authorizationStatus.rawValue)",
                "calendar_authorization_can_read=\(snapshot.authorizationStatus.canReadEvents)",
                guidance.isEmpty ? "calendar_authorization_guidance=none" : "calendar_authorization_guidance=\(guidance)",
                "calendar_heads_up_minutes=\(snapshot.headsUpMinutes)",
                "calendar_final_call_minutes=\(snapshot.finalCallMinutes)",
                "calendar_notification_fallback_enabled=\(snapshot.notificationFallbackEnabled)",
                snapshot.schedulerLastRunAtMs > 0
                    ? "calendar_scheduler_last_run_ms=\(snapshot.schedulerLastRunAtMs)"
                    : "calendar_scheduler_last_run_ms=0",
                schedulerStatus.isEmpty
                    ? "calendar_scheduler_status=unknown"
                    : "calendar_scheduler_status=\(schedulerStatus)",
                snapshot.eventStoreLastRefreshedAtMs > 0
                    ? "calendar_snapshot_last_refresh_ms=\(snapshot.eventStoreLastRefreshedAtMs)"
                    : "calendar_snapshot_last_refresh_ms=0",
                eventStoreStatus.isEmpty
                    ? "calendar_snapshot_status=unknown"
                    : "calendar_snapshot_status=\(eventStoreStatus)",
                "calendar_upcoming_meeting_count=\(snapshot.upcomingMeetingCount)"
            ] + previewLines
        )

        if !snapshot.enabled {
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .ready,
                headline: "XT 自管的日历提醒当前按你的设置保持关闭",
                summary: "Hub 已不再请求 Calendar 权限。个人会议提醒继续只保留在这台 X-Terminal 本机上，现在只是按设置关闭，并不是坏了。",
                nextStep: "如果你想在这台设备上开启会议提醒，去 Supervisor Settings -> Calendar Reminders 运行本地 smoke 动作即可。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        switch snapshot.authorizationStatus {
        case .notDetermined:
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .inProgress,
                headline: "日历提醒已开启，但 XT 还没有日历权限",
                summary: "提醒链路已经打开，但在这台设备授予 Calendar 权限之前，XT 还读不到本地会议。",
                nextStep: "先在 macOS 系统设置里给 X-Terminal 授予 Calendar 权限，然后刷新会议并重跑 live delivery smoke。",
                repairEntry: .systemPermissions,
                detailLines: details
            )
        case .denied, .writeOnly:
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .permissionDenied,
                headline: "当前权限状态下，日历提醒还读不到会议",
                summary: guidance.isEmpty
                    ? "X-Terminal 现在还不能读取 Calendar 事件，所以 Supervisor 的会议提醒在这台设备上必须继续保持阻塞。"
                    : guidance,
                nextStep: "先在 macOS 系统设置里恢复 Calendar 读取权限，再运行 Refresh Meetings，并补一次 live reminder smoke。",
                repairEntry: .systemPermissions,
                detailLines: details
            )
        case .restricted, .unavailable:
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .blockedWaitingUpstream,
                headline: "日历提醒被系统可用性或策略拦住了",
                summary: guidance.isEmpty
                    ? "这台 XT 设备当前还不能向 Supervisor 提供可读取的 Calendar 事件。"
                    : guidance,
                nextStep: "先解决系统层面的 Calendar 限制，再刷新 XT 的提醒快照。",
                repairEntry: .systemPermissions,
                detailLines: details
            )
        case .authorized, .fullAccess:
            if snapshot.upcomingMeetingCount > 0 {
                return XTUnifiedDoctorSection(
                    kind: .calendarReminderReadiness,
                    state: .ready,
                    headline: "XT 日历提醒已就绪，并拿到了本地会议快照",
                    summary: "XT 已在这台设备上持有 Calendar 权限，提醒调度器也在运行，临近会议可以直接在本机可见，不需要把原始事件再绕回 Hub。",
                    nextStep: "先运行一次 Simulate Live Delivery，再在这台 XT 设备上核对一笔真实的临近会议。",
                    repairEntry: .xtDiagnostics,
                    detailLines: details
                )
            }
            return XTUnifiedDoctorSection(
                kind: .calendarReminderReadiness,
                state: .ready,
                headline: "XT 日历提醒已就绪，但暂时没有临近会议",
                summary: "这台设备上的 Calendar 权限和提醒调度器都正常，只是当前本地快照里还没有临近会议。",
                nextStep: "现在先运行 Preview Voice Reminder / Test Notification Fallback / Simulate Live Delivery，然后创建一笔临近测试会议做端到端验证。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }
    }

    private static func buildSkillsCompatibilitySection(
        hubInteractive: Bool,
        snapshot: AXSkillsDoctorSnapshot
    ) -> XTUnifiedDoctorSection {
        let projectRefs = snapshot.projectIndexEntries.map(\.path)
        let globalRefs = snapshot.globalIndexEntries.map(\.path)
        let activePublishers = snapshot.activePublisherIDs
        let activeSources = snapshot.activeSourceIDs
        let baselinePublishers = snapshot.baselinePublisherIDs
        let builtinPreview = snapshot.builtinGovernedSkillIDs.prefix(5)
        let details = [
            "hub_index_available=\(snapshot.hubIndexAvailable)",
            "installed_skills=\(snapshot.installedSkillCount)",
            "compatible_skills=\(snapshot.compatibleSkillCount)",
            "partial_skills=\(snapshot.partialCompatibilityCount)",
            "revoked_matches=\(snapshot.revokedMatchCount)",
            "trusted_publishers=\(snapshot.trustEnabledPublisherCount)",
            "xt_builtin_governed_skills=\(snapshot.builtinGovernedSkillCount)",
            builtinPreview.isEmpty ? "xt_builtin_governed_preview=none" : "xt_builtin_governed_preview=\(builtinPreview.joined(separator: ","))",
            "xt_builtin_supervisor_voice=\(snapshot.builtinSupervisorVoiceAvailable ? "available" : "missing")",
            snapshot.officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel=unknown"
                : "official_channel=\(snapshot.officialChannelStatus)",
            "official_channel_skills=\(snapshot.officialChannelSkillCount)",
            snapshot.officialChannelLastSuccessAtMs > 0
                ? "official_channel_last_success_ms=\(snapshot.officialChannelLastSuccessAtMs)"
                : "official_channel_last_success_ms=0",
            "official_channel_maintenance_enabled=\(snapshot.officialChannelMaintenanceEnabled)",
            "official_channel_maintenance_interval_ms=\(snapshot.officialChannelMaintenanceIntervalMs)",
            snapshot.officialChannelMaintenanceLastRunAtMs > 0
                ? "official_channel_maintenance_last_run_ms=\(snapshot.officialChannelMaintenanceLastRunAtMs)"
                : "official_channel_maintenance_last_run_ms=0",
            snapshot.officialChannelMaintenanceSourceKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel_maintenance_source=unknown"
                : "official_channel_maintenance_source=\(snapshot.officialChannelMaintenanceSourceKind)",
            snapshot.officialChannelLastTransitionAtMs > 0
                ? "official_channel_last_transition_ms=\(snapshot.officialChannelLastTransitionAtMs)"
                : "official_channel_last_transition_ms=0",
            snapshot.officialChannelLastTransitionKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel_last_transition_kind=none"
                : "official_channel_last_transition_kind=\(snapshot.officialChannelLastTransitionKind)",
            snapshot.officialChannelLastTransitionSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel_last_transition_summary=none"
                : "official_channel_last_transition_summary=\(snapshot.officialChannelLastTransitionSummary)",
            snapshot.officialChannelErrorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "official_channel_error=none"
                : "official_channel_error=\(snapshot.officialChannelErrorCode)",
            activePublishers.isEmpty ? "active_publishers=none" : "active_publishers=\(activePublishers.joined(separator: ","))",
            activeSources.isEmpty ? "active_sources=none" : "active_sources=\(activeSources.joined(separator: ","))",
            "local_dev_publisher_active=\(snapshot.localDevPublisherActive ? "yes" : "no")",
            snapshot.baselineRecommendedSkills.isEmpty
                ? "baseline_publishers=none"
                : (baselinePublishers.isEmpty ? "baseline_publishers=none" : "baseline_publishers=\(baselinePublishers.joined(separator: ","))"),
            snapshot.baselineRecommendedSkills.isEmpty
                ? "baseline_local_dev=0/0"
                : "baseline_local_dev=\(snapshot.baselineLocalDevSkillCount)/\(snapshot.baselineRecommendedSkills.count)",
            snapshot.missingBaselineSkillIDs.isEmpty
                ? "baseline_missing=none"
                : "baseline_missing=\(snapshot.missingBaselineSkillIDs.joined(separator: ","))",
            projectRefs.isEmpty ? "project_indexes=none" : "project_indexes=\(projectRefs.joined(separator: ","))",
            globalRefs.isEmpty ? "global_indexes=none" : "global_indexes=\(globalRefs.joined(separator: ","))"
        ]

        if !snapshot.hubIndexAvailable {
            return XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: hubInteractive ? .diagnosticRequired : .blockedWaitingUpstream,
                headline: hubInteractive ? "Hub 技能索引暂时不可用" : "技能兼容性正在等待 Hub 可达",
                summary: hubInteractive
                    ? "Hub 控制面已经可达，但 skills store index 还不可读，所以兼容性必须继续保持 fail-closed。XT 原生 built-in governed skills 仍可用。"
                    : "在 Hub 可达恢复前，XT 还无法验证 managed skills 的兼容性。XT 原生 built-in governed skills 仍可用。",
                nextStep: "先刷新 Hub skills store，再重新打开当前项目 / 全局 skills index，然后再依赖 managed skills。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.revokedMatchCount > 0 {
            return XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: .diagnosticRequired,
                headline: "已安装技能里包含 revoked 匹配",
                summary: "至少有一个已安装或已 pin 的技能命中了被撤销的包或发布者，所以当前兼容性不能算 ready。",
                nextStep: "移除这些 revoked 技能，或重新 pin 到正确来源，然后重新打开 skills index 并重跑 Verify。",
                repairEntry: .xtDiagnostics,
                detailLines: details + Array(snapshot.conflictWarnings.prefix(3))
            )
        }

        if !snapshot.missingBaselineSkillIDs.isEmpty {
            let missing = snapshot.missingBaselineSkillIDs.joined(separator: ", ")
            return XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: .inProgress,
                headline: "Default Agent 基线还不完整",
                summary: "XT 已经可达，也基本兼容，可以继续往下走；但 managed skill 集合里仍缺少一个或多个默认基线技能。XT 原生 built-in governed skills 仍可用，包含已提供的 Supervisor Voice，无需额外 pin。",
                nextStep: "先导入并启用缺失的基线技能，再重新 pin 项目 / 全局 profile。缺失项：\(missing)。",
                repairEntry: .xtDiagnostics,
                detailLines: details
            )
        }

        if snapshot.partialCompatibilityCount > 0 || !snapshot.conflictWarnings.isEmpty {
            return XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: .inProgress,
                headline: "技能兼容性已部分就绪",
                summary: "Managed skills 已经存在，但至少还有一个包需要继续做兼容性清理，或解决 pin 冲突。XT 原生 built-in governed skills 仍可并行使用。",
                nextStep: "在默认认为所有 managed skill 都能稳定运行前，先复核项目 / 全局 skills index。",
                repairEntry: .xtDiagnostics,
                detailLines: details + Array(snapshot.conflictWarnings.prefix(3))
            )
        }

        return XTUnifiedDoctorSection(
            kind: .skillsCompatibilityReadiness,
            state: .ready,
            headline: "技能兼容性已就绪",
            summary: "已安装技能已经足够兼容 XT 使用，Default Agent 基线也已齐备，同时不存在 revoked 匹配或 pin 冲突。XT 原生 built-in governed skills 也会继续和 managed 集合一起可用。",
            nextStep: "当前项目 / 全局 skills index 就可以作为唯一兼容性参考。",
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
        if let firstMainlineBlocker = sections.first(where: {
            $0.kind.contributesToFirstTaskReadiness && $0.state != .ready
        }) {
            return "当前为 fail-closed：\(summaryKindLabel(firstMainlineBlocker.kind)) 仍未就绪：\(firstMainlineBlocker.headline)"
        }
        if readyForFirstTask {
            if let firstAdvisoryIssue = sections.first(where: { $0.state != .ready }) {
                return "首个任务已可启动，但\(summaryKindLabel(firstAdvisoryIssue.kind)) 仍需修复：\(firstAdvisoryIssue.headline)"
            }
            return "配对、模型路由、工具链路和会话运行时已在同一路径验证通过"
        }
        if let firstBlocking = sections.first(where: { $0.state != .ready }) {
            return "当前为 fail-closed：\(summaryKindLabel(firstBlocking.kind)) 仍未就绪：\(firstBlocking.headline)"
        }
        return "Doctor 仍在收集就绪信号"
    }

    private static func summaryKindLabel(_ kind: XTUnifiedDoctorSectionKind) -> String {
        switch kind {
        case .hubReachability:
            return "Hub 可达性"
        case .pairingValidity:
            return "配对有效性"
        case .modelRouteReadiness:
            return "模型路由"
        case .bridgeToolReadiness:
            return "桥接 / 工具链路"
        case .sessionRuntimeReadiness:
            return "会话运行时"
        case .wakeProfileReadiness:
            return "唤醒配置就绪"
        case .talkLoopReadiness:
            return "对话链路就绪"
        case .voicePlaybackReadiness:
            return "语音播放就绪"
        case .calendarReminderReadiness:
            return "日历提醒就绪"
        case .skillsCompatibilityReadiness:
            return "技能兼容性"
        }
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

private func normalizedOptionalDoctorField(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedDoctorField(_ value: String?, fallback: String) -> String {
    normalizedOptionalDoctorField(value) ?? fallback
}

enum XTUnifiedDoctorStore {
    typealias WriteAttemptOverride = @Sendable (Data, URL, Data.WritingOptions) throws -> Void
    typealias LogSink = @Sendable (String) -> Void
    typealias NowProvider = @Sendable () -> Date

    private struct WriteFailureLogState {
        var signature: String
        var nextAllowedLogAt: Date
        var suppressedCount: Int
    }

    private static let testingOverrideLock = NSLock()
    private static var writeAttemptOverrideForTesting: WriteAttemptOverride?
    private static var logSinkForTesting: LogSink?
    private static var nowProviderForTesting: NowProvider?
    private static var writeFailureLogStateByPath: [String: WriteFailureLogState] = [:]
    private static let writeFailureLogCooldown: TimeInterval = 30

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

    static func loadReport(from url: URL) throws -> XTUnifiedDoctorReport {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
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
        } catch {
            emitWriteFailureLog(error, url: url, usedFallback: false)
            return
        }

        if existingReportMatches(data, at: url) {
            clearWriteFailureLogState(for: url)
            return
        }

        do {
            try writeData(data, to: url, options: .atomic)
            clearWriteFailureLogState(for: url)
            return
        } catch {
            guard looksLikeDiskSpaceExhaustion(error),
                  FileManager.default.fileExists(atPath: url.path) else {
                emitWriteFailureLog(error, url: url, usedFallback: false)
                return
            }

            do {
                try writeData(data, to: url, options: [])
                clearWriteFailureLogState(for: url)
            } catch {
                emitWriteFailureLog(error, url: url, usedFallback: true)
            }
        }
    }

    static func installWriteAttemptOverrideForTesting(_ override: WriteAttemptOverride?) {
        withTestingOverrideLock {
            writeAttemptOverrideForTesting = override
        }
    }

    static func installLogSinkForTesting(_ sink: LogSink?) {
        withTestingOverrideLock {
            logSinkForTesting = sink
        }
    }

    static func installNowProviderForTesting(_ provider: NowProvider?) {
        withTestingOverrideLock {
            nowProviderForTesting = provider
        }
    }

    static func resetWriteBehaviorForTesting() {
        withTestingOverrideLock {
            writeAttemptOverrideForTesting = nil
            logSinkForTesting = nil
            nowProviderForTesting = nil
            writeFailureLogStateByPath = [:]
        }
    }

    private static func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        if let override = withTestingOverrideLock({ writeAttemptOverrideForTesting }) {
            try override(data, url, options)
            return
        }
        try data.write(to: url, options: options)
    }

    private static func existingReportMatches(_ data: Data, at url: URL) -> Bool {
        guard let existing = try? Data(contentsOf: url) else { return false }
        return existing == data
    }

    private static func looksLikeDiskSpaceExhaustion(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 28 {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return looksLikeDiskSpaceExhaustion(underlying)
        }
        return false
    }

    private static func emitWriteFailureLog(_ error: Error, url: URL, usedFallback: Bool) {
        let nsError = error as NSError
        let now = currentDate()
        let signature = "\(usedFallback ? "fallback" : "direct"):\(nsError.domain):\(nsError.code)"
        let path = url.path
        let maybeMessage = withTestingOverrideLock { () -> String? in
            if var state = writeFailureLogStateByPath[path],
               state.signature == signature,
               now < state.nextAllowedLogAt {
                state.suppressedCount += 1
                writeFailureLogStateByPath[path] = state
                return nil
            }

            let suppressedCount = writeFailureLogStateByPath[path]?.suppressedCount ?? 0
            writeFailureLogStateByPath[path] = WriteFailureLogState(
                signature: signature,
                nextAllowedLogAt: now.addingTimeInterval(writeFailureLogCooldown),
                suppressedCount: 0
            )

            let prefix = usedFallback
                ? "XTUnifiedDoctor write report failed after non-atomic fallback"
                : "XTUnifiedDoctor write report failed"
            let suppressedSuffix = suppressedCount > 0 ? " suppressed=\(suppressedCount)" : ""
            return "\(prefix): \(error) path=\(path)\(suppressedSuffix)"
        }

        guard let message = maybeMessage else { return }
        if let sink = withTestingOverrideLock({ logSinkForTesting }) {
            sink(message)
            return
        }
        print(message)
    }

    private static func clearWriteFailureLogState(for url: URL) {
        withTestingOverrideLock {
            writeFailureLogStateByPath.removeValue(forKey: url.path)
        }
    }

    private static func currentDate() -> Date {
        if let provider = withTestingOverrideLock({ nowProviderForTesting }) {
            return provider()
        }
        return Date()
    }

    @discardableResult
    private static func withTestingOverrideLock<T>(_ body: () -> T) -> T {
        testingOverrideLock.lock()
        defer { testingOverrideLock.unlock() }
        return body()
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
                    Text("当前链路")
                        .foregroundStyle(.secondary)
                    Text(report.currentRoute.routeLabel)
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("传输方式")
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
                    Text(report.currentRoute.internetHost.isEmpty ? "未设置" : report.currentRoute.internetHost)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(report.currentRoute.internetHost.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("模型")
                        .foregroundStyle(.secondary)
                    Text("已配置=\(report.configuredModelRoles) 可用=\(report.availableModelCount) 已加载=\(report.loadedModelCount)")
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("首个任务")
                        .foregroundStyle(.secondary)
                    Text(report.readyForFirstTask ? "可启动" : "暂缓")
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

    private var routeTruthProjection: AXModelRouteTruthProjection? {
        guard section.kind == .modelRouteReadiness else { return nil }
        if let projection = section.memoryRouteTruthProjection {
            return projection
        }
        return AXModelRouteTruthProjection(doctorDetailLines: section.detailLines)
    }

    private var routeTruthSummary: XTDoctorProjectionSummary? {
        guard let routeTruthProjection else { return nil }
        return XTDoctorRouteTruthPresentation.summary(projection: routeTruthProjection)
    }

    private var projectContextPresentation: AXProjectContextAssemblyPresentation? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let presentation = section.projectContextPresentation {
            return presentation
        }
        return AXProjectContextAssemblyPresentation.from(detailLines: section.detailLines)
    }

    private var durableCandidateMirrorProjection: XTUnifiedDoctorDurableCandidateMirrorProjection? {
        guard section.kind == .sessionRuntimeReadiness else { return nil }
        if let projection = section.durableCandidateMirrorProjection {
            return projection
        }
        return XTUnifiedDoctorDurableCandidateMirrorProjection.from(detailLines: section.detailLines)
    }

    private var durableCandidateMirrorSummary: XTDoctorProjectionSummary? {
        guard let durableCandidateMirrorProjection else { return nil }
        return XTDoctorDurableCandidateMirrorPresentation.summary(projection: durableCandidateMirrorProjection)
    }

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
            Text("下一步：\(section.nextStep)")
                .font(.caption)
            Text("修复入口：\(section.repairEntry.label)")
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)

            if let routeTruthSummary {
                XTDoctorProjectionSummaryView(summary: routeTruthSummary)
            }

            if let projectContextPresentation {
                XTDoctorProjectContextSummaryView(presentation: projectContextPresentation)
            }

            if let durableCandidateMirrorSummary {
                XTDoctorProjectionSummaryView(summary: durableCandidateMirrorSummary)
            }

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

private struct XTDoctorProjectionSummaryView: View {
    let summary: XTDoctorProjectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.title)
                .font(.caption.weight(.semibold))

            ForEach(summary.lines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct XTDoctorProjectContextSummaryView: View {
    let presentation: AXProjectContextAssemblyPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("项目上下文")
                    .font(.caption.weight(.semibold))
                Text(presentation.userSourceBadge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((presentation.sourceKind == .latestCoderUsage ? Color.green : Color.orange).opacity(0.16))
                    )
                    .foregroundStyle(presentation.sourceKind == .latestCoderUsage ? Color.green : Color.orange)
                Spacer()
            }

            if let projectLabel = presentation.projectLabel {
                Text(projectLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(presentation.userStatusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("对话")
                        .foregroundStyle(.secondary)
                    Text(presentation.userDialogueMetric)
                }
                GridRow {
                    Text("深度")
                        .foregroundStyle(.secondary)
                    Text(presentation.userDepthMetric)
                }
                if let coverageMetric = presentation.userCoverageSummary {
                    GridRow {
                        Text("纳入内容")
                            .foregroundStyle(.secondary)
                        Text(coverageMetric)
                    }
                }
                if let boundaryMetric = presentation.userBoundarySummary {
                    GridRow {
                        Text("隐私边界")
                            .foregroundStyle(.secondary)
                        Text(boundaryMetric)
                    }
                }
            }
            .font(.caption2)

            Text(presentation.userDialogueLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.userDepthLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }
}
