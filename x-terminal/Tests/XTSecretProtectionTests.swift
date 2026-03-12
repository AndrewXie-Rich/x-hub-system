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
        #expect(session.isSending == false)

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
}
