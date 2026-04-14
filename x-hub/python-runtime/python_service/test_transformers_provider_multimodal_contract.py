from __future__ import annotations

import json
import os
import sys
import tempfile
import types
import zlib
from contextlib import contextmanager
from typing import Any


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if THIS_DIR not in sys.path:
    sys.path.insert(0, THIS_DIR)

from providers.transformers_provider import TransformersProvider
import providers.transformers_provider as transformers_provider_module
from relflowhub_local_runtime import _status_payload, run_local_bench


def run(name: str, fn) -> None:
    try:
        fn()
        sys.stdout.write(f"ok - {name}\n")
    except Exception:
        sys.stderr.write(f"not ok - {name}\n")
        raise


def write_png(path: str, *, width: int = 16, height: int = 12) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    safe_width = max(1, int(width or 1))
    safe_height = max(1, int(height or 1))

    def _chunk(chunk_type: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(chunk_type)
        crc = zlib.crc32(data, crc) & 0xFFFFFFFF
        return (
            len(data).to_bytes(4, "big", signed=False)
            + chunk_type
            + data
            + crc.to_bytes(4, "big", signed=False)
        )

    row = b"\x00" + (b"\xe8\xf1\xff" * safe_width)
    raw = row * safe_height
    payload = bytearray(b"\x89PNG\r\n\x1a\n")
    payload.extend(
        _chunk(
            b"IHDR",
            safe_width.to_bytes(4, "big", signed=False)
            + safe_height.to_bytes(4, "big", signed=False)
            + b"\x08\x02\x00\x00\x00",
        )
    )
    payload.extend(_chunk(b"IDAT", zlib.compress(raw, level=9)))
    payload.extend(_chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(bytes(payload))


def write_json(path: str, obj: Any) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(obj, handle)


def write_bench_fixture_pack(path: str) -> None:
    write_json(
        path,
        {
            "schemaVersion": "xhub.local_bench_fixture_pack.v1",
            "fixtures": [
                {
                    "id": "vision_single_image",
                    "taskKind": "vision_understand",
                    "title": "Single Image Vision",
                    "description": "focused multimodal contract fixture",
                    "input": {
                        "image": {
                            "generator": "png_header",
                            "width": 48,
                            "height": 32,
                        },
                        "prompt": "Describe the image layout.",
                    },
                }
            ],
        },
    )


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


@contextmanager
def temporary_transformers_runtime_modules():
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

    class FakeVisionModel:
        def __init__(self) -> None:
            self.config = types.SimpleNamespace(hidden_size=16)
            self.device = "cpu"

        def eval(self) -> "FakeVisionModel":
            return self

        def to(self, device: str) -> "FakeVisionModel":
            self.device = device
            return self

        def generate(self, **kwargs):
            prompt = str(kwargs.get("prompt") or "").strip()
            raw_sizes = kwargs.get("image_size")
            size_rows: list[tuple[int, int]] = []
            if isinstance(raw_sizes, list):
                for item in raw_sizes:
                    if isinstance(item, (list, tuple)) and len(item) >= 2:
                        size_rows.append((int(item[0] or 0), int(item[1] or 0)))
            elif isinstance(raw_sizes, (list, tuple)) and len(raw_sizes) >= 2:
                size_rows.append((int(raw_sizes[0] or 0), int(raw_sizes[1] or 0)))
            prefix = "ocr" if "extract" in prompt.lower() else "vision"
            sizes = "|".join(f"{width}x{height}" for width, height in size_rows)
            return [
                {
                    "generated_text": f"{prefix}:{sizes} {prompt}".strip(),
                }
            ]

    class FakeAutoProcessor:
        tokenizer = None

        def __init__(self) -> None:
            self.tokenizer = self

        @staticmethod
        def from_pretrained(*args, **kwargs) -> "FakeAutoProcessor":
            _ = args, kwargs
            return FakeAutoProcessor()

        def apply_chat_template(self, messages: list[dict[str, Any]], tokenize: bool = False, add_generation_prompt: bool = True) -> str:
            _ = tokenize, add_generation_prompt
            texts: list[str] = []
            for message in messages:
                if not isinstance(message, dict):
                    continue
                for item in message.get("content") if isinstance(message.get("content"), list) else []:
                    if not isinstance(item, dict) or item.get("type") != "text":
                        continue
                    text = str(item.get("text") or "").strip()
                    if text:
                        texts.append(text)
            return " ".join(texts)

        def __call__(self, images=None, text=None, return_tensors=None, **kwargs) -> dict[str, Any]:
            _ = return_tensors, kwargs
            image_rows = images if isinstance(images, list) else ([images] if images is not None else [])
            size_rows = [
                (
                    int(getattr(image, "size", (0, 0))[0] or 0),
                    int(getattr(image, "size", (0, 0))[1] or 0),
                )
                for image in image_rows
            ]
            return {
                "prompt": str(text or ""),
                "image_size": size_rows if len(size_rows) > 1 else (size_rows[0] if size_rows else (0, 0)),
                "input_ids": [[101, 102, 103]],
            }

        def batch_decode(self, generated, skip_special_tokens: bool = True):
            _ = skip_special_tokens
            item = generated[0] if isinstance(generated, list) and generated else generated
            if isinstance(item, dict):
                return [str(item.get("generated_text") or "")]
            return [str(item or "")]

        def decode(self, generated, skip_special_tokens: bool = True):
            return self.batch_decode(generated, skip_special_tokens=skip_special_tokens)[0]

    class FakeImageHandle:
        def __init__(self, path: str) -> None:
            self.path = path
            self.size = self._read_size(path)

        def __enter__(self) -> "FakeImageHandle":
            return self

        def __exit__(self, exc_type, exc, tb) -> bool:
            _ = exc_type, exc, tb
            return False

        def convert(self, mode: str) -> "FakeImageHandle":
            _ = mode
            return self

        def close(self) -> None:
            return None

        def _read_size(self, path: str) -> tuple[int, int]:
            with open(path, "rb") as handle:
                data = handle.read(32)
            if len(data) >= 24 and data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
                return (
                    int.from_bytes(data[16:20], "big", signed=False),
                    int.from_bytes(data[20:24], "big", signed=False),
                )
            return (0, 0)

    transformers_module = types.ModuleType("transformers")
    transformers_module.AutoProcessor = FakeAutoProcessor
    transformers_module.AutoModelForImageTextToText = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeVisionModel())
    transformers_module.AutoModelForVision2Seq = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeVisionModel())
    transformers_module.AutoModelForCausalLM = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeVisionModel())
    transformers_module.AutoModelForSeq2SeqLM = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeVisionModel())

    pil_module = types.ModuleType("PIL")
    pil_image_module = types.ModuleType("PIL.Image")
    pil_image_module.open = lambda path: FakeImageHandle(path)
    pil_module.Image = pil_image_module

    with temporary_modules(
        {
            "torch": torch_module,
            "transformers": transformers_module,
            "PIL": pil_module,
            "PIL.Image": pil_image_module,
        }
    ):
        yield


