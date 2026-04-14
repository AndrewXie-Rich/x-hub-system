import Darwin
import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class HubStoreLocalRuntimePythonSelectionTests: XCTestCase {
    func testLocalRuntimeCommandLaunchPrefersVendorPythonWhenSupplementalSitePackagesUnlockTransformers() throws {
        let home = try makeTempDir()
        let previousHomeOverride = getenv("XHUB_SOURCE_RUN_HOME").map { String(cString: $0) }
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            if let previousHomeOverride {
                setenv("XHUB_SOURCE_RUN_HOME", previousHomeOverride, 1)
            } else {
                unsetenv("XHUB_SOURCE_RUN_HOME")
            }
        }

        let builtinPython = home
            .appendingPathComponent("builtin", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let vendorRoot = home
            .appendingPathComponent(".lmstudio/extensions/backends/vendor", isDirectory: true)
            .appendingPathComponent("_amphibian", isDirectory: true)
        let vendorPython = vendorRoot
            .appendingPathComponent("cpython3.11-mac-arm64@10", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let vendorSitePackages = vendorRoot
            .appendingPathComponent("app-mlx-generate-mac14-arm64@19", isDirectory: true)
            .appendingPathComponent("lib/python3.11/site-packages", isDirectory: true)

        try FileManager.default.createDirectory(
            at: vendorSitePackages,
            withIntermediateDirectories: true
        )
        try makeMockPython(
            at: builtinPython,
            readyWithoutSupplementalPath: "mlx"
        )
        try makeMockPython(
            at: vendorPython,
            readyWithoutSupplementalPath: "mlx",
            readyWithSupplementalPath: "transformers,mlx",
            requiredSupplementalPath: vendorSitePackages.path
        )

        let store = HubStore(startServices: false)
        store.aiRuntimePython = "/usr/bin/env"
        store.localPythonCandidatePathsOverride = [
            builtinPython.path,
            vendorPython.path,
        ]

        XCTAssertEqual(
            store.preferredLocalProviderPythonPath(preferredProviderID: "transformers"),
            vendorPython.path
        )

        let launchConfig = try XCTUnwrap(
            store.localRuntimeCommandLaunchConfig(preferredProviderID: "transformers")
        )
        XCTAssertEqual(launchConfig.executable, vendorPython.path)

        let pythonPathEntries = (launchConfig.environment["PYTHONPATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        XCTAssertTrue(pythonPathEntries.contains(vendorSitePackages.path))
        XCTAssertEqual(pythonPathEntries.first, vendorSitePackages.path)
    }

    func testPreferredLocalProviderPythonPathReusesProbeCacheAcrossRepeatedLookups() throws {
        let home = try makeTempDir()
        let previousHomeOverride = getenv("XHUB_SOURCE_RUN_HOME").map { String(cString: $0) }
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            if let previousHomeOverride {
                setenv("XHUB_SOURCE_RUN_HOME", previousHomeOverride, 1)
            } else {
                unsetenv("XHUB_SOURCE_RUN_HOME")
            }
        }

        let python = home
            .appendingPathComponent("cached", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let invocationCountFile = home.appendingPathComponent("probe_count.txt")

        try makeMockPython(
            at: python,
            readyWithoutSupplementalPath: "transformers",
            invocationCountFile: invocationCountFile.path
        )

        let store = HubStore(startServices: false)
        store.aiRuntimePython = python.path
        store.localPythonCandidatePathsOverride = [python.path]

        XCTAssertEqual(
            store.preferredLocalProviderPythonPath(preferredProviderID: "transformers"),
            python.path
        )
        let firstInvocationCount = try readInvocationCount(from: invocationCountFile)
        XCTAssertGreaterThan(firstInvocationCount, 0)

        XCTAssertEqual(
            store.preferredLocalProviderPythonPath(preferredProviderID: "transformers"),
            python.path
        )
        XCTAssertEqual(try readInvocationCount(from: invocationCountFile), firstInvocationCount)
    }

    func testPreferredLocalProviderPythonPathRetriesTransientVersionProbeFailure() throws {
        let home = try makeTempDir()
        let previousHomeOverride = getenv("XHUB_SOURCE_RUN_HOME").map { String(cString: $0) }
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            if let previousHomeOverride {
                setenv("XHUB_SOURCE_RUN_HOME", previousHomeOverride, 1)
            } else {
                unsetenv("XHUB_SOURCE_RUN_HOME")
            }
        }

        let python = home
            .appendingPathComponent("transient", isDirectory: true)
            .appendingPathComponent("bin/python3")
        try makeMockPython(
            at: python,
            readyWithoutSupplementalPath: "transformers",
            firstVersionProbeSleepSeconds: 1.5
        )

        let store = HubStore(startServices: false)
        store.aiRuntimePython = "/usr/bin/env"
        store.localPythonCandidatePathsOverride = [python.path]

        XCTAssertEqual(
            store.preferredLocalProviderPythonPath(preferredProviderID: "transformers"),
            python.path
        )
    }

    func testLocalRuntimeProbePrefersActiveRuntimeSourcePythonOverConfiguredSelection() throws {
        let home = try makeTempDir()
        let previousHomeOverride = getenv("XHUB_SOURCE_RUN_HOME").map { String(cString: $0) }
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            if let previousHomeOverride {
                setenv("XHUB_SOURCE_RUN_HOME", previousHomeOverride, 1)
            } else {
                unsetenv("XHUB_SOURCE_RUN_HOME")
            }
        }

        let builtinPython = home
            .appendingPathComponent("builtin", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let vendorRoot = home
            .appendingPathComponent(".lmstudio/extensions/backends/vendor", isDirectory: true)
            .appendingPathComponent("_amphibian", isDirectory: true)
        let vendorPython = vendorRoot
            .appendingPathComponent("cpython3.11-mac-arm64@10", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let vendorSitePackages = vendorRoot
            .appendingPathComponent("app-mlx-generate-mac14-arm64@19", isDirectory: true)
            .appendingPathComponent("lib/python3.11/site-packages", isDirectory: true)

        try FileManager.default.createDirectory(
            at: vendorSitePackages,
            withIntermediateDirectories: true
        )
        try makeMockPython(
            at: builtinPython,
            readyWithoutSupplementalPath: "mlx"
        )
        try makeMockPython(
            at: vendorPython,
            readyWithoutSupplementalPath: "mlx",
            readyWithSupplementalPath: "transformers,mlx",
            requiredSupplementalPath: vendorSitePackages.path
        )

        let runtimeStatus = AIRuntimeStatus(
            pid: 57539,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "test-runtime",
                    runtimeSource: "user_python_custom",
                    runtimeSourcePath: vendorPython.path,
                    runtimeResolutionState: "user_runtime_fallback",
                    runtimeReasonCode: "ready",
                    fallbackUsed: true,
                    availableTaskKinds: ["text_generate"],
                    updatedAt: Date().timeIntervalSince1970
                ),
            ]
        )
        try writeRuntimeStatus(runtimeStatus)

        let store = HubStore(startServices: false)
        store.aiRuntimePython = builtinPython.path
        store.localPythonCandidatePathsOverride = [builtinPython.path]

        XCTAssertEqual(
            store.preferredLocalProviderPythonPath(preferredProviderID: "transformers"),
            vendorPython.path
        )

        let launchConfig = try XCTUnwrap(
            store.localRuntimePythonProbeLaunchConfig(preferredProviderID: "transformers")
        )
        XCTAssertEqual(launchConfig.executable, vendorPython.path)

        let pythonPathEntries = (launchConfig.environment["PYTHONPATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        XCTAssertEqual(pythonPathEntries.first, vendorSitePackages.path)
    }

    func testTransformersCompatibilityProbeUsesActiveRuntimeSourcePython() throws {
        let home = try makeTempDir()
        let previousHomeOverride = getenv("XHUB_SOURCE_RUN_HOME").map { String(cString: $0) }
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            if let previousHomeOverride {
                setenv("XHUB_SOURCE_RUN_HOME", previousHomeOverride, 1)
            } else {
                unsetenv("XHUB_SOURCE_RUN_HOME")
            }
        }

        let builtinPython = home
            .appendingPathComponent("builtin", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let vendorRoot = home
            .appendingPathComponent(".lmstudio/extensions/backends/vendor", isDirectory: true)
            .appendingPathComponent("_amphibian", isDirectory: true)
        let vendorPython = vendorRoot
            .appendingPathComponent("cpython3.11-mac-arm64@10", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let vendorSitePackages = vendorRoot
            .appendingPathComponent("app-mlx-generate-mac14-arm64@19", isDirectory: true)
            .appendingPathComponent("lib/python3.11/site-packages", isDirectory: true)
        let modelDir = home.appendingPathComponent("Qwen2.5-0.5B-Instruct", isDirectory: true)

        try FileManager.default.createDirectory(
            at: vendorSitePackages,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true
        )
        try Data("{\"model_type\":\"qwen2\"}".utf8).write(
            to: modelDir.appendingPathComponent("config.json")
        )

        try makeMockPython(
            at: builtinPython,
            readyWithoutSupplementalPath: "mlx",
            runtimeProbeOutput: """
code=missing_module:torch
summary=Current Python runtime is missing torch.
detail=Hub cannot load this Transformers model until torch is available.
blocking=1
"""
        )
        try makeMockPython(
            at: vendorPython,
            readyWithoutSupplementalPath: "mlx",
            readyWithSupplementalPath: "transformers,mlx",
            requiredSupplementalPath: vendorSitePackages.path
        )

        let runtimeStatus = AIRuntimeStatus(
            pid: 57539,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    runtimeVersion: "test-runtime",
                    runtimeSource: "user_python_custom",
                    runtimeSourcePath: vendorPython.path,
                    runtimeResolutionState: "user_runtime_fallback",
                    runtimeReasonCode: "ready",
                    fallbackUsed: true,
                    availableTaskKinds: ["text_generate"],
                    updatedAt: Date().timeIntervalSince1970
                ),
            ]
        )
        try writeRuntimeStatus(runtimeStatus)

        let store = HubStore(startServices: false)
        store.aiRuntimePython = builtinPython.path
        store.localPythonCandidatePathsOverride = [builtinPython.path]

        let model = HubModel(
            id: "hf-qwen25-05b-instruct",
            name: "Qwen 2.5 0.5B",
            backend: "transformers",
            runtimeProviderID: "transformers",
            quant: "fp16",
            contextLength: 32768,
            paramsB: 0.5,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["text_generate"]
        )

        let blockedMessage = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "load",
            model: model,
            probeLaunchConfig: store.localRuntimePythonProbeLaunchConfig(
                preferredProviderID: "transformers"
            ),
            pythonPath: store.preferredLocalProviderPythonPath(
                preferredProviderID: "transformers"
            )
        )

        XCTAssertNil(blockedMessage)
    }

    func testTransformersCompatibilityProbeUsesManagedOfflinePyDepsMarker() throws {
        let home = try makeTempDir()
        let previousHomeOverride = getenv("XHUB_SOURCE_RUN_HOME").map { String(cString: $0) }
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            if let previousHomeOverride {
                setenv("XHUB_SOURCE_RUN_HOME", previousHomeOverride, 1)
            } else {
                unsetenv("XHUB_SOURCE_RUN_HOME")
            }
        }

        let builtinPython = home
            .appendingPathComponent("framework-python", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let offlineRoot = home
            .appendingPathComponent("RELFlowHub", isDirectory: true)
            .appendingPathComponent("py_deps", isDirectory: true)
        let offlineSitePackages = offlineRoot.appendingPathComponent("site-packages", isDirectory: true)
        let modelDir = home.appendingPathComponent("Qwen2.5-0.5B-Instruct", isDirectory: true)

        try FileManager.default.createDirectory(
            at: offlineSitePackages,
            withIntermediateDirectories: true
        )
        try Data().write(to: offlineRoot.appendingPathComponent("USE_PYTHONPATH"))
        try FileManager.default.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true
        )
        try Data("{\"model_type\":\"qwen2\"}".utf8).write(
            to: modelDir.appendingPathComponent("config.json")
        )

        try makeMockPython(
            at: builtinPython,
            readyWithoutSupplementalPath: "mlx",
            readyWithSupplementalPath: "transformers,mlx",
            requiredSupplementalPath: offlineSitePackages.path,
            runtimeProbeOutput: """
code=missing_module:torch
summary=Current Python runtime is missing torch.
detail=Hub cannot load this Transformers model until torch is available.
blocking=1
""",
            runtimeProbeOutputWithSupplementalPath: """
code=ok
summary=ok
blocking=0
"""
        )

        let store = HubStore(startServices: false)
        store.aiRuntimePython = builtinPython.path
        store.localPythonCandidatePathsOverride = [builtinPython.path]

        let launchConfig = try XCTUnwrap(
            store.localRuntimePythonProbeLaunchConfig(preferredProviderID: "transformers")
        )
        XCTAssertEqual(launchConfig.executable, builtinPython.path)

        let pythonPathEntries = (launchConfig.environment["PYTHONPATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        XCTAssertEqual(pythonPathEntries.first, offlineSitePackages.path)

        let model = HubModel(
            id: "hf-qwen25-05b-instruct",
            name: "Qwen 2.5 0.5B",
            backend: "transformers",
            runtimeProviderID: "transformers",
            quant: "fp16",
            contextLength: 32768,
            paramsB: 0.5,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["text_generate"]
        )

        let blockedMessage = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "load",
            model: model,
            probeLaunchConfig: launchConfig,
            pythonPath: store.preferredLocalProviderPythonPath(
                preferredProviderID: "transformers"
            )
        )

        XCTAssertNil(blockedMessage)
    }

    func testPreferredLocalProviderPythonPathOverridesPinnedPythonWhenPreferredProviderNeedsDifferentRuntime() throws {
        let home = try makeTempDir()
        let previousHomeOverride = getenv("XHUB_SOURCE_RUN_HOME").map { String(cString: $0) }
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            if let previousHomeOverride {
                setenv("XHUB_SOURCE_RUN_HOME", previousHomeOverride, 1)
            } else {
                unsetenv("XHUB_SOURCE_RUN_HOME")
            }
        }

        let pinnedPython = home
            .appendingPathComponent("framework-python", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let vendorRoot = home
            .appendingPathComponent(".lmstudio/extensions/backends/vendor", isDirectory: true)
            .appendingPathComponent("_amphibian", isDirectory: true)
        let vendorPython = vendorRoot
            .appendingPathComponent("cpython3.11-mac-arm64@10", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let vendorSitePackages = vendorRoot
            .appendingPathComponent("app-mlx-generate-mac14-arm64@19", isDirectory: true)
            .appendingPathComponent("lib/python3.11/site-packages", isDirectory: true)

        try FileManager.default.createDirectory(
            at: vendorSitePackages,
            withIntermediateDirectories: true
        )
        try makeMockPython(
            at: pinnedPython,
            readyWithoutSupplementalPath: "mlx"
        )
        try makeMockPython(
            at: vendorPython,
            readyWithoutSupplementalPath: "mlx",
            readyWithSupplementalPath: "transformers,mlx",
            requiredSupplementalPath: vendorSitePackages.path
        )

        let store = HubStore(startServices: false)
        store.aiRuntimePython = pinnedPython.path
        store.localPythonCandidatePathsOverride = [
            pinnedPython.path,
            vendorPython.path,
        ]

        XCTAssertEqual(
            store.preferredLocalProviderPythonPath(preferredProviderID: "transformers"),
            vendorPython.path
        )

        let launchConfig = try XCTUnwrap(
            store.localRuntimePythonProbeLaunchConfig(preferredProviderID: "transformers")
        )
        XCTAssertEqual(launchConfig.executable, vendorPython.path)
        XCTAssertEqual(launchConfig.resolvedPythonPath, vendorPython.path)

        let pythonPathEntries = (launchConfig.environment["PYTHONPATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        XCTAssertEqual(pythonPathEntries.first, vendorSitePackages.path)
    }

    func testRuntimeBootstrapPreferredProviderIDPrefersTransformersWhenCatalogContainsTransformersModels() {
        let store = HubStore(startServices: false)
        let catalog = ModelCatalogSnapshot(
            models: [
                ModelCatalogEntry(
                    id: "mlx-local",
                    name: "MLX Local",
                    backend: "mlx",
                    modelPath: "/tmp/mlx-local"
                ),
                ModelCatalogEntry(
                    id: "transformers-local",
                    name: "Transformers Local",
                    backend: "transformers",
                    runtimeProviderID: "transformers",
                    modelPath: "/tmp/qwen25-05b",
                    taskKinds: ["text_generate"]
                ),
            ],
            updatedAt: Date().timeIntervalSince1970
        )

        XCTAssertEqual(
            store.runtimeBootstrapPreferredProviderID(catalog: catalog),
            "transformers"
        )
    }

    func testPreferredLocalProviderPythonPathReusesRecentReadyHomeStatusWhenContainerStatusIsBroken() throws {
        let home = try makeTempDir()
        let previousHomeOverride = getenv("XHUB_SOURCE_RUN_HOME").map { String(cString: $0) }
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            if let previousHomeOverride {
                setenv("XHUB_SOURCE_RUN_HOME", previousHomeOverride, 1)
            } else {
                unsetenv("XHUB_SOURCE_RUN_HOME")
            }
        }

        let homeVendorPython = home
            .appendingPathComponent(".lmstudio/extensions/backends/vendor/_amphibian/cpython3.11-mac-arm64@10/bin/python")
        try FileManager.default.createDirectory(
            at: homeVendorPython.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: homeVendorPython.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: homeVendorPython.path
        )

        let brokenPython = home
            .appendingPathComponent("framework-python/bin/python3")
        try makeMockPython(
            at: brokenPython,
            readyWithoutSupplementalPath: "mlx"
        )

        let readyUpdatedAt = Date().timeIntervalSince1970 - 2
        let brokenUpdatedAt = Date().timeIntervalSince1970 - 1
        try writeRuntimeStatus(
            AIRuntimeStatus(
                pid: 57539,
                updatedAt: readyUpdatedAt,
                mlxOk: true,
                providers: [
                    "transformers": AIRuntimeProviderStatus(
                        provider: "transformers",
                        ok: true,
                        reasonCode: "ready",
                        runtimeVersion: "test-runtime",
                        runtimeSource: "user_python_custom",
                        runtimeSourcePath: homeVendorPython.path,
                        runtimeResolutionState: "user_runtime_fallback",
                        runtimeReasonCode: "ready",
                        fallbackUsed: true,
                        availableTaskKinds: ["text_generate"],
                        updatedAt: readyUpdatedAt
                    ),
                ]
            ),
            to: home.appendingPathComponent("RELFlowHub/ai_runtime_status.json")
        )

        try writeRuntimeStatus(
            AIRuntimeStatus(
                pid: 21554,
                updatedAt: brokenUpdatedAt,
                mlxOk: true,
                providers: [
                    "transformers": AIRuntimeProviderStatus(
                        provider: "transformers",
                        ok: false,
                        reasonCode: "missing_runtime",
                        runtimeVersion: "test-runtime",
                        runtimeSource: "hub_py_deps",
                        runtimeSourcePath: home.appendingPathComponent("Library/Containers/com.rel.flowhub/Data/RELFlowHub/ai_runtime").path,
                        runtimeResolutionState: "runtime_missing",
                        runtimeReasonCode: "missing_runtime",
                        fallbackUsed: false,
                        availableTaskKinds: [],
                        updatedAt: brokenUpdatedAt,
                        importError: "missing_module:torch"
                    ),
                ]
            ),
            to: home.appendingPathComponent("Library/Containers/com.rel.flowhub/Data/RELFlowHub/ai_runtime_status.json")
        )

        let store = HubStore(startServices: false)
        store.aiRuntimePython = brokenPython.path
        store.localPythonCandidatePathsOverride = [brokenPython.path]

        XCTAssertEqual(
            store.preferredLocalProviderPythonPath(preferredProviderID: "transformers"),
            homeVendorPython.path
        )
    }

    func testHubStoreDefaultsToHubManagedRuntimeWrapperPythonWhenPresent() throws {
        let home = try makeTempDir()
        let previousHomeOverride = getenv("XHUB_SOURCE_RUN_HOME").map { String(cString: $0) }
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            if let previousHomeOverride {
                setenv("XHUB_SOURCE_RUN_HOME", previousHomeOverride, 1)
            } else {
                unsetenv("XHUB_SOURCE_RUN_HOME")
            }
        }

        let defaultsKey = "relflowhub_ai_runtime_python"
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: defaultsKey)
        defaults.removeObject(forKey: defaultsKey)
        addTeardownBlock {
            if let previousValue {
                defaults.set(previousValue, forKey: defaultsKey)
            } else {
                defaults.removeObject(forKey: defaultsKey)
            }
        }

        let wrapperPython = home
            .appendingPathComponent("RELFlowHub", isDirectory: true)
            .appendingPathComponent("ai_runtime", isDirectory: true)
            .appendingPathComponent("python3")
        try makeMockPython(
            at: wrapperPython,
            readyWithoutSupplementalPath: "transformers,mlx"
        )

        let store = HubStore(startServices: false)
        XCTAssertEqual(store.aiRuntimePython, wrapperPython.path)
    }

    func testLocalModelRuntimePresentationDoesNotBlockOnPythonProbe() throws {
        let tempDir = try makeTempDir()

        let model = HubModel(
            id: "presentation-\(UUID().uuidString)",
            name: "Bench Probe Avoidance",
            backend: "transformers",
            runtimeProviderID: "transformers",
            quant: "int4",
            contextLength: 4096,
            paramsB: 7.0,
            state: .available,
            modelPath: tempDir.path,
            taskKinds: ["text_generate"]
        )

        let start = CFAbsoluteTimeGetCurrent()
        let presentation = ModelStore.shared.localModelRuntimePresentation(for: model)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(presentation?.providerID, "transformers")
        XCTAssertLessThan(
            elapsed,
            0.4,
            "Runtime presentation should stay render-safe and avoid synchronous python probes."
        )
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeMockPython(
        at url: URL,
        version: String = "3.11",
        readyWithoutSupplementalPath: String,
        readyWithSupplementalPath: String? = nil,
        requiredSupplementalPath: String? = nil,
        invocationCountFile: String? = nil,
        firstVersionProbeSleepSeconds: Double? = nil,
        runtimeProbeOutput: String? = nil,
        runtimeProbeOutputWithSupplementalPath: String? = nil,
        runtimeProbeRequiredSupplementalPath: String? = nil
    ) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let requiredPath = shellSingleQuoted(requiredSupplementalPath ?? "")
        let invocationCountPath = shellSingleQuoted(invocationCountFile ?? "")
        let firstVersionProbeSleep = firstVersionProbeSleepSeconds ?? 0
        let readyWithPath = readyWithSupplementalPath ?? readyWithoutSupplementalPath
        let normalizedRuntimeProbeOutput = runtimeProbeOutput ?? """
code=ok
summary=ok
blocking=0
"""
        let normalizedRuntimeProbeOutputWithSupplementalPath = runtimeProbeOutputWithSupplementalPath
            ?? normalizedRuntimeProbeOutput
        let runtimeProbeRequiredPath = shellSingleQuoted(
            runtimeProbeRequiredSupplementalPath ?? requiredSupplementalPath ?? ""
        )
        let runtimeProbeOutputText = shellSingleQuoted(normalizedRuntimeProbeOutput)
        let runtimeProbeOutputWithPathText = shellSingleQuoted(
            normalizedRuntimeProbeOutputWithSupplementalPath
        )
        let script = """
#!/bin/sh
count_file=\(invocationCountPath)
if [ -n "$count_file" ]; then
  count=0
  if [ -f "$count_file" ]; then
    count="$(cat "$count_file" 2>/dev/null || printf '0')"
  fi
  count=$((count + 1))
  printf '%s' "$count" > "$count_file"
fi
code="${2:-}"
if [ "$#" -ge 4 ]; then
  runtime_required_path=\(runtimeProbeRequiredPath)
  runtime_output=\(runtimeProbeOutputText)
  if [ -n "$runtime_required_path" ] && printf '%s' ":${PYTHONPATH:-}:" | grep -Fq ":$runtime_required_path:"; then
    runtime_output=\(runtimeProbeOutputWithPathText)
  fi
  printf '%s\\n' "$runtime_output"
  exit 0
fi
case "$code" in
  *"sys.version_info"*)
    first_version_probe_sleep="\(firstVersionProbeSleep)"
    first_version_probe_marker="$0.first_version_probe_seen"
    if [ "$first_version_probe_sleep" != "0.0" ] && [ ! -f "$first_version_probe_marker" ]; then
      : > "$first_version_probe_marker"
      sleep "$first_version_probe_sleep"
    fi
    printf '%s\\n' "\(version)"
    exit 0
    ;;
  *"import transformers"*)
    ready="\(readyWithoutSupplementalPath)"
    required_path=\(requiredPath)
    if [ -n "$required_path" ] && printf '%s' ":${PYTHONPATH:-}:" | grep -Fq ":$required_path:"; then
      ready="\(readyWithPath)"
    fi
    printf 'ready=%s\\n' "$ready"
    exit 0
    ;;
esac
exit 1
"""

        try XCTUnwrap(script.data(using: .utf8)).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }

    private func makeSlowPython(at url: URL, sleepSeconds: Double) throws {
        let script = """
#!/bin/sh
sleep \(sleepSeconds)
printf '3.11\\n'
exit 0
"""
        try XCTUnwrap(script.data(using: .utf8)).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }

    private func writeRuntimeStatus(_ status: AIRuntimeStatus) throws {
        try writeRuntimeStatus(status, to: AIRuntimeStatusStorage.url())
    }

    private func writeRuntimeStatus(_ status: AIRuntimeStatus, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: url)
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func readInvocationCount(from url: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let text = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(text) ?? 0
    }
}
