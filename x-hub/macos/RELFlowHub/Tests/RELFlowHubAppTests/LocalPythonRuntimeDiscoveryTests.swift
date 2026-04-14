import XCTest
@testable import RELFlowHub

final class LocalPythonRuntimeDiscoveryTests: XCTestCase {
    func testBuiltinCandidatesExcludeDeveloperPythonStub() {
        XCTAssertFalse(LocalPythonRuntimeDiscovery.builtinCandidates.contains("/usr/bin/python3"))
    }

    func testCandidatePathsDiscoverHomeAndProjectVirtualEnvs() throws {
        let home = try makeTempDir()
        let homeVenvPython = home.appendingPathComponent(".venv/bin/python3")
        let projectVenvPython = home
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("DemoProject", isDirectory: true)
            .appendingPathComponent(".venv/bin/python3")
        let nestedWorkspacePython = home
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("AX", isDirectory: true)
            .appendingPathComponent("Opensource", isDirectory: true)
            .appendingPathComponent("lmstudio-js-main", isDirectory: true)
            .appendingPathComponent(".venv/bin/python3")
        let nestedRadarPython = home
            .appendingPathComponent("SystemLogChecker", isDirectory: true)
            .appendingPathComponent(".systemlogchecker", isDirectory: true)
            .appendingPathComponent("radar_venv/bin/python3")

        try makeExecutable(at: homeVenvPython)
        try makeExecutable(at: projectVenvPython)
        try makeExecutable(at: nestedWorkspacePython)
        try makeExecutable(at: nestedRadarPython)

        let candidates = LocalPythonRuntimeDiscovery.candidatePaths(
            homeDirectory: home,
            fileManager: .default,
            builtinCandidates: [],
            environment: [:],
            childSearchRootNames: ["Documents"]
        )

        XCTAssertEqual(
            Set(candidates),
            Set([
                homeVenvPython.path,
                projectVenvPython.path,
                nestedWorkspacePython.path,
                nestedRadarPython.path,
            ])
        )
    }

    func testCandidatePathsPreferEnvironmentVirtualEnvFirst() throws {
        let home = try makeTempDir()
        let envPython = home
            .appendingPathComponent("custom_runtime", isDirectory: true)
            .appendingPathComponent("bin/python3")
        try makeExecutable(at: envPython)

        let candidates = LocalPythonRuntimeDiscovery.candidatePaths(
            homeDirectory: home,
            fileManager: .default,
            builtinCandidates: [],
            environment: ["VIRTUAL_ENV": envPython.deletingLastPathComponent().deletingLastPathComponent().path],
            childSearchRootNames: []
        )

        XCTAssertEqual(candidates.first, envPython.path)
    }

    func testCandidatePathsDiscoverLMStudioVendorPythons() throws {
        let home = try makeTempDir()
        let vendorPython = home
            .appendingPathComponent(".lmstudio/extensions/backends/vendor", isDirectory: true)
            .appendingPathComponent("_amphibian", isDirectory: true)
            .appendingPathComponent("cpython3.11-mac-arm64@10", isDirectory: true)
            .appendingPathComponent("bin/python3")

        try makeExecutable(at: vendorPython)

        let candidates = LocalPythonRuntimeDiscovery.candidatePaths(
            homeDirectory: home,
            fileManager: .default,
            builtinCandidates: [],
            environment: [:],
            childSearchRootNames: []
        )

        XCTAssertEqual(candidates, [vendorPython.path])
    }

    func testCandidatePathsPreferHubManagedRuntimeWrapperBeforeBuiltinPython() throws {
        let home = try makeTempDir()
        let hubBase = home.appendingPathComponent("RELFlowHub", isDirectory: true)
        let hubWrapperPython = hubBase
            .appendingPathComponent("ai_runtime", isDirectory: true)
            .appendingPathComponent("python3")
        let builtinPython = home
            .appendingPathComponent("framework", isDirectory: true)
            .appendingPathComponent("bin/python3")

        try makeExecutable(at: hubWrapperPython)
        try makeExecutable(at: builtinPython)

        let candidates = LocalPythonRuntimeDiscovery.candidatePaths(
            homeDirectory: home,
            fileManager: .default,
            builtinCandidates: [builtinPython.path],
            environment: [:],
            childSearchRootNames: [],
            hubBaseDirectories: [hubBase]
        )

        XCTAssertEqual(candidates, [hubWrapperPython.path, builtinPython.path])
    }

    func testSupplementalPythonPathEntriesPreferLMStudioAppSitePackages() throws {
        let home = try makeTempDir()
        let vendorRoot = home
            .appendingPathComponent(".lmstudio/extensions/backends/vendor", isDirectory: true)
            .appendingPathComponent("_amphibian", isDirectory: true)
        let vendorPython = vendorRoot
            .appendingPathComponent("cpython3.11-mac-arm64@10", isDirectory: true)
            .appendingPathComponent("bin/python3")
        let appSitePackages = vendorRoot
            .appendingPathComponent("app-mlx-generate-mac14-arm64@19", isDirectory: true)
            .appendingPathComponent("lib/python3.11/site-packages", isDirectory: true)
        let harmonySitePackages = vendorRoot
            .appendingPathComponent("app-harmony-mac-arm64@6", isDirectory: true)
            .appendingPathComponent("lib/python3.11/site-packages", isDirectory: true)

        try makeExecutable(at: vendorPython)
        try FileManager.default.createDirectory(at: appSitePackages, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: harmonySitePackages, withIntermediateDirectories: true)

        let entries = LocalPythonRuntimeDiscovery.supplementalPythonPathEntries(
            forPythonPath: vendorPython.path,
            homeDirectory: home,
            fileManager: .default
        )

        XCTAssertEqual(entries, [appSitePackages.path, harmonySitePackages.path])
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

    private func makeExecutable(at url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap("#!/bin/sh\nexit 0\n".data(using: .utf8))
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }
}