def _patch_provider_for_real_runtime(provider: TransformersProvider, *, model_id: str, task_kinds: list[str]) -> None:
    provider._resolve_model_info = lambda request: {  # type: ignore[method-assign]
        "model_id": model_id,
        "model_path": f"/models/{model_id}",
        "task_kinds": list(task_kinds),
    }
    provider._runtime_resolution = lambda **kwargs: object()  # type: ignore[method-assign]
    provider._image_runtime_ready = lambda resolution: True  # type: ignore[method-assign]
    provider._helper_bridge_ready = lambda resolution: False  # type: ignore[method-assign]
    provider._helper_bridge_binary_path = lambda resolution: ""  # type: ignore[method-assign]


def _patch_provider_for_helper_bridge(provider: TransformersProvider, *, model_id: str, task_kinds: list[str]) -> None:
    provider._resolve_model_info = lambda request: {  # type: ignore[method-assign]
        "model_id": model_id,
        "model_path": f"/models/{model_id}",
        "task_kinds": list(task_kinds),
    }
    provider._runtime_resolution = lambda **kwargs: object()  # type: ignore[method-assign]
    provider._image_runtime_ready = lambda resolution: False  # type: ignore[method-assign]
    provider._helper_bridge_ready = lambda resolution: True  # type: ignore[method-assign]
    provider._helper_bridge_binary_path = lambda resolution: "/fake/helper"  # type: ignore[method-assign]
    provider._helper_bridge_resolve_instance_row = lambda **kwargs: {"instanceKey": f"{model_id}-instance"}  # type: ignore[method-assign]


