from __future__ import annotations

import os
import sys
import tempfile
import types
from contextlib import contextmanager
from typing import Any


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if THIS_DIR not in sys.path:
    sys.path.insert(0, THIS_DIR)

from providers.transformers_provider import TransformersProvider


def run(name: str, fn) -> None:
    try:
        fn()
        sys.stdout.write(f"ok - {name}\n")
    except Exception:
        sys.stderr.write(f"not ok - {name}\n")
        raise


@contextmanager
def temporary_modules(overrides: dict[str, Any]):
    sentinel = object()
    previous: dict[str, Any] = {}
    for name, module in (overrides or {}).items():
        previous[name] = sys.modules.get(name, sentinel)
        sys.modules[name] = module
    try:
        yield
    finally:
        for name, module in previous.items():
            if module is sentinel:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = module


class FakeRuntimeResolution:
    def __init__(self, *available_modules: str) -> None:
        self._available = {str(name).lower() for name in available_modules}
        self.runtime_source = "user_python_custom"
        self.runtime_source_path = "/fake/python3"
        self.runtime_resolution_state = "ready"
        self.runtime_reason_code = "ready"
        self.fallback_used = False
        self.runtime_hint = ""
        self.missing_requirements: list[str] = []
        self.missing_optional_requirements: list[str] = []
        self.managed_service_state: dict[str, Any] = {}
        self.import_error = ""

    def supports_modules(self, *names: str) -> bool:
        return all(str(name).lower() in self._available for name in names)


@contextmanager
def temporary_text_runtime_modules():
    torch_module = types.ModuleType("torch")
    torch_module.backends = types.SimpleNamespace(
        mps=types.SimpleNamespace(is_available=lambda: False),
    )
    torch_module.cuda = types.SimpleNamespace(is_available=lambda: False)

    class FakeNoGrad:
        def __enter__(self) -> None:
            return None

        def __exit__(self, exc_type, exc, tb) -> bool:
            _ = exc_type, exc, tb
            return False

    torch_module.no_grad = lambda: FakeNoGrad()

    class FakeTokenizer:
        pad_token_id = 0
        eos_token_id = 99

        @staticmethod
        def from_pretrained(*args, **kwargs) -> "FakeTokenizer":
            _ = args, kwargs
            return FakeTokenizer()

        def apply_chat_template(
            self,
            messages: list[dict[str, Any]],
            tokenize: bool = False,
            add_generation_prompt: bool = True,
        ) -> str:
            _ = tokenize, add_generation_prompt
            rows: list[str] = []
            for message in messages:
                if not isinstance(message, dict):
                    continue
                role = str(message.get("role") or "user").lower()
                content = str(message.get("content") or "").strip()
                if not content:
                    continue
                rows.append(f"{role}:{content}")
            rows.append("assistant:")
            return "\n".join(rows)

        def __call__(self, prompt: str, return_tensors: str = "pt", truncation: bool = True, max_length: int = 0) -> dict[str, Any]:
            _ = return_tensors, truncation, max_length
            token_count = max(3, len(str(prompt or "").split()))
            input_ids = [list(range(100, 100 + token_count))]
            return {
                "input_ids": input_ids,
                "attention_mask": [[1] * token_count],
            }

        def batch_decode(self, generated: Any, skip_special_tokens: bool = True) -> list[str]:
            _ = skip_special_tokens
            row = generated[0] if isinstance(generated, list) and generated else generated
            if row == [901, 902]:
                return ["native text runtime ok"]
            return [str(row)]

        def decode(self, generated: Any, skip_special_tokens: bool = True) -> str:
            return self.batch_decode(generated, skip_special_tokens=skip_special_tokens)[0]

    class FakeTextModel:
        def __init__(self) -> None:
            self.config = types.SimpleNamespace(
                is_encoder_decoder=False,
                max_position_embeddings=128,
            )
            self.device = "cpu"

        def eval(self) -> "FakeTextModel":
            return self

        def to(self, device: str) -> "FakeTextModel":
            self.device = device
            return self

        def generate(self, **kwargs):
            input_ids = kwargs.get("input_ids") or [[100, 101, 102]]
            prompt = list(input_ids[0]) if isinstance(input_ids, list) and input_ids else [100, 101, 102]
            return [prompt + [901, 902]]

    transformers_module = types.ModuleType("transformers")
    transformers_module.AutoTokenizer = FakeTokenizer
    transformers_module.AutoModelForCausalLM = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeTextModel())
    transformers_module.AutoModelForSeq2SeqLM = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeTextModel())

    with temporary_modules(
        {
            "torch": torch_module,
            "transformers": transformers_module,
        }
    ):
        yield


def _provider_with_native_runtime() -> TransformersProvider:
    provider = TransformersProvider()
    provider._runtime_resolution = lambda **kwargs: FakeRuntimeResolution("transformers", "torch")  # type: ignore[method-assign]
    return provider


def _text_request(base_dir: str) -> dict[str, Any]:
    return {
        "_base_dir": base_dir,
        "task_kind": "text_generate",
        "model_id": "tiny-native-text",
        "model_path": "/tmp/tiny-native-text",
        "instance_key": "transformers::tiny-native-text::default",
        "task_kinds": ["text_generate"],
        "messages": [
            {"role": "system", "content": "You are a governed project supervisor."},
            {"role": "user", "content": "Continue with the next safe step."},
        ],
        "max_new_tokens": 24,
        "temperature": 0.0,
    }


def _test_healthcheck_reports_native_text_generation_ready() -> None:
    provider = _provider_with_native_runtime()
    with tempfile.TemporaryDirectory(prefix="xhub_tf_text_health_") as base_dir:
        health = provider.healthcheck(
            base_dir=base_dir,
            catalog_models=[
                {
                    "id": "tiny-native-text",
                    "backend": "transformers",
                    "modelPath": "/tmp/tiny-native-text",
                    "taskKinds": ["text_generate"],
                }
            ],
        )

    assert health.ok is True
    assert "text_generate" in (health.available_task_kinds or [])
    assert "text_generate" in (health.real_task_kinds or [])
    assert "text_generate" in (health.warmup_task_kinds or [])


def _test_native_text_runtime_warmup_run_and_unload() -> None:
    provider = _provider_with_native_runtime()
    with tempfile.TemporaryDirectory(prefix="xhub_tf_text_runtime_") as base_dir:
        request = _text_request(base_dir)
        with temporary_text_runtime_modules():
            warmup = provider.warmup_model(request)
            assert warmup["ok"] is True
            assert "text_generate" in (warmup.get("taskKinds") or [])

            loaded = provider.loaded_instances()
            assert len(loaded) == 1
            assert loaded[0]["taskKinds"] == ["text_generate"]

            result = provider.run_task(request)
            assert result["ok"] is True
            assert result["text"] == "native text runtime ok"
            assert result["finishReason"] == "stop"
            usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}
            assert int(usage.get("promptTokens") or 0) > 0
            assert int(usage.get("completionTokens") or 0) == 2
            assert int(usage.get("totalTokens") or 0) == int(usage.get("promptTokens") or 0) + 2

            unload = provider.unload_model(request)
            assert unload["ok"] is True
            assert unload["taskKinds"] == ["text_generate"]
            assert provider.loaded_instances() == []


if __name__ == "__main__":
    run(
        "transformers provider healthcheck exposes native text generation when transformers+torch are ready",
        _test_healthcheck_reports_native_text_generation_ready,
    )
    run(
        "transformers provider native text runtime can warm up, generate text, and unload cleanly",
        _test_native_text_runtime_warmup_run_and_unload,
    )
