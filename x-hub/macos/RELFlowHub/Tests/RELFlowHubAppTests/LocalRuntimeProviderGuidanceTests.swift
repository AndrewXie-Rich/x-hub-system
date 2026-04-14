import XCTest
@testable import RELFlowHub

final class LocalRuntimeProviderGuidanceTests: XCTestCase {
    func testTransformersMissingTorchHintMentionsAutoDetectWhenNoSupportingCandidateExists() {
        let hint = LocalRuntimeProviderGuidance.providerHint(
            providerID: "transformers",
            reasonCode: "import_error",
            importError: "missing_module:torch",
            selectedPythonPath: "/usr/bin/python3",
            preferredPythonPath: "/usr/bin/python3",
            candidates: [
                LocalPythonRuntimeCandidateStatus(
                    path: "/usr/bin/python3",
                    version: "3.9",
                    readyProviders: ["mlx"],
                    score: 5
                ),
                LocalPythonRuntimeCandidateStatus(
                    path: "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11",
                    version: "3.11",
                    readyProviders: ["mlx"],
                    score: 6
                ),
            ]
        )

        XCTAssertTrue(hint.contains("缺少 torch"))
        XCTAssertTrue(hint.contains("目前都不支持 transformers"))
        XCTAssertTrue(hint.contains("会在下次刷新时自动发现"))
    }

    func testTransformersMissingTorchHintMentionsBetterDetectedPython() {
        let hint = LocalRuntimeProviderGuidance.providerHint(
            providerID: "transformers",
            reasonCode: "import_error",
            importError: "missing_module:torch",
            selectedPythonPath: "/usr/bin/python3",
            preferredPythonPath: "/Users/test/Documents/AX/project/.venv/bin/python3",
            candidates: [
                LocalPythonRuntimeCandidateStatus(
                    path: "/Users/test/Documents/AX/project/.venv/bin/python3",
                    version: "3.11",
                    readyProviders: ["transformers", "mlx"],
                    score: 18
                ),
            ]
        )

        XCTAssertTrue(hint.contains("更合适的本地 Python"))
        XCTAssertTrue(hint.contains("Hub 会自动切换"))
        XCTAssertTrue(hint.contains("/Users/test/Documents/AX/project/.venv/bin/python3"))
    }

    func testTransformersHintMentionsUserRuntimeFallbackSource() {
        let hint = LocalRuntimeProviderGuidance.providerHint(
            providerID: "transformers",
            reasonCode: "ready",
            importError: "",
            runtimeResolutionState: "user_runtime_fallback",
            runtimeSource: "user_python_venv",
            runtimeSourcePath: "/Users/test/project/.venv/bin/python3",
            runtimeReasonCode: "ready",
            runtimeHint: "transformers 当前运行在用户 Python /Users/test/project/.venv/bin/python3，而不是 Hub 托管的运行时包。",
            fallbackUsed: true,
            selectedPythonPath: "/Users/test/project/.venv/bin/python3",
            preferredPythonPath: nil,
            candidates: []
        )

        XCTAssertTrue(hint.contains("用户 Python"))
        XCTAssertTrue(hint.contains("/Users/test/project/.venv/bin/python3"))
    }

    func testTransformersHintMentionsLocalHelperWhenHelperBridgeIsUnavailable() {
        let hint = LocalRuntimeProviderGuidance.providerHint(
            providerID: "transformers",
            reasonCode: "import_error",
            importError: "",
            runtimeResolutionState: "runtime_missing",
            runtimeSource: "helper_binary_bridge",
            runtimeSourcePath: "/Users/test/.lmstudio/bin/lms",
            runtimeReasonCode: "helper_service_down",
            runtimeHint: "Hub 会在下一次预热时自动启动本地辅助运行时。",
            fallbackUsed: false,
            selectedPythonPath: "/usr/bin/python3",
            preferredPythonPath: nil,
            candidates: []
        )

        XCTAssertTrue(hint.contains("本地辅助运行时"))
        XCTAssertTrue(hint.contains("辅助服务当前不可用"))
        XCTAssertTrue(hint.contains("/Users/test/.lmstudio/bin/lms"))
    }

    func testTransformersHintMentionsLocalServiceDisabledWhenHelperBridgeSettingsDisableIt() {
        let hint = LocalRuntimeProviderGuidance.providerHint(
            providerID: "transformers",
            reasonCode: "import_error",
            importError: "",
            runtimeResolutionState: "runtime_missing",
            runtimeSource: "helper_binary_bridge",
            runtimeSourcePath: "/Users/test/.lmstudio/bin/lms",
            runtimeReasonCode: "helper_local_service_disabled",
            runtimeHint: "请在 LM Studio 里启用 Local Service，然后重新运行 helper 探测。",
            fallbackUsed: false,
            selectedPythonPath: "/usr/bin/python3",
            preferredPythonPath: nil,
            candidates: []
        )

        XCTAssertTrue(hint.contains("Local Service 当前是关闭的"))
        XCTAssertTrue(hint.contains("启用 Local Service"))
    }