def _test_transformers_provider_real_runtime_supports_multi_image_inputs() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_tf_multi_real_") as base_dir:
        image_a = os.path.join(base_dir, "FrameA.PNG")
        image_b = os.path.join(base_dir, "FrameB.PNG")
        write_png(image_a, width=24, height=18)
        write_png(image_b, width=32, height=16)
        expected_total_bytes = os.path.getsize(image_a) + os.path.getsize(image_b)

        provider = TransformersProvider()
        _patch_provider_for_real_runtime(
            provider,
            model_id="hf-vision-multi",
            task_kinds=["vision_understand"],
        )

        with temporary_transformers_runtime_modules():
            result = provider._run_image_task(
                {
                    "task_kind": "vision_understand",
                    "model_id": "hf-vision-multi",
                    "image_paths": [image_a, image_b],
                    "multimodal_messages": [
                        {
                            "role": "system",
                            "content": [{"type": "text", "text": "You are a careful vision assistant."}],
                        },
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "Describe both frames."},
                                {"type": "image", "imagePath": image_a},
                                {"type": "image", "imagePath": image_b},
                            ],
                        },
                    ],
                    "prompt": "Describe both frames.",
                    "max_new_tokens": 96,
                },
                task_kind="vision_understand",
            )

    assert result["ok"] is True
    assert result["taskKind"] == "vision_understand"
    assert result["modelId"] == "hf-vision-multi"
    assert result["usage"]["inputImageCount"] == 2
    assert result["usage"]["inputImageWidth"] == 24
    assert result["usage"]["inputImageHeight"] == 18
    assert result["usage"]["inputImagePixels"] == (24 * 18) + (32 * 16)
    assert result["usage"]["inputImageBytes"] == expected_total_bytes
    assert "24x18" in result["text"]
    assert "32x16" in result["text"]
    assert "Describe both frames." in result["text"]


def _test_transformers_provider_helper_bridge_preserves_multi_image_message_order() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_tf_multi_helper_") as base_dir:
        image_a = os.path.join(base_dir, "ReceiptA.PNG")
        image_b = os.path.join(base_dir, "ReceiptB.PNG")
        write_png(image_a, width=18, height=12)
        write_png(image_b, width=20, height=10)

        provider = TransformersProvider()
        _patch_provider_for_helper_bridge(
            provider,
            model_id="hf-vision-helper",
            task_kinds=["vision_understand"],
        )

        captured: dict[str, Any] = {}
        original = transformers_provider_module.helper_bridge_chat_completion

        def fake_helper_bridge_chat_completion(
            helper_binary: str,
            *,
            identifier: str,
            messages: list[dict[str, Any]],
            max_tokens: int = 0,
            temperature: float = 0.0,
            timeout_sec: float = 0.0,
        ) -> dict[str, Any]:
            captured["helper_binary"] = helper_binary
            captured["identifier"] = identifier
            captured["messages"] = [dict(message) for message in messages]
            captured["max_tokens"] = max_tokens
            captured["temperature"] = temperature
            captured["timeout_sec"] = timeout_sec
            return {
                "ok": True,
                "text": "helper multi ok",
                "usage": {
                    "prompt_tokens": 7,
                    "completion_tokens": 3,
                    "total_tokens": 10,
                },
            }

        transformers_provider_module.helper_bridge_chat_completion = fake_helper_bridge_chat_completion
        try:
            result = provider._run_image_task(
                {
                    "task_kind": "vision_understand",
                    "model_id": "hf-vision-helper",
                    "image_paths": [image_a, image_b],
                    "multimodal_messages": [
                        {
                            "role": "system",
                            "content": [{"type": "text", "text": "You are a careful vision assistant."}],
                        },
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "Compare the first receipt."},
                                {"type": "image", "imagePath": image_a},
                                {"type": "text", "text": "Then compare the second receipt."},
                                {"type": "image", "imagePath": image_b},
                            ],
                        },
                    ],
                    "max_new_tokens": 80,
                },
                task_kind="vision_understand",
            )
        finally:
            transformers_provider_module.helper_bridge_chat_completion = original

    assert result["ok"] is True
    assert result["text"] == "helper multi ok"
    assert result["usage"]["inputImageCount"] == 2
    assert captured["helper_binary"] == "/fake/helper"
    assert captured["identifier"] == "hf-vision-helper-instance"
    assert captured["max_tokens"] == 80
    assert len(captured["messages"]) == 2
    assert captured["messages"][0]["role"] == "system"
    assert captured["messages"][1]["role"] == "user"
    user_content = captured["messages"][1]["content"]
    assert [row["type"] for row in user_content] == ["text", "image_url", "text", "image_url"]
    assert user_content[0]["text"] == "Compare the first receipt."
    assert user_content[2]["text"] == "Then compare the second receipt."
    assert str(user_content[1]["image_url"]["url"]).startswith("data:image/png;base64,")
    assert str(user_content[3]["image_url"]["url"]).startswith("data:image/png;base64,")


