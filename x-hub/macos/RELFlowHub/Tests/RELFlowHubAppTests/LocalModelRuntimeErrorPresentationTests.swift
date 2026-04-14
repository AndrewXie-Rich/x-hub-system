import XCTest
@testable import RELFlowHub

final class LocalModelRuntimeErrorPresentationTests: XCTestCase {
    func testHumanizedMissingTorchError() {
        XCTAssertEqual(
            LocalModelRuntimeErrorPresentation.humanized("missing_module:torch"),
            "当前 Python 运行时缺少 torch。"
        )
    }

    func testHumanizedUnsupportedTransformersModelTypeError() {
        XCTAssertEqual(
            LocalModelRuntimeErrorPresentation.humanized("load_failed:ValueError:Model_type_glm4v_not_supported"),
            "当前 Python Transformers 运行时暂不支持 model_type=glm4v。"
        )
    }

    func testHumanizedUnsupportedModelTypeProbeError() {
        XCTAssertEqual(
            LocalModelRuntimeErrorPresentation.humanized("unsupported_model_type:qwen3_vl_moe"),
            "当前 Python Transformers 运行时暂不支持 model_type=qwen3_vl_moe。"
        )
    }

    func testHumanizedTextToSpeechUnavailableErrors() {
        XCTAssertEqual(
            LocalModelRuntimeErrorPresentation.humanized("text_to_speech_runtime_unavailable"),
            "当前本地运行时还未提供文本转语音能力。"
        )
        XCTAssertEqual(
            LocalModelRuntimeErrorPresentation.humanized("text_to_speech_unavailable"),
            "虽然已经登记了 Voice 模型，但当前本地运行时还不能执行文本转语音。"
        )
    }

    func testHumanizedProcessorBootstrapTypeError() {
        XCTAssertEqual(
            LocalModelRuntimeErrorPresentation.humanized(
                "processor_init_failed:TypeError",
                detail: "argument of type 'NoneType' is not iterable"
            ),
            "当前 Python Transformers 运行时过旧，无法初始化这个模型的图像/视频处理器。"
        )
        XCTAssertEqual(
            LocalModelRuntimeErrorPresentation.detailHint(
                for: "processor_init_failed:TypeError",
                detail: "argument of type 'NoneType' is not iterable"
            ),
            "安装中的 Transformers 版本里 AutoProcessor 初始化失败。通常需要更新的 Transformers + torch 运行时。"
        )
    }

    func testDetailHintForUnsupportedModelTypeGetsLocalized() {
        XCTAssertEqual(
            LocalModelRuntimeErrorPresentation.detailHint(
                for: "unsupported_model_type:qwen3_vl_moe",
                detail: "Detected in probe. Current transformers=4.55.0."
            ),
            "检测位置：probe。 当前 transformers=4.55.0。"
        )
    }

    func testDetailHintFallsBackToOriginalDetailWhenNoLocalizationApplies() {
        XCTAssertEqual(
            LocalModelRuntimeErrorPresentation.detailHint(
                for: "unsupported_model_type:qwen3_vl_moe",
                detail: "raw detail"
            ),
            "raw detail"
        )
    }
}
