import Testing
@testable import XTerminal

struct XTHubGenerateWaitPresentationTests {

    @Test
    func grpcLocalModelInitialLineMentionsHubLocalModel() {
        let descriptor = XTHubGenerateWaitDescriptor(
            transportMode: .grpc,
            modelLabel: "gpt-oss-20b",
            backend: "mlx",
            usesHubLocalModel: true
        )

        #expect(
            XTHubGenerateWaitPresentation.initialLine(for: descriptor)
                == "已把请求发给 Hub 本地模型 gpt-oss-20b，正在等待首段输出。"
        )
    }

    @Test
    func grpcLocalModelFollowUpExplainsSilentWarmup() {
        let descriptor = XTHubGenerateWaitDescriptor(
            transportMode: .grpc,
            modelLabel: "qwen3-vl-30b",
            backend: "mlx",
            usesHubLocalModel: true
        )

        #expect(
            XTHubGenerateWaitPresentation.followUpLine(
                for: descriptor,
                elapsedSeconds: 12
            ).contains("前几十秒可能没有可见输出")
        )
    }

    @Test
    func fileIPCFollowUpMentionsLocalModelWait() {
        let descriptor = XTHubGenerateWaitDescriptor(
            transportMode: .fileIPC,
            modelLabel: "Qwen3-1.7B",
            backend: "mlx",
            usesHubLocalModel: true
        )

        #expect(
            XTHubGenerateWaitPresentation.followUpLine(
                for: descriptor,
                elapsedSeconds: 22
            ) == "已等待 22 秒；本机模型仍在生成，可继续等待或点停止取消。"
        )
    }
}
