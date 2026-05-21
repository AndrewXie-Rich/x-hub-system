import Foundation
#if canImport(Darwin)
import Darwin
#endif
import Testing
@testable import XTerminal

struct HubPairingCoordinatorRoleTurnBridgeLiveTests {
    @Test
    func remoteProjectConversationAppendAndSnapshotRoundTripRoleTurnMetadata() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hubServerRoot = repoRoot
            .appendingPathComponent("x-hub", isDirectory: true)
            .appendingPathComponent("grpc-server", isDirectory: true)
            .appendingPathComponent("hub_grpc_server", isDirectory: true)
        let hubServerJS = hubServerRoot
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent("server.js")
        let protoPath = repoRoot
            .appendingPathComponent("protocol", isDirectory: true)
            .appendingPathComponent("hub_protocol_v1.proto")
        let nodeModules = hubServerRoot.appendingPathComponent("node_modules", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubServerJS.path),
              FileManager.default.fileExists(atPath: protoPath.path),
              FileManager.default.fileExists(atPath: nodeModules.path),
              let nodeBin = findNodeBinary() else {
            return
        }

        let stateDir = try makeTempDir(prefix: "xt_role_turn_bridge_e2e")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        let dataDir = stateDir.appendingPathComponent("data", isDirectory: true)
        let runtimeDir = stateDir.appendingPathComponent("runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        try FileManager.default.createDirectory(at: clientKitBase, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: clientKitHub, withDestinationURL: hubServerRoot)

        let grpcPort = try freeLoopbackPort()
        let pairingPort = try freeLoopbackPort()
        let token = "xt-role-turn-bridge-\(UUID().uuidString)"
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_HOST='127.0.0.1'
            export HUB_PORT='\(grpcPort)'
            export HUB_CLIENT_TOKEN='\(token)'
            export HUB_DEVICE_ID='dev-xt-role-turn-e2e'
            export HUB_USER_ID='user-xt-role-turn-e2e'
            export HUB_APP_ID='x_terminal'
            export HUB_GRPC_TLS_MODE='insecure'
            export HUB_PROTO_PATH='\(protoPath.path)'
            export AXHUBCTL_NODE_BIN='\(nodeBin)'
            """
        )

        let server = TempHubRoleTurnServer(
            nodeBin: nodeBin,
            serverJS: hubServerJS,
            serverRoot: hubServerRoot,
            stateDir: stateDir,
            grpcPort: grpcPort,
            pairingPort: pairingPort,
            token: token,
            protoPath: protoPath,
            dbPath: dataDir.appendingPathComponent("hub.sqlite3"),
            runtimeDir: runtimeDir
        )
        try server.start()
        defer { server.stop() }

        let options = HubRemoteConnectOptions(
            grpcPort: grpcPort,
            pairingPort: pairingPort,
            deviceName: "XT Role Turn Bridge E2E",
            internetHost: "127.0.0.1",
            axhubctlPath: "",
            configuredEndpointIsAuthoritative: true,
            stateDir: stateDir
        )

        let projectId = "project-role-turn-xt-e2e"
        let threadKey = XTProjectConversationMirror.projectThreadKey(projectId: projectId)
        let dispatchId = "dispatch_xt_bridge_e2e_1"
        let dispatchLineage = AXChatMessageLineageMetadata(
            dispatchId: dispatchId,
            sourceRole: "supervisor",
            targetRole: "coder",
            dispatchKind: "supervisor_to_coder",
            projectId: projectId,
            runId: "run-xt-bridge-e2e-1",
            launchRunId: "launch-xt-bridge-e2e-1",
            status: "dispatched",
            createdAtMs: 1_772_200_000_125
        )
        let createdAt = 1_772_200_000.125
        let dispatchMessages = XTProjectConversationMirror.roleAwareMessages(
            projectId: projectId,
            threadKey: threadKey,
            userText: "Supervisor dispatches a Hub-first role metadata bridge smoke.",
            assistantText: "Coder replies through the same Hub Memory dispatch id.",
            createdAt: createdAt,
            userSender: .supervisor,
            userLineage: dispatchLineage,
            assistantLineage: dispatchLineage.coderReply(status: "completed")
        )

        let appendDispatch = await HubPairingCoordinator.shared.appendRemoteProjectConversationTurn(
            options: options,
            payload: HubRemoteProjectConversationPayload(
                projectId: projectId,
                threadKey: threadKey,
                requestId: XTProjectConversationMirror.requestID(projectId: projectId, createdAt: createdAt),
                createdAtMs: XTProjectConversationMirror.createdAtMs(createdAt),
                userText: "",
                assistantText: "",
                messages: dispatchMessages
            )
        )
        #expect(appendDispatch.ok == true, "append failed: \(appendDispatch.logText)")

        let reviewerCreatedAt = createdAt + 0.5
        let reviewerMessage = XTProjectConversationMirrorMessage(
            role: "user",
            content: "Reviewer note confirms the bridge must read Hub metadata before local text fallback.",
            turnMetadata: XTProjectConversationTurnMetadata(
                clientMessageId: "reviewer-note-xt-bridge-e2e-1",
                sourceRole: "reviewer",
                targetRole: "coder",
                projectId: projectId,
                threadKey: threadKey,
                dispatchId: dispatchId,
                dispatchKind: "reviewer_note",
                reviewerNoteId: "reviewer-note-xt-bridge-e2e-1",
                status: "observed",
                evidenceRefs: ["xt_bridge_role_turn_e2e"],
                auditRefs: ["xt_bridge_role_turn_e2e"],
                observedAtMs: XTProjectConversationMirror.createdAtMs(reviewerCreatedAt)
            )
        )
        let appendReviewer = await HubPairingCoordinator.shared.appendRemoteProjectConversationTurn(
            options: options,
            payload: HubRemoteProjectConversationPayload(
                projectId: projectId,
                threadKey: threadKey,
                requestId: "\(XTProjectConversationMirror.requestID(projectId: projectId, createdAt: reviewerCreatedAt))_reviewer",
                createdAtMs: XTProjectConversationMirror.createdAtMs(reviewerCreatedAt),
                userText: "",
                assistantText: "",
                messages: [reviewerMessage]
            )
        )
        #expect(appendReviewer.ok == true, "reviewer append failed: \(appendReviewer.logText)")

        let toolCreatedAt = createdAt + 1.0
        let toolLineage = dispatchLineage.coderReply(status: "running")
        let toolMessages = [
            XTProjectConversationMirror.roleEventMessage(
                role: "tool",
                projectId: projectId,
                threadKey: threadKey,
                content: "Tool approval awaiting authorization.",
                createdAt: toolCreatedAt,
                sourceRole: "tool",
                targetRole: "supervisor",
                dispatchKind: "tool_approval",
                status: "awaiting_authorization",
                lineage: toolLineage,
                toolCallId: "call-xt-bridge-e2e-1",
                tags: ["xt_tool_approval"]
            ),
            XTProjectConversationMirror.roleEventMessage(
                role: "system",
                projectId: projectId,
                threadKey: threadKey,
                content: "Tool approval decision observed.",
                createdAt: toolCreatedAt + 0.001,
                sourceRole: "user",
                targetRole: "coder",
                dispatchKind: "tool_approval_decision",
                status: "completed",
                lineage: toolLineage,
                toolCallId: "call-xt-bridge-e2e-1",
                tags: ["xt_tool_approval_decision", "approve_one"]
            ),
            XTProjectConversationMirror.roleEventMessage(
                role: "tool",
                projectId: projectId,
                threadKey: threadKey,
                content: "Tool result observed.",
                createdAt: toolCreatedAt + 0.002,
                sourceRole: "tool",
                targetRole: "coder",
                dispatchKind: "tool_result",
                status: "completed",
                lineage: toolLineage,
                toolCallId: "call-xt-bridge-e2e-1",
                tags: ["xt_tool_result", "execution", "ok"]
            )
        ].compactMap { $0 }
        let appendToolEvents = await HubPairingCoordinator.shared.appendRemoteProjectConversationTurn(
            options: options,
            payload: HubRemoteProjectConversationPayload(
                projectId: projectId,
                threadKey: threadKey,
                requestId: "\(XTProjectConversationMirror.requestID(projectId: projectId, createdAt: toolCreatedAt))_tool_events",
                createdAtMs: XTProjectConversationMirror.createdAtMs(toolCreatedAt),
                userText: "",
                assistantText: "",
                messages: toolMessages
            )
        )
        #expect(appendToolEvents.ok == true, "tool events append failed: \(appendToolEvents.logText)")

        let heartbeatCreatedAtMs = XTProjectConversationMirror.createdAtMs(toolCreatedAt + 0.5)
        let heartbeatRecord = makeHeartbeatRecord(
            projectId: projectId,
            projectName: "Role Turn Bridge E2E",
            createdAtMs: heartbeatCreatedAtMs
        )
        let heartbeatMessage = try #require(
            SupervisorProjectHeartbeatCanonicalSync.roleTurnMessage(record: heartbeatRecord)
        )
        let appendHeartbeat = await HubPairingCoordinator.shared.appendRemoteProjectConversationTurn(
            options: options,
            payload: HubRemoteProjectConversationPayload(
                projectId: projectId,
                threadKey: threadKey,
                requestId: "\(XTProjectConversationMirror.requestID(projectId: projectId, createdAt: Double(heartbeatCreatedAtMs) / 1000.0))_heartbeat",
                createdAtMs: heartbeatCreatedAtMs,
                userText: "",
                assistantText: "",
                messages: [heartbeatMessage]
            )
        )
        #expect(appendHeartbeat.ok == true, "heartbeat append failed: \(appendHeartbeat.logText)")

        let snapshot = await HubPairingCoordinator.shared.fetchRemoteMemorySnapshot(
            options: options,
            mode: "project",
            projectId: projectId,
            canonicalLimit: 4,
            workingLimit: 10,
            timeoutSec: 3.0
        )
        #expect(snapshot.ok == true, "snapshot failed: \(snapshot.logText)")

        let roleMessages = snapshot.roleTurnMessages
            .filter { $0.turnMetadata?.dispatchId == dispatchId }
        #expect(roleMessages.count == 6)
        #expect(roleMessages.contains { $0.turnMetadata?.sourceRole == "supervisor" && $0.turnMetadata?.targetRole == "coder" })
        #expect(roleMessages.contains { $0.turnMetadata?.sourceRole == "coder" && $0.turnMetadata?.targetRole == "supervisor" })
        #expect(roleMessages.contains { $0.turnMetadata?.sourceRole == "reviewer" && $0.turnMetadata?.reviewerNoteId == "reviewer-note-xt-bridge-e2e-1" })
        #expect(roleMessages.contains { $0.turnMetadata?.dispatchKind == "tool_approval" && $0.turnMetadata?.status == "awaiting_authorization" })
        #expect(roleMessages.contains { $0.turnMetadata?.dispatchKind == "tool_approval_decision" && $0.turnMetadata?.toolCallId == "call-xt-bridge-e2e-1" })
        #expect(roleMessages.contains { $0.turnMetadata?.dispatchKind == "tool_result" && $0.turnMetadata?.targetRole == "coder" })
        let heartbeatMessages = snapshot.roleTurnMessages
            .filter { $0.turnMetadata?.dispatchKind == "heartbeat" }
        #expect(heartbeatMessages.count == 1)
        #expect(heartbeatMessages.first?.turnMetadata?.sourceRole == "hub")
        #expect(heartbeatMessages.first?.turnMetadata?.targetRole == "all")
        #expect(heartbeatMessages.first?.turnMetadata?.status == "observed")
        #expect(heartbeatMessages.first?.turnMetadata?.auditRefs == [heartbeatRecord.auditRef])
        #expect(heartbeatMessages.first?.content.contains("Heartbeat governance projection observed.") == true)

        let projection = XTProjectTranscriptProjection.build(
            projectId: projectId,
            projectName: "Role Turn Bridge E2E",
            hubMessages: snapshot.roleTurnMessages
        )
        #expect(projection.source == "hub_role_turn_metadata_projection")
        #expect(projection.latestDispatchId == dispatchId)
        #expect(projection.latestSupervisorDispatch?.role == "supervisor")
        #expect(projection.latestCoderReply?.role == "coder")
        #expect(projection.latestReviewerNote?.role == "reviewer")
        #expect(projection.latestToolApproval?.status == "awaiting_authorization")
        #expect(projection.latestToolApprovalDecision?.status == "completed")
        #expect(projection.latestToolResult?.status == "completed")
        #expect(projection.latestHeartbeat?.role == "hub")
        #expect(projection.latestHeartbeat?.status == "observed")
        #expect(projection.status == "latest_coder_reply_observed")
        #expect(projection.promptBlock().contains("truth_boundary=Hub role-turn metadata projection"))
    }

    private func makeHeartbeatRecord(
        projectId: String,
        projectName: String,
        createdAtMs: Int64
    ) -> SupervisorProjectHeartbeatCanonicalRecord {
        SupervisorProjectHeartbeatCanonicalRecord(
            schemaVersion: SupervisorProjectHeartbeatCanonicalRecord.schemaVersion,
            projectId: projectId,
            projectName: projectName,
            updatedAtMs: createdAtMs,
            lastHeartbeatAtMs: max(0, createdAtMs - 1_000),
            statusDigest: "Hub heartbeat governance is alive",
            currentStateSummary: "Role-aware heartbeat projection is available from Hub Memory.",
            nextStepSummary: "Keep XT projection sourced from Hub role metadata.",
            blockerSummary: "",
            latestQualityBand: nil,
            latestQualityScore: nil,
            weakReasons: [],
            openAnomalyTypes: [],
            projectPhase: nil,
            executionStatus: nil,
            riskTier: nil,
            cadence: makeHeartbeatCadence(createdAtMs: createdAtMs),
            nextReviewKind: .reviewPulse,
            nextReviewDueAtMs: createdAtMs + 60_000,
            nextReviewDue: false,
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["role_turn_bridge_e2e"],
                whatChangedText: "Hub emitted a role-aware heartbeat projection.",
                whyImportantText: "XT must consume this as Hub truth rather than local memory authority.",
                systemNextStepText: "Continue projecting conversation state from Hub Memory."
            ),
            recoveryDecision: nil,
            auditRef: "supervisor_project_heartbeat:\(projectId):\(createdAtMs)"
        )
    }

    private func makeHeartbeatCadence(createdAtMs: Int64) -> SupervisorCadenceExplainability {
        SupervisorCadenceExplainability(
            progressHeartbeat: SupervisorCadenceDimensionExplainability(
                dimension: .progressHeartbeat,
                configuredSeconds: 300,
                recommendedSeconds: 300,
                effectiveSeconds: 300,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: createdAtMs + 300_000,
                nextDueReasonCodes: ["heartbeat_active"],
                isDue: false
            ),
            reviewPulse: SupervisorCadenceDimensionExplainability(
                dimension: .reviewPulse,
                configuredSeconds: 900,
                recommendedSeconds: 900,
                effectiveSeconds: 900,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: createdAtMs + 60_000,
                nextDueReasonCodes: ["role_turn_bridge_e2e"],
                isDue: false
            ),
            brainstormReview: SupervisorCadenceDimensionExplainability(
                dimension: .brainstormReview,
                configuredSeconds: 1800,
                recommendedSeconds: 1800,
                effectiveSeconds: 1800,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: createdAtMs + 1_800_000,
                nextDueReasonCodes: ["not_due"],
                isDue: false
            ),
            eventFollowUpCooldownSeconds: 300
        )
    }

    private func makeTempDir(prefix: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeFile(_ url: URL, _ contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func findNodeBinary() -> String? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func freeLoopbackPort() throws -> Int {
        #if canImport(Darwin)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EADDRNOTAVAIL) }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &len)
            }
        }
        guard nameResult == 0 else { throw POSIXError(.EINVAL) }
        return Int(UInt16(bigEndian: bound.sin_port))
        #else
        return Int.random(in: 40_000...60_000)
        #endif
    }
}

private final class TempHubRoleTurnServer {
    private let nodeBin: String
    private let serverJS: URL
    private let serverRoot: URL
    private let stateDir: URL
    private let grpcPort: Int
    private let pairingPort: Int
    private let token: String
    private let protoPath: URL
    private let dbPath: URL
    private let runtimeDir: URL
    private let stdoutPath: URL
    private let stderrPath: URL
    private var process: Process?

    init(
        nodeBin: String,
        serverJS: URL,
        serverRoot: URL,
        stateDir: URL,
        grpcPort: Int,
        pairingPort: Int,
        token: String,
        protoPath: URL,
        dbPath: URL,
        runtimeDir: URL
    ) {
        self.nodeBin = nodeBin
        self.serverJS = serverJS
        self.serverRoot = serverRoot
        self.stateDir = stateDir
        self.grpcPort = grpcPort
        self.pairingPort = pairingPort
        self.token = token
        self.protoPath = protoPath
        self.dbPath = dbPath
        self.runtimeDir = runtimeDir
        self.stdoutPath = stateDir.appendingPathComponent("hub_server.out.log")
        self.stderrPath = stateDir.appendingPathComponent("hub_server.err.log")
    }

    func start() throws {
        let stdout = FileManager.default.createFile(atPath: stdoutPath.path, contents: nil)
        let stderr = FileManager.default.createFile(atPath: stderrPath.path, contents: nil)
        guard stdout, stderr,
              let outHandle = try? FileHandle(forWritingTo: stdoutPath),
              let errHandle = try? FileHandle(forWritingTo: stderrPath) else {
            throw POSIXError(.EIO)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodeBin)
        process.arguments = [serverJS.path]
        process.currentDirectoryURL = serverRoot
        process.environment = ProcessInfo.processInfo.environment.merging([
            "HUB_HOST": "127.0.0.1",
            "HUB_PORT": String(grpcPort),
            "HUB_PAIRING_ENABLE": "0",
            "HUB_PAIRING_PORT": String(pairingPort),
            "HUB_DB_PATH": dbPath.path,
            "HUB_RUNTIME_BASE_DIR": runtimeDir.path,
            "HUB_CLIENT_TOKEN": token,
            "HUB_GRPC_TLS_MODE": "insecure",
            "HUB_PROVIDER_KEY_REFRESH_ENABLED": "false",
            "HUB_PROVIDER_KEY_QUOTA_REFRESH_ENABLED": "false",
            "HUB_MEMORY_AT_REST_ENABLED": "false",
            "HUB_MEMORY_RETENTION_ENABLED": "false",
            "HUB_PROTO_PATH": protoPath.path
        ]) { _, new in new }
        process.standardOutput = outHandle
        process.standardError = errHandle
        try process.run()
        try? outHandle.close()
        try? errHandle.close()
        self.process = process

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if process.isRunning == false {
                throw NSError(
                    domain: "TempHubRoleTurnServer",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Hub server exited before listening. stdout=\(read(stdoutPath)) stderr=\(read(stderrPath))"]
                )
            }
            if read(stdoutPath).contains("[hub_grpc] listening") {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw NSError(
            domain: "TempHubRoleTurnServer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for Hub server. stdout=\(read(stdoutPath)) stderr=\(read(stderrPath))"]
        )
    }

    func stop() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                #if canImport(Darwin)
                kill(process.processIdentifier, SIGKILL)
                #else
                process.interrupt()
                #endif
            }
        }
    }

    private func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
