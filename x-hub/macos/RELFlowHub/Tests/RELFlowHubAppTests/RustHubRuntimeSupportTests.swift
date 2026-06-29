import XCTest
@testable import RELFlowHub

final class RustHubRuntimeSupportTests: XCTestCase {
    func testEmbeddedPackageInfoRequiresPackagedBinaryAndRunner() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeExecutableFile(at: root.appendingPathComponent("bin/xhubd"))
        try makeExecutableFile(at: root.appendingPathComponent("tools/run_rust_hub.command"))
        try """
        {
          "schema_version": "xhub.embedded_rust_hub.v1",
          "source_package_dir": "/tmp/rust-hub-20260512T152203Z",
          "embedded_at_utc": "2026-05-12T15:22:03Z"
        }
        """.write(to: root.appendingPathComponent("embedded_manifest.json"), atomically: true, encoding: .utf8)

        let info = RustHubRuntimeSupport.embeddedPackageInfo(root: root)

        XCTAssertTrue(info.exists)
        XCTAssertTrue(info.valid)
        XCTAssertEqual(info.rootPath, root.path)
        XCTAssertEqual(info.sourcePackageDir, "/tmp/rust-hub-20260512T152203Z")
        XCTAssertEqual(info.embeddedAtUTC, "2026-05-12T15:22:03Z")
    }

    func testLocalModelRepairPlanURLCarriesRuntimeBaseDirAndTaskKind() throws {
        let runtimeBaseDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/AX/RELFlowHub", isDirectory: true)

        let url = try XCTUnwrap(
            RustHubRuntimeSupport.localModelRepairPlanURL(
                taskKind: "vision_understand",
                runtimeBaseDir: runtimeBaseDir,
                baseURL: "http://127.0.0.1:50151/"
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "http")
        XCTAssertEqual(components.host, "127.0.0.1")
        XCTAssertEqual(components.path, "/model/repair-plan")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "runtime_base_dir" })?.value,
            runtimeBaseDir.standardizedFileURL.path
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "task_kind" })?.value,
            "vision_understand"
        )
    }

    func testLocalModelRepairApplyURLAndBodyCarriesConfirmationToken() throws {
        let runtimeBaseDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/AX/RELFlowHub", isDirectory: true)
        let plan = try XCTUnwrap(
            RustLocalModelRepairPlanSupport.decode(data: Data(sampleRustRepairPlanJSON.utf8))
        )

        let url = try XCTUnwrap(
            RustHubRuntimeSupport.localModelRepairApplyURL(baseURL: "http://127.0.0.1:50151/")
        )
        let body = try XCTUnwrap(
            RustHubRuntimeSupport.localModelRepairApplyRequestBody(
                plan: plan,
                requestedBy: "unit_test",
                runtimeBaseDir: runtimeBaseDir
            )
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(url.path, "/model/repair-apply")
        XCTAssertEqual(object["action"] as? String, "install_provider_pack:mlx_vlm")
        XCTAssertEqual(object["task_kind"] as? String, "vision_understand")
        XCTAssertEqual(object["provider_id"] as? String, "mlx_vlm")
        XCTAssertEqual(object["confirm"] as? Bool, true)
        XCTAssertEqual(object["dry_run"] as? Bool, false)
        XCTAssertEqual(object["confirmation_token"] as? String, "confirm:install_provider_pack:mlx_vlm")
        XCTAssertEqual(object["requested_by"] as? String, "unit_test")
        XCTAssertEqual(object["runtime_base_dir"] as? String, runtimeBaseDir.standardizedFileURL.path)
    }

    func testLocalModelRepairApplyDecodeCarriesQueuedJobPolicyWithoutSecrets() throws {
        let result = try XCTUnwrap(
            RustLocalModelRepairApplySupport.decode(data: Data(sampleRustRepairApplyJSON.utf8))
        )

        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.accepted)
        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.status, "queued_waiting_executor")
        XCTAssertEqual(result.jobID, "repair_install_provider_pack_mlx_vlm_1001")
        XCTAssertEqual(result.resolved.action, "install_provider_pack:mlx_vlm")
        XCTAssertEqual(result.jobPolicy.executionMode, "queued_nonblocking")
        XCTAssertFalse(result.jobPolicy.uiThreadBlockingAllowed)
        XCTAssertFalse(result.jobPolicy.httpRequestBlockingAllowed)
        XCTAssertTrue(result.jobPolicy.executorReady)

        let secretRaw = sampleRustRepairApplyJSON.replacingOccurrences(
            of: "\"job_id\": \"repair_install_provider_pack_mlx_vlm_1001\"",
            with: "\"job_id\": \"api_key=sk-should-not-cross-ui\""
        )
        XCTAssertNil(RustLocalModelRepairApplySupport.decode(data: Data(secretRaw.utf8)))
    }

    func testLocalModelRepairJobsURLAndDecodeCarriesLatestJob() throws {
        let runtimeBaseDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/AX/RELFlowHub", isDirectory: true)
        let url = try XCTUnwrap(
            RustHubRuntimeSupport.localModelRepairJobsURL(
                limit: 7,
                runtimeBaseDir: runtimeBaseDir,
                baseURL: "http://127.0.0.1:50151/"
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let snapshot = try XCTUnwrap(
            RustLocalModelRepairApplySupport.decodeJobs(data: Data(sampleRustRepairJobsJSON.utf8))
        )

        XCTAssertEqual(components.path, "/model/repair-jobs")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "limit" })?.value, "7")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "runtime_base_dir" })?.value,
            runtimeBaseDir.standardizedFileURL.path
        )
        XCTAssertTrue(snapshot.ok)
        XCTAssertEqual(snapshot.jobs.count, 2)
        XCTAssertEqual(snapshot.latestJob?.jobID, "repair_install_provider_pack_mlx_vlm_1002")
        XCTAssertEqual(snapshot.latestJob?.status, "applied_pending_runtime_restart")
        XCTAssertEqual(snapshot.latestJob?.executorState.reasonCode, "rust_model_repair_executor_completed")

        let secretRaw = sampleRustRepairJobsJSON.replacingOccurrences(
            of: "\"requested_by\": \"swift_hub_settings\"",
            with: "\"requested_by\": \"api_key=sk-should-not-cross-ui\""
        )
        XCTAssertNil(RustLocalModelRepairApplySupport.decodeJobs(data: Data(secretRaw.utf8)))
    }

    func testNodeSidecarEnvironmentPointsAtEmbeddedPackageWithoutCutoverAuthority() throws {
        let info = RustHubEmbeddedPackageInfo(
            rootPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub",
            xhubdPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/bin/xhubd",
            runnerPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/tools/run_rust_hub.command",
            manifestPath: "",
            exists: true,
            valid: true,
            sourcePackageDir: "",
            embeddedAtUTC: ""
        )

        let env = RustHubRuntimeSupport.nodeSidecarEnvironmentAdditions(embeddedPackage: info)

        XCTAssertEqual(env["XHUB_RUST_HUB_EMBEDDED"], "1")
        XCTAssertEqual(env["XHUB_RUST_HUB_ROOT"], info.rootPath)
        XCTAssertEqual(env["XHUB_RUST_HUB_RUNNER"], info.runnerPath)
        XCTAssertEqual(env["XHUB_RUST_HUB_HTTP_PORT"], "50151")
        XCTAssertNil(env["XHUB_RUST_SCHEDULER_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION"])
        XCTAssertNil(env["XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER"])
        XCTAssertNil(env["XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY"])
        XCTAssertNil(env["XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION"])
        XCTAssertNil(env["XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER"])
        XCTAssertNil(env["XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY"])
        XCTAssertNil(env["XHUB_RUST_MEMORY_WRITER_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_SKILLS_EXECUTION_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER"])
        XCTAssertNil(env["XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER"])
        XCTAssertNil(env["XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP"])
        XCTAssertNil(env["XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE"])
    }

    func testNodeSidecarEnvironmentPassesProductionAuthorityOnlyWithExplicitCutoverAndClampsMemorySkills() throws {
        let overrideRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: overrideRoot) }
        try makeExecutableFile(at: overrideRoot.appendingPathComponent("bin/xhubd"))
        try makeExecutableFile(at: overrideRoot.appendingPathComponent("tools/run_rust_hub.command"))

        let info = RustHubEmbeddedPackageInfo(
            rootPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub",
            xhubdPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/bin/xhubd",
            runnerPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/tools/run_rust_hub.command",
            manifestPath: "",
            exists: true,
            valid: true,
            sourcePackageDir: "",
            embeddedAtUTC: ""
        )
        let base = RustHubRuntimeSupport.nodeSidecarBaseEnvironment([
            "XHUB_ENABLE_RUST_AUTHORITY_CUTOVER": "1",
            "XHUB_RUST_HUB_ROOT": overrideRoot.path,
            "XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY": "1",
            "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION": "1",
            "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL": "http://127.0.0.1:50151",
            "XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY": "1",
            "XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION": "1",
            "XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL": "http://127.0.0.1:50151",
            "XHUB_RUST_SCHEDULER_AUTHORITY": "1",
            "XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL": "http://127.0.0.1:50151",
            "XHUB_RUST_MEMORY_WRITER_AUTHORITY": "1",
            "XHUB_RUST_SKILLS_EXECUTION_AUTHORITY": "1"
        ])

        let env = RustHubRuntimeSupport.nodeSidecarEnvironmentAdditions(
            embeddedPackage: info,
            baseEnvironment: base
        )

        XCTAssertEqual(env["XHUB_RUST_HUB_ROOT"], overrideRoot.path)
        XCTAssertEqual(env["XHUB_RUST_HUB_RUNNER"], overrideRoot.appendingPathComponent("tools/run_rust_hub.command").path)
        XCTAssertEqual(env["XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY"], "1")
        XCTAssertEqual(env["XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION"], "1")
        XCTAssertEqual(env["XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY"], "1")
        XCTAssertEqual(env["XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION"], "1")
        XCTAssertEqual(env["XHUB_RUST_SCHEDULER_AUTHORITY"], "1")
        XCTAssertNil(env["XHUB_RUST_MEMORY_WRITER_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_SKILLS_EXECUTION_AUTHORITY"])
    }

    func testNodeSidecarRuntimeBaseStaysSwiftBaseWithoutExplicitCutover() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let swiftBase = root.appendingPathComponent("swift-sidecar", isDirectory: true)
        let rustRuntime = root.appendingPathComponent("real-home/Library/Application Support/AX/rust-hub/local/runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: swiftBase, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rustRuntime, withIntermediateDirectories: true)

        let selected = RustHubRuntimeSupport.nodeSidecarRuntimeBaseDir(
            swiftBaseDir: swiftBase,
            baseEnvironment: [
                "XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY": "1"
            ],
            homeDirectory: root.appendingPathComponent("real-home", isDirectory: true)
        )

        XCTAssertEqual(selected.standardizedFileURL.path, swiftBase.standardizedFileURL.path)
    }

    func testNodeSidecarRuntimeBaseUsesRustLiveRuntimeAfterAuthorityCutover() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let swiftBase = root.appendingPathComponent("swift-sidecar", isDirectory: true)
        let rustHome = root.appendingPathComponent("real-home", isDirectory: true)
        let rustRuntime = rustHome.appendingPathComponent("Library/Application Support/AX/rust-hub/local/runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: swiftBase, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rustRuntime, withIntermediateDirectories: true)

        let selected = RustHubRuntimeSupport.nodeSidecarRuntimeBaseDir(
            swiftBaseDir: swiftBase,
            baseEnvironment: [
                "XHUB_ENABLE_RUST_AUTHORITY_CUTOVER": "1",
                "XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY": "1",
                "XHUB_RUST_LOCAL_ML_EXECUTION_AUTHORITY": "1"
            ],
            homeDirectory: rustHome
        )

        XCTAssertEqual(selected.standardizedFileURL.path, rustRuntime.standardizedFileURL.path)
    }

    func testNodeSidecarRuntimeBaseHonorsExplicitOverride() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let swiftBase = root.appendingPathComponent("swift-sidecar", isDirectory: true)
        let override = root.appendingPathComponent("override-runtime", isDirectory: true)

        let selected = RustHubRuntimeSupport.nodeSidecarRuntimeBaseDir(
            swiftBaseDir: swiftBase,
            baseEnvironment: [
                "XHUB_NODE_SIDECAR_RUNTIME_BASE_DIR": override.path
            ],
            homeDirectory: root
        )

        XCTAssertEqual(selected.standardizedFileURL.path, override.standardizedFileURL.path)
    }

    func testNodeSidecarEnvironmentDropsStaleProductionAuthorityWithoutExplicitCutover() throws {
        let info = RustHubEmbeddedPackageInfo(
            rootPath: "/Users/test/Library/Application Support/AX/rust-hub/current",
            xhubdPath: "/Users/test/Library/Application Support/AX/rust-hub/current/bin/xhubd",
            runnerPath: "/Users/test/Library/Application Support/AX/rust-hub/current/tools/run_rust_hub.command",
            manifestPath: "",
            exists: true,
            valid: true,
            sourcePackageDir: "",
            embeddedAtUTC: ""
        )
        let base = RustHubRuntimeSupport.nodeSidecarBaseEnvironment([
            "XHUB_RUST_HUB_ROOT": "/Users/test/rust hub/dist/stale",
            "XHUB_RUST_SCHEDULER_AUTHORITY": "1",
            "XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY": "1",
            "XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY": "1",
            "XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER": "1"
        ])

        let env = RustHubRuntimeSupport.nodeSidecarEnvironmentAdditions(
            embeddedPackage: info,
            baseEnvironment: base
        )

        XCTAssertEqual(env["XHUB_RUST_HUB_ROOT"], info.rootPath)
        XCTAssertEqual(env["XHUB_RUST_HUB_RUNNER"], info.runnerPath)
        XCTAssertNil(base["XHUB_RUST_SCHEDULER_AUTHORITY"])
        XCTAssertNil(base["XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY"])
        XCTAssertNil(base["XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY"])
        XCTAssertNil(base["XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER"])
        XCTAssertNil(env["XHUB_RUST_SCHEDULER_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY"])
    }

    func testNodeSidecarEnvironmentPassesResolvedRustAccessKeyWithoutFilePath() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeExecutableFile(at: root.appendingPathComponent("bin/xhubd"))
        try makeExecutableFile(at: root.appendingPathComponent("tools/run_rust_hub.command"))
        let keyFile = root.appendingPathComponent("secrets/xhubd_domain_access_key")
        try FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "node-sidecar-secret\n".write(to: keyFile, atomically: true, encoding: .utf8)

        let info = RustHubEmbeddedPackageInfo(
            rootPath: root.path,
            xhubdPath: root.appendingPathComponent("bin/xhubd").path,
            runnerPath: root.appendingPathComponent("tools/run_rust_hub.command").path,
            manifestPath: "",
            exists: true,
            valid: true,
            sourcePackageDir: "",
            embeddedAtUTC: ""
        )

        let env = RustHubRuntimeSupport.nodeSidecarEnvironmentAdditions(
            embeddedPackage: info,
            baseEnvironment: [:]
        )

        XCTAssertEqual(env["XHUB_RUST_HTTP_ACCESS_KEY"], "node-sidecar-secret")
        XCTAssertEqual(env["XHUB_RUST_HUB_ACCESS_KEY"], "node-sidecar-secret")
        XCTAssertNil(env["XHUB_RUST_HTTP_ACCESS_KEY_FILE"])
        XCTAssertNil(env["XHUB_RUST_HUB_ACCESS_KEY_FILE"])
    }

    func testNodeSidecarBaseEnvironmentRemovesFalseAuthorityDefaults() {
        let env = RustHubRuntimeSupport.nodeSidecarBaseEnvironment([
            "XHUB_RUST_SCHEDULER_AUTHORITY": "0",
            "XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY": "false",
            "XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY": "off",
            "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL": "http://127.0.0.1:50151"
        ])

        XCTAssertNil(env["XHUB_RUST_SCHEDULER_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY"])
        XCTAssertNil(env["XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY"])
        XCTAssertEqual(env["XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL"], "http://127.0.0.1:50151")
    }

    func testPreferredPackageUsesActiveRootWhenValid() {
        let embedded = RustHubEmbeddedPackageInfo(
            rootPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub",
            xhubdPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/bin/xhubd",
            runnerPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/tools/run_rust_hub.command",
            manifestPath: "",
            exists: true,
            valid: true,
            sourcePackageDir: "",
            embeddedAtUTC: ""
        )
        let active = RustHubEmbeddedPackageInfo(
            rootPath: "/Users/test/Library/Application Support/AX/rust-hub/current",
            xhubdPath: "/Users/test/Library/Application Support/AX/rust-hub/current/bin/xhubd",
            runnerPath: "/Users/test/Library/Application Support/AX/rust-hub/current/tools/run_rust_hub.command",
            manifestPath: "",
            exists: true,
            valid: true,
            sourcePackageDir: "",
            embeddedAtUTC: ""
        )

        let preferred = RustHubRuntimeSupport.preferredPackageInfo(embeddedPackage: embedded, activePackage: active)

        XCTAssertEqual(preferred.rootPath, active.rootPath)
    }

    func testPreferredPackageFallsBackToEmbeddedWhenActiveRootIsMissing() {
        let embedded = RustHubEmbeddedPackageInfo(
            rootPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub",
            xhubdPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/bin/xhubd",
            runnerPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/tools/run_rust_hub.command",
            manifestPath: "",
            exists: true,
            valid: true,
            sourcePackageDir: "",
            embeddedAtUTC: ""
        )

        let preferred = RustHubRuntimeSupport.preferredPackageInfo(embeddedPackage: embedded, activePackage: .empty)

        XCTAssertEqual(preferred.rootPath, embedded.rootPath)
    }

    func testActivePackageInfoPrefersFirstValidActiveRootCandidate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let containerRoot = root.appendingPathComponent("container-current")
        let userRoot = root.appendingPathComponent("user-current")
        try makeExecutableFile(at: containerRoot.appendingPathComponent("bin/xhubd"))
        try makeExecutableFile(at: containerRoot.appendingPathComponent("tools/run_rust_hub.command"))
        try makeExecutableFile(at: userRoot.appendingPathComponent("bin/xhubd"))
        try makeExecutableFile(at: userRoot.appendingPathComponent("tools/run_rust_hub.command"))

        let active = RustHubRuntimeSupport.activePackageInfo(roots: [containerRoot, userRoot])

        XCTAssertEqual(active.rootPath, containerRoot.path)
        XCTAssertTrue(active.valid)
    }

    func testActivePackageRootsIncludeSandboxHomeContainerRootFirst() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realHome = root.appendingPathComponent("real-home", isDirectory: true)
        let sandboxHome = root.appendingPathComponent("container-data", isDirectory: true)
        let environmentHome = root.appendingPathComponent("environment-container-data", isDirectory: true)

        let roots = RustHubRuntimeSupport.activePackageRoots(
            homeDirectory: realHome,
            containerHomeDirectory: sandboxHome,
            environment: ["HOME": environmentHome.path]
        )

        XCTAssertEqual(
            roots.first?.path,
            environmentHome.appendingPathComponent("RELFlowHub/rust-hub/current", isDirectory: true).path
        )
        XCTAssertEqual(
            roots.dropFirst().first?.path,
            sandboxHome.appendingPathComponent("RELFlowHub/rust-hub/current", isDirectory: true).path
        )
        XCTAssertTrue(roots.map(\.path).contains(
            realHome.appendingPathComponent("Library/Application Support/AX/rust-hub/current", isDirectory: true).path
        ))
    }

    func testProductionOverrideRootFallsBackWhenSandboxCannotValidateIt() throws {
        let info = RustHubEmbeddedPackageInfo(
            rootPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub",
            xhubdPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/bin/xhubd",
            runnerPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub/tools/run_rust_hub.command",
            manifestPath: "",
            exists: true,
            valid: true,
            sourcePackageDir: "",
            embeddedAtUTC: ""
        )
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let base = RustHubRuntimeSupport.nodeSidecarBaseEnvironment([
            "XHUB_ENABLE_RUST_AUTHORITY_CUTOVER": "1",
            "XHUB_RUST_HUB_ROOT": missingRoot.path,
            "XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY": "1"
        ])

        let env = RustHubRuntimeSupport.nodeSidecarEnvironmentAdditions(
            embeddedPackage: info,
            baseEnvironment: base
        )

        XCTAssertEqual(env["XHUB_RUST_HUB_ROOT"], info.rootPath)
        XCTAssertEqual(env["XHUB_RUST_HUB_RUNNER"], info.runnerPath)
        XCTAssertEqual(env["XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY"], "1")
    }

    func testIncompletePackageDoesNotInjectNodeSidecarEnvironment() {
        let info = RustHubEmbeddedPackageInfo(
            rootPath: "/Applications/X-Hub.app/Contents/Resources/rust-hub",
            xhubdPath: "",
            runnerPath: "",
            manifestPath: "",
            exists: true,
            valid: false,
            sourcePackageDir: "",
            embeddedAtUTC: ""
        )

        XCTAssertTrue(RustHubRuntimeSupport.nodeSidecarEnvironmentAdditions(embeddedPackage: info).isEmpty)
    }

    func testSnapshotSummarizesShadowReadiness() {
        let snapshot = RustHubRuntimeSupport.makeSnapshot(
            health: [
                "ok": true,
                "version": "0.1.0",
                "mode": "shadow_http",
                "grpc_compat": "not_started",
                "http_addr": "127.0.0.1:50151",
                "db_path": "/tmp/hub.sqlite3"
            ],
            readiness: [
                "ready": true,
                "mode": "shadow_http",
                "memory": ["canonical_writer_in_rust": false],
                "skills": ["execution_authority_in_rust": false],
                "capabilities": [
                    "xt_classic_hub_compat_authority": "preflight_only",
                    "xt_classic_hub_status_writer_authority": "explicit_cutover_only"
                ],
                "checks": [["name": "proto", "blocking": true, "ok": true]]
            ]
        )

        XCTAssertTrue(snapshot.healthOK)
        XCTAssertTrue(snapshot.ready)
        XCTAssertEqual(snapshot.version, "0.1.0")
        XCTAssertEqual(snapshot.mode, "shadow_http")
        XCTAssertTrue(snapshot.authoritySummary.contains("Memory shadow"))
        XCTAssertTrue(snapshot.authoritySummary.contains("Skill policy gate"))
        XCTAssertEqual(snapshot.endpointText, "127.0.0.1:50151")
    }

    func testProductKernelSnapshotDeclaresRustKernelSwiftShellBoundary() {
        let snapshot = RustHubRuntimeSupport.makeSnapshot(
            health: [:],
            readiness: [:],
            productKernel: [
                "schema_version": "xhub.product_kernel.v1",
                "ok": true,
                "ready": true,
                "product": [
                    "name": "X-Hub",
                    "boundary": "rust_product_kernel_swift_shell"
                ],
                "kernel": [
                    "name": "rust",
                    "version": "0.1.0",
                    "mode": "shadow_http",
                    "http_addr": "127.0.0.1:50151"
                ],
                "shell": [
                    "name": "swift",
                    "role": "product_ui_shell"
                ],
                "network": [
                    "cross_network_ready": true,
                    "domain_public_endpoint_ready": true
                ],
                "storage": [
                    "db_path": "/tmp/hub.sqlite3"
                ],
                "authority": [
                    "provider_route_in_rust": true,
                    "model_route_in_rust": true,
                    "scheduler_in_rust": true,
                    "memory_writer_in_rust": true,
                    "skills_execution_in_rust": true,
                    "xt_file_ipc_in_rust": true,
                    "local_ml_execution_in_rust": true,
                    "node_compatibility_layer": true,
                    "node_remains_authority": false,
                    "swift_shell_owns_ui": true,
                    "rust_browser_product_ui": false
                ]
            ]
        )

        XCTAssertTrue(snapshot.productKernelOK)
        XCTAssertTrue(snapshot.ready)
        XCTAssertEqual(snapshot.productKernelSchemaVersion, "xhub.product_kernel.v1")
        XCTAssertEqual(snapshot.productName, "X-Hub")
        XCTAssertEqual(snapshot.productBoundary, "rust_product_kernel_swift_shell")
        XCTAssertEqual(snapshot.kernelName, "rust")
        XCTAssertEqual(snapshot.shellName, "swift")
        XCTAssertTrue(snapshot.crossNetworkReady)
        XCTAssertTrue(snapshot.domainPublicEndpointReady)
        XCTAssertTrue(snapshot.authoritySummary.contains("Rust kernel"))
        XCTAssertTrue(snapshot.authoritySummary.contains("Swift shell"))
        XCTAssertTrue(snapshot.authoritySummary.contains("Route authority"))
        XCTAssertEqual(snapshot.dbPath, "/tmp/hub.sqlite3")
    }

    func testProductKernelLaunchStatusReadyBecomesServingWithoutBlockedCapabilities() throws {
        let snapshot = try XCTUnwrap(
            RustHubRuntimeSupport.makeProductKernelLaunchStatusSnapshot(
                object: [
                    "schema_version": "xhub.product_kernel.v1",
                    "ok": true,
                    "ready": true,
                    "readiness": [
                        "ready": true,
                        "checks": [
                            ["name": "proto", "blocking": true, "ok": true],
                            ["name": "sqlite_parent", "blocking": true, "ok": true]
                        ]
                    ]
                ],
                launchId: "unit-product-ready",
                nowMs: 42
            )
        )

        XCTAssertEqual(snapshot.launchId, "unit-product-ready")
        XCTAssertEqual(snapshot.state.rawValue, "SERVING")
        XCTAssertNil(snapshot.rootCause)
        XCTAssertFalse(snapshot.degraded.isDegraded)
        XCTAssertTrue(snapshot.degraded.blockedCapabilities.isEmpty)
    }

    func testRelabelProductKernelLaunchStatusUsesCurrentLaunchIdAndTimestamp() throws {
        let snapshot = try XCTUnwrap(
            RustHubRuntimeSupport.makeProductKernelLaunchStatusSnapshot(
                object: [
                    "schema_version": "xhub.product_kernel.v1",
                    "ok": true,
                    "ready": true,
                    "readiness": [
                        "ready": true,
                        "checks": [
                            ["name": "proto", "blocking": true, "ok": true]
                        ]
                    ]
                ],
                launchId: "prewarm-launch",
                nowMs: 100
            )
        )

        let relabeled = RustHubRuntimeSupport.relabelProductKernelLaunchStatus(
            snapshot,
            launchId: "current-launch",
            nowMs: 200
        )

        XCTAssertEqual(relabeled.launchId, "current-launch")
        XCTAssertEqual(relabeled.updatedAtMs, 200)
        XCTAssertEqual(relabeled.state, .serving)
        XCTAssertTrue(relabeled.steps.allSatisfy { $0.tsMs == 200 && $0.elapsedMs == 0 })
    }

    func testProductKernelLaunchStatusMapsBlockingChecksToRootCauseAndBlockedCapability() throws {
        let snapshot = try XCTUnwrap(
            RustHubRuntimeSupport.makeProductKernelLaunchStatusSnapshot(
                object: [
                    "schema_version": "xhub.product_kernel.v1",
                    "ok": true,
                    "ready": false,
                    "readiness": [
                        "ready": false,
                        "checks": [
                            ["name": "sqlite_parent", "blocking": true, "ok": false],
                            ["name": "memory_dir", "blocking": true, "ok": true]
                        ]
                    ]
                ],
                launchId: "unit-product-db-blocked",
                nowMs: 43
            )
        )

        XCTAssertEqual(snapshot.state.rawValue, "DEGRADED_SERVING")
        XCTAssertEqual(snapshot.rootCause?.component.rawValue, "db")
        XCTAssertEqual(snapshot.rootCause?.errorCode, "XHUB_KERNEL_SQLITE_PARENT_NOT_READY")
        XCTAssertEqual(snapshot.degraded.blockedCapabilities, ["hub.db.write"])
    }

    func testHTTPAccessKeyReadsDirectEnvironmentBeforeFile() throws {
        let keyFile = try makeTemporaryDirectory().appendingPathComponent("access_key")
        defer { try? FileManager.default.removeItem(at: keyFile.deletingLastPathComponent()) }
        try "file-secret\n".write(to: keyFile, atomically: true, encoding: .utf8)

        let key = RustHubRuntimeSupport.httpAccessKey(
            environment: [
                "XHUB_RUST_HTTP_ACCESS_KEY": "direct-secret",
                "XHUB_RUST_HTTP_ACCESS_KEY_FILE": keyFile.path
            ],
            activePackageRoots: []
        )

        XCTAssertEqual(key, "direct-secret")
    }

    func testHTTPAccessKeyReadsConfiguredFile() throws {
        let keyFile = try makeTemporaryDirectory().appendingPathComponent("access_key")
        defer { try? FileManager.default.removeItem(at: keyFile.deletingLastPathComponent()) }
        try "file-secret\n".write(to: keyFile, atomically: true, encoding: .utf8)

        let key = RustHubRuntimeSupport.httpAccessKey(
            environment: ["XHUB_RUST_HTTP_ACCESS_KEY_FILE": keyFile.path],
            activePackageRoots: []
        )

        XCTAssertEqual(key, "file-secret")
    }

    func testHTTPAccessKeyReadsLaunchctlDirectEnvironmentBeforeFile() throws {
        let keyFile = try makeTemporaryDirectory().appendingPathComponent("access_key")
        defer { try? FileManager.default.removeItem(at: keyFile.deletingLastPathComponent()) }
        try "file-secret\n".write(to: keyFile, atomically: true, encoding: .utf8)

        let key = RustHubRuntimeSupport.httpAccessKey(
            environment: [:],
            activePackageRoots: [],
            fallbackPackageRoots: [],
            launchctlEnvironment: [
                "XHUB_RUST_HTTP_ACCESS_KEY": "launchctl-direct-secret",
                "XHUB_RUST_HTTP_ACCESS_KEY_FILE": keyFile.path
            ]
        )

        XCTAssertEqual(key, "launchctl-direct-secret")
    }

    func testHTTPAccessKeyReadsLaunchctlConfiguredFile() throws {
        let keyFile = try makeTemporaryDirectory().appendingPathComponent("access_key")
        defer { try? FileManager.default.removeItem(at: keyFile.deletingLastPathComponent()) }
        try "launchctl-file-secret\n".write(to: keyFile, atomically: true, encoding: .utf8)

        let key = RustHubRuntimeSupport.httpAccessKey(
            environment: [:],
            activePackageRoots: [],
            fallbackPackageRoots: [],
            launchctlEnvironment: ["XHUB_RUST_HTTP_ACCESS_KEY_FILE": keyFile.path]
        )

        XCTAssertEqual(key, "launchctl-file-secret")
    }

    func testHTTPAccessKeyReadsActivePackageSecretCandidates() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyFile = root.appendingPathComponent("secrets/xhubd_domain_access_key")
        try FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "active-root-secret\n".write(to: keyFile, atomically: true, encoding: .utf8)

        let key = RustHubRuntimeSupport.httpAccessKey(
            environment: [:],
            activePackageRoots: [root]
        )

        XCTAssertEqual(key, "active-root-secret")
    }

    func testHTTPAccessKeyReadsActivePackageConfigCandidates() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyFile = root.appendingPathComponent("config/xhubd_domain_access_key")
        try FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "active-root-config-secret\n".write(to: keyFile, atomically: true, encoding: .utf8)

        let key = RustHubRuntimeSupport.httpAccessKey(
            environment: [:],
            activePackageRoots: [root]
        )

        XCTAssertEqual(key, "active-root-config-secret")
    }

    func testHTTPAccessKeyReadsLocalAndDomainFallbackRoots() throws {
        let installRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: installRoot) }
        let domainRoot = installRoot.appendingPathComponent("domain", isDirectory: true)
        let localRoot = installRoot.appendingPathComponent("local", isDirectory: true)
        let domainKeyFile = domainRoot.appendingPathComponent("secrets/xhubd_domain_access_key")
        let localKeyFile = localRoot.appendingPathComponent("config/xhubd_local_access_key")
        try FileManager.default.createDirectory(at: domainKeyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localKeyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "domain-fallback-secret\n".write(to: domainKeyFile, atomically: true, encoding: .utf8)
        try "local-fallback-secret\n".write(to: localKeyFile, atomically: true, encoding: .utf8)

        let domainFirst = RustHubRuntimeSupport.httpAccessKey(
            environment: [:],
            activePackageRoots: [],
            fallbackPackageRoots: [domainRoot, localRoot]
        )
        let localFirst = RustHubRuntimeSupport.httpAccessKey(
            environment: [:],
            activePackageRoots: [],
            fallbackPackageRoots: [localRoot, domainRoot]
        )

        XCTAssertEqual(domainFirst, "domain-fallback-secret")
        XCTAssertEqual(localFirst, "local-fallback-secret")
    }

    func testRemoteEntryCandidatesPrefersNoDomainPrivateHostFromRustCore() {
        let candidates = RustHubRuntimeSupport.makeRemoteEntryCandidates(object: [
            "schema_version": "xhub.rust_hub.remote_entry_candidates.v1",
            "ok": true,
            "source": "rust_core_network_bridge",
            "recommended_setup": "use_no_domain_private_network",
            "preferred": [
                "route_kind": "no_domain_private_network",
                "source": "local_interface",
                "host": "100.122.237.57",
                "public_base_url": "https://100.122.237.57",
                "usable": true,
                "requires_same_private_network": true,
                "requires_mtls": true,
                "classification": [
                    "kind": "vpn_raw",
                    "scope": "tailscale_ip",
                    "stable": true,
                    "encrypted_private_candidate": true
                ]
            ],
            "candidates": [[
                "route_kind": "no_domain_private_network",
                "source": "local_interface",
                "host": "100.122.237.57",
                "public_base_url": "https://100.122.237.57",
                "usable": true,
                "requires_same_private_network": true,
                "requires_mtls": true,
                "classification": [
                    "kind": "vpn_raw",
                    "scope": "tailscale_ip",
                    "stable": true,
                    "encrypted_private_candidate": true
                ]
            ]]
        ])

        XCTAssertTrue(candidates.ok)
        XCTAssertEqual(candidates.recommendedSetup, "use_no_domain_private_network")
        XCTAssertEqual(candidates.preferredNoDomainPrivateHost, "100.122.237.57")
        XCTAssertEqual(candidates.candidates.first?.classification.scope, "tailscale_ip")
    }

    func testRemoteEntryCandidatesDoesNotTreatDomainAsNoDomainPrivateHost() {
        let candidates = RustHubRuntimeSupport.makeRemoteEntryCandidates(object: [
            "schema_version": "xhub.rust_hub.remote_entry_candidates.v1",
            "ok": true,
            "recommended_setup": "use_stable_domain_or_tunnel",
            "preferred": [
                "route_kind": "stable_domain_or_tunnel",
                "source": "public_base_url",
                "host": "hub.example.com",
                "public_base_url": "https://hub.example.com",
                "usable": true
            ],
            "candidates": [[
                "route_kind": "stable_domain_or_tunnel",
                "source": "public_base_url",
                "host": "hub.example.com",
                "public_base_url": "https://hub.example.com",
                "usable": true
            ]]
        ])

        XCTAssertNil(candidates.preferredNoDomainPrivateHost)
    }

    private var sampleRustRepairPlanJSON: String {
        """
        {
          "schema_version": "xhub.model_local_runtime_repair_plan.v1",
          "ok": true,
          "state": "repair_required",
          "safe_to_auto_apply": false,
          "requires_user_approval": true,
          "requires_network": true,
          "requires_download": true,
          "secret_fields_included": false,
          "summary": "Install or repair Hub local provider pack `mlx_vlm` before XT uses local model tasks.",
          "resolved": {
            "action": "install_provider_pack:mlx_vlm",
            "task_kind": "vision_understand",
            "provider_id": "mlx_vlm",
            "source": "request_task_kind"
          },
          "target": {
            "kind": "provider_pack",
            "provider_id": "mlx_vlm",
            "task_kind": "vision_understand"
          },
          "requirements": {
            "engine": "mlx-vlm",
            "execution_mode": "builtin_python",
            "install_target": "hub_managed_python_runtime",
            "python_import_modules": ["mlx_vlm"],
            "python_packages": ["mlx-vlm"],
            "supported_domains": ["vision"],
            "expected_task_kinds": ["vision_understand"]
          },
          "missing_requirements": ["python_module:mlx_vlm"],
          "confirmation": {
            "required_for_apply": true,
            "token_hint": "confirm:install_provider_pack:mlx_vlm",
            "apply_endpoint": "/model/repair-apply",
            "heavy_work_policy": "never_run_installs_on_ui_or_http_request_thread"
          },
          "steps": []
        }
        """
    }

    private var sampleRustRepairApplyJSON: String {
        """
        {
          "schema_version": "xhub.model_local_runtime_repair_apply.v1",
          "ok": true,
          "accepted": true,
          "dry_run": false,
          "status": "queued_waiting_executor",
          "updated_at_ms": 1001,
          "runtime_base_dir": "/Users/test/Library/Application Support/AX/RELFlowHub",
          "job_id": "repair_install_provider_pack_mlx_vlm_1001",
          "job_path": "/Users/test/Library/Application Support/AX/RELFlowHub/model_repair_jobs/repair_install_provider_pack_mlx_vlm_1001.json",
          "resolved": {
            "action": "install_provider_pack:mlx_vlm",
            "task_kind": "vision_understand",
            "provider_id": "mlx_vlm",
            "source": "request_task_kind"
          },
          "target": {
            "kind": "provider_pack",
            "provider_id": "mlx_vlm",
            "task_kind": "vision_understand"
          },
          "requirements": {
            "engine": "mlx-vlm",
            "execution_mode": "builtin_python",
            "install_target": "hub_managed_python_runtime",
            "python_import_modules": ["mlx_vlm"],
            "python_packages": ["mlx-vlm"],
            "supported_domains": ["vision"],
            "expected_task_kinds": ["vision_understand"]
          },
          "job_policy": {
            "execution_mode": "queued_nonblocking",
            "ui_thread_blocking_allowed": false,
            "http_request_blocking_allowed": false,
            "network_install_requires_user_approval": true,
            "executor": "rust_model_repair_executor",
            "executor_ready": true
          },
          "secret_fields_included": false
        }
        """
    }

    private var sampleRustRepairJobsJSON: String {
        """
        {
          "schema_version": "xhub.model_local_runtime_repair_jobs.v1",
          "ok": true,
          "runtime_base_dir": "/Users/test/Library/Application Support/AX/RELFlowHub",
          "jobs_dir": "/Users/test/Library/Application Support/AX/RELFlowHub/model_repair_jobs",
          "count": 2,
          "limit": 10,
          "updated_at_ms": 1003,
          "secret_fields_included": false,
          "jobs": [
            {
              "job_id": "repair_install_provider_pack_mlx_vlm_1001",
              "status": "queued_waiting_executor",
              "created_at_ms": 1001,
              "updated_at_ms": 1001,
              "requested_by": "swift_hub_settings",
              "resolved": {
                "action": "install_provider_pack:mlx_vlm",
                "task_kind": "vision_understand",
                "provider_id": "mlx_vlm",
                "source": "request_task_kind"
              },
              "target": {
                "kind": "provider_pack",
                "provider_id": "mlx_vlm",
                "task_kind": "vision_understand"
              },
              "job_policy": {
                "execution_mode": "queued_nonblocking",
                "ui_thread_blocking_allowed": false,
                "http_request_blocking_allowed": false,
                "network_install_requires_user_approval": true,
                "executor": "rust_model_repair_executor",
                "executor_ready": true
              },
              "executor_state": {
                "ready": true,
                "reason_code": "rust_model_repair_executor_available"
              },
              "secret_fields_included": false
            },
            {
              "job_id": "repair_install_provider_pack_mlx_vlm_1002",
              "status": "applied_pending_runtime_restart",
              "created_at_ms": 1002,
              "updated_at_ms": 1003,
              "requested_by": "swift_hub_settings",
              "resolved": {
                "action": "install_provider_pack:mlx_vlm",
                "task_kind": "vision_understand",
                "provider_id": "mlx_vlm",
                "source": "request_task_kind"
              },
              "target": {
                "kind": "provider_pack",
                "provider_id": "mlx_vlm",
                "task_kind": "vision_understand"
              },
              "job_policy": {
                "execution_mode": "queued_nonblocking",
                "ui_thread_blocking_allowed": false,
                "http_request_blocking_allowed": false,
                "network_install_requires_user_approval": true,
                "executor": "rust_model_repair_executor",
                "executor_ready": true
              },
              "executor_state": {
                "ready": true,
                "reason_code": "rust_model_repair_executor_completed"
              },
              "secret_fields_included": false
            }
          ]
        }
        """
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeExecutableFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data("#!/bin/bash\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
    }
}
