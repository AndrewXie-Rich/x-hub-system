import Foundation
import Testing
@testable import XTerminal

struct XTSecretProtectionTests {
    @Test
    func englishCredentialAssignmentIsProtected() {
        let analysis = XTSecretProtection.analyzeUserInput(
            "Please log in. password=SuperSecret123"
        )

        #expect(analysis.shouldProtect)
        #expect(analysis.sanitizedText.contains("password=[redacted]"))
        #expect(analysis.signals.contains("named_secret_assignment"))
    }

    @Test
    func chineseCredentialAssignmentIsProtected() {
        let analysis = XTSecretProtection.analyzeUserInput(
            "帮我登录这个网站，密码是abc123456"
        )

        #expect(analysis.shouldProtect)
        #expect(analysis.sanitizedText.contains("密码=[已脱敏]"))
        #expect(analysis.signals.contains("named_secret_assignment_zh"))
    }

    @Test
    func plainPasswordQuestionIsNotProtected() {
        let analysis = XTSecretProtection.analyzeUserInput(
            "我忘了网站密码，该怎么重置？"
        )

        #expect(!analysis.shouldProtect)
        #expect(analysis.sanitizedText == "我忘了网站密码，该怎么重置？")
        #expect(analysis.signals.isEmpty)
    }

    @Test
    func supervisorGovernanceDispatchWithHexProjectIdDoesNotTripSecretProtection() {
        let projectID = "cd5d806cf69a246d909f3d45ab85c43e0d6442fb966a34856585d39419bb6270"
        let payload = """
        来自 Supervisor 的项目执行派发。
        项目：坦克大战
        project_id：\(projectID)

        trigger=heartbeat
        project_ref=坦克大战
        project_id=\(projectID)
        review_trigger=pre_done_summary
        review_level_hint=r3_rescue
        policy_reason=heartbeat_anomaly=weak_done_claim quality=weak anomalies=weak_done_claim
        project_memory_truth_source=latest_coder_usage
        active_job_goal=交付一个最小可运行的网页版本：`坦克大战`
        active_job_status=running
        step_title=搭建最小可运行骨架
        """

        let analysis = XTSecretProtection.analyzeUserInput(payload)

        #expect(analysis.shouldProtect == false)
        #expect(analysis.signals.isEmpty)
    }

    @Test
    func standalonePrivateTagIsStillProtected() {
        let analysis = XTSecretProtection.analyzeUserInput(
            "<private>use the credential from my notes"
        )

        #expect(analysis.shouldProtect)
        #expect(analysis.sanitizedText.contains("[private omitted]"))
        #expect(analysis.signals.contains("private_tag"))
    }

    @Test
    func bearerTokenIsProtected() {
        let analysis = XTSecretProtection.analyzeUserInput(
            "Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456"
        )

        #expect(analysis.shouldProtect)
        #expect(
            analysis.sanitizedText.contains("Bearer [redacted_token]")
                || analysis.sanitizedText.contains("Authorization: [redacted]")
        )
        #expect(analysis.signals.contains("bearer_token") || analysis.signals.contains("authorization_header"))
    }

    @MainActor
    @Test
    func chatSendProtectsSecretBeforeRawLogPersistence() throws {
        let root = try makeProjectRoot(named: "project-secret-protection-send")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let store = SettingsStore()
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        session.draft = "请帮我登录，password=SuperSecret123"
        session.send(
            ctx: ctx,
            memory: nil,
            config: AXProjectConfig.default(forProjectRoot: root),
            router: router
        )

        #expect(session.messages.count == 2)
        #expect(session.messages[0].content.contains("password=[redacted]"))
        #expect(session.messages[1].content.contains("保护模式"))
        #expect(session.messages[1].content.contains("status=awaiting_authorization"))
        #expect(session.messages[1].content.contains("approval_actor=user_or_supervisor"))
        #expect(session.isSending == false)

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(!rawLog.contains("SuperSecret123"))
        #expect(rawLog.contains("password=[redacted]"))
    }

    @MainActor
    @Test
    func approvedProtectedInputContinuesWithSanitizedTextOnly() async throws {
        let root = try makeProjectRoot(named: "project-secret-protection-approval")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let store = SettingsStore()
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        session.draft = "请帮我登录，password=SuperSecret123"
        session.send(
            ctx: ctx,
            memory: nil,
            config: AXProjectConfig.default(forProjectRoot: root),
            router: router
        )

        #expect(session.messages[1].content.contains("status=awaiting_authorization"))

        ChatSessionModel.installLLMGenerateOverrideForTesting { _, prompt, _ in
            #expect(!prompt.contains("SuperSecret123"))
            #expect(prompt.contains("password=[redacted]"))
            return #"{"final":"已按脱敏输入继续。"}"#
        }
        defer { ChatSessionModel.resetLLMGenerateOverrideForTesting() }

        session.draft = "approve_sanitized_continue"
        session.send(
            ctx: ctx,
            memory: nil,
            config: AXProjectConfig.default(forProjectRoot: root),
            router: router
        )

        try await waitUntil(timeoutMs: 2_000) {
            session.isSending == false && session.messages.last?.role == .assistant
        }

        #expect(session.messages.contains { $0.role == .user && $0.content.contains("password=[redacted]") })
        #expect(session.messages.last?.content.contains("已按脱敏输入继续") == true)

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(!rawLog.contains("SuperSecret123"))
        #expect(rawLog.contains("password=[redacted]"))
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_secret_protection_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor
    private func waitUntil(
        timeoutMs: UInt64,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(condition())
    }
}
