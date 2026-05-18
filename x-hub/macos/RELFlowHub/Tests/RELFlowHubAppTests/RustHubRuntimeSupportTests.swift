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
                    "scope": "tailscale_headscale_ip",
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
                    "scope": "tailscale_headscale_ip",
                    "stable": true,
                    "encrypted_private_candidate": true
                ]
            ]]
        ])

        XCTAssertTrue(candidates.ok)
        XCTAssertEqual(candidates.recommendedSetup, "use_no_domain_private_network")
        XCTAssertEqual(candidates.preferredNoDomainPrivateHost, "100.122.237.57")
        XCTAssertEqual(candidates.candidates.first?.classification.scope, "tailscale_headscale_ip")
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
