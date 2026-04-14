import Foundation
import Testing
@testable import XTerminal

@MainActor
@Suite(.serialized)
struct AppModelSkillToolbarActionTests {

    @Test
    func editSkillOpensSkillMarkdownWhenFolderSelected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-edit-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = root.appendingPathComponent("demo-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillMarkdown = skillDir.appendingPathComponent("SKILL.md")
        try "# Demo Skill\n".write(to: skillMarkdown, atomically: true, encoding: .utf8)

        let appModel = AppModel()
        var openedURL: URL?
        appModel.openPanelSelectionOverrideForTesting = { panel in
            #expect(panel.title == "Choose Skill Folder or SKILL.md")
            return [skillDir]
        }
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }

        appModel.openSkillEditor()

        #expect(openedURL?.standardizedFileURL == skillMarkdown.standardizedFileURL)
    }

    @Test
    func importSkillsImportsSelectionAndShowsSummary() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-import-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceSkillDir = root.appendingPathComponent("agent-browser", isDirectory: true)
        let sourceNestedDir = sourceSkillDir.appendingPathComponent("assets", isDirectory: true)
        let targetSkillsDir = root.appendingPathComponent("skills-library", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceNestedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetSkillsDir, withIntermediateDirectories: true)
        try "# Agent Browser\n".write(
            to: sourceSkillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "asset".write(
            to: sourceNestedDir.appendingPathComponent("readme.txt"),
            atomically: true,
            encoding: .utf8
        )

        let appModel = AppModel()
        var alerts: [(title: String, message: String)] = []
        appModel.skillsDirectoryOverrideForTesting = targetSkillsDir
        appModel.openPanelSelectionOverrideForTesting = { panel in
            #expect(panel.title == "Import Skills or Packages")
            return [sourceSkillDir]
        }
        appModel.stagedImportSummaryOverrideForTesting = { skillDirectory, repoRoot in
            #expect(skillDirectory.lastPathComponent == "agent-browser")
            #expect(repoRoot.standardizedFileURL == targetSkillsDir.standardizedFileURL)
            return "agent-browser: staged for review"
        }
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        appModel.importSkills()

        let importedSkillDir = targetSkillsDir.appendingPathComponent("agent-browser", isDirectory: true)
        let importedAsset = importedSkillDir.appendingPathComponent("assets/readme.txt")
        try await waitUntil(timeoutMs: 5_000) {
            FileManager.default.fileExists(atPath: importedAsset.path) && !alerts.isEmpty
        }

        #expect(appModel.lastImportedAgentSkillDirectory?.standardizedFileURL == importedSkillDir.standardizedFileURL)
        #expect(appModel.lastImportedAgentSkillName == "agent-browser")
        #expect(alerts.last?.title == "Import Skills")
        #expect(alerts.last?.message.contains("Imported 1, skipped 0.") == true)
        #expect(alerts.last?.message.contains("agent-browser: staged for review") == true)
    }

    @Test
    func importSkillsExtractsZipArchiveAndImportsExtractedSkill() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-import-skill-archive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceSkillDir = root.appendingPathComponent("agent-browser", isDirectory: true)
        let sourceNestedDir = sourceSkillDir.appendingPathComponent("assets", isDirectory: true)
        let targetSkillsDir = root.appendingPathComponent("skills-library", isDirectory: true)
        let archiveURL = root.appendingPathComponent("agent-browser.zip")

        try FileManager.default.createDirectory(at: sourceNestedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetSkillsDir, withIntermediateDirectories: true)
        try "# Agent Browser\n".write(
            to: sourceSkillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "asset".write(
            to: sourceNestedDir.appendingPathComponent("readme.txt"),
            atomically: true,
            encoding: .utf8
        )

        let zipResult = try ProcessCapture.run(
            "/usr/bin/ditto",
            ["-c", "-k", "--keepParent", sourceSkillDir.path, archiveURL.path],
            cwd: nil,
            timeoutSec: 30.0
        )
        #expect(zipResult.exitCode == 0)

        let appModel = AppModel()
        var alerts: [(title: String, message: String)] = []
        appModel.skillsDirectoryOverrideForTesting = targetSkillsDir
        appModel.openPanelSelectionOverrideForTesting = { panel in
            #expect(panel.title == "Import Skills or Packages")
            return [archiveURL]
        }
        appModel.stagedImportSummaryOverrideForTesting = { skillDirectory, repoRoot in
            #expect(skillDirectory.lastPathComponent == "agent-browser")
            #expect(repoRoot.standardizedFileURL == targetSkillsDir.standardizedFileURL)
            return "agent-browser: staged from archive"
        }
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        appModel.importSkills()

        let importedSkillDir = targetSkillsDir.appendingPathComponent("agent-browser", isDirectory: true)
        let importedAsset = importedSkillDir.appendingPathComponent("assets/readme.txt")
        try await waitUntil(timeoutMs: 5_000) {
            FileManager.default.fileExists(atPath: importedAsset.path) && !alerts.isEmpty
        }

        #expect(appModel.lastImportedAgentSkillDirectory?.standardizedFileURL == importedSkillDir.standardizedFileURL)
        #expect(alerts.last?.title == "Import Skills")
        #expect(alerts.last?.message.contains("Imported 1, skipped 0.") == true)
        #expect(alerts.last?.message.contains("agent-browser: staged from archive") == true)
    }

    @Test
    func openCurrentSkillsIndexOpensGlobalIndexWhenPresent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-skills-index-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let indexDir = root
            .appendingPathComponent("memory-core", isDirectory: true)
            .appendingPathComponent("references", isDirectory: true)
        let indexURL = indexDir.appendingPathComponent("skills-index.md")
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)
        try "# Skills Index (auto)\n".write(to: indexURL, atomically: true, encoding: .utf8)

        let appModel = AppModel()
        var openedURL: URL?
        var alerts: [(title: String, message: String)] = []
        appModel.registry = .empty()
        appModel.selectedProjectId = nil
        appModel.skillsDirectoryOverrideForTesting = root
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        appModel.openCurrentSkillsIndex()

        #expect(openedURL?.standardizedFileURL == indexURL.standardizedFileURL)
        #expect(alerts.isEmpty)
    }

    @Test
    func openSupervisorVoiceSmokeReportUsesWorkspaceOpenHelper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-voice-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let reportURL = root.appendingPathComponent("xt_supervisor_voice_smoke.runtime.json")
        try "{}\n".write(to: reportURL, atomically: true, encoding: .utf8)

        let appModel = AppModel()
        var openedURL: URL?
        appModel.supervisorVoiceSmokeReportURLOverrideForTesting = reportURL
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }

        appModel.openSupervisorVoiceSmokeReport()

        #expect(appModel.canOpenSupervisorVoiceSmokeReport)
        #expect(openedURL?.standardizedFileURL == reportURL.standardizedFileURL)
    }

    @Test
    func openWorkspaceURLUsesWorkspaceOpenHelper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-open-url-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let targetURL = root.appendingPathComponent("artifact.txt")
        let appModel = AppModel()
        var openedURL: URL?
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }

        appModel.openWorkspaceURL(targetURL)

        #expect(openedURL?.standardizedFileURL == targetURL.standardizedFileURL)
    }

    @Test
    func createLocalSkillManifestWritesCanonicalManifestOpensFileAndShowsSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-create-manifest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = try makeMinimalSkillDirectory(root: root, name: "agent-browser")
        let manifestURL = skillDir.appendingPathComponent("skill.json")
        let appModel = AppModel()
        var openedURL: URL?
        var alerts: [(title: String, message: String)] = []
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        appModel.createLocalSkillManifest(at: skillDir)

        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        #expect(openedURL?.standardizedFileURL == manifestURL.standardizedFileURL)
        #expect(alerts.last?.title == "Create skill.json")
        #expect(alerts.last?.message.contains("agent-browser") == true)

        let data = try Data(contentsOf: manifestURL)
        let rootObject = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(rootObject["schema_version"] as? String == "xhub.skill_manifest.v1")
        #expect(rootObject["skill_id"] as? String == "agent-browser")
        #expect(rootObject["name"] as? String == "Agent Browser")
        #expect(rootObject["version"] as? String == "0.0.0-local")
        #expect(rootObject["description"] as? String == "Browser automation helper")

        let entrypoint = try #require(rootObject["entrypoint"] as? [String: Any])
        #expect(entrypoint["runtime"] as? String == "node")
        #expect(entrypoint["command"] as? String == "node")
        #expect(entrypoint["args"] as? [String] == ["main.js"])

        let networkPolicy = try #require(rootObject["network_policy"] as? [String: Any])
        #expect(networkPolicy["direct_network_forbidden"] as? Bool == true)

        let publisher = try #require(rootObject["publisher"] as? [String: Any])
        #expect(publisher["publisher_id"] as? String == "xhub.local.dev")
    }

    @Test
    func renameLocalSkillMovesFolderUpdatesTrackingOpensRenamedSkillMarkdownAndShowsSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-rename-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = try makeMinimalSkillDirectory(root: root, name: "agent-browser")
        let renamedDir = root.appendingPathComponent("agent-browser-fork", isDirectory: true)
        let renamedMarkdown = renamedDir.appendingPathComponent("SKILL.md")
        let appModel = AppModel()
        var openedURL: URL?
        var alerts: [(title: String, message: String)] = []
        appModel.lastImportedAgentSkillDirectory = skillDir
        appModel.lastImportedAgentSkillName = "agent-browser"
        appModel.skillRenamePromptOverrideForTesting = { title, message, initialValue in
            #expect(title == "Rename Skill Folder")
            #expect(message.contains("changes the folder name only") == true)
            #expect(initialValue == "agent-browser")
            return "agent-browser-fork"
        }
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        appModel.renameLocalSkill(at: skillDir)

        #expect(!FileManager.default.fileExists(atPath: skillDir.path))
        #expect(FileManager.default.fileExists(atPath: renamedDir.path))
        #expect(FileManager.default.fileExists(atPath: renamedDir.appendingPathComponent("main.js").path))
        #expect(openedURL?.standardizedFileURL == renamedMarkdown.standardizedFileURL)
        #expect(appModel.lastImportedAgentSkillDirectory?.standardizedFileURL == renamedDir.standardizedFileURL)
        #expect(appModel.lastImportedAgentSkillName == "agent-browser-fork")
        #expect(alerts.last?.title == "Rename Skill Folder")
        #expect(alerts.last?.message.contains("agent-browser -> agent-browser-fork") == true)
    }

    @Test
    func duplicateLocalSkillCopiesFolderOpensDuplicatedSkillMarkdownAndShowsSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-duplicate-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = try makeMinimalSkillDirectory(root: root, name: "agent-browser")
        var openedURL: URL?
        var alerts: [(title: String, message: String)] = []
        let appModel = AppModel()
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        appModel.duplicateLocalSkill(at: skillDir)

        let duplicatedSkillDir = root.appendingPathComponent("agent-browser-copy", isDirectory: true)
        let duplicatedSkillMarkdown = duplicatedSkillDir.appendingPathComponent("SKILL.md")
        let duplicatedEntrypoint = duplicatedSkillDir.appendingPathComponent("main.js")

        #expect(FileManager.default.fileExists(atPath: duplicatedSkillMarkdown.path))
        #expect(FileManager.default.fileExists(atPath: duplicatedEntrypoint.path))
        #expect(openedURL?.standardizedFileURL == duplicatedSkillMarkdown.standardizedFileURL)
        #expect(alerts.last?.title == "Duplicate Skill")
        #expect(alerts.last?.message.contains("agent-browser-copy") == true)
    }

    @Test
    func removeLocalSkillDeletesFolderClearsLastImportedTrackingAndShowsSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-remove-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = try makeMinimalSkillDirectory(root: root, name: "agent-browser")
        let appModel = AppModel()
        var alerts: [(title: String, message: String)] = []
        appModel.lastImportedAgentSkillDirectory = skillDir
        appModel.lastImportedAgentSkillName = "agent-browser"
        appModel.lastImportedAgentSkillStage = HubIPCClient.AgentImportStageResult(
            ok: true,
            source: "hub_runtime_grpc",
            stagingId: "stage-remove-001",
            status: "staged",
            auditRef: "audit-remove-001",
            preflightStatus: "passed",
            skillId: "agent-browser",
            policyScope: "global",
            findingsCount: 0,
            vetterStatus: "passed",
            vetterCriticalCount: 0,
            vetterWarnCount: 0,
            vetterAuditRef: nil,
            recordPath: nil,
            reasonCode: nil
        )
        appModel.skillRemovalConfirmationOverrideForTesting = { title, message in
            #expect(title == "Remove Skill")
            #expect(message.contains("agent-browser") == true)
            return true
        }
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        appModel.removeLocalSkill(at: skillDir)

        #expect(!FileManager.default.fileExists(atPath: skillDir.path))
        #expect(appModel.lastImportedAgentSkillDirectory == nil)
        #expect(appModel.lastImportedAgentSkillName.isEmpty)
        #expect(appModel.lastImportedAgentSkillStage == nil)
        #expect(appModel.lastImportedAgentSkillStatusLine.isEmpty)
        #expect(alerts.last?.title == "Remove Skill")
        #expect(alerts.last?.message.contains("Removed agent-browser") == true)
    }

    @Test
    func currentProjectArtifactOpenersUseWorkspaceOpenHelper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-project-openers-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let appModel = AppModel()
        var openedURLs: [URL] = []
        appModel.projectContext = ctx
        appModel.openedURLOverrideForTesting = { url in
            openedURLs.append(url)
        }

        appModel.openCurrentProjectXTerminalFolder()
        appModel.openCurrentProjectMemoryMarkdown()
        appModel.openCurrentProjectMemoryJSON()
        appModel.openCurrentProjectConfig()
        appModel.openCurrentProjectRawLog()

        let expectedURLs = [
            ctx.xterminalDir,
            ctx.memoryMarkdownURL,
            ctx.memoryJSONURL,
            ctx.configURL,
            ctx.rawLogURL
        ].map(\.standardizedFileURL)

        #expect(openedURLs.map(\.standardizedFileURL) == expectedURLs)
    }

    @Test
    func reviewLastImportedSkillShowsFetchedRecordAndUpdatesStatusLine() async throws {
        let appModel = AppModel()
        var alerts: [(title: String, message: String)] = []
        let stagingId = "stage-review-001"
        let packageSHA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

        appModel.lastImportedAgentSkillName = "agent-browser"
        appModel.lastImportedAgentSkillStage = HubIPCClient.AgentImportStageResult(
            ok: true,
            source: "hub_runtime_grpc",
            stagingId: stagingId,
            status: "staged",
            auditRef: "audit-stage-001",
            preflightStatus: "passed",
            skillId: "agent-browser",
            policyScope: "global",
            findingsCount: 1,
            vetterStatus: "passed",
            vetterCriticalCount: 0,
            vetterWarnCount: 1,
            vetterAuditRef: "audit-vetter-001",
            recordPath: "/tmp/import-record.json",
            reasonCode: nil
        )
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        let recordJSON = """
        {
          "staging_id": "\(stagingId)",
          "status": "staged",
          "audit_ref": "audit-stage-001",
          "requested_by": "xt-ui",
          "note": "ui_import:agent-browser",
          "vetter_status": "passed",
          "vetter_critical_count": 0,
          "vetter_warn_count": 1,
          "vetter_audit_ref": "audit-vetter-001",
          "enabled_package_sha256": "\(packageSHA)",
          "enabled_scope": "global",
          "import_manifest": {
            "skill_id": "agent-browser",
            "display_name": "Agent Browser",
            "preflight_status": "passed",
            "risk_level": "high",
            "policy_scope": "global",
            "requires_grant": true,
            "sandbox_class": "governed"
          },
          "findings": [
            {
              "code": "network_forbidden",
              "detail": "direct network disabled"
            }
          ]
        }
        """

        HubIPCClient.installAgentImportRecordOverrideForTesting { lookup in
            #expect(lookup.stagingId == stagingId)
            #expect(lookup.selector == nil)
            return HubIPCClient.AgentImportRecordResult(
                ok: true,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: stagingId,
                status: "staged",
                auditRef: "audit-stage-001",
                schemaVersion: "xhub.agent_import_record.v1",
                skillId: "agent-browser",
                projectId: nil,
                recordJSON: recordJSON,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetAgentImportRecordOverrideForTesting() }

        appModel.reviewLastImportedSkill()

        try await waitUntil(timeoutMs: 20_000) {
            !alerts.isEmpty
        }

        #expect(appModel.lastImportedAgentSkillStatusLine == "agent-browser: reviewed")
        #expect(alerts.last?.title == "Review Imported Skill")
        #expect(alerts.last?.message.contains("staging_id: \(stagingId)") == true)
        #expect(alerts.last?.message.contains("skill_id: agent-browser") == true)
        #expect(alerts.last?.message.contains("enabled_package: aaaaaaaaaaaa") == true)
        #expect(alerts.last?.message.contains("findings (1):") == true)
    }

    @Test
    func enableLastImportedSkillRunsGovernedFlowAndUpdatesStatusLine() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-appmodel-enable-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = try makeMinimalSkillDirectory(root: root, name: "agent-browser")
        let appModel = AppModel()
        var alerts: [(title: String, message: String)] = []
        let stagingId = "stage-enable-001"
        let packageSHA = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

        appModel.lastImportedAgentSkillDirectory = skillDir
        appModel.lastImportedAgentSkillName = "agent-browser"
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        HubIPCClient.installAgentImportStageOverrideForTesting { request in
            #expect(request.requestedBy == "xt-ui")
            #expect(request.note == "ui_import:agent-browser")
            #expect(request.importManifestJSON.contains("\"skill_id\":\""))
            #expect(request.importManifestJSON.contains("\"source_ref\":\"SKILL.md\""))
            return HubIPCClient.AgentImportStageResult(
                ok: true,
                source: "hub_runtime_grpc",
                stagingId: stagingId,
                status: "staged",
                auditRef: "audit-stage-enable",
                preflightStatus: "passed",
                skillId: "agent-browser",
                policyScope: "global",
                findingsCount: 0,
                vetterStatus: "passed",
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: "audit-vetter-enable",
                recordPath: "/tmp/import-enable.json",
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetAgentImportStageOverrideForTesting() }

        HubIPCClient.installSkillPackageUploadOverrideForTesting { request in
            #expect(request.sourceId == "local:xt-import")
            #expect(FileManager.default.fileExists(atPath: request.packageFileURL.path))
            #expect(request.manifestJSON.contains("\"skill_id\" : \""))
            #expect(request.manifestJSON.contains("\"description\" : \"Browser automation helper\""))
            #expect(request.manifestJSON.contains("\"path\" : \"main.js\""))
            return HubIPCClient.SkillPackageUploadResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA,
                alreadyPresent: false,
                skillId: "agent-browser",
                version: "0.0.0-local",
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetSkillPackageUploadOverrideForTesting() }

        HubIPCClient.installAgentImportPromoteOverrideForTesting { request in
            #expect(request.stagingId == stagingId)
            #expect(request.packageSHA256 == packageSHA)
            #expect(request.note == "ui_enable:agent-browser")
            return HubIPCClient.AgentImportPromoteResult(
                ok: true,
                source: "hub_runtime_grpc",
                stagingId: stagingId,
                status: "enabled",
                auditRef: "audit-promote-enable",
                packageSHA256: packageSHA,
                scope: "global",
                skillId: "agent-browser",
                previousPackageSHA256: nil,
                recordPath: "/tmp/import-enabled.json",
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetAgentImportPromoteOverrideForTesting() }

        appModel.enableLastImportedSkill()

        try await waitUntil(timeoutMs: 20_000) {
            !alerts.isEmpty
        }

        #expect(appModel.lastImportedAgentSkillStage?.stagingId == stagingId)
        #expect(appModel.lastImportedAgentSkillStatusLine == "agent-browser: enabled @0123456789ab")
        #expect(alerts.last?.title == "Enable Imported Skill")
        #expect(alerts.last?.message.contains("Package: sha=0123456789ab") == true)
        #expect(alerts.last?.message.contains("Included:") == true)
        #expect(alerts.last?.message.contains("SKILL.md") == true)
        #expect(alerts.last?.message.contains("main.js") == true)
        #expect(alerts.last?.message.contains("Enabled: agent-browser") == true)
        #expect(alerts.last?.message.contains("Scope: global") == true)
    }

    @Test
    func governanceSurfacePinProjectPinsSelectedProjectAndShowsSummary() async throws {
        let appModel = AppModel()
        let projectId = "project-alpha"
        let packageSHA = String(repeating: "a", count: 64)
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            packageSHA256: packageSHA,
            executionReadiness: XTSkillExecutionReadinessState.notInstalled.rawValue,
            whyNotRunnable: "not_installed",
            unblockActions: ["pin_package_project"]
        )

        var alerts: [(title: String, message: String)] = []
        var capturedRequest: HubIPCClient.SkillPinRequestPayload?
        appModel.selectedProjectId = projectId
        appModel.hubConnected = true
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        HubIPCClient.installSkillPinOverrideForTesting { request in
            await MainActor.run {
                capturedRequest = request
            }
            return HubIPCClient.SkillPinResult(
                ok: true,
                source: "hub_runtime_grpc",
                scope: request.scope,
                userId: "tester",
                projectId: request.projectId ?? "",
                skillId: request.skillId,
                packageSHA256: request.packageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 1_744_000_000_000,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetSkillPinOverrideForTesting() }

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("pin_package_project", for: entry))

        appModel.performSkillGovernanceSurfaceAction("pin_package_project", for: entry)

        try await waitUntil(timeoutMs: 5_000) {
            capturedRequest != nil
                && !alerts.isEmpty
                && appModel.skillGovernanceActionStatusLine.contains("status=ok")
        }

        let request = try #require(capturedRequest)
        #expect(request.scope == "project")
        #expect(request.projectId == projectId)
        #expect(request.skillId == "agent-browser")
        #expect(request.packageSHA256 == packageSHA)
        #expect(request.note == "xt_skill_governance_surface:project:agent-browser")
        #expect(request.requestId?.hasPrefix("xt-skill-governance-") == true)

        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=pin skill=agent-browser scope=project status=ok sha=aaaaaaaaaaaa")
        #expect(alerts.last?.title == "Pin Governed Skill")
        #expect(alerts.last?.message.contains("Pinned Agent Browser (agent-browser)") == true)
        #expect(alerts.last?.message.contains("Scope: project") == true)
        #expect(alerts.last?.message.contains("Package: aaaaaaaaaaaa") == true)
    }

    @Test
    func governanceSurfacePinProjectWithoutSelectedProjectShowsAlertAndDoesNotStartPin() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            unblockActions: ["pin_package_project"]
        )
        var alerts: [(title: String, message: String)] = []
        appModel.hubConnected = true
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        #expect(!appModel.canPerformSkillGovernanceSurfaceAction("pin_package_project", for: entry))

        appModel.performSkillGovernanceSurfaceAction("pin_package_project", for: entry)

        #expect(alerts.last?.title == "Pin Governed Skill")
        #expect(alerts.last?.message.contains("Select a project first") == true)
        #expect(appModel.skillGovernanceActionStatusLine.isEmpty)
    }

    @Test
    func governanceSurfaceOpenSurfaceRoutesToProjectGovernanceOverview() throws {
        let appModel = AppModel()
        let projectId = "project-alpha"
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            packageSHA256: String(repeating: "b", count: 64),
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            whyNotRunnable: "hub_grant_required",
            installHint: "Install the baseline or pin this package first.",
            unblockActions: ["open_skill_governance_surface"]
        )
        appModel.selectedProjectId = projectId

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("open_skill_governance_surface", for: entry))

        appModel.performSkillGovernanceSurfaceAction("open_skill_governance_surface", for: entry)

        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.projectId == projectId)
        #expect(request.destination == .overview)
        #expect(request.context?.title == "技能治理明细")
        #expect(request.context?.detail?.contains("Agent Browser") == true)
        #expect(request.context?.detail?.contains("state=blocked") == true)
        #expect(request.context?.detail?.contains("why_not=hub_grant_required") == true)
        #expect(request.context?.detail?.contains("Install the baseline or pin this package first.") == true)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=open_surface skill=agent-browser")
    }

    @Test
    func governanceSurfaceRequestLocalApprovalRoutesToProjectGovernanceOverview() throws {
        let appModel = AppModel()
        let projectId = "project-alpha"
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            whyNotRunnable: "local_approval_required",
            installHint: "Handle the pending local approval in project governance.",
            unblockActions: ["request_local_approval"]
        )
        appModel.selectedProjectId = projectId

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("request_local_approval", for: entry))

        appModel.performSkillGovernanceSurfaceAction("request_local_approval", for: entry)

        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.projectId == projectId)
        #expect(request.destination == .overview)
        #expect(request.context?.title == "处理本地技能审批")
        #expect(request.context?.detail?.contains("Agent Browser") == true)
        #expect(request.context?.detail?.contains("why_not=local_approval_required") == true)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=request_local_approval skill=agent-browser scope=project")
    }

    @Test
    func governanceSurfaceRequestLocalApprovalWithoutProjectShowsAlert() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            whyNotRunnable: "local_approval_required",
            unblockActions: ["request_local_approval"]
        )
        var alerts: [(title: String, message: String)] = []
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        #expect(!appModel.canPerformSkillGovernanceSurfaceAction("request_local_approval", for: entry))

        appModel.performSkillGovernanceSurfaceAction("request_local_approval", for: entry)

        #expect(alerts.last?.title == "Handle Local Approval")
        #expect(alerts.last?.message.contains("Select a project first") == true)
        #expect(appModel.projectSettingsFocusRequest == nil)
    }

    @Test
    func governanceSurfaceOpenProjectSettingsRoutesToProjectGovernanceOverview() throws {
        let appModel = AppModel()
        let projectId = "project-alpha"
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            executionReadiness: XTSkillExecutionReadinessState.degraded.rawValue,
            whyNotRunnable: "policy_review_needed",
            installHint: "Inspect governed skill profiles and blockers in project settings.",
            unblockActions: ["open_project_settings"]
        )
        appModel.selectedProjectId = projectId

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("open_project_settings", for: entry))

        appModel.performSkillGovernanceSurfaceAction("open_project_settings", for: entry)

        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.projectId == projectId)
        #expect(request.destination == .overview)
        #expect(request.context?.title == "技能治理总览")
        #expect(request.context?.detail?.contains("Agent Browser") == true)
        #expect(request.context?.detail?.contains("why_not=policy_review_needed") == true)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=open_project_settings skill=agent-browser scope=project")
    }

    @Test
    func governanceSurfaceOpenProjectSettingsWithoutProjectShowsAlert() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            unblockActions: ["open_project_settings"]
        )
        var alerts: [(title: String, message: String)] = []
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        #expect(!appModel.canPerformSkillGovernanceSurfaceAction("open_project_settings", for: entry))

        appModel.performSkillGovernanceSurfaceAction("open_project_settings", for: entry)

        #expect(alerts.last?.title == "Open Project Settings")
        #expect(alerts.last?.message.contains("No project is currently selected") == true)
        #expect(appModel.projectSettingsFocusRequest == nil)
    }

    @Test
    func governanceSurfaceOpenSurfaceWithoutProjectOpensDiagnosticsDeepLink() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            executionReadiness: XTSkillExecutionReadinessState.runtimeUnavailable.rawValue,
            whyNotRunnable: "runner_missing",
            installHint: "Open diagnostics to inspect runner readiness.",
            unblockActions: ["open_skill_governance_surface"]
        )
        var openedURL: URL?
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }

        appModel.performSkillGovernanceSurfaceAction("open_skill_governance_surface", for: entry)

        let url = try #require(openedURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.scheme == "xterminal")
        #expect(components.host == "settings")
        #expect(query["section_id"] == "diagnostics")
        #expect(query["title"] == "技能治理明细")
        #expect(query["detail"]?.contains("Agent Browser") == true)
        #expect(query["detail"]?.contains("why_not=runner_missing") == true)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=open_surface skill=agent-browser")
    }

    @Test
    func governanceSurfacePinGlobalPinsWithoutProjectAndShowsSummary() async throws {
        let appModel = AppModel()
        let packageSHA = String(repeating: "c", count: 64)
        let entry = makeGovernanceSurfaceEntry(
            skillID: "summarize",
            name: "Summarize",
            packageSHA256: packageSHA,
            executionReadiness: XTSkillExecutionReadinessState.notInstalled.rawValue,
            whyNotRunnable: "not_installed",
            unblockActions: ["pin_package_global"]
        )
        var alerts: [(title: String, message: String)] = []
        var capturedRequest: HubIPCClient.SkillPinRequestPayload?
        appModel.hubConnected = true
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        HubIPCClient.installSkillPinOverrideForTesting { request in
            await MainActor.run {
                capturedRequest = request
            }
            return HubIPCClient.SkillPinResult(
                ok: true,
                source: "hub_runtime_grpc",
                scope: request.scope,
                userId: "tester",
                projectId: request.projectId ?? "",
                skillId: request.skillId,
                packageSHA256: request.packageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 1_744_000_000_000,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetSkillPinOverrideForTesting() }

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("pin_package_global", for: entry))

        appModel.performSkillGovernanceSurfaceAction("pin_package_global", for: entry)

        try await waitUntil(timeoutMs: 5_000) {
            capturedRequest != nil
                && !alerts.isEmpty
                && appModel.skillGovernanceActionStatusLine.contains("scope=global")
                && appModel.skillGovernanceActionStatusLine.contains("status=ok")
        }

        let request = try #require(capturedRequest)
        #expect(request.scope == "global")
        #expect(request.projectId == nil)
        #expect(request.skillId == "summarize")
        #expect(request.packageSHA256 == packageSHA)
        #expect(request.note == "xt_skill_governance_surface:global:summarize")
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=pin skill=summarize scope=global status=ok sha=cccccccccccc")
        #expect(alerts.last?.message.contains("Scope: global") == true)
    }

    @Test
    func governanceSurfacePinGlobalWithoutHubShowsBlockedAlert() async throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "summarize",
            name: "Summarize",
            packageSHA256: String(repeating: "d", count: 64),
            unblockActions: ["pin_package_global"]
        )
        var alerts: [(title: String, message: String)] = []
        appModel.alertPresenterOverrideForTesting = { title, message in
            alerts.append((title, message))
        }

        #expect(!appModel.canPerformSkillGovernanceSurfaceAction("pin_package_global", for: entry))

        appModel.performSkillGovernanceSurfaceAction("pin_package_global", for: entry)

        try await waitUntil(timeoutMs: 2_000) {
            !alerts.isEmpty
                && appModel.skillGovernanceActionStatusLine.contains("status=blocked")
                && appModel.skillGovernanceActionStatusLine.contains("hub_pairing_required")
        }

        #expect(alerts.last?.title == "Pin Governed Skill")
        #expect(alerts.last?.message.contains("Pair X-Terminal to X-Hub first") == true)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=pin skill=summarize scope=global status=blocked reason=hub_pairing_required")
    }

    @Test
    func governanceSurfaceRequestHubGrantOpensHubSetupTroubleshootDeepLink() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            whyNotRunnable: "hub_grant_required",
            installHint: "Request the missing Hub grant.",
            unblockActions: ["request_hub_grant"]
        )
        var openedURL: URL?
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("request_hub_grant", for: entry))

        appModel.performSkillGovernanceSurfaceAction("request_hub_grant", for: entry)

        let url = try #require(openedURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.scheme == "xterminal")
        #expect(components.host == "hub-setup")
        #expect(query["section_id"] == "troubleshoot")
        #expect(query["title"] == "处理技能 Hub Grant")
        #expect(query["detail"]?.contains("Agent Browser") == true)
        #expect(query["detail"]?.contains("why_not=hub_grant_required") == true)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=request_hub_grant skill=agent-browser")
    }

    @Test
    func governanceSurfaceOpenTrustedAutomationDoctorOpensDiagnosticsDeepLink() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            executionReadiness: XTSkillExecutionReadinessState.runtimeUnavailable.rawValue,
            whyNotRunnable: "trusted_automation_not_ready",
            installHint: "Inspect local trusted automation readiness.",
            unblockActions: ["open_trusted_automation_doctor"]
        )
        var openedURL: URL?
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("open_trusted_automation_doctor", for: entry))

        appModel.performSkillGovernanceSurfaceAction("open_trusted_automation_doctor", for: entry)

        let query = try queryItems(from: #require(openedURL))
        #expect(query["section_id"] == "diagnostics")
        #expect(query["title"] == "Trusted Automation Doctor")
        #expect(query["detail"]?.contains("why_not=trusted_automation_not_ready") == true)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=open_trusted_automation_doctor skill=agent-browser")
    }

    @Test
    func governanceSurfaceReconnectHubOpensPairProgressDeepLink() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            executionReadiness: XTSkillExecutionReadinessState.hubDisconnected.rawValue,
            whyNotRunnable: "hub_disconnected",
            installHint: "Reconnect X-Terminal to X-Hub.",
            unblockActions: ["reconnect_hub"]
        )
        var openedURL: URL?
        appModel.openedURLOverrideForTesting = { url in
            openedURL = url
        }

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("reconnect_hub", for: entry))

        appModel.performSkillGovernanceSurfaceAction("reconnect_hub", for: entry)

        let query = try queryItems(from: #require(openedURL))
        #expect(query["section_id"] == "pair_progress")
        #expect(query["title"] == "Reconnect Hub")
        #expect(query["detail"]?.contains("why_not=hub_disconnected") == true)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=reconnect_hub skill=agent-browser")
    }

    @Test
    func governanceSurfaceRetryDispatchRechecksAndRoutesToGovernanceOverview() throws {
        let appModel = AppModel()
        let projectId = "project-alpha"
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            executionReadiness: XTSkillExecutionReadinessState.degraded.rawValue,
            whyNotRunnable: "dispatch_stale",
            installHint: "Retry the governed dispatch and inspect the latest truth.",
            unblockActions: ["retry_dispatch"]
        )
        appModel.selectedProjectId = projectId

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("retry_dispatch", for: entry))

        appModel.performSkillGovernanceSurfaceAction("retry_dispatch", for: entry)

        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.projectId == projectId)
        #expect(request.destination == .overview)
        #expect(request.context?.title == "重查技能执行状态")
        #expect(request.context?.detail?.contains("why_not=dispatch_stale") == true)
        #expect(request.context?.detail?.contains("Retry the governed dispatch and inspect the latest truth.") == true)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=retry_dispatch skill=agent-browser status=rechecking")
        #expect(appModel.officialSkillsRecheckStatusLine.contains("reason=skill_governance_retry_dispatch"))
    }

    @Test
    func governanceSurfaceRefreshResolvedCacheRecordsRecheckReason() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            unblockActions: ["refresh_resolved_cache"]
        )

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("refresh_resolved_cache", for: entry))

        appModel.performSkillGovernanceSurfaceAction("refresh_resolved_cache", for: entry)

        #expect(appModel.officialSkillsRecheckStatusLine.contains("official_skills_recheck="))
        #expect(appModel.officialSkillsRecheckStatusLine.contains("reason=skill_governance_surface_refresh"))
        #expect(appModel.skillGovernanceActionStatusLine.contains("official_skills_recheck="))
        #expect(appModel.skillGovernanceActionStatusLine.contains("reason=skill_governance_surface_refresh"))
    }

    @Test
    func governanceSurfaceInstallBaselineUsesProjectScopeWhenProjectSelected() throws {
        let appModel = AppModel()
        let projectId = "project-alpha"
        let entry = makeGovernanceSurfaceEntry(
            skillID: "find-skills",
            name: "Find Skills",
            unblockActions: ["install_baseline"]
        )
        var capturedScope: AXAgentBaselineInstallScope?
        appModel.selectedProjectId = projectId
        appModel.hubConnected = true
        appModel.baselineInstallActionOverrideForTesting = { scope in
            capturedScope = scope
        }

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("install_baseline", for: entry))

        appModel.performSkillGovernanceSurfaceAction("install_baseline", for: entry)

        #expect(capturedScope == .project(projectId: projectId, projectName: nil))
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=install_baseline skill=find-skills target=project")
    }

    @Test
    func governanceSurfaceInstallBaselineUsesGlobalScopeWithoutProject() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "find-skills",
            name: "Find Skills",
            unblockActions: ["install_baseline"]
        )
        var capturedScope: AXAgentBaselineInstallScope?
        appModel.hubConnected = true
        appModel.baselineInstallActionOverrideForTesting = { scope in
            capturedScope = scope
        }

        #expect(appModel.canPerformSkillGovernanceSurfaceAction("install_baseline", for: entry))

        appModel.performSkillGovernanceSurfaceAction("install_baseline", for: entry)

        #expect(capturedScope == .global)
        #expect(appModel.skillGovernanceActionStatusLine == "skill_governance_action=install_baseline skill=find-skills target=global")
    }

    @Test
    func governanceSurfaceInstallBaselineRequiresInteractiveHub() throws {
        let appModel = AppModel()
        let entry = makeGovernanceSurfaceEntry(
            skillID: "find-skills",
            name: "Find Skills",
            unblockActions: ["install_baseline"]
        )

        #expect(!appModel.canPerformSkillGovernanceSurfaceAction("install_baseline", for: entry))
    }

    private func makeMinimalSkillDirectory(root: URL, name: String) throws -> URL {
        let skillDir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillMarkdown = """
        ---
        name: Agent Browser
        version: 0.0.0-local
        description: Browser automation helper
        ---
        # Agent Browser
        """
        try skillMarkdown.write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "console.log('ok');\n".write(
            to: skillDir.appendingPathComponent("main.js"),
            atomically: true,
            encoding: .utf8
        )
        return skillDir
    }

    private func makeGovernanceSurfaceEntry(
        skillID: String = "agent-browser",
        name: String = "Agent Browser",
        packageSHA256: String = String(repeating: "a", count: 64),
        executionReadiness: String = XTSkillExecutionReadinessState.notInstalled.rawValue,
        whyNotRunnable: String = "not_installed",
        installHint: String = "Install baseline.",
        unblockActions: [String] = []
    ) -> AXSkillGovernanceSurfaceEntry {
        AXSkillGovernanceSurfaceEntry(
            skillID: skillID,
            name: name,
            version: "1.0.0",
            riskLevel: "high",
            packageSHA256: packageSHA256,
            publisherID: "xhub.official",
            sourceID: "hub_catalog",
            policyScope: "project",
            tone: .blocked,
            stateLabel: "blocked",
            intentFamilies: ["research"],
            capabilityFamilies: ["browser"],
            capabilityProfiles: ["browser_research"],
            grantFloor: XTSkillGrantFloor.readonly.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            requestabilityState: "requestable",
            executionReadiness: executionReadiness,
            whyNotRunnable: whyNotRunnable,
            unblockActions: unblockActions,
            trustRootValue: "trusted",
            pinnedVersionValue: "none",
            runnerRequirementValue: "node",
            compatibilityStatusValue: "compatible",
            preflightResultValue: "passed",
            note: "",
            installHint: installHint
        )
    }

    private func queryItems(from url: URL) throws -> [String: String] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private func waitUntil(timeoutMs: UInt64, condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().timeIntervalSince1970 + Double(timeoutMs) / 1000.0
        while Date().timeIntervalSince1970 < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("condition not met before timeout")
    }
}