def _test_transformers_provider_real_runtime_ocr_multi_image_emits_page_aware_spans() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_tf_multi_ocr_") as base_dir:
        image_a = os.path.join(base_dir, "ReceiptA.PNG")
        image_b = os.path.join(base_dir, "ReceiptB.PNG")
        write_png(image_a, width=18, height=12)
        write_png(image_b, width=20, height=10)

        provider = TransformersProvider()
        _patch_provider_for_real_runtime(
            provider,
            model_id="hf-ocr-multi",
            task_kinds=["ocr"],
        )

        with temporary_transformers_runtime_modules():
            result = provider._run_image_task(
                {
                    "task_kind": "ocr",
                    "model_id": "hf-ocr-multi",
                    "image_paths": [image_a, image_b],
                    "multimodal_messages": [
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "Extract every page."},
                                {"type": "image", "imagePath": image_a},
                                {"type": "image", "imagePath": image_b},
                            ],
                        },
                    ],
                    "max_new_tokens": 96,
                },
                task_kind="ocr",
            )

    assert result["ok"] is True
    assert result["taskKind"] == "ocr"
    assert result["usage"]["inputImageCount"] == 2
    assert result["routeTrace"]["executionPath"] == "real_runtime"
    assert result["routeTrace"]["pageAwareSpans"] is True
    assert result["routeTrace"]["pageCount"] == 2
    assert result["routeTrace"]["pageExecutionPaths"] == ["real_runtime", "real_runtime"]
    assert "[page 1]" in result["text"]
    assert "[page 2]" in result["text"]
    assert "18x12" in result["text"]
    assert "20x10" in result["text"]
    assert len(result["spans"]) == 2
    assert result["spans"][0]["pageIndex"] == 0
    assert result["spans"][0]["pageCount"] == 2
    assert result["spans"][0]["fileName"] == "ReceiptA.PNG"
    assert result["spans"][0]["bbox"]["width"] == 18
    assert result["spans"][0]["bbox"]["height"] == 12
    assert result["spans"][1]["pageIndex"] == 1
    assert result["spans"][1]["pageCount"] == 2
    assert result["spans"][1]["fileName"] == "ReceiptB.PNG"
    assert result["spans"][1]["bbox"]["width"] == 20
    assert result["spans"][1]["bbox"]["height"] == 10


def _test_local_runtime_bench_persists_route_trace_and_monitor_snapshot_exposes_recent_bench_results() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_tf_bench_route_trace_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-vision",
                        "name": "HF Vision",
                        "backend": "transformers",
                        "modelPath": "/models/hf-vision",
                        "taskKinds": ["vision_understand"],
                    }
                ]
            },
        )
        pack_path = os.path.join(base_dir, "bench_fixture_pack.json")
        write_bench_fixture_pack(pack_path)

        with temporary_transformers_runtime_modules():
            result = run_local_bench(
                {
                    "provider": "transformers",
                    "model_id": "hf-vision",
                    "task_kind": "vision_understand",
                    "fixture_profile": "vision_single_image",
                    "fixture_pack_path": pack_path,
                    "allow_bench_fallback": False,
                },
                base_dir=base_dir,
            )
            status = _status_payload(base_dir)

        assert result["ok"] is True
        assert result["taskKind"] == "vision_understand"
        assert result["routeTrace"]["selectedTaskKind"] == "vision_understand"
        assert result["routeTrace"]["imageCount"] == 1
        assert result["routeTrace"]["executionPath"] == "real_runtime"

        with open(os.path.join(base_dir, "models_bench.json"), "r", encoding="utf-8") as handle:
            bench_snapshot = json.load(handle)
        assert bench_snapshot["schemaVersion"] == "xhub.models_bench.v2"
        assert len(bench_snapshot["results"]) == 1
        bench_row = bench_snapshot["results"][0]
        assert bench_row["routeTrace"]["selectedTaskKind"] == "vision_understand"
        assert bench_row["routeTrace"]["imageCount"] == 1
        assert bench_row["routeTraceSummary"]["selectedTaskKind"] == "vision_understand"
        assert bench_row["routeTraceSummary"]["imageCount"] == 1
        assert bench_row["routeTraceSummary"]["executionPath"] == "real_runtime"

        assert len(status["recentBenchResults"]) == 1
        assert status["recentBenchResults"][0]["routeTraceSummary"]["selectedTaskKind"] == "vision_understand"
        assert status["recentBenchResults"][0]["routeTraceSummary"]["executionPath"] == "real_runtime"
        assert len(status["monitorSnapshot"]["recentBenchResults"]) == 1
        assert status["monitorSnapshot"]["recentBenchResults"][0]["routeTraceSummary"]["imageCount"] == 1


run(
    "transformers provider real image runtime supports multi-image inputs without lowercasing paths",
    lambda: _test_transformers_provider_real_runtime_supports_multi_image_inputs(),
)
run(
    "transformers provider helper bridge preserves multi-image message order and encodes every image",
    lambda: _test_transformers_provider_helper_bridge_preserves_multi_image_message_order(),
)
run(
    "transformers provider real runtime OCR multi-image emits page-aware spans",
    lambda: _test_transformers_provider_real_runtime_ocr_multi_image_emits_page_aware_spans(),
)
run(
    "local runtime bench persists route trace and monitor snapshot exposes recent bench results",
    lambda: _test_local_runtime_bench_persists_route_trace_and_monitor_snapshot_exposes_recent_bench_results(),
)
