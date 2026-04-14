import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class LocalLibraryRuntimeReadinessResolverTests: XCTestCase {
    func testVoiceModelReadyUsesTTSReadiness() {
        let readiness = LocalLibraryRuntimeReadinessResolver.readiness(
            for: makeVoiceModel(),
            ttsReadinessEvaluator: { modelID in
                IPCVoiceTTSReadinessResult(
                    ok: true,
                    source: "test",
                    provider: "transformers",
                    modelID: modelID,
                    reasonCode: "voice_tts_ready",
                    detail: "ready"
                )
            },
            commandLaunchConfigResolver: { _ in false },
            compatibilityEvaluator: { _, _ in nil }
        )

        XCTAssertEqual(readiness, LocalLibraryRuntimeReadiness.ready("已导入，可用于 Hub 本地语音播放。"))
    }

    func testVoiceModelUnavailableUsesReadinessDetail() {
        let readiness = LocalLibraryRuntimeReadinessResolver.readiness(
            for: makeVoiceModel(),
            ttsReadinessEvaluator: { modelID in
                IPCVoiceTTSReadinessResult(
                    ok: false,
                    source: "test",
                    provider: "transformers",
                    modelID: modelID,
                    reasonCode: "voice_tts_runtime_launch_config_unavailable",
                    detail: "local runtime command launch configuration is unavailable"
                )
            },
            commandLaunchConfigResolver: { _ in false },
            compatibilityEvaluator: { _, _ in nil }
        )

        XCTAssertEqual(
            readiness,
            LocalLibraryRuntimeReadiness.unavailable("local runtime command launch configuration is unavailable")
        )
    }

    func testLocalModelUnavailableWhenLaunchConfigMissing() {
        let readiness = LocalLibraryRuntimeReadinessResolver.readiness(
            for: makeTextModel(),
            commandLaunchConfigResolver: { _ in false },
            compatibilityEvaluator: { _, _ in nil }
        )

        XCTAssertEqual(
            readiness,
            LocalLibraryRuntimeReadiness.unavailable("Hub 无法为 mlx 解析本地运行时启动配置。")
        )
    }

    func testLocalModelUnavailableWhenCompatibilityBlocksLoad() {
        let readiness = LocalLibraryRuntimeReadinessResolver.readiness(
            for: makeTextModel(),
            commandLaunchConfigResolver: { _ in true },
            compatibilityEvaluator: { _, _ in
                "无法加载。当前 Python 运行时缺少 transformers。"
            }
        )

        XCTAssertEqual(
            readiness,
            LocalLibraryRuntimeReadiness.unavailable("无法加载。当前 Python 运行时缺少 transformers。")
        )
    }

    func testLocalModelReadyWhenLaunchConfigExistsAndNoCompatibilityBlock() {
        let readiness = LocalLibraryRuntimeReadinessResolver.readiness(
            for: makeTextModel(),
            commandLaunchConfigResolver: { _ in true },
            compatibilityEvaluator: { _, _ in nil }
        )

        XCTAssertEqual(readiness, LocalLibraryRuntimeReadiness.ready("已导入，可用于 Hub 本地执行。"))
    }

    func testReadinessSessionReusesProviderProbeForSameProvider() {
        var providerProbeCalls: [String: Int] = [:]
        let session = LocalLibraryRuntimeReadinessSession(
            providerProbeResolver: { providerID in
                providerProbeCalls[providerID, default: 0] += 1
                return LocalLibraryRuntimeProviderProbe(
                    launchConfigAvailable: true,
                    probeLaunchConfig: nil,
                    pythonPath: "/opt/homebrew/bin/python3"
                )
            },
            compatibilityEvaluator: { _, _ in nil }
        )

        let first = session.readiness(for: makeTextModel(id: "mlx/qwen"))
        let second = session.readiness(for: makeTextModel(id: "mlx/phi"))

        XCTAssertEqual(first, LocalLibraryRuntimeReadiness.ready("已导入，可用于 Hub 本地执行。"))
        XCTAssertEqual(second, LocalLibraryRuntimeReadiness.ready("已导入，可用于 Hub 本地执行。"))
        XCTAssertEqual(providerProbeCalls["mlx"], 1)
    }

    private func makeVoiceModel() -> HubModel {
        HubModel(
            id: "hexgrad/kokoro-82m",
            name: "Kokoro",
            backend: "transformers",
            quant: "bf16",
            contextLength: 4096,
            paramsB: 0.08,
            state: .available,
            modelPath: "/tmp/kokoro",
            taskKinds: ["text_to_speech"]
        )
    }

    private func makeTextModel(id: String = "mlx-community/qwen3-4b-instruct-4bit") -> HubModel {
        HubModel(
            id: id,
            name: "Qwen3 4B",
            backend: "mlx",
            quant: "4bit",
            contextLength: 8192,
            paramsB: 4.0,
            state: .available,
            modelPath: "/tmp/qwen3",
            taskKinds: ["text_generate"]
        )
    }
}