    func testTransformersHintMentionsHubManagedLocalServiceWhenServiceIsUnavailable() {
        let hint = LocalRuntimeProviderGuidance.providerHint(
            providerID: "transformers",
            reasonCode: "import_error",
            importError: "",
            runtimeResolutionState: "runtime_missing",
            runtimeSource: "xhub_local_service",
            runtimeSourcePath: "http://127.0.0.1:50171",
            runtimeReasonCode: "xhub_local_service_unreachable",
            runtimeHint: "Hub 托管的本地运行时服务 http://127.0.0.1:50171 当前不可达。",
            fallbackUsed: false,
            selectedPythonPath: "/usr/bin/python3",
            preferredPythonPath: nil,
            candidates: []
        )

        XCTAssertTrue(hint.contains("Hub 托管的本地运行时服务"))
        XCTAssertTrue(hint.contains("当前无法访问这个服务"))
        XCTAssertTrue(hint.contains("http://127.0.0.1:50171"))
    }

    func testMLXVLMHintUsesProviderSpecificHelperGuidanceInsteadOfGenericFallback() {
        let hint = LocalRuntimeProviderGuidance.providerHint(
            providerID: "mlx_vlm",
            reasonCode: "import_error",
            importError: "",
            runtimeResolutionState: "runtime_missing",
            runtimeSource: "helper_binary_bridge",
            runtimeSourcePath: "/Users/test/.lmstudio/bin/lms",
            runtimeReasonCode: "helper_service_down",
            runtimeHint: "Hub 会在下一次预热时自动启动本地辅助运行时。",
            fallbackUsed: false,
            selectedPythonPath: "/usr/bin/python3",
            preferredPythonPath: nil,
            candidates: []
        )

        XCTAssertTrue(hint.contains("MLX VLM"))
        XCTAssertTrue(hint.contains("本地辅助运行时"))
        XCTAssertTrue(hint.contains("辅助服务当前不可用"))
        XCTAssertTrue(hint.contains("/Users/test/.lmstudio/bin/lms"))
    }

    func testLlamaCppHintUsesProviderSpecificHelperGuidanceInsteadOfGenericFallback() {
        let hint = LocalRuntimeProviderGuidance.providerHint(
            providerID: "llama.cpp",
            reasonCode: "import_error",
            importError: "",
            runtimeResolutionState: "runtime_missing",
            runtimeSource: "helper_binary_bridge",
            runtimeSourcePath: "/Users/test/.lmstudio/bin/lms",
            runtimeReasonCode: "helper_service_down",
            runtimeHint: "Hub 会在下一次预热时自动启动本地辅助运行时。",
            fallbackUsed: false,
            selectedPythonPath: "/usr/bin/python3",
            preferredPythonPath: nil,
            candidates: []
        )

        XCTAssertTrue(hint.contains("llama.cpp"))
        XCTAssertTrue(hint.contains("本地辅助运行时"))
        XCTAssertTrue(hint.contains("辅助服务当前不可用"))
        XCTAssertTrue(hint.contains("/Users/test/.lmstudio/bin/lms"))
    }

    func testMLXVLMHintMentionsBetterDetectedPythonThatSupportsMLXVLM() {
        let hint = LocalRuntimeProviderGuidance.providerHint(
            providerID: "mlx_vlm",
            reasonCode: "import_error",
            importError: "missing_module:torch",
            selectedPythonPath: "/usr/bin/python3",
            preferredPythonPath: "/Users/test/Documents/AX/project/.venv/bin/python3",
            candidates: [
                LocalPythonRuntimeCandidateStatus(
                    path: "/Users/test/Documents/AX/project/.venv/bin/python3",
                    version: "3.11",
                    readyProviders: ["mlx_vlm"],
                    score: 18
                ),
            ]
        )

        XCTAssertTrue(hint.contains("MLX VLM"))
        XCTAssertTrue(hint.contains("更合适的本地 Python"))
        XCTAssertTrue(hint.contains("自动切换"))
        XCTAssertTrue(hint.contains("/Users/test/Documents/AX/project/.venv/bin/python3"))
    }

    func testPythonCandidatesSummaryIncludesSelectedAndAutoProviderPaths() {
        let summary = LocalRuntimeProviderGuidance.pythonCandidatesSummary(
            selectedPythonPath: "/usr/bin/python3",
            preferredProviderPaths: [
                "mlx": "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11",
                "mlx_vlm": "/Users/test/Documents/AX/project/.venv/bin/python3",
                "transformers": "/Users/test/Documents/AX/project/.venv/bin/python3",
            ],
            candidates: [
                LocalPythonRuntimeCandidateStatus(
                    path: "/Users/test/Documents/AX/project/.venv/bin/python3",
                    version: "3.11",
                    readyProviders: ["transformers", "mlx"],
                    score: 18
                ),
                LocalPythonRuntimeCandidateStatus(
                    path: "/usr/bin/python3",
                    version: "3.9",
                    readyProviders: ["mlx"],
                    score: 5
                ),
            ]
        )

        XCTAssertTrue(summary.contains("selected_python=/usr/bin/python3"))
        XCTAssertTrue(summary.contains("auto_mlx_vlm_python=/Users/test/Documents/AX/project/.venv/bin/python3"))
        XCTAssertTrue(summary.contains("auto_transformers_python=/Users/test/Documents/AX/project/.venv/bin/python3"))
        XCTAssertTrue(summary.contains("candidate=/Users/test/Documents/AX/project/.venv/bin/python3"))
        XCTAssertTrue(summary.contains("ready=transformers,mlx"))
    }
}
