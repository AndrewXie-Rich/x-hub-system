import XCTest
@testable import RELFlowHub

final class CLIProxyRuntimeSupportTests: XCTestCase {
    func testSettingsDecodeUsesDefaultsWhenFieldsMissing() throws {
        let data = Data("{}".utf8)

        let settings = try JSONDecoder().decode(CLIProxyRuntimeSupport.Settings.self, from: data)

        XCTAssertEqual(settings.packageDirectoryPath, "")
        XCTAssertTrue(settings.preferDetectedPackage)
        XCTAssertTrue(settings.useLocalModel)
    }

    func testDetectPackageDirectoryPrefersNewestValidCandidate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let older = root.appendingPathComponent("CLIProxyAPI_6.9.10_darwin_amd64", isDirectory: true)
        let newer = root.appendingPathComponent("CLIProxyAPI_6.9.30_darwin_amd64", isDirectory: true)
        let broken = root.appendingPathComponent("CLIProxyAPI_broken_darwin_amd64", isDirectory: true)

        try makePackageDirectory(at: older)
        try makePackageDirectory(at: newer)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: older.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newer.path
        )

        let detected = CLIProxyRuntimeSupport.detectPackageDirectoryURL(searchRoots: [root])

        XCTAssertEqual(detected?.standardizedFileURL.path, newer.standardizedFileURL.path)
    }

    func testLaunchCommandSummaryReflectsLocalModelChoice() {
        XCTAssertEqual(
            CLIProxyRuntimeSupport.launchCommandSummary(for: .init()),
            "./cli-proxy-api --config config.yaml --local-model"
        )
        XCTAssertEqual(
            CLIProxyRuntimeSupport.launchCommandSummary(
                for: .init(packageDirectoryPath: "", preferDetectedPackage: true, useLocalModel: false)
            ),
            "./cli-proxy-api --config config.yaml"
        )
    }

    func testAuditConfigFlagsRecommendedFixes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try makePackageDirectory(at: directory)

        let configURL = directory.appendingPathComponent("config.yaml")
        try sampleConfigNeedingFixes.write(to: configURL, atomically: true, encoding: .utf8)

        let audit = CLIProxyRuntimeSupport.auditConfig(
            settings: .init(packageDirectoryPath: directory.path, preferDetectedPackage: false, useLocalModel: true)
        )

        XCTAssertEqual(audit.recommendations.count, 6)
        XCTAssertEqual(audit.unresolvedCount, 3)
        XCTAssertTrue(
            audit.unresolvedRecommendations.contains { $0.kind == .bindLocalHost }
        )
        XCTAssertTrue(
            audit.unresolvedRecommendations.contains { $0.kind == .disablePanelAutoUpdate }
        )
        XCTAssertTrue(
            audit.unresolvedRecommendations.contains { $0.kind == .disableLoggingToFile }
        )
    }

    func testApplyRecommendedConfigFixesUpdatesConfigAndWritesBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try makePackageDirectory(at: directory)

        let configURL = directory.appendingPathComponent("config.yaml")
        try sampleConfigNeedingFixes.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try CLIProxyRuntimeSupport.applyRecommendedConfigFixes(
            settings: .init(packageDirectoryPath: directory.path, preferDetectedPackage: false, useLocalModel: true)
        )

        let updated = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(updated.contains(#"host: "127.0.0.1""#))
        XCTAssertTrue(updated.contains("  disable-auto-update-panel: true"))
        XCTAssertTrue(updated.contains("logging-to-file: false"))
        XCTAssertFalse(updated.contains("# disable-auto-update-panel: false"))
        XCTAssertEqual(result.changedCount, 3)
        XCTAssertFalse(result.backupPath.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupPath))

        let postAudit = CLIProxyRuntimeSupport.auditConfig(
            settings: .init(packageDirectoryPath: directory.path, preferDetectedPackage: false, useLocalModel: true)
        )
        XCTAssertEqual(postAudit.unresolvedCount, 0)
    }

    func testRotateManagementKeyUpdatesConfigAndWritesBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try makePackageDirectory(at: directory)

        let configURL = directory.appendingPathComponent("config.yaml")
        try sampleConfigNeedingFixes.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try CLIProxyRuntimeSupport.rotateManagementKey(
            settings: .init(packageDirectoryPath: directory.path, preferDetectedPackage: false, useLocalModel: true)
        )

        let updated = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(result.newKey.isEmpty)
        XCTAssertNotEqual(result.newKey, "example-secret")
        XCTAssertTrue(updated.contains(#"  secret-key: ""#))
        XCTAssertTrue(updated.contains(result.newKey))
        XCTAssertFalse(result.backupPath.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupPath))

        let backup = try String(contentsOfFile: result.backupPath, encoding: .utf8)
        XCTAssertTrue(backup.contains(#"  secret-key: "example-secret""#))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makePackageDirectory(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let executableURL = directory.appendingPathComponent("cli-proxy-api")
        let configURL = directory.appendingPathComponent("config.yaml")

        FileManager.default.createFile(atPath: executableURL.path, contents: Data("echo ok".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        FileManager.default.createFile(atPath: configURL.path, contents: Data("port: 8317\n".utf8))
    }

    private var sampleConfigNeedingFixes: String {
        """
        host: ""
        remote-management:
          allow-remote: false
          secret-key: "example-secret"
          disable-control-panel: false
        # disable-auto-update-panel: false
        logging-to-file: true
        usage-statistics-enabled: false
        """
    }
}
