import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubAICancelTests {
    @Test
    func cancelWritesCommandFileWhenQueueSucceeds() async throws {
        let base = try makeTempDirectory("hub_ai_cancel_success")
        HubPaths.setPinnedBaseDirOverride(base)
        defer {
            HubAIClient.resetCancelWriteOverrideForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let status = await HubAIClient.shared.cancel(reqId: "req-success")
        #expect(status.requestQueued == true)
        #expect(status.requestError.isEmpty)

        let url = base
            .appendingPathComponent("ai_cancels", isDirectory: true)
            .appendingPathComponent("cancel_req-success.json")
        let data = try Data(contentsOf: url)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["req_id"] as? String == "req-success")
    }

    @Test
    func cancelReportsCommandQueueFailure() async throws {
        let base = try makeTempDirectory("hub_ai_cancel_failure")
        HubPaths.setPinnedBaseDirOverride(base)
        HubAIClient.installCancelWriteOverrideForTesting { _, _, _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: 28)
        }
        defer {
            HubAIClient.resetCancelWriteOverrideForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let status = await HubAIClient.shared.cancel(reqId: "req-failure")
        #expect(status.requestQueued == false)
        #expect(status.requestError.contains("cancel_command_write_failed"))
    }

    @Test
    func chatSessionCancelSurfacesDeliveryFailureToUI() async throws {
        let base = try makeTempDirectory("hub_ai_cancel_chat")
        HubPaths.setPinnedBaseDirOverride(base)
        HubAIClient.installCancelWriteOverrideForTesting { _, _, _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: 28)
        }
        defer {
            HubAIClient.resetCancelWriteOverrideForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let session = await MainActor.run { ChatSessionModel() }
        await MainActor.run {
            session.currentReqId = "req-chat"
            session.cancel()
        }

        let lastError = try await waitForLastError(session)
        #expect(lastError.contains("取消请求未成功送达 Hub"))
        #expect(lastError.contains("cancel_command_write_failed"))
    }

    private func makeTempDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForLastError(_ session: ChatSessionModel) async throws -> String {
        for _ in 0..<40 {
            let value = await MainActor.run { session.lastError }
            if let value,
               !value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return value
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        struct TimedOut: Error {}
        throw TimedOut()
    }
}
