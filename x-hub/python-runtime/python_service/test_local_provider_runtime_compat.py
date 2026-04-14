from __future__ import annotations

import json
import io
import os
import subprocess
import sys
import tempfile
import threading
import time
import types
import wave
import zlib
from contextlib import contextmanager
from typing import Any


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if THIS_DIR not in sys.path:
    sys.path.insert(0, THIS_DIR)

from providers.mlx_provider import MLXProvider, run_legacy_runtime
from providers.tts_kokoro_adapter import discover_available_speaker_ids
from providers.transformers_provider import TransformersProvider
import providers.llama_cpp_provider as llama_cpp_provider_module
import helper_binary_bridge as helper_binary_bridge_module
import xhub_local_service_bridge as xhub_local_service_bridge_module
from helper_binary_bridge import (
    list_helper_bridge_downloaded_models,
    list_helper_bridge_loaded_models,
    probe_helper_binary_bridge,
)
from local_provider_scheduler import acquire_provider_slot, read_provider_scheduler_telemetry, release_provider_slot
from provider_pack_registry import provider_pack_inventory
from provider_runtime_resolver import ProviderRuntimeResolution, resolve_provider_runtime
from relflowhub_local_runtime import _status_payload, _runtime_supports_command_proxy, build_registry, manage_local_model, provider_status_snapshot, run_local_bench, run_local_task
from relflowhub_mlx_runtime import MLXRuntime, _load_routing_settings, _resolve_routing_preferred_model_id, _runtime_status_path, _sync_state_from_provider_statuses, _write_runtime_status
from xhub_local_service_bridge import probe_xhub_local_service


def run(name: str, fn) -> None:
    try:
        fn()
        sys.stdout.write(f"ok - {name}\n")
    except Exception:
        sys.stderr.write(f"not ok - {name}\n")
        raise


def write_json(path: str, obj: Any) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(obj, handle)


def write_text(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(str(text))


def write_executable(path: str, text: str) -> None:
    write_text(path, text)
    os.chmod(path, 0o755)


def write_fake_say(path: str) -> None:
    write_executable(
        path,
        """#!/usr/bin/env python3
import os
import sys

args = sys.argv[1:]
if args == ["-v", "?"]:
    sys.stdout.write("Eddy (Chinese (China mainland))    zh_CN    # fake\\n")
    sys.stdout.write("Flo (English (US))    en_US    # fake\\n")
    raise SystemExit(0)

output_path = ""
for index, token in enumerate(args):
    if token == "-o" and index + 1 < len(args):
        output_path = args[index + 1]
        break

if not output_path:
    sys.stderr.write("missing_output_path\\n")
    raise SystemExit(2)

os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, "wb") as handle:
    handle.write(b"FORM")
    handle.write(b"FAKEAIF1")
raise SystemExit(0)
""",
    )


def write_wav(path: str, *, duration_sec: float = 0.25, sample_rate: int = 16000) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frame_count = max(1, int(round(duration_sec * sample_rate)))
    silence = (b"\x00\x00") * frame_count
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(silence)


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


@contextmanager
def temporary_env(key: str, value: str):
    previous = os.environ.get(key)
    os.environ[key] = value
    try:
        yield
    finally:
        if previous is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = previous


@contextmanager
def temporary_env_map(overrides: dict[str, str | None]):
    sentinel = object()
    previous: dict[str, Any] = {}
    for key, value in (overrides or {}).items():
        previous[key] = os.environ.get(key, sentinel)
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value
    try:
        yield
    finally:
        for key, value in previous.items():
            if value is sentinel:
                os.environ.pop(key, None)
            else:
                os.environ[key] = str(value)


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
def fake_helper_http_server(
    *,
    embedding_dims: int = 4,
    vision_text: str = "vision-helper-ok",
    ocr_text: str = "ocr-helper-ok",
):
    original = helper_binary_bridge_module._http_json_request

    def fake_http_json_request(
        url: str,
        *,
        method: str = "GET",
        payload: dict[str, Any] | None = None,
        timeout_sec: float = 0.0,
    ) -> dict[str, Any]:
        _ = method, timeout_sec
        normalized_url = str(url or "")
        body = payload if isinstance(payload, dict) else {}
        if normalized_url.endswith("/v1/models"):
            return {
                "ok": True,
                "status": 200,
                "body": {
                    "data": [
                        {
                            "id": "helper-model",
                            "object": "model",
                        }
                    ]
                },
                "text": "",
                "error": "",
            }
        if normalized_url.endswith("/v1/embeddings"):
            inputs = body.get("input")
            text_rows = inputs if isinstance(inputs, list) else [str(inputs or "")]
            data = []
            prompt_tokens = 0
            for index, text in enumerate(text_rows):
                value = str(text or "")
                prompt_tokens += max(1, len(value.split()))
                vector = [
                    round((index + 1) * 0.1 + (dim + 1) * 0.01 + len(value) * 0.001, 6)
                    for dim in range(max(1, embedding_dims))
                ]
                data.append({"index": index, "embedding": vector})
            return {
                "ok": True,
                "status": 200,
                "body": {
                    "object": "list",
                    "model": str(body.get("model") or ""),
                    "data": data,
                    "usage": {
                        "prompt_tokens": prompt_tokens,
                        "total_tokens": prompt_tokens,
                    },
                },
                "text": "",
                "error": "",
            }
        if normalized_url.endswith("/v1/chat/completions"):
            messages = body.get("messages") if isinstance(body.get("messages"), list) else []
            content_rows = messages[0].get("content") if messages and isinstance(messages[0], dict) else []
            prompt = " ".join(
                str(item.get("text") or "").strip()
                for item in content_rows
                if isinstance(item, dict) and item.get("type") == "text"
            ).strip()
            text = ocr_text if "extract" in prompt.lower() else vision_text
            return {
                "ok": True,
                "status": 200,
                "body": {
                    "id": "chatcmpl-helper",
                    "object": "chat.completion",
                    "model": str(body.get("model") or ""),
                    "choices": [
                        {
                            "index": 0,
                            "finish_reason": "stop",
                            "message": {
                                "role": "assistant",
                                "content": text,
                            },
                        }
                    ],
                    "usage": {
                        "prompt_tokens": max(1, len(prompt.split())),
                        "completion_tokens": max(1, len(text.split())),
                        "total_tokens": max(2, len(prompt.split()) + len(text.split())),
                    },
                },
                "text": "",
                "error": "",
            }
        return {
            "ok": False,
            "status": 404,
            "body": {"error": {"message": "not_found"}},
            "text": "not_found",
            "error": "not_found",
        }

    helper_binary_bridge_module._http_json_request = fake_http_json_request
    try:
        yield 1234
    finally:
        helper_binary_bridge_module._http_json_request = original


@contextmanager
def fake_xhub_local_service_health(response: dict[str, Any]):
    original = xhub_local_service_bridge_module._http_json_request

    def fake_http_json_request(
        url: str,
        *,
        method: str = "GET",
        payload: dict[str, Any] | None = None,
        timeout_sec: float = 0.0,
    ) -> dict[str, Any]:
        _ = method, payload, timeout_sec
        if str(url or "").endswith("/health"):
            out = dict(response or {})
            out.setdefault("ok", False)
            out.setdefault("status", 0)
            out.setdefault("body", {})
            out.setdefault("text", "")
            out.setdefault("error", "")
            return out
        return {
            "ok": False,
            "status": 404,
            "body": {"error": {"message": "not_found"}},
            "text": "not_found",
            "error": "not_found",
        }

    xhub_local_service_bridge_module._http_json_request = fake_http_json_request
    try:
        yield
    finally:
        xhub_local_service_bridge_module._http_json_request = original


@contextmanager
def fake_xhub_local_service_autostart(health_body: dict[str, Any] | None = None):
    original_http = xhub_local_service_bridge_module._http_json_request
    original_spawn = xhub_local_service_bridge_module._spawn_xhub_local_service_process
    original_process_running = xhub_local_service_bridge_module._service_process_running
    state: dict[str, Any] = {
        "spawn_calls": [],
        "health_calls": 0,
        "running_pids": set(),
    }

    def fake_http_json_request(
        url: str,
        *,
        method: str = "GET",
        payload: dict[str, Any] | None = None,
        timeout_sec: float = 0.0,
    ) -> dict[str, Any]:
        _ = method, payload, timeout_sec
        if str(url or "").endswith("/health"):
            state["health_calls"] += 1
            if state["running_pids"]:
                body = dict(
                    health_body
                    or {
                        "ok": True,
                        "status": "ready",
                        "version": "xhub-local-service-dev",
                        "capabilities": ["health", "chat_completions", "embeddings"],
                    }
                )
                return {
                    "ok": True,
                    "status": 200,
                    "body": body,
                    "text": "",
                    "error": "",
                }
            return {
                "ok": False,
                "status": 0,
                "body": {},
                "text": "",
                "error": "ConnectionRefusedError:[Errno 61] Connection refused",
            }
        return {
            "ok": False,
            "status": 404,
            "body": {"error": {"message": "not_found"}},
            "text": "not_found",
            "error": "not_found",
        }

    def fake_spawn_xhub_local_service_process(
        base_dir: str,
        *,
        bind_host: str,
        bind_port: int,
    ):
        pid = 43000 + len(state["spawn_calls"]) + 1
        state["spawn_calls"].append(
            {
                "base_dir": base_dir,
                "bind_host": bind_host,
                "bind_port": bind_port,
                "pid": pid,
            }
        )
        state["running_pids"].add(pid)
        return types.SimpleNamespace(pid=pid)

    def fake_process_running(pid: int) -> bool:
        return int(pid or 0) in state["running_pids"]

    xhub_local_service_bridge_module._http_json_request = fake_http_json_request
    xhub_local_service_bridge_module._spawn_xhub_local_service_process = fake_spawn_xhub_local_service_process
    xhub_local_service_bridge_module._service_process_running = fake_process_running
    try:
        yield state
    finally:
        xhub_local_service_bridge_module._http_json_request = original_http
        xhub_local_service_bridge_module._spawn_xhub_local_service_process = original_spawn
        xhub_local_service_bridge_module._service_process_running = original_process_running


class StubMLXRuntime:
    def __init__(
        self,
        *,
        ok: bool,
        import_error: str = "",
        loaded: dict[str, Any] | None = None,
        loaded_instances: list[dict[str, Any]] | None = None,
        memory_pair: tuple[int, int] = (0, 0),
    ) -> None:
        self._mlx_ok = ok
        self._import_error = import_error
        self._loaded = dict(loaded or {})
        self._loaded_instances = [dict(item) for item in (loaded_instances or []) if isinstance(item, dict)]
        self._memory_pair = tuple(memory_pair)

    def memory_bytes(self) -> tuple[int, int]:
        return self._memory_pair

    def loaded_instance_rows(self) -> list[dict[str, Any]]:
        return [dict(item) for item in self._loaded_instances]

    def loaded_model_ids(self) -> list[str]:
        if self._loaded_instances:
            return sorted(
                {
                    str(item.get("modelId") or item.get("model_id") or "").strip()
                    for item in self._loaded_instances
                    if str(item.get("modelId") or item.get("model_id") or "").strip()
                }
            )
        return sorted(str(model_id) for model_id in self._loaded.keys() if str(model_id or "").strip())

    def loaded_model_count(self) -> int:
        return len(self.loaded_model_ids())


@contextmanager
def temporary_transformers_runtime_modules(*, module_root: str | None = None):
    def _module_file(module_name: str) -> str:
        normalized_root = str(module_root or "").strip()
        if not normalized_root:
            return ""
        return os.path.join(normalized_root, module_name.replace(".", "/"), "__init__.py")

    torch_module = types.ModuleType("torch")
    torch_module.__file__ = _module_file("torch")
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

    class FakeModel:
        def __init__(self) -> None:
            self.config = types.SimpleNamespace(hidden_size=16)
            self.device = "cpu"

        def eval(self) -> "FakeModel":
            return self

        def to(self, device: str) -> "FakeModel":
            self.device = device
            return self

    class FakeVisionModel(FakeModel):
        def generate(self, **kwargs):
            prompt = str(kwargs.get("prompt") or "").strip()
            image_size = kwargs.get("image_size") or (0, 0)
            if isinstance(image_size, list) and image_size:
                image_size = image_size[0]
            width = int(image_size[0] or 0) if isinstance(image_size, (list, tuple)) and len(image_size) > 0 else 0
            height = int(image_size[1] or 0) if isinstance(image_size, (list, tuple)) and len(image_size) > 1 else 0
            prefix = "ocr" if "extract" in prompt.lower() else "vision"
            return [
                {
                    "generated_text": f"{prefix}:{width}x{height} {prompt}".strip(),
                }
            ]

    class FakeAutoTokenizer:
        @staticmethod
        def from_pretrained(*args, **kwargs) -> dict[str, Any]:
            return {
                "args": list(args),
                "kwargs": dict(kwargs),
            }

    class FakeAutoModel:
        @staticmethod
        def from_pretrained(*args, **kwargs) -> FakeModel:
            _ = args, kwargs
            return FakeModel()

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
            content = messages[0].get("content") if messages else []
            texts = [
                str(item.get("text") or "").strip()
                for item in content
                if isinstance(item, dict) and item.get("type") == "text"
            ]
            return " ".join(token for token in texts if token)

        def __call__(self, images=None, text=None, return_tensors=None, **kwargs) -> dict[str, Any]:
            _ = return_tensors, kwargs
            image = images[0] if isinstance(images, list) and images else images
            width = int(getattr(image, "size", (0, 0))[0] or 0) if image is not None else 0
            height = int(getattr(image, "size", (0, 0))[1] or 0) if image is not None else 0
            return {
                "prompt": str(text or ""),
                "image_size": (width, height),
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

    class FakePipeline:
        def __init__(self) -> None:
            self.device = "cpu"

        def __call__(self, *args, **kwargs):
            _ = args, kwargs
            return {"text": "fake asr transcript"}

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

        def _read_size(self, path: str) -> tuple[int, int]:
            try:
                with open(path, "rb") as handle:
                    data = handle.read(32)
            except Exception:
                return (0, 0)
            if len(data) >= 24 and data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
                return (
                    int.from_bytes(data[16:20], "big", signed=False),
                    int.from_bytes(data[20:24], "big", signed=False),
                )
            return (0, 0)

    transformers_module = types.ModuleType("transformers")
    transformers_module.__file__ = _module_file("transformers")
    transformers_module.AutoTokenizer = FakeAutoTokenizer
    transformers_module.AutoModel = FakeAutoModel
    transformers_module.AutoProcessor = FakeAutoProcessor
    transformers_module.AutoModelForImageTextToText = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeVisionModel())
    transformers_module.AutoModelForVision2Seq = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeVisionModel())
    transformers_module.AutoModelForCausalLM = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeVisionModel())
    transformers_module.AutoModelForSeq2SeqLM = types.SimpleNamespace(from_pretrained=lambda *args, **kwargs: FakeVisionModel())
    transformers_module.pipeline = lambda *args, **kwargs: FakePipeline()
    tokenizers_module = types.ModuleType("tokenizers")
    tokenizers_module.__file__ = _module_file("tokenizers")
    pil_module = types.ModuleType("PIL")
    pil_module.__file__ = _module_file("PIL")
    pil_image_module = types.ModuleType("PIL.Image")
    pil_image_module.__file__ = _module_file("PIL.Image")
    pil_image_module.open = lambda path: FakeImageHandle(path)
    pil_module.Image = pil_image_module

    with temporary_modules(
        {
            "torch": torch_module,
            "transformers": transformers_module,
            "tokenizers": tokenizers_module,
            "PIL": pil_module,
            "PIL.Image": pil_image_module,
        }
    ):
        yield


@contextmanager
def temporary_kokoro_runtime_module(*, module_root: str | None = None):
    def _module_file(module_name: str) -> str:
        normalized_root = str(module_root or "").strip()
        if not normalized_root:
            return ""
        return os.path.join(normalized_root, module_name.replace(".", "/"), "__init__.py")

    class FakeKPipeline:
        def __init__(self, *args, **kwargs) -> None:
            self.args = list(args)
            self.kwargs = dict(kwargs)
            self.device = "cpu"

        def __call__(self, text: str, voice: str = "", speed: float = 1.0, **kwargs):
            _ = kwargs
            sample_count = max(8, len(str(text or "")) * 6)
            samples = [0.15 if index % 2 == 0 else -0.15 for index in range(sample_count)]
            return [
                {
                    "audio": samples,
                    "sample_rate": 24000,
                    "speakerId": str(voice or "default"),
                    "speed": speed,
                }
            ]

    kokoro_module = types.ModuleType("kokoro")
    kokoro_module.__file__ = _module_file("kokoro")
    kokoro_module.KPipeline = FakeKPipeline

    with temporary_modules(
        {
            "kokoro": kokoro_module,
        }
    ):
        yield


def make_runtime_resolution(
    *,
    runtime_source: str = "hub_py_deps",
    runtime_source_path: str = "",
    runtime_resolution_state: str = "runtime_missing",
    runtime_reason_code: str = "missing_runtime",
    fallback_used: bool = False,
    import_error: str = "",
    runtime_hint: str = "",
    missing_requirements: list[str] | None = None,
    missing_optional_requirements: list[str] | None = None,
    ready_python_modules: list[str] | None = None,
) -> ProviderRuntimeResolution:
    return ProviderRuntimeResolution(
        provider_id="transformers",
        runtime_source=runtime_source,
        runtime_source_path=runtime_source_path,
        runtime_resolution_state=runtime_resolution_state,
        runtime_reason_code=runtime_reason_code,
        fallback_used=fallback_used,
        import_error=import_error,
        runtime_hint=runtime_hint,
        missing_requirements=list(missing_requirements or []),
        missing_optional_requirements=list(missing_optional_requirements or []),
        ready_python_modules=list(ready_python_modules or []),
        python_executable="/usr/bin/python3",
        module_origins={},
    )


@contextmanager
def patched_transformers_runtime_resolution(resolution: ProviderRuntimeResolution):
    original = TransformersProvider._runtime_resolution

    def fake_runtime_resolution(self, *, base_dir: str, request=None):
        _ = self, base_dir, request
        return resolution

    TransformersProvider._runtime_resolution = fake_runtime_resolution
    try:
        yield
    finally:
        TransformersProvider._runtime_resolution = original


class FakeMLXTokenizer:
    vocab_size = 4096

    def encode(self, text: str) -> list[int]:
        token_count = max(1, len(str(text or "").split()))
        return [1] * token_count

    def get_vocab(self) -> dict[str, int]:
        return {str(idx): idx for idx in range(32)}


class FakeMLXRandom:
    def seed(self, value: int) -> None:
        _ = value

    def randint(self, low: int, high: int, shape: Any):
        size = 0
        if isinstance(shape, tuple) and shape:
            size = int(shape[0] or 0)
        else:
            size = int(shape or 0)
        upper = max(int(high or 0), 1)
        values = [int((int(low or 0) + idx) % upper) for idx in range(max(0, size))]
        return types.SimpleNamespace(tolist=lambda: list(values))


class FakeMLXCore:
    def __init__(self) -> None:
        self.random = FakeMLXRandom()
        self._peak_memory = 512 * 1024 * 1024

    def get_active_memory(self) -> int:
        return 128 * 1024 * 1024

    def get_peak_memory(self) -> int:
        return self._peak_memory

    def reset_peak_memory(self) -> None:
        self._peak_memory = 512 * 1024 * 1024


def _build_fake_mlx_runtime() -> tuple[MLXRuntime, list[str], list[dict[str, Any]], list[dict[str, Any]]]:
    runtime = MLXRuntime()
    runtime._mlx_ok = True
    runtime._probe_attempted = True
    runtime._import_error = ""
    runtime._mx = FakeMLXCore()
    runtime._tokenizer_wrapper = None

    load_calls: list[str] = []
    generate_calls: list[dict[str, Any]] = []
    stream_calls: list[dict[str, Any]] = []

    def fake_load(model_path: str):
        load_calls.append(str(model_path))
        return object(), FakeMLXTokenizer()

    def fake_generate(model: Any, tokenizer: Any, prompt: Any, **kwargs: Any) -> str:
        _ = model, tokenizer
        generate_calls.append(
            {
                "prompt": str(prompt),
                "kwargs": dict(kwargs),
            }
        )
        return "synthetic response"

    def fake_stream_generate(model: Any, tokenizer: Any, prompt: Any, **kwargs: Any):
        _ = model, tokenizer
        prompt_tokens = len(prompt) if hasattr(prompt, "__len__") else 0
        generation_tokens = int(kwargs.get("max_tokens") or 0)
        stream_calls.append(
            {
                "prompt_tokens": prompt_tokens,
                "kwargs": dict(kwargs),
            }
        )
        yield types.SimpleNamespace(
            prompt_tokens=prompt_tokens,
            generation_tokens=generation_tokens,
            prompt_tps=120.0,
            generation_tps=48.0,
            peak_memory=0.5,
        )

    runtime._mlx_load = fake_load
    runtime._mlx_generate = fake_generate
    runtime._mlx_stream_generate = fake_stream_generate
    runtime._mlx_make_sampler = lambda temp=0.0, top_p=1.0: {"temp": temp, "top_p": top_p}
    runtime._ensure_runtime_imported = lambda: True  # type: ignore[method-assign]
    return runtime, load_calls, generate_calls, stream_calls


def _test_provider_status_snapshot() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_snapshot_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "mlx-qwen",
                        "name": "MLX Qwen",
                        "backend": "mlx",
                        "modelPath": "/models/mlx-qwen",
                    },
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    },
                ]
            },
        )
        runtime = StubMLXRuntime(
            ok=True,
            loaded={"mlx-qwen": object()},
            memory_pair=(1234, 4321),
        )
        snapshot = provider_status_snapshot(base_dir, runtime=runtime)

        assert snapshot["mlx"]["ok"] is True
        assert snapshot["mlx"]["availableTaskKinds"] == ["text_generate"]
        assert snapshot["mlx"]["loadedModels"] == ["mlx-qwen"]
        assert "mlx-qwen" in snapshot["mlx"]["registeredModels"]
        assert snapshot["mlx"]["packId"] == "mlx"
        assert snapshot["mlx"]["packEngine"] == "mlx-llm"
        assert snapshot["mlx"]["packInstalled"] is True
        assert snapshot["mlx"]["packState"] == "installed"
        assert snapshot["transformers"]["provider"] == "transformers"
        assert "hf-embed" in snapshot["transformers"]["registeredModels"]
        assert snapshot["transformers"]["packId"] == "transformers"
        assert snapshot["transformers"]["packEngine"] == "hf-transformers"
        assert snapshot["transformers"]["packInstalled"] is True
        assert snapshot["transformers"]["packState"] == "installed"


def _test_provider_pack_registry_overrides_version_and_disables_provider_execution() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_pack_registry_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    },
                ]
            },
        )
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "enabled": False,
                        "version": "operator-pinned-2026-03-16",
                        "reasonCode": "provider_pack_disabled",
                    },
                ],
            },
        )

        with temporary_transformers_runtime_modules():
            snapshot = provider_status_snapshot(base_dir)
            run_result = run_local_task(
                {
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "texts": ["offline note"],
                },
                base_dir=base_dir,
            )
            bench_result = run_local_bench(
                {
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                },
                base_dir=base_dir,
            )
            warmup_result = manage_local_model(
                {
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "action": "warmup_local_model",
                },
                base_dir=base_dir,
            )

        assert snapshot["transformers"]["ok"] is False
        assert snapshot["transformers"]["reasonCode"] == "provider_pack_disabled"
        assert snapshot["transformers"]["packEnabled"] is False
        assert snapshot["transformers"]["packVersion"] == "operator-pinned-2026-03-16"
        assert snapshot["transformers"]["packState"] == "disabled"
        assert snapshot["transformers"]["availableTaskKinds"] == []
        assert snapshot["transformers"]["unavailableTaskKinds"] == ["embedding"]

        assert run_result["ok"] is False
        assert run_result["error"] == "provider_pack_disabled"
        assert run_result["packEnabled"] is False
        assert run_result["packVersion"] == "operator-pinned-2026-03-16"

        assert bench_result["ok"] is False
        assert bench_result["reasonCode"] == "provider_pack_disabled"
        assert bench_result["packEnabled"] is False
        assert bench_result["packState"] == "disabled"

        assert warmup_result["ok"] is False
        assert warmup_result["error"] == "provider_pack_disabled"
        assert warmup_result["packEnabled"] is False


def _test_provider_pack_inventory_exposes_builtin_llama_cpp_manifest() -> None:
    packs = provider_pack_inventory(["llama.cpp"])
    llama_cpp = next(row for row in packs if row["providerId"] == "llama.cpp")

    assert llama_cpp["engine"] == "llama.cpp"
    assert llama_cpp["supportedFormats"] == ["gguf"]
    assert llama_cpp["supportedDomains"] == ["text", "embedding"]
    assert llama_cpp["packState"] == "installed"
    assert llama_cpp["reasonCode"] == "builtin_pack_registered"
    assert llama_cpp["runtimeRequirements"]["executionMode"] == "helper_binary_bridge"


def _test_provider_status_snapshot_exposes_llama_cpp_helper_runtime_truth_for_gguf_models() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_llama_cpp_runtime_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "qwen3-gguf",
                        "name": "Qwen3 GGUF",
                        "backend": "llama.cpp",
                        "runtimeProviderID": "llama.cpp",
                        "modelPath": "/models/qwen3-q4_k_m.gguf",
                        "taskKinds": ["text_generate"],
                    },
                ]
            },
        )
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "llama.cpp",
                        "runtimeRequirements": {
                            "executionMode": "helper_binary_bridge",
                            "helperBinary": os.path.join(base_dir, "missing-lms"),
                        },
                    },
                ],
            },
        )

        snapshot = provider_status_snapshot(base_dir)
        llama_cpp = snapshot["llama.cpp"]

        assert llama_cpp["ok"] is False
        assert llama_cpp["reasonCode"] == "helper_binary_missing"
        assert llama_cpp["packId"] == "llama.cpp"
        assert llama_cpp["packEngine"] == "llama.cpp"
        assert llama_cpp["packState"] == "installed"
        assert llama_cpp["runtimeSource"] == "helper_binary_bridge"
        assert llama_cpp["runtimeReasonCode"] == "helper_binary_missing"
        assert llama_cpp["unavailableTaskKinds"] == ["text_generate"]


def _test_run_local_task_mlx_delegate() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_delegate_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "mlx-qwen",
                        "name": "MLX Qwen",
                        "backend": "mlx",
                        "modelPath": "/models/mlx-qwen",
                    }
                ]
            },
        )
        result = run_local_task(
            {
                "task_kind": "text_generate",
                "model_id": "mlx-qwen",
            },
            base_dir=base_dir,
        )

        assert result["ok"] is False
        assert result["provider"] == "mlx"
        assert result["taskKind"] == "text_generate"
        assert result["error"] == "delegate_to_runtime_loop:mlx"


def _test_mlx_provider_import_error() -> None:
    runtime = StubMLXRuntime(
        ok=False,
        import_error="missing_module:mlx_lm",
        loaded={},
    )
    provider = MLXProvider(runtime=runtime, runtime_version="compat-test")
    health = provider.healthcheck(base_dir="/tmp", catalog_models=[])

    assert health.ok is False
    assert health.reason_code == "import_error"
    assert health.import_error == "missing_module:mlx_lm"
    assert health.to_dict()["importError"] == "missing_module:mlx_lm"


def _test_mlx_provider_without_runtime_uses_safe_probe_result() -> None:
    import relflowhub_mlx_runtime as mlx_runtime_entry

    original_probe = mlx_runtime_entry.probe_mlx_runtime_support
    original_cache = dict(mlx_runtime_entry._MLX_IMPORT_PROBE_CACHE)
    try:
        mlx_runtime_entry._MLX_IMPORT_PROBE_CACHE.update(
            {
                "attempted": False,
                "ok": False,
                "error": "",
            }
        )
        mlx_runtime_entry.probe_mlx_runtime_support = lambda force=False: (False, "mlx_probe_failed:exit_-6")
        provider = MLXProvider(runtime=None, runtime_version="compat-test")
        health = provider.healthcheck(base_dir="/tmp", catalog_models=[])
    finally:
        mlx_runtime_entry.probe_mlx_runtime_support = original_probe
        mlx_runtime_entry._MLX_IMPORT_PROBE_CACHE.update(original_cache)

    assert health.ok is False
    assert health.reason_code == "import_error"
    assert health.import_error == "mlx_probe_failed:exit_-6"


def _test_runtime_status_writer_merge() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_status_") as base_dir:
        _write_runtime_status(
            base_dir,
            mlx_ok=False,
            import_error="missing_module:mlx_lm",
            active_memory_bytes=0,
            peak_memory_bytes=0,
            loaded_model_count=0,
            loaded_model_ids=[],
            provider_statuses={
                "transformers": {
                    "provider": "transformers",
                    "ok": False,
                    "reasonCode": "import_error",
                    "runtimeVersion": "transformers-skeleton",
                    "availableTaskKinds": ["embedding"],
                    "loadedModels": [],
                    "deviceBackend": "mps_or_cpu",
                    "updatedAt": 1.0,
                    "importError": "missing_module:torch",
                    "loadedInstances": [
                        {
                            "instanceKey": "transformers:hf-embed:abc123",
                            "modelId": "hf-embed",
                            "taskKinds": ["embedding"],
                            "loadProfileHash": "abc123",
                            "effectiveContextLength": 24576,
                            "loadedAt": 1.0,
                            "lastUsedAt": 2.0,
                            "residency": "resident",
                            "residencyScope": "process_local",
                            "deviceBackend": "cpu",
                        }
                    ],
                    "idleEviction": {
                        "policy": "manual_or_process_exit",
                        "automaticIdleEvictionEnabled": False,
                        "idleTimeoutSec": 0,
                        "processScoped": True,
                        "lastEvictionReason": "manual_unload",
                        "lastEvictionAt": 3.0,
                        "lastEvictedInstanceKeys": ["transformers:hf-embed:old"],
                        "lastEvictedModelIds": ["hf-embed"],
                        "lastEvictedCount": 1,
                        "totalEvictedInstanceCount": 1,
                        "updatedAt": 3.0,
                        "ownerPid": 123,
                    },
                }
            },
        )

        with open(_runtime_status_path(base_dir), "r", encoding="utf-8") as handle:
            payload = json.load(handle)

        assert payload["mlxOk"] is False
        assert payload["providers"]["mlx"]["importError"] == "missing_module:mlx_lm"
        assert payload["providers"]["mlx"]["availableTaskKinds"] == []
        assert payload["providers"]["transformers"]["provider"] == "transformers"
        assert payload["providers"]["transformers"]["importError"] == "missing_module:torch"
        assert payload["localCommandIpcVersion"] == "xhub.local_runtime_command_ipc.v1"
        assert payload["loadedInstanceCount"] == 1
        assert payload["loadedInstances"][0]["instanceKey"] == "transformers:hf-embed:abc123"
        assert payload["idleEvictionByProvider"]["transformers"]["lastEvictionReason"] == "manual_unload"


def _test_runtime_status_mirror_paths_skip_container_and_public_bases() -> None:
    import relflowhub_local_runtime as local_runtime_entry

    home_base = os.path.join(os.path.expanduser("~"), "RELFlowHub")
    mirrors = local_runtime_entry._runtime_status_mirror_paths(home_base)

    assert os.path.join("/private/tmp", "XHub", "ai_runtime_status.json") in mirrors
    assert os.path.join("/private/tmp", "RELFlowHub", "ai_runtime_status.json") in mirrors
    assert os.path.join(
        os.path.expanduser("~"),
        "Library",
        "Containers",
        "com.rel.flowhub",
        "Data",
        "XHub",
        "ai_runtime_status.json",
    ) in mirrors

    container_base = os.path.join(
        os.path.expanduser("~"),
        "Library",
        "Containers",
        "com.rel.flowhub",
        "Data",
        "RELFlowHub",
    )
    assert local_runtime_entry._runtime_status_mirror_paths(container_base) == []
    assert local_runtime_entry._runtime_status_mirror_paths("/private/tmp/RELFlowHub") == []


def _test_publish_runtime_status_mirrors_home_runtime_snapshot_into_fallback_locations() -> None:
    import relflowhub_local_runtime as local_runtime_entry

    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_status_mirror_") as temp_root:
        base_dir = os.path.join(temp_root, "RELFlowHub")
        os.makedirs(base_dir, exist_ok=True)
        public_mirror = os.path.join(temp_root, "public", "XHub", "ai_runtime_status.json")
        container_mirror = os.path.join(temp_root, "container", "Data", "XHub", "ai_runtime_status.json")
        payload = {
            "schema_version": "xhub.local_runtime_status.v2",
            "pid": 1234,
            "updatedAt": 1700000000.0,
            "providers": {
                "transformers": {
                    "provider": "transformers",
                    "ok": True,
                    "reasonCode": "ready",
                    "updatedAt": 1700000000.0,
                    "runtimeSourcePath": "/Users/test/.lmstudio/vendor/python",
                }
            },
        }

        original_status_payload = local_runtime_entry._status_payload
        original_mirror_paths = local_runtime_entry._runtime_status_mirror_paths
        try:
            local_runtime_entry._status_payload = lambda _base: dict(payload)
            local_runtime_entry._runtime_status_mirror_paths = lambda _base: [
                public_mirror,
                container_mirror,
            ]
            local_runtime_entry._publish_runtime_status(base_dir)
        finally:
            local_runtime_entry._status_payload = original_status_payload
            local_runtime_entry._runtime_status_mirror_paths = original_mirror_paths

        for expected_path in [
            local_runtime_entry._runtime_status_path(base_dir),
            public_mirror,
            container_mirror,
        ]:
            with open(expected_path, "r", encoding="utf-8") as handle:
                mirrored = json.load(handle)
            assert mirrored == payload


def _test_mlx_runtime_probe_failure_stays_fail_closed_without_importing_runtime() -> None:
    import relflowhub_mlx_runtime as mlx_runtime_entry

    original_run = mlx_runtime_entry.subprocess.run
    original_executable = mlx_runtime_entry.sys.executable
    original_cache = dict(mlx_runtime_entry._MLX_IMPORT_PROBE_CACHE)
    try:
        mlx_runtime_entry._MLX_IMPORT_PROBE_CACHE.update(
            {
                "attempted": False,
                "ok": False,
                "error": "",
            }
        )
        def fake_run(*args, **kwargs):
            _ = args, kwargs
            return subprocess.CompletedProcess(
                args=["python3", "-c", "probe"],
                returncode=-6,
                stdout="",
                stderr="libmlx probe crashed",
            )

        mlx_runtime_entry.subprocess.run = fake_run
        mlx_runtime_entry.sys.executable = "/opt/homebrew/bin/python3"
        runtime = MLXRuntime()
        ok, error = runtime._probe_runtime_support()
    finally:
        mlx_runtime_entry.subprocess.run = original_run
        mlx_runtime_entry.sys.executable = original_executable
        mlx_runtime_entry._MLX_IMPORT_PROBE_CACHE.update(original_cache)

    assert ok is False
    assert "mlx_probe_failed:exit_-6" in error
    assert "libmlx probe crashed" in error
    assert runtime.memory_bytes() == (0, 0)
    load_ok, load_message, load_memory = runtime.load("mlx-local", "/tmp/not-a-real-model")
    assert load_ok is False
    assert "mlx_lm_unavailable:mlx_probe_failed:exit_-6" in load_message
    assert load_memory == 0


def _test_mlx_runtime_probe_skips_unsafe_xcode_python_without_spawning_probe() -> None:
    import relflowhub_mlx_runtime as mlx_runtime_entry

    original_run = mlx_runtime_entry.subprocess.run
    original_executable = mlx_runtime_entry.sys.executable
    original_cache = dict(mlx_runtime_entry._MLX_IMPORT_PROBE_CACHE)
    try:
        mlx_runtime_entry._MLX_IMPORT_PROBE_CACHE.update(
            {
                "attempted": False,
                "ok": False,
                "error": "",
            }
        )

        def fail_run(*args, **kwargs):
            _ = args, kwargs
            raise AssertionError("probe subprocess should not run for unsafe Xcode python")

        mlx_runtime_entry.subprocess.run = fail_run
        mlx_runtime_entry.sys.executable = "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python"
        ok, error = mlx_runtime_entry.probe_mlx_runtime_support(force=True)
    finally:
        mlx_runtime_entry.subprocess.run = original_run
        mlx_runtime_entry.sys.executable = original_executable
        mlx_runtime_entry._MLX_IMPORT_PROBE_CACHE.update(original_cache)

    assert ok is False
    assert "mlx_probe_skipped:unsafe_python_executable" in error


def _test_mlx_runtime_load_profile_instances_share_physical_load() -> None:
    runtime, load_calls, _, _ = _build_fake_mlx_runtime()
    with tempfile.TemporaryDirectory(prefix="xhub_py_mlx_model_a_") as model_dir_a, tempfile.TemporaryDirectory(
        prefix="xhub_py_mlx_model_b_"
    ) as model_dir_b:
        ok_first, msg_first, delta_first = runtime.load(
            "mlx-qwen",
            model_dir_a,
            instance_key="mlx:mlx-qwen:hash-a",
            load_profile_hash="hash-a",
            effective_context_length=8192,
        )
        ok_second, msg_second, delta_second = runtime.load(
            "mlx-qwen",
            model_dir_b,
            instance_key="mlx:mlx-qwen:hash-b",
            load_profile_hash="hash-b",
            effective_context_length=24576,
        )

    assert ok_first is True
    assert ok_second is True
    assert msg_first == "ok"
    assert msg_second == "ok"
    assert delta_first >= 0
    assert delta_second == 0
    assert len(load_calls) == 1
    assert runtime.loaded_model_ids() == ["mlx-qwen"]
    assert runtime.loaded_model_count() == 1

    rows = runtime.loaded_instance_rows()
    assert len(rows) == 2
    first = next(row for row in rows if row["instanceKey"] == "mlx:mlx-qwen:hash-a")
    second = next(row for row in rows if row["instanceKey"] == "mlx:mlx-qwen:hash-b")
    assert first["loadProfileHash"] == "hash-a"
    assert second["loadProfileHash"] == "hash-b"
    assert first["effectiveContextLength"] == 8192
    assert second["effectiveContextLength"] == 24576
    assert runtime.is_loaded("mlx-qwen", instance_key="mlx:mlx-qwen:hash-a") is True
    assert runtime.is_loaded("mlx-qwen", instance_key="mlx:mlx-qwen:hash-b") is True

    unload_one_ok, unload_one_msg = runtime.unload("", instance_key="mlx:mlx-qwen:hash-a")
    assert unload_one_ok is True
    assert unload_one_msg == "ok"
    assert runtime.is_loaded("mlx-qwen", instance_key="mlx:mlx-qwen:hash-a") is False
    assert runtime.is_loaded("mlx-qwen") is True

    unload_all_ok, unload_all_msg = runtime.unload("mlx-qwen")
    assert unload_all_ok is True
    assert unload_all_msg == "ok"
    assert runtime.is_loaded("mlx-qwen") is False


def _test_mlx_runtime_generate_and_bench_apply_effective_context_length() -> None:
    runtime, _, generate_calls, stream_calls = _build_fake_mlx_runtime()
    with tempfile.TemporaryDirectory(prefix="xhub_py_mlx_model_ctx_") as model_dir:
        ok_load, msg_load, _ = runtime.load(
            "mlx-qwen",
            model_dir,
            instance_key="mlx:mlx-qwen:hash-ctx",
            load_profile_hash="hash-ctx",
            effective_context_length=24576,
        )

    assert ok_load is True
    assert msg_load == "ok"

    ok_gen, text, meta = runtime.generate_text(
        "mlx-qwen",
        "hello local model",
        max_tokens=32,
        temperature=0.2,
        top_p=0.95,
        instance_key="mlx:mlx-qwen:hash-ctx",
        load_profile_hash="hash-ctx",
    )
    assert ok_gen is True
    assert text == "synthetic response"
    assert meta["loadProfileHash"] == "hash-ctx"
    assert meta["effectiveContextLength"] == 24576
    assert len(generate_calls) == 1
    assert generate_calls[0]["kwargs"]["max_kv_size"] == 24576

    ok_bench, msg_bench, bench_meta = runtime.bench(
        "mlx-qwen",
        prompt_tokens=64,
        generation_tokens=48,
        instance_key="mlx:mlx-qwen:hash-ctx",
        load_profile_hash="hash-ctx",
    )
    assert ok_bench is True
    assert msg_bench == "ok"
    assert bench_meta["loadProfileHash"] == "hash-ctx"
    assert bench_meta["effectiveContextLength"] == 24576
    assert len(stream_calls) == 2
    assert stream_calls[0]["kwargs"]["max_kv_size"] == 24576
    assert stream_calls[1]["kwargs"]["max_kv_size"] == 24576


def _test_mlx_provider_healthcheck_exposes_loaded_instances_machine_readably() -> None:
    runtime = StubMLXRuntime(
        ok=True,
        loaded={"mlx-qwen": {"model_id": "mlx-qwen"}},
        loaded_instances=[
            {
                "instanceKey": "mlx:mlx-qwen:hash-a",
                "modelId": "mlx-qwen",
                "taskKinds": ["text_generate"],
                "loadProfileHash": "hash-a",
                "effectiveContextLength": 24576,
                "loadedAt": 1.0,
                "lastUsedAt": 2.0,
                "residency": "resident",
                "residencyScope": "legacy_runtime",
                "deviceBackend": "mps",
            }
        ],
        memory_pair=(1024, 2048),
    )
    provider = MLXProvider(runtime=runtime, runtime_version="compat-test")
    health = provider.healthcheck(
        base_dir="/tmp",
        catalog_models=[
            {
                "id": "mlx-qwen",
                "backend": "mlx",
                "modelPath": "/models/mlx-qwen",
            }
        ],
    )

    payload = health.to_dict()
    assert payload["loadedModels"] == ["mlx-qwen"]
    assert payload["loadedModelCount"] == 1
    assert len(payload["loadedInstances"]) == 1
    assert payload["loadedInstances"][0]["instanceKey"] == "mlx:mlx-qwen:hash-a"
    assert payload["loadedInstances"][0]["effectiveContextLength"] == 24576


def _test_transformers_embedding_hash_fallback_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_embed_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )
        with temporary_env("XHUB_TRANSFORMERS_ALLOW_HASH_EMBED_FALLBACK", "1"):
            result = run_local_task(
                {
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "texts": ["buy water", "approve payment"],
                    "input_sanitized": True,
                },
                base_dir=base_dir,
            )

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "embedding"
        assert result["modelId"] == "hf-embed"
        assert int(result["vectorCount"]) == 2
        assert int(result["dims"]) >= 8
        assert len(result["vectors"]) == 2
        assert len(result["vectors"][0]) == int(result["dims"])
        assert result["fallbackMode"] == "hash"
        assert result["usage"]["inputSanitized"] is True


def _test_transformers_embedding_runtime_failure_exposes_runtime_resolution_fields() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_embed_runtime_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )
        resolution = make_runtime_resolution(
            runtime_source="hub_py_deps",
            runtime_source_path=os.path.join(base_dir, "py_deps", "site-packages"),
            runtime_resolution_state="runtime_missing",
            runtime_reason_code="missing_runtime",
            import_error="missing_module:torch",
            runtime_hint="transformers runtime is missing required dependencies (python_module:torch).",
            missing_requirements=["python_module:torch"],
            ready_python_modules=["transformers"],
        )

        with patched_transformers_runtime_resolution(resolution):
            result = run_local_task(
                {
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "texts": ["buy water"],
                },
                base_dir=base_dir,
            )

        assert result["ok"] is False
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "embedding"
        assert result["taskKinds"] == ["embedding"]
        assert result["error"] == "missing_module:torch"
        assert result["reasonCode"] == "missing_runtime"
        assert result["runtimeReasonCode"] == "missing_runtime"
        assert result["runtimeSource"] == "hub_py_deps"
        assert result["runtimeResolutionState"] == "runtime_missing"
        assert result["runtimeSourcePath"].endswith("/py_deps/site-packages")
        assert "python_module:torch" in result["runtimeMissingRequirements"]
        assert result["runtimeMissingOptionalRequirements"] == []
        assert "missing required dependencies" in result["runtimeHint"]


def _test_transformers_embedding_quantization_config_failure_classifies_reason_code() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_embed_quant_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed-mlx-quant",
                        "name": "HF Embed MLX Quant",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed-mlx-quant",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )

        original = TransformersProvider._run_real_embedding
        try:
            def _raise_quantization_config_error(self, **kwargs):
                raise RuntimeError(
                    "The model's quantization config from the arguments has no `quant_method` attribute. "
                    "Make sure that the model has been correctly quantized"
                )

            TransformersProvider._run_real_embedding = _raise_quantization_config_error  # type: ignore[method-assign]
            with temporary_transformers_runtime_modules():
                result = run_local_task(
                    {
                        "provider": "transformers",
                        "task_kind": "embedding",
                        "model_id": "hf-embed-mlx-quant",
                        "texts": ["probe"],
                    },
                    base_dir=base_dir,
                )
        finally:
            TransformersProvider._run_real_embedding = original  # type: ignore[method-assign]

        assert result["ok"] is False
        assert result["error"] == "embedding_runtime_failed"
        assert result["reasonCode"] == "unsupported_quantization_config"
        assert result["runtimeReasonCode"] == "unsupported_quantization_config"
        assert "quant_method" in result["errorDetail"]


def _test_transformers_asr_fallback_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_asr_") as base_dir:
        audio_path = os.path.join(base_dir, "clip.wav")
        write_wav(audio_path, duration_sec=0.5)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-asr",
                        "name": "HF ASR",
                        "backend": "transformers",
                        "modelPath": "/models/hf-asr",
                        "taskKinds": ["speech_to_text"],
                    }
                ]
            },
        )
        with temporary_env("XHUB_TRANSFORMERS_ALLOW_ASR_FALLBACK", "1"):
            result = run_local_task(
                {
                    "provider": "transformers",
                    "task_kind": "speech_to_text",
                    "model_id": "hf-asr",
                    "input": {
                        "audio_path": audio_path,
                    },
                    "options": {
                        "language": "en",
                        "timestamps": True,
                    },
                },
                base_dir=base_dir,
            )

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "speech_to_text"
        assert result["modelId"] == "hf-asr"
        assert result["fallbackMode"] == "wav_hash"
        assert isinstance(result["text"], str) and result["text"].startswith("[offline_asr_fallback:")
        assert len(result["segments"]) == 1
        assert float(result["usage"]["inputAudioSec"]) > 0
        assert int(result["usage"]["inputAudioBytes"]) > 0
        assert result["usage"]["timestampsRequested"] is True


def _test_transformers_asr_guard_rejects_overlong_audio() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_asr_guard_") as base_dir:
        audio_path = os.path.join(base_dir, "long.wav")
        write_wav(audio_path, duration_sec=2.0)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-asr",
                        "name": "HF ASR",
                        "backend": "transformers",
                        "modelPath": "/models/hf-asr",
                        "taskKinds": ["speech_to_text"],
                    }
                ]
            },
        )
        result = run_local_task(
            {
                "provider": "transformers",
                "task_kind": "speech_to_text",
                "model_id": "hf-asr",
                "audio_path": audio_path,
                "max_audio_seconds": 1,
            },
            base_dir=base_dir,
        )

        assert result["ok"] is False
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "speech_to_text"
        assert result["error"] == "audio_duration_too_long"


def _test_transformers_asr_real_runtime_coerces_samples_to_numpy_array_when_available() -> None:
    provider = TransformersProvider()
    captured: dict[str, Any] = {}
    original_runtime_loader = TransformersProvider._load_asr_runtime
    original_numpy = sys.modules.get("numpy")

    class _FakeNumpyModule:
        @staticmethod
        def asarray(values: Any, dtype: Any = None) -> dict[str, Any]:
            captured["numpy_values"] = list(values or [])
            captured["numpy_dtype"] = dtype
            return {
                "kind": "fake_ndarray",
                "dtype": dtype,
                "values": list(values or []),
            }

    def _fake_pipeline(payload: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
        captured["payload"] = payload
        captured["kwargs"] = kwargs
        return {
            "text": "zero",
            "chunks": [
                {
                    "timestamp": (0.0, 0.25),
                    "text": "zero",
                }
            ],
        }

    def _fake_runtime_loader(self, **kwargs: Any) -> dict[str, Any]:
        captured["runtime_loader_kwargs"] = dict(kwargs)
        return {
            "pipeline": _fake_pipeline,
            "device": "cpu",
        }

    try:
        sys.modules["numpy"] = _FakeNumpyModule()
        TransformersProvider._load_asr_runtime = _fake_runtime_loader  # type: ignore[method-assign]
        text, segments, device = provider._run_real_asr(
            model_id="hf-asr",
            model_path="/models/hf-asr",
            instance_key="transformers:hf-asr:test-hash",
            load_profile_hash="test-hash",
            effective_context_length=8192,
            max_context_length=8192,
            effective_load_profile={"context_length": 8192},
            audio_meta={
                "samples": [0.0, 0.25, -0.5],
                "sample_rate": 16000,
                "duration_sec": 0.25,
            },
            language="en",
            timestamps=True,
        )
    finally:
        TransformersProvider._load_asr_runtime = original_runtime_loader  # type: ignore[method-assign]
        if original_numpy is None:
            sys.modules.pop("numpy", None)
        else:
            sys.modules["numpy"] = original_numpy

    assert captured["numpy_dtype"] == "float32"
    assert captured["numpy_values"] == [0.0, 0.25, -0.5]
    assert captured["payload"]["raw"]["kind"] == "fake_ndarray"
    assert captured["payload"]["raw"]["dtype"] == "float32"
    assert captured["payload"]["sampling_rate"] == 16000
    assert captured["kwargs"]["return_timestamps"] is True
    assert captured["kwargs"]["generate_kwargs"] == {"language": "en"}
    assert text == "zero"
    assert len(segments) == 1
    assert segments[0]["text"] == "zero"
    assert device == "cpu"


def _test_transformers_asr_runtime_strips_loader_only_forward_params() -> None:
    provider = TransformersProvider()
    original_transformers = sys.modules.get("transformers")

    class _FakePipeline:
        def __init__(self) -> None:
            self._forward_params = {
                "local_files_only": True,
                "return_timestamps": False,
            }
            self.device = "cpu"

    captured: dict[str, Any] = {}
    fake_pipe = _FakePipeline()

    class _FakeTransformersModule:
        @staticmethod
        def pipeline(task: str, model: str, **kwargs: Any) -> _FakePipeline:
            captured["task"] = task
            captured["model"] = model
            captured["kwargs"] = dict(kwargs)
            return fake_pipe

    try:
        sys.modules["transformers"] = _FakeTransformersModule()
        runtime = provider._load_asr_runtime(
            model_id="hf-asr",
            model_path="/models/hf-asr",
            instance_key="transformers:hf-asr:test-hash",
            load_profile_hash="test-hash",
            effective_context_length=8192,
            max_context_length=8192,
            effective_load_profile={"context_length": 8192},
        )
    finally:
        if original_transformers is None:
            sys.modules.pop("transformers", None)
        else:
            sys.modules["transformers"] = original_transformers

    assert captured["task"] == "automatic-speech-recognition"
    assert captured["model"] == "/models/hf-asr"
    assert captured["kwargs"]["local_files_only"] is True
    assert captured["kwargs"]["trust_remote_code"] is False
    assert runtime["pipeline"] is fake_pipe
    assert "local_files_only" not in fake_pipe._forward_params
    assert fake_pipe._forward_params["return_timestamps"] is False


def _test_transformers_tts_contract_fails_closed_when_system_fallback_is_disabled() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_tts_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-tts",
                        "name": "HF TTS",
                        "backend": "transformers",
                        "modelPath": "/models/hf-tts",
                        "taskKinds": ["text_to_speech"],
                    }
                ]
            },
        )
        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "0"):
            with temporary_transformers_runtime_modules():
                result = run_local_task(
                    {
                        "provider": "transformers",
                        "task_kind": "text_to_speech",
                        "model_id": "hf-tts",
                        "text": "project status normal",
                        "options": {
                            "locale": "en-US",
                            "voice_color": "warm",
                            "speech_rate": 1.1,
                        },
                    },
                    base_dir=base_dir,
                )

        assert result["ok"] is False
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "text_to_speech"
        assert result["taskKinds"] == ["text_to_speech"]
        assert result["modelId"] == "hf-tts"
        assert result["error"] == "task_not_implemented:transformers:text_to_speech"
        assert result["reasonCode"] == "tts_native_engine_not_supported"
        assert result["runtimeReasonCode"] == "tts_native_engine_not_supported"
        assert result["nativeTTSUsed"] is False
        assert result["fallbackMode"] == ""
        assert int(result["usage"]["inputTextChars"]) > 0


def _test_transformers_tts_contract_returns_audio_path_when_system_fallback_is_enabled() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_tts_fallback_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-tts",
                        "name": "HF TTS",
                        "backend": "transformers",
                        "modelPath": "/models/hf-tts",
                        "taskKinds": ["text_to_speech"],
                    }
                ]
            },
        )
        fake_say = os.path.join(base_dir, "fake_say.py")
        write_fake_say(fake_say)

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "1"):
            with temporary_env("XHUB_TRANSFORMERS_TTS_SAY_BINARY", fake_say):
                with temporary_transformers_runtime_modules():
                    result = run_local_task(
                        {
                            "provider": "transformers",
                            "task_kind": "text_to_speech",
                            "model_id": "hf-tts",
                            "text": "项目进度正常",
                            "options": {
                                "locale": "zh-CN",
                                "voice_color": "warm",
                                "speech_rate": 1.2,
                            },
                        },
                        base_dir=base_dir,
                    )

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "text_to_speech"
        assert result["modelId"] == "hf-tts"
        assert result["audioFormat"] == "aiff"
        assert result["engineName"] == "system_voice_compatibility"
        assert result["nativeTTSUsed"] is False
        assert result["fallbackMode"] == "system_voice_compatibility"
        assert result["fallbackReasonCode"] == "tts_native_engine_not_supported"
        assert result["deviceBackend"] == "system_voice_compatibility"
        assert result["voiceColor"] == "warm"
        assert result["speechRate"] == 1.2
        assert result["locale"] == "zh-CN"
        assert result["voiceName"] == "Eddy (Chinese (China mainland))"
        assert os.path.isfile(result["audioPath"])
        assert os.path.getsize(result["audioPath"]) > 0
        assert int(result["usage"]["inputTextChars"]) > 0
        assert int(result["usage"]["outputAudioBytes"]) > 0


def _test_transformers_tts_kokoro_native_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_tts_kokoro_") as base_dir:
        model_dir = os.path.join(base_dir, "kokoro_model")
        os.makedirs(model_dir, exist_ok=True)
        model_path = os.path.join(model_dir, "model.safetensors")
        write_text(model_path, "fake kokoro weights")
        write_json(
            os.path.join(model_dir, "config.json"),
            {
                "architectures": ["KokoroTTSModel"],
                "model_type": "kokoro_tts",
                "voices": ["zh_warm_f1"],
            },
        )
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-kokoro",
                        "name": "HF Kokoro",
                        "backend": "transformers",
                        "modelPath": model_path,
                        "taskKinds": ["text_to_speech"],
                        "voiceProfile": {
                            "engineHints": ["kokoro"],
                            "languageHints": ["zh"],
                            "styleHints": ["warm"],
                        },
                    }
                ]
            },
        )
        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "0"):
            with temporary_transformers_runtime_modules():
                with temporary_kokoro_runtime_module():
                    result = run_local_task(
                        {
                            "provider": "transformers",
                            "task_kind": "text_to_speech",
                            "model_id": "hf-kokoro",
                            "text": "项目进度正常",
                            "options": {
                                "locale": "zh-CN",
                                "voice_color": "warm",
                                "speech_rate": 1.05,
                            },
                        },
                        base_dir=base_dir,
                    )

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "text_to_speech"
        assert result["modelId"] == "hf-kokoro"
        assert result["audioFormat"] == "wav"
        assert result["engineName"] == "kokoro"
        assert result["speakerId"] == "zh_warm_f1"
        assert result["nativeTTSUsed"] is True
        assert result["fallbackMode"] == ""
        assert os.path.isfile(result["audioPath"])
        assert os.path.getsize(result["audioPath"]) > 0
        assert int(result["usage"]["inputTextChars"]) > 0
        assert int(result["usage"]["outputAudioBytes"]) > 0


def _test_transformers_tts_kokoro_missing_dependency_falls_back_when_allowed() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_tts_kokoro_fallback_") as base_dir:
        model_dir = os.path.join(base_dir, "kokoro_model")
        os.makedirs(model_dir, exist_ok=True)
        model_path = os.path.join(model_dir, "model.safetensors")
        write_text(model_path, "fake kokoro weights")
        write_json(
            os.path.join(model_dir, "config.json"),
            {
                "architectures": ["KokoroTTSModel"],
                "model_type": "kokoro_tts",
                "voices": ["zh_warm_f1"],
            },
        )
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-kokoro",
                        "name": "HF Kokoro",
                        "backend": "transformers",
                        "modelPath": model_path,
                        "taskKinds": ["text_to_speech"],
                        "voiceProfile": {
                            "engineHints": ["kokoro"],
                            "languageHints": ["zh"],
                            "styleHints": ["warm"],
                        },
                    }
                ]
            },
        )
        fake_say = os.path.join(base_dir, "fake_say.py")
        write_fake_say(fake_say)

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "1"):
            with temporary_env("XHUB_TRANSFORMERS_TTS_SAY_BINARY", fake_say):
                with temporary_transformers_runtime_modules():
                    result = run_local_task(
                        {
                            "provider": "transformers",
                            "task_kind": "text_to_speech",
                            "model_id": "hf-kokoro",
                            "text": "项目进度正常",
                            "options": {
                                "locale": "zh-CN",
                                "voice_color": "warm",
                                "speech_rate": 1.1,
                            },
                        },
                        base_dir=base_dir,
                    )

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "text_to_speech"
        assert result["engineName"] == "system_voice_compatibility"
        assert result["nativeTTSUsed"] is False
        assert result["fallbackMode"] == "system_voice_compatibility"
        assert result["fallbackReasonCode"] == "native_dependency_error"
        assert os.path.isfile(result["audioPath"])
        assert os.path.getsize(result["audioPath"]) > 0


def _test_transformers_tts_kokoro_routes_zh_bright_to_clear_speaker_from_filesystem() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_tts_kokoro_route_zh_") as base_dir:
        model_dir = os.path.join(base_dir, "kokoro_model")
        voices_dir = os.path.join(model_dir, "voices")
        os.makedirs(voices_dir, exist_ok=True)
        model_path = os.path.join(model_dir, "model.safetensors")
        write_text(model_path, "fake kokoro weights")
        write_text(os.path.join(voices_dir, "zh_warm_f1.bin"), "voice")
        write_text(os.path.join(voices_dir, "zh_clear_f1.bin"), "voice")
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-kokoro-zh",
                        "name": "HF Kokoro Chinese",
                        "backend": "transformers",
                        "modelPath": model_path,
                        "taskKinds": ["text_to_speech"],
                        "voiceProfile": {
                            "engineHints": ["kokoro"],
                            "languageHints": ["zh"],
                            "styleHints": ["clear"],
                        },
                    }
                ]
            },
        )

        speakers = discover_available_speaker_ids(model_dir)
        assert speakers == ["zh_clear_f1", "zh_warm_f1"]

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "0"):
            with temporary_transformers_runtime_modules():
                with temporary_kokoro_runtime_module():
                    result = run_local_task(
                        {
                            "provider": "transformers",
                            "task_kind": "text_to_speech",
                            "model_id": "hf-kokoro-zh",
                            "text": "现在开始播报项目进度",
                            "options": {
                                "locale": "zh-CN",
                                "voice_color": "bright",
                                "speech_rate": 1.0,
                            },
                        },
                        base_dir=base_dir,
                    )

        assert result["ok"] is True
        assert result["engineName"] == "kokoro"
        assert result["nativeTTSUsed"] is True
        assert result["speakerId"] == "zh_clear_f1"


def _test_transformers_tts_kokoro_routes_en_calm_to_expected_speaker() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_tts_kokoro_route_en_") as base_dir:
        model_dir = os.path.join(base_dir, "kokoro_model")
        os.makedirs(model_dir, exist_ok=True)
        model_path = os.path.join(model_dir, "model.safetensors")
        write_text(model_path, "fake kokoro weights")
        write_json(
            os.path.join(model_dir, "config.json"),
            {
                "architectures": ["KokoroTTSModel"],
                "model_type": "kokoro_tts",
                "voices": ["af_bella", "bf_emma", "am_adam"],
            },
        )
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-kokoro-en",
                        "name": "HF Kokoro English",
                        "backend": "transformers",
                        "modelPath": model_path,
                        "taskKinds": ["text_to_speech"],
                        "voiceProfile": {
                            "engineHints": ["kokoro"],
                            "languageHints": ["en"],
                            "styleHints": ["calm"],
                        },
                    }
                ]
            },
        )

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "0"):
            with temporary_transformers_runtime_modules():
                with temporary_kokoro_runtime_module():
                    result = run_local_task(
                        {
                            "provider": "transformers",
                            "task_kind": "text_to_speech",
                            "model_id": "hf-kokoro-en",
                            "text": "The project is ready for review.",
                            "options": {
                                "locale": "en-US",
                                "voice_color": "calm",
                                "speech_rate": 0.98,
                            },
                        },
                        base_dir=base_dir,
                    )

        assert result["ok"] is True
        assert result["engineName"] == "kokoro"
        assert result["nativeTTSUsed"] is True
        assert result["speakerId"] == "bf_emma"


def _test_transformers_tts_healthcheck_reports_unavailable_when_system_fallback_is_disabled() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_tts_status_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-tts",
                        "name": "HF TTS",
                        "backend": "transformers",
                        "modelPath": "/models/hf-tts",
                        "taskKinds": ["text_to_speech"],
                    }
                ]
            },
        )

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "0"):
            with temporary_transformers_runtime_modules():
                snapshot = provider_status_snapshot(base_dir)

        assert snapshot["transformers"]["availableTaskKinds"] == []
        assert snapshot["transformers"]["unavailableTaskKinds"] == ["text_to_speech"]
        assert snapshot["transformers"]["reasonCode"] == "text_to_speech_unavailable"


def _test_transformers_tts_healthcheck_reports_native_ready_when_kokoro_runtime_is_available() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_tts_status_kokoro_") as base_dir:
        model_dir = os.path.join(base_dir, "kokoro_model")
        os.makedirs(model_dir, exist_ok=True)
        write_text(os.path.join(model_dir, "model.safetensors"), "fake kokoro weights")
        write_json(
            os.path.join(model_dir, "config.json"),
            {
                "architectures": ["KokoroTTSModel"],
                "model_type": "kokoro_tts",
                "voices": ["zh_warm_f1"],
            },
        )
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-kokoro",
                        "name": "HF Kokoro",
                        "backend": "transformers",
                        "modelPath": os.path.join(model_dir, "model.safetensors"),
                        "taskKinds": ["text_to_speech"],
                        "voiceProfile": {
                            "engineHints": ["kokoro"],
                            "languageHints": ["zh"],
                            "styleHints": ["warm"],
                        },
                    }
                ]
            },
        )

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "0"):
            with temporary_transformers_runtime_modules():
                with temporary_kokoro_runtime_module():
                    snapshot = provider_status_snapshot(base_dir)

        assert snapshot["transformers"]["availableTaskKinds"] == ["text_to_speech"]
        assert snapshot["transformers"]["realTaskKinds"] == ["text_to_speech"]
        assert snapshot["transformers"]["fallbackTaskKinds"] == []
        assert snapshot["transformers"]["reasonCode"] == "ready"


def _test_transformers_tts_healthcheck_reports_fallback_ready_when_system_fallback_is_enabled() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_tts_status_fallback_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-tts",
                        "name": "HF TTS",
                        "backend": "transformers",
                        "modelPath": "/models/hf-tts",
                        "taskKinds": ["text_to_speech"],
                    }
                ]
            },
        )
        fake_say = os.path.join(base_dir, "fake_say.py")
        write_fake_say(fake_say)

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "1"):
            with temporary_env("XHUB_TRANSFORMERS_TTS_SAY_BINARY", fake_say):
                with temporary_transformers_runtime_modules():
                    snapshot = provider_status_snapshot(base_dir)

        assert snapshot["transformers"]["availableTaskKinds"] == ["text_to_speech"]
        assert snapshot["transformers"]["fallbackTaskKinds"] == ["text_to_speech"]
        assert snapshot["transformers"]["unavailableTaskKinds"] == []
        assert snapshot["transformers"]["reasonCode"] == "fallback_ready"
        assert snapshot["transformers"]["deviceBackend"] == "system_voice_compatibility"


def _test_transformers_vision_healthcheck_requires_real_runtime_by_default() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_vision_status_") as base_dir:
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

        without_env = provider_status_snapshot(base_dir)
        assert "vision_understand" not in list(without_env["transformers"].get("availableTaskKinds") or [])
        assert without_env["transformers"]["reasonCode"] == "missing_runtime"
        assert without_env["transformers"]["importError"] == "missing_module:torch"

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_VISION_FALLBACK", "1"):
            with_env = provider_status_snapshot(base_dir)

        assert "vision_understand" in list(with_env["transformers"].get("availableTaskKinds") or [])
        assert with_env["transformers"]["reasonCode"] == "fallback_ready"
        assert with_env["transformers"]["importError"] == "missing_module:torch"

        with temporary_transformers_runtime_modules():
            ready = provider_status_snapshot(base_dir)

        assert "vision_understand" in list(ready["transformers"].get("availableTaskKinds") or [])
        assert ready["transformers"]["reasonCode"] == "ready"
        assert ready["transformers"]["realTaskKinds"] == ["vision_understand"]


def _test_transformers_warmup_runtime_failure_preserves_task_kinds_and_optional_runtime_requirements() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_warmup_runtime_") as base_dir:
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
        resolution = make_runtime_resolution(
            runtime_source="user_python_venv",
            runtime_source_path="/Users/test/project/.venv/bin/python3",
            runtime_resolution_state="user_runtime_fallback",
            runtime_reason_code="ready",
            fallback_used=True,
            missing_optional_requirements=["python_module:pil"],
            ready_python_modules=["transformers", "torch"],
        )

        with patched_transformers_runtime_resolution(resolution):
            result = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "vision_understand",
                    "model_id": "hf-vision",
                },
                base_dir=base_dir,
            )

        assert result["ok"] is False
        assert result["provider"] == "transformers"
        assert result["action"] == "warmup_local_model"
        assert result["taskKind"] == "vision_understand"
        assert result["taskKinds"] == ["vision_understand"]
        assert result["reasonCode"] == "missing_runtime"
        assert result["runtimeReasonCode"] == "missing_runtime"
        assert result["runtimeResolutionState"] == "user_runtime_fallback"
        assert result["runtimeSource"] == "user_python_venv"
        assert result["runtimeSourcePath"] == "/Users/test/project/.venv/bin/python3"
        assert result["runtimeMissingRequirements"] == []
        assert result["runtimeMissingOptionalRequirements"] == ["python_module:pil"]
        assert "Pillow" in result["runtimeHint"]


def _test_transformers_vision_real_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_vision_") as base_dir:
        image_path = os.path.join(base_dir, "frame.png")
        write_png(image_path, width=24, height=18)
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
        with temporary_transformers_runtime_modules():
            result = run_local_task(
                {
                    "provider": "transformers",
                    "task_kind": "vision_understand",
                    "model_id": "hf-vision",
                    "image_path": image_path,
                    "prompt": "describe the scene",
                },
                base_dir=base_dir,
            )

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "vision_understand"
        assert result["modelId"] == "hf-vision"
        assert result["fallbackMode"] == ""
        assert isinstance(result["text"], str) and result["text"].startswith("vision:")
        assert "24x18" in result["text"]
        assert "describe the scene" in result["text"]
        assert result["usage"]["inputImageWidth"] == 24
        assert result["usage"]["inputImageHeight"] == 18
        assert result["usage"]["inputImagePixels"] == 432


def _test_transformers_ocr_real_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_ocr_") as base_dir:
        image_path = os.path.join(base_dir, "page.png")
        write_png(image_path, width=64, height=32)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-ocr",
                        "name": "HF OCR",
                        "backend": "transformers",
                        "modelPath": "/models/hf-ocr",
                        "taskKinds": ["ocr"],
                    }
                ]
            },
        )
        with temporary_transformers_runtime_modules():
            result = run_local_task(
                {
                    "provider": "transformers",
                    "task_kind": "ocr",
                    "model_id": "hf-ocr",
                    "input": {
                        "image_path": image_path,
                    },
                    "options": {
                        "language": "en",
                    },
                },
                base_dir=base_dir,
            )

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "ocr"
        assert result["modelId"] == "hf-ocr"
        assert result["fallbackMode"] == ""
        assert isinstance(result["text"], str) and result["text"].startswith("ocr:")
        assert len(result["spans"]) == 1
        assert "64x32" in result["text"]
        assert result["spans"][0]["bbox"]["width"] == 64
        assert result["spans"][0]["bbox"]["height"] == 32
        assert result["usage"]["inputImagePixels"] == 2048


def _test_transformers_image_guard_rejects_overlarge_dimensions() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_image_guard_") as base_dir:
        image_path = os.path.join(base_dir, "wide.png")
        write_png(image_path, width=128, height=48)
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
        result = run_local_task(
            {
                "provider": "transformers",
                "task_kind": "vision_understand",
                "model_id": "hf-vision",
                "image_path": image_path,
                "max_image_dimension": 64,
            },
            base_dir=base_dir,
        )

        assert result["ok"] is False
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "vision_understand"
        assert result["error"] == "image_dimensions_too_large"
        assert result["usage"]["inputImageWidth"] == 128
        assert result["usage"]["inputImageHeight"] == 48


def _test_transformers_image_guard_uses_effective_load_profile_image_dimension() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_image_profile_guard_") as base_dir:
        image_path = os.path.join(base_dir, "wide.png")
        write_png(image_path, width=128, height=48)
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
                        "default_load_config": {
                            "vision": {"image_max_dimension": 64}
                        },
                    }
                ]
            },
        )
        result = run_local_task(
            {
                "provider": "transformers",
                "task_kind": "vision_understand",
                "model_id": "hf-vision",
                "image_path": image_path,
                "allow_vision_fallback": True,
            },
            base_dir=base_dir,
        )

        assert result["ok"] is False
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "vision_understand"
        assert result["error"] == "image_dimensions_too_large"
        assert result["usage"]["inputImageWidth"] == 128
        assert result["usage"]["inputImageHeight"] == 48


def _test_provider_status_snapshot_exposes_resource_policy_and_scheduler_state() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_scheduler_status_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                        "resourceProfile": {
                            "preferredDevice": "cpu",
                            "memoryFloorMB": 1024,
                            "dtype": "float32",
                        },
                    }
                ]
            },
        )

        snapshot = provider_status_snapshot(base_dir)
        policy = snapshot["transformers"]["resourcePolicy"]
        scheduler = snapshot["transformers"]["schedulerState"]

        assert policy["preferredDevice"] == "cpu"
        assert policy["memoryFloorMB"] == 1024
        assert policy["taskLimits"]["embedding"] == 2
        assert policy["concurrencyLimit"] == 2
        assert scheduler["activeTaskCount"] == 0
        assert scheduler["queuedTaskCount"] == 0
        assert scheduler["oldestWaiterStartedAt"] == 0
        assert scheduler["oldestWaiterAgeMs"] == 0


def _test_provider_status_snapshot_exposes_real_and_fallback_task_metadata() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_task_readiness_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    },
                    {
                        "id": "hf-vision",
                        "name": "HF Vision",
                        "backend": "transformers",
                        "modelPath": "/models/hf-vision",
                        "taskKinds": ["vision_understand"],
                    },
                ]
            },
        )

        with temporary_transformers_runtime_modules():
            snapshot = provider_status_snapshot(base_dir)

        transformers = snapshot["transformers"]
        assert sorted(transformers["realTaskKinds"]) == ["embedding", "vision_understand"]
        assert sorted(transformers["fallbackTaskKinds"]) == []
        assert transformers["unavailableTaskKinds"] == []


def _test_provider_status_snapshot_exposes_lifecycle_contract_metadata() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_lifecycle_status_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "mlx-qwen",
                        "name": "MLX Qwen",
                        "backend": "mlx",
                        "modelPath": "/models/mlx-qwen",
                    },
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    },
                    {
                        "id": "hf-asr",
                        "name": "HF ASR",
                        "backend": "transformers",
                        "modelPath": "/models/hf-asr",
                        "taskKinds": ["speech_to_text"],
                    },
                ]
            },
        )

        with temporary_transformers_runtime_modules():
            snapshot = provider_status_snapshot(base_dir)

        assert snapshot["mlx"]["lifecycleMode"] == "mlx_legacy"
        assert snapshot["mlx"]["supportedLifecycleActions"] == []
        assert snapshot["transformers"]["lifecycleMode"] == "warmable"
        assert "warmup_local_model" in snapshot["transformers"]["supportedLifecycleActions"]
        assert snapshot["transformers"]["warmupTaskKinds"] == ["embedding", "speech_to_text"]
        assert snapshot["transformers"]["residencyScope"] == "process_local"


def _test_provider_status_snapshot_exposes_runtime_resolution_state_and_hint() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_runtime_resolution_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    },
                ]
            },
        )

        with temporary_transformers_runtime_modules():
            snapshot = provider_status_snapshot(base_dir)

        transformers = snapshot["transformers"]
        assert transformers["runtimeResolutionState"] == "user_runtime_fallback"
        assert transformers["runtimeSource"].startswith("user_python_")
        assert transformers["fallbackUsed"] is True
        assert transformers["runtimeSourcePath"]
        assert "user Python" in transformers["runtimeHint"]
        assert transformers["runtimeMissingRequirements"] == []


def _test_provider_status_snapshot_marks_hub_py_deps_runtime_as_pack_ready() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_pack_runtime_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    },
                ]
            },
        )
        py_deps_root = os.path.join(base_dir, "py_deps")
        site_packages = os.path.join(py_deps_root, "site-packages")
        os.makedirs(site_packages, exist_ok=True)
        with open(os.path.join(py_deps_root, "USE_PYTHONPATH"), "w", encoding="utf-8") as handle:
            handle.write("1\n")

        with temporary_transformers_runtime_modules(module_root=site_packages):
            snapshot = provider_status_snapshot(base_dir)

        transformers = snapshot["transformers"]
        assert transformers["runtimeResolutionState"] == "pack_runtime_ready"
        assert transformers["runtimeSource"] == "hub_py_deps"
        assert transformers["fallbackUsed"] is False
        assert transformers["runtimeSourcePath"] == site_packages
        assert transformers["runtimeHint"] == ""


def _test_provider_status_snapshot_marks_runtime_resident_transformers_when_requested() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_runtime_resident_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )

        with temporary_transformers_runtime_modules():
            snapshot = provider_status_snapshot(base_dir, resident_transformers=True)

        assert snapshot["transformers"]["lifecycleMode"] == "warmable"
        assert snapshot["transformers"]["residencyScope"] == "runtime_process"


def _test_runtime_status_proxy_support_requires_fresh_ipc_marker() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_proxy_support_") as base_dir:
        write_json(
            _runtime_status_path(base_dir),
            {
                "pid": os.getpid() + 1000,
                "updatedAt": time.time(),
                "localCommandIpcVersion": "xhub.local_runtime_command_ipc.v1",
            },
        )
        assert _runtime_supports_command_proxy(base_dir) is True

        write_json(
            _runtime_status_path(base_dir),
            {
                "pid": os.getpid() + 1000,
                "updatedAt": time.time() - 10.0,
                "localCommandIpcVersion": "xhub.local_runtime_command_ipc.v1",
            },
        )
        assert _runtime_supports_command_proxy(base_dir) is False


def _test_proxy_runtime_command_round_trip_through_file_ipc() -> None:
    import relflowhub_local_runtime as local_runtime_entry

    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_proxy_roundtrip_") as base_dir:
        observed: dict[str, Any] = {}

        def responder() -> None:
            deadline = time.time() + 2.0
            req_dir = os.path.join(base_dir, "local_runtime_commands")
            while time.time() < deadline:
                names = sorted(os.listdir(req_dir)) if os.path.isdir(req_dir) else []
                if not names:
                    time.sleep(0.02)
                    continue
                req_path = os.path.join(req_dir, names[0])
                with open(req_path, "r", encoding="utf-8") as handle:
                    command = json.load(handle)
                observed.update(command)
                req_id = str(command.get("req_id") or "").strip()
                assert req_id
                write_json(
                    os.path.join(base_dir, "local_runtime_command_results", f"resp_{req_id}.json"),
                    {
                        "ok": True,
                        "provider": "transformers",
                        "command": command.get("command"),
                        "via": "daemon_proxy_roundtrip",
                    },
                )
                try:
                    os.remove(req_path)
                except Exception:
                    pass
                return
            raise AssertionError("runtime command request was not observed")

        worker = threading.Thread(target=responder, daemon=True)
        worker.start()
        result = local_runtime_entry._proxy_runtime_command(
            base_dir,
            command="run_local_task",
            request={
                "provider": "transformers",
                "model_id": "hf-embed",
                "task_kind": "embedding",
            },
            timeout_sec=2.0,
        )
        worker.join(timeout=1.0)

        assert observed["type"] == "local_runtime_command"
        assert observed["command"] == "run_local_task"
        assert observed["request"]["model_id"] == "hf-embed"
        assert result["ok"] is True
        assert result["via"] == "daemon_proxy_roundtrip"


def _test_main_manage_local_model_prefers_daemon_proxy_when_available() -> None:
    import relflowhub_local_runtime as local_runtime_entry

    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_main_proxy_") as base_dir:
        captured: dict[str, Any] = {}
        original_base_dir = local_runtime_entry._base_dir
        original_support = local_runtime_entry._runtime_supports_command_proxy
        original_proxy = local_runtime_entry._proxy_runtime_command
        original_manage = local_runtime_entry.manage_local_model
        original_stdout = sys.stdout
        try:
            local_runtime_entry._base_dir = lambda: base_dir
            local_runtime_entry._runtime_supports_command_proxy = lambda candidate, max_age_sec=5.0: candidate == base_dir

            def fake_proxy(candidate: str, *, command: str, request: dict[str, Any], timeout_sec: float) -> dict[str, Any]:
                captured["base_dir"] = candidate
                captured["command"] = command
                captured["request"] = dict(request)
                captured["timeout_sec"] = float(timeout_sec)
                return {
                    "ok": True,
                    "provider": "transformers",
                    "action": request.get("action"),
                    "modelId": request.get("model_id"),
                    "via": "main_proxy_path",
                }

            def fail_direct_manage(*args, **kwargs):
                raise AssertionError("manage_local_model should not run directly when daemon proxy is available")

            local_runtime_entry._proxy_runtime_command = fake_proxy
            local_runtime_entry.manage_local_model = fail_direct_manage

            stdout = io.StringIO()
            sys.stdout = stdout
            exit_code = local_runtime_entry.main(
                [
                    "manage-local-model",
                    json.dumps(
                        {
                            "action": "warmup_local_model",
                            "provider": "transformers",
                            "model_id": "hf-embed",
                        }
                    ),
                ]
            )
        finally:
            sys.stdout = original_stdout
            local_runtime_entry._base_dir = original_base_dir
            local_runtime_entry._runtime_supports_command_proxy = original_support
            local_runtime_entry._proxy_runtime_command = original_proxy
            local_runtime_entry.manage_local_model = original_manage

        payload = json.loads(stdout.getvalue())
        assert exit_code == 0
        assert captured["base_dir"] == base_dir
        assert captured["command"] == "manage_local_model"
        assert captured["request"]["action"] == "warmup_local_model"
        assert captured["request"]["provider"] == "transformers"
        assert captured["request"]["model_id"] == "hf-embed"
        assert captured["timeout_sec"] == 60.0
        assert payload["ok"] is True
        assert payload["via"] == "main_proxy_path"


def _test_main_run_local_bench_skips_daemon_proxy_when_request_disables_it() -> None:
    import relflowhub_local_runtime as local_runtime_entry

    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_main_bench_direct_") as base_dir:
        original_base_dir = local_runtime_entry._base_dir
        original_support = local_runtime_entry._runtime_supports_command_proxy
        original_proxy = local_runtime_entry._proxy_runtime_command
        original_run_bench = local_runtime_entry.run_local_bench
        original_stdout = sys.stdout
        try:
            local_runtime_entry._base_dir = lambda: base_dir
            local_runtime_entry._runtime_supports_command_proxy = lambda candidate, max_age_sec=5.0: candidate == base_dir

            def fail_proxy(*args, **kwargs):
                raise AssertionError("run_local_bench should bypass daemon proxy when allow_daemon_proxy=false")

            def fake_run_local_bench(request: dict[str, Any], *, base_dir: str | None = None) -> dict[str, Any]:
                return {
                    "ok": True,
                    "provider": str(request.get("provider") or ""),
                    "taskKind": str(request.get("task_kind") or ""),
                    "modelId": str(request.get("model_id") or ""),
                    "via": "direct_main_path",
                }

            local_runtime_entry._proxy_runtime_command = fail_proxy
            local_runtime_entry.run_local_bench = fake_run_local_bench

            stdout = io.StringIO()
            sys.stdout = stdout
            exit_code = local_runtime_entry.main(
                [
                    "run-local-bench",
                    json.dumps(
                        {
                            "provider": "transformers",
                            "model_id": "glm4v-local",
                            "task_kind": "vision_understand",
                            "allow_daemon_proxy": False,
                        }
                    ),
                ]
            )
        finally:
            sys.stdout = original_stdout
            local_runtime_entry._base_dir = original_base_dir
            local_runtime_entry._runtime_supports_command_proxy = original_support
            local_runtime_entry._proxy_runtime_command = original_proxy
            local_runtime_entry.run_local_bench = original_run_bench

        payload = json.loads(stdout.getvalue())
        assert exit_code == 0
        assert payload["ok"] is True
        assert payload["provider"] == "transformers"
        assert payload["taskKind"] == "vision_understand"
        assert payload["modelId"] == "glm4v-local"
        assert payload["via"] == "direct_main_path"


def _test_manage_local_model_warmup_contract_for_transformers_embedding() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_warmup_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                        "default_load_config": {
                            "context_length": 16384,
                        },
                    }
                ]
            },
        )

        with temporary_transformers_runtime_modules():
            result = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                },
                base_dir=base_dir,
            )

        assert result["ok"] is True
        assert result["action"] == "warmup_local_model"
        assert result["provider"] == "transformers"
        assert result["modelId"] == "hf-embed"
        assert result["taskKinds"] == ["embedding"]
        assert result["lifecycleMode"] == "warmable"
        assert result["residencyScope"] == "process_local"
        assert result["processScoped"] is True
        assert result["deviceBackend"] == "cpu"
        assert isinstance(result["instanceKey"], str) and result["instanceKey"].startswith("transformers:hf-embed:")
        assert result["coldStartMs"] >= 0
        assert result["scheduler"]["provider"] == "transformers"


def _test_manage_local_model_unload_and_evict_transformers_instances() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_evict_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )

        with temporary_transformers_runtime_modules():
            first = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "load_profile_override": {
                        "context_length": 8192,
                    },
                },
                base_dir=base_dir,
            )
            second = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "load_profile_override": {
                        "context_length": 12288,
                    },
                },
                base_dir=base_dir,
            )
            evicted = manage_local_model(
                {
                    "action": "evict_local_instance",
                    "instance_key": first["instanceKey"],
                },
                base_dir=base_dir,
            )
            unloaded = manage_local_model(
                {
                    "action": "unload_local_model",
                    "provider": "transformers",
                    "model_id": "hf-embed",
                },
                base_dir=base_dir,
            )
            snapshot = provider_status_snapshot(base_dir)

        assert first["ok"] is True
        assert second["ok"] is True
        assert first["instanceKey"] != second["instanceKey"]
        assert evicted["ok"] is True
        assert evicted["instanceKey"] == first["instanceKey"]
        assert evicted["evictedInstanceCount"] == 1
        assert unloaded["ok"] is True
        assert unloaded["modelId"] == "hf-embed"
        assert unloaded["unloadedInstanceCount"] == 1
        assert snapshot["transformers"]["loadedModels"] == []
        assert snapshot["transformers"]["loadedInstances"] == []


def _test_transformers_loaded_instance_inventory_and_idle_eviction_state() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_inventory_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )

        with temporary_transformers_runtime_modules():
            first = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "load_profile_override": {
                        "context_length": 8192,
                    },
                },
                base_dir=base_dir,
            )
            second = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "load_profile_override": {
                        "context_length": 12288,
                    },
                },
                base_dir=base_dir,
            )
            loaded_snapshot = provider_status_snapshot(base_dir)
            evicted = manage_local_model(
                {
                    "action": "evict_local_instance",
                    "instance_key": first["instanceKey"],
                },
                base_dir=base_dir,
            )
            after_evict = provider_status_snapshot(base_dir)
            unloaded = manage_local_model(
                {
                    "action": "unload_local_model",
                    "provider": "transformers",
                    "model_id": "hf-embed",
                },
                base_dir=base_dir,
            )
            after_unload = provider_status_snapshot(base_dir)

        assert first["ok"] is True
        assert second["ok"] is True
        assert len(loaded_snapshot["transformers"]["loadedInstances"]) == 2
        assert {
            row["instanceKey"]
            for row in loaded_snapshot["transformers"]["loadedInstances"]
        } == {first["instanceKey"], second["instanceKey"]}
        assert loaded_snapshot["transformers"]["idleEviction"]["policy"] == "manual_or_process_exit"
        assert loaded_snapshot["transformers"]["idleEviction"]["automaticIdleEvictionEnabled"] is False
        assert loaded_snapshot["transformers"]["idleEviction"]["processScoped"] is True
        assert loaded_snapshot["transformers"]["idleEviction"]["lastEvictionReason"] == "none"

        assert evicted["ok"] is True
        assert after_evict["transformers"]["idleEviction"]["lastEvictionReason"] == "manual_evict_instance"
        assert after_evict["transformers"]["idleEviction"]["lastEvictedInstanceKeys"] == [first["instanceKey"]]
        assert after_evict["transformers"]["idleEviction"]["lastEvictedCount"] == 1
        assert after_evict["transformers"]["idleEviction"]["totalEvictedInstanceCount"] == 1
        assert len(after_evict["transformers"]["loadedInstances"]) == 1

        assert unloaded["ok"] is True
        assert after_unload["transformers"]["loadedInstances"] == []
        assert after_unload["transformers"]["idleEviction"]["lastEvictionReason"] == "manual_unload"
        assert after_unload["transformers"]["idleEviction"]["lastEvictedCount"] == 1
        assert after_unload["transformers"]["idleEviction"]["totalEvictedInstanceCount"] == 2


def _test_transformers_process_exit_marks_inventory_as_evicted() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_process_exit_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )

        with temporary_transformers_runtime_modules():
            result = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                },
                base_dir=base_dir,
            )
            registry = build_registry(base_dir=base_dir)
            provider = registry.get("transformers")
            assert isinstance(provider, TransformersProvider)
            provider._handle_process_exit()
            snapshot = provider_status_snapshot(base_dir)

        assert result["ok"] is True
        assert snapshot["transformers"]["loadedInstances"] == []
        assert snapshot["transformers"]["idleEviction"]["lastEvictionReason"] == "process_exit"
        assert snapshot["transformers"]["idleEviction"]["lastEvictedCount"] == 1


def _test_manage_local_model_warmup_supports_transformers_vision_when_runtime_is_available() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_preview_warmup_") as base_dir:
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

        with temporary_transformers_runtime_modules():
            result = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "vision_understand",
                    "model_id": "hf-vision",
                },
                base_dir=base_dir,
            )
            snapshot = provider_status_snapshot(base_dir)

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["action"] == "warmup_local_model"
        assert result["taskKinds"] == ["vision_understand"]
        assert result["deviceBackend"] == "cpu"
        assert isinstance(result["instanceKey"], str) and result["instanceKey"].startswith("transformers:hf-vision:")
        assert snapshot["transformers"]["loadedInstances"][0]["modelId"] == "hf-vision"
        assert snapshot["transformers"]["loadedInstances"][0]["taskKinds"] == ["vision_understand"]


def _test_manage_local_model_mlx_legacy_fails_closed() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_mlx_lifecycle_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "mlx-qwen",
                        "name": "MLX Qwen",
                        "backend": "mlx",
                        "modelPath": "/models/mlx-qwen",
                    }
                ]
            },
        )

        result = manage_local_model(
            {
                "action": "warmup_local_model",
                "provider": "mlx",
                "task_kind": "text_generate",
                "model_id": "mlx-qwen",
            },
            base_dir=base_dir,
        )

        assert result["ok"] is False
        assert result["provider"] == "mlx"
        assert result["action"] == "warmup_local_model"
        assert result["lifecycleMode"] == "mlx_legacy"
        assert result["error"] == "unsupported_lifecycle:mlx_legacy"


def _test_routing_settings_schema_v2_resolves_device_and_hub_defaults() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_routing_v2_") as base_dir:
        write_json(
            os.path.join(base_dir, "routing_settings.json"),
            {
                "type": "routing_settings",
                "schemaVersion": "xhub.routing_settings.v2",
                "updatedAt": 1741850000.0,
                "hubDefaultModelIdByTaskKind": {
                    "text_generate": "mlx-qwen",
                    "embedding": "hf-embed",
                },
                "devicePreferredModelIdByTaskKind": {
                    "terminal_device": {
                        "embedding": "hf-embed-device",
                    }
                },
            },
        )

        settings = _load_routing_settings(base_dir)
        device_model, device_source = _resolve_routing_preferred_model_id(base_dir, "embedding", "terminal_device")
        hub_model, hub_source = _resolve_routing_preferred_model_id(base_dir, "text_generate", "")
        missing_model, missing_source = _resolve_routing_preferred_model_id(base_dir, "speech_to_text", "terminal_device")

        assert settings["schemaVersion"] == "xhub.routing_settings.v2"
        assert settings["hubDefaultModelIdByTaskKind"]["embedding"] == "hf-embed"
        assert settings["devicePreferredModelIdByTaskKind"]["terminal_device"]["embedding"] == "hf-embed-device"
        assert device_model == "hf-embed-device"
        assert device_source == "device_override"
        assert hub_model == "mlx-qwen"
        assert hub_source == "hub_default"
        assert missing_model == ""
        assert missing_source == ""


def _test_routing_settings_legacy_map_stays_backward_compatible() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_routing_legacy_") as base_dir:
        write_json(
            os.path.join(base_dir, "routing_settings.json"),
            {
                "preferredModelIdByTask": {
                    "summarize": "mlx-summary",
                }
            },
        )

        settings = _load_routing_settings(base_dir)
        model_id, source = _resolve_routing_preferred_model_id(base_dir, "summarize")

        assert settings["hubDefaultModelIdByTaskKind"]["summarize"] == "mlx-summary"
        assert model_id == "mlx-summary"
        assert source == "hub_default"


def _test_run_local_task_rejects_when_provider_slot_is_busy() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_scheduler_busy_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                        "resourceProfile": {
                            "preferredDevice": "mps",
                            "memoryFloorMB": 2048,
                            "dtype": "float16",
                        },
                    }
                ]
            },
        )
        catalog_models = [
            {
                "id": "hf-embed",
                "backend": "transformers",
                "taskKinds": ["embedding"],
                "resourceProfile": {
                    "preferredDevice": "mps",
                    "memoryFloorMB": 2048,
                    "dtype": "float16",
                },
            }
        ]
        slot = acquire_provider_slot(
            base_dir,
            "transformers",
            request={
                "provider": "transformers",
                "task_kind": "embedding",
                "model_id": "hf-embed",
            },
            catalog_models=catalog_models,
        )
        assert slot["ok"] is True
        try:
            with temporary_env("XHUB_TRANSFORMERS_ALLOW_HASH_EMBED_FALLBACK", "1"):
                result = run_local_task(
                    {
                        "provider": "transformers",
                        "task_kind": "embedding",
                        "model_id": "hf-embed",
                        "texts": ["buy water"],
                    },
                    base_dir=base_dir,
                )
        finally:
            release_provider_slot(base_dir, "transformers", slot.get("lease_id"))

        assert result["ok"] is False
        assert result["error"] == "provider_busy"
        assert result["scheduler"]["queueState"] == "rejected"
        assert result["scheduler"]["concurrencyLimit"] == 1


def _test_run_local_task_queue_timeout_when_provider_slot_stays_busy() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_scheduler_timeout_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                        "resourceProfile": {
                            "preferredDevice": "mps",
                            "memoryFloorMB": 2048,
                            "dtype": "float16",
                        },
                    }
                ]
            },
        )
        catalog_models = [
            {
                "id": "hf-embed",
                "backend": "transformers",
                "taskKinds": ["embedding"],
                "resourceProfile": {
                    "preferredDevice": "mps",
                    "memoryFloorMB": 2048,
                    "dtype": "float16",
                },
            }
        ]
        slot = acquire_provider_slot(
            base_dir,
            "transformers",
            request={
                "provider": "transformers",
                "task_kind": "embedding",
                "model_id": "hf-embed",
            },
            catalog_models=catalog_models,
        )
        assert slot["ok"] is True
        try:
            with temporary_env("XHUB_TRANSFORMERS_ALLOW_HASH_EMBED_FALLBACK", "1"):
                result = run_local_task(
                    {
                        "provider": "transformers",
                        "task_kind": "embedding",
                        "model_id": "hf-embed",
                        "texts": ["buy water"],
                        "queue_if_busy": True,
                        "queue_timeout_ms": 25,
                        "queue_poll_ms": 10,
                    },
                    base_dir=base_dir,
                )
        finally:
            release_provider_slot(base_dir, "transformers", slot.get("lease_id"))

        assert result["ok"] is False
        assert result["error"] == "provider_queue_timeout"
        assert result["scheduler"]["queueState"] == "timed_out"
        assert result["scheduler"]["queueWaitMs"] >= 20


def _test_run_local_task_waits_then_executes_when_provider_slot_frees() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_scheduler_wait_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                        "resourceProfile": {
                            "preferredDevice": "mps",
                            "memoryFloorMB": 2048,
                            "dtype": "float16",
                        },
                    }
                ]
            },
        )
        catalog_models = [
            {
                "id": "hf-embed",
                "backend": "transformers",
                "taskKinds": ["embedding"],
                "resourceProfile": {
                    "preferredDevice": "mps",
                    "memoryFloorMB": 2048,
                    "dtype": "float16",
                },
            }
        ]
        slot = acquire_provider_slot(
            base_dir,
            "transformers",
            request={
                "provider": "transformers",
                "task_kind": "embedding",
                "model_id": "hf-embed",
            },
            catalog_models=catalog_models,
        )
        assert slot["ok"] is True

        release_thread = threading.Thread(
            target=lambda: (time.sleep(0.05), release_provider_slot(base_dir, "transformers", slot.get("lease_id"))),
            daemon=True,
        )
        release_thread.start()
        with temporary_env("XHUB_TRANSFORMERS_ALLOW_HASH_EMBED_FALLBACK", "1"):
            result = run_local_task(
                {
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "texts": ["buy water"],
                    "queue_if_busy": True,
                    "queue_timeout_ms": 250,
                    "queue_poll_ms": 10,
                },
                base_dir=base_dir,
            )
        release_thread.join(timeout=1.0)

        assert result["ok"] is True
        assert result["taskKind"] == "embedding"
        assert result["scheduler"]["queueState"] == "waited"
        assert result["scheduler"]["queueWaitMs"] >= 30
        assert result["scheduler"]["concurrencyLimit"] == 1


def _test_run_local_task_resolves_device_scoped_load_profile_identity() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_profile_identity_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                        "max_context_length": 32768,
                        "default_load_config": {
                            "context_length": 16384,
                            "gpu_offload_ratio": 0.5,
                            "eval_batch_size": 8,
                            "ttl": 900,
                            "identifier": "hf-embed-default",
                            "vision": {"image_max_dimension": 4096},
                        },
                    }
                ]
            },
        )
        write_json(
            os.path.join(base_dir, "hub_paired_terminal_local_model_profiles.json"),
            {
                "schema_version": "hub.paired_terminal_local_model_profiles.v1",
                "updated_at_ms": 1741800000000,
                "profiles": [
                    {
                        "device_id": "terminal_device",
                        "model_id": "hf-embed",
                        "override_profile": {
                            "context_length": 65536,
                            "rope_frequency_scale": 2.0,
                            "parallel": 3,
                            "identifier": "terminal-hf-embed",
                            "vision": {"image_max_dimension": 2048},
                        },
                        "updated_at_ms": 1741800001000,
                    }
                ],
            },
        )

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_HASH_EMBED_FALLBACK", "1"):
            result = run_local_task(
                {
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "device_id": "terminal_device",
                    "texts": ["buy water"],
                    "input_sanitized": True,
                },
                base_dir=base_dir,
            )

        assert result["ok"] is True
        assert result["effectiveContextSource"] == "runtime_clamped"
        assert result["effectiveContextLength"] == 32768
        assert result["effectiveLoadProfile"]["context_length"] == 32768
        assert result["effectiveLoadProfile"]["gpu_offload_ratio"] == 0.5
        assert result["effectiveLoadProfile"]["eval_batch_size"] == 8
        assert result["effectiveLoadProfile"]["rope_frequency_scale"] == 2.0
        assert result["effectiveLoadProfile"]["ttl"] == 900
        assert result["effectiveLoadProfile"]["parallel"] == 3
        assert result["effectiveLoadProfile"]["identifier"] == "terminal-hf-embed"
        assert result["effectiveLoadProfile"]["vision"]["image_max_dimension"] == 2048
        assert result["deviceId"] == "terminal_device"
        assert isinstance(result["loadProfileHash"], str) and len(result["loadProfileHash"]) == 64
        assert result["instanceKey"] == f"transformers:hf-embed:{result['loadProfileHash']}"
        assert result["scheduler"]["loadProfileHash"] == result["loadProfileHash"]
        assert result["scheduler"]["instanceKey"] == result["instanceKey"]
        assert result["scheduler"]["effectiveContextLength"] == 32768


def _test_scheduler_telemetry_tracks_instance_key_and_load_profile_hash() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_scheduler_identity_") as base_dir:
        catalog_models = [
            {
                "id": "hf-embed",
                "backend": "transformers",
                "taskKinds": ["embedding"],
                "resourceProfile": {
                    "preferredDevice": "cpu",
                    "memoryFloorMB": 1024,
                    "dtype": "float32",
                },
            }
        ]
        slot = acquire_provider_slot(
            base_dir,
            "transformers",
            request={
                "provider": "transformers",
                "task_kind": "embedding",
                "model_id": "hf-embed",
                "request_id": "req-1",
                "device_id": "terminal_device",
                "load_profile_hash": "abc123",
                "instance_key": "transformers:hf-embed:abc123",
                "effective_context_length": 24576,
                "lease_ttl_ms": 120_000,
            },
            catalog_models=catalog_models,
        )
        assert slot["ok"] is True
        try:
            telemetry = read_provider_scheduler_telemetry(
                base_dir,
                "transformers",
                policy={"concurrencyLimit": 2},
            )
        finally:
            release_provider_slot(base_dir, "transformers", slot.get("lease_id"))

        assert telemetry["activeTaskCount"] == 1
        assert len(telemetry["activeTasks"]) == 1
        active = telemetry["activeTasks"][0]
        assert active["modelId"] == "hf-embed"
        assert active["requestId"] == "req-1"
        assert active["deviceId"] == "terminal_device"
        assert active["loadProfileHash"] == "abc123"
        assert active["instanceKey"] == "transformers:hf-embed:abc123"
        assert active["effectiveContextLength"] == 24576
        assert active["leaseTtlSec"] == 120
        assert 0 < active["leaseRemainingTtlSec"] <= 120
        assert active["expiresAt"] >= active["startedAt"]


def _test_scheduler_telemetry_exposes_oldest_waiter_age() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_scheduler_queue_") as base_dir:
        catalog_models = [
            {
                "id": "hf-embed",
                "backend": "transformers",
                "taskKinds": ["embedding"],
                "resourceProfile": {
                    "preferredDevice": "cpu",
                    "memoryFloorMB": 4096,
                    "dtype": "float32",
                },
            }
        ]
        first_slot = acquire_provider_slot(
            base_dir,
            "transformers",
            request={
                "provider": "transformers",
                "task_kind": "embedding",
                "model_id": "hf-embed",
                "request_id": "req-1",
            },
            catalog_models=catalog_models,
        )
        assert first_slot["ok"] is True

        queued_result: dict[str, Any] = {}

        def _queue_waiter() -> None:
            queued_result["slot"] = acquire_provider_slot(
                base_dir,
                "transformers",
                request={
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "request_id": "req-2",
                    "queue_if_busy": True,
                    "queue_timeout_ms": 1000,
                    "queue_poll_ms": 25,
                },
                catalog_models=catalog_models,
            )

        waiter = threading.Thread(target=_queue_waiter)
        waiter.start()
        try:
            telemetry: dict[str, Any] = {}
            for _ in range(20):
                telemetry = read_provider_scheduler_telemetry(
                    base_dir,
                    "transformers",
                    policy={"concurrencyLimit": 1, "queueingSupported": True, "queueMode": "opt_in_wait"},
                )
                if telemetry["queuedTaskCount"] >= 1:
                    break
                time.sleep(0.02)
            assert telemetry["queuedTaskCount"] == 1
            assert telemetry["oldestWaiterStartedAt"] > 0
            assert telemetry["oldestWaiterAgeMs"] >= 0
        finally:
            release_provider_slot(base_dir, "transformers", first_slot.get("lease_id"))
            waiter.join(timeout=2.0)

        assert queued_result["slot"]["ok"] is True


def _test_runtime_status_payload_exposes_monitor_snapshot() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_monitor_snapshot_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                        "resourceProfile": {
                            "preferredDevice": "cpu",
                            "memoryFloorMB": 4096,
                            "dtype": "float32",
                        },
                    },
                    {
                        "id": "hf-vision",
                        "name": "HF Vision",
                        "backend": "transformers",
                        "modelPath": "/models/hf-vision",
                        "taskKinds": ["vision_understand"],
                    },
                ]
            },
        )

        with temporary_transformers_runtime_modules():
            slot = acquire_provider_slot(
                base_dir,
                "transformers",
                request={
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "hf-embed",
                    "request_id": "req-monitor",
                    "device_id": "terminal_device",
                    "load_profile_hash": "abc123",
                    "instance_key": "transformers:hf-embed:abc123",
                    "effective_context_length": 24576,
                },
                catalog_models=[
                    {
                        "id": "hf-embed",
                        "backend": "transformers",
                        "taskKinds": ["embedding"],
                        "resourceProfile": {
                            "preferredDevice": "cpu",
                            "memoryFloorMB": 4096,
                            "dtype": "float32",
                        },
                    },
                    {
                        "id": "hf-vision",
                        "backend": "transformers",
                        "taskKinds": ["vision_understand"],
                    },
                ],
            )
            assert slot["ok"] is True
            try:
                payload = _status_payload(base_dir)
            finally:
                release_provider_slot(base_dir, "transformers", slot.get("lease_id"))

        monitor = payload["monitorSnapshot"]
        packs = {
            str(row.get("providerId") or row.get("provider_id")): row
            for row in payload["providerPacks"]
            if isinstance(row, dict)
        }
        assert "transformers" in packs
        assert packs["transformers"]["engine"] == "hf-transformers"
        assert packs["transformers"]["runtimeRequirements"]["executionMode"] == "builtin_python"
        assert "transformers" in packs["transformers"]["runtimeRequirements"]["pythonModules"]
        assert payload["providers"]["transformers"]["packId"] == "transformers"
        assert payload["providers"]["transformers"]["packVersion"] == packs["transformers"]["version"]
        assert payload["providers"]["transformers"]["packState"] == "installed"
        assert monitor["schemaVersion"] == "xhub.local_runtime_monitor.v1"
        assert monitor["queue"]["activeTaskCount"] == 1
        assert monitor["queue"]["queuedTaskCount"] == 0
        assert len(monitor["activeTasks"]) == 1
        assert monitor["activeTasks"][0]["provider"] == "transformers"
        assert monitor["activeTasks"][0]["leaseTtlSec"] > 0
        assert monitor["activeTasks"][0]["expiresAt"] >= monitor["activeTasks"][0]["startedAt"]
        assert monitor["fallbackCounters"]["fallbackReadyProviderCount"] == 0
        assert monitor["fallbackCounters"]["taskKindCounts"] == {}
        transformers = next(row for row in monitor["providers"] if row["provider"] == "transformers")
        assert transformers["realTaskKinds"] == ["embedding", "vision_understand"]
        assert transformers["fallbackTaskKinds"] == []
        assert transformers["activeTaskCount"] == 1
        assert transformers["queueingSupported"] is True
        assert transformers["memoryState"] == "unknown"


def _test_transformers_embedding_cache_isolated_by_instance_key() -> None:
    provider = TransformersProvider()
    torch_module = types.ModuleType("torch")
    torch_module.backends = types.SimpleNamespace(
        mps=types.SimpleNamespace(is_available=lambda: False),
    )

    class FakeModel:
        def __init__(self) -> None:
            self.config = types.SimpleNamespace(hidden_size=16)
            self.device = "cpu"

        def eval(self) -> "FakeModel":
            return self

        def to(self, device: str) -> "FakeModel":
            self.device = device
            return self

    class FakeAutoTokenizer:
        @staticmethod
        def from_pretrained(*args, **kwargs) -> dict[str, Any]:
            return {
                "args": list(args),
                "kwargs": dict(kwargs),
            }

    class FakeAutoModel:
        @staticmethod
        def from_pretrained(*args, **kwargs) -> FakeModel:
            _ = args, kwargs
            return FakeModel()

    transformers_module = types.ModuleType("transformers")
    transformers_module.AutoTokenizer = FakeAutoTokenizer
    transformers_module.AutoModel = FakeAutoModel

    with temporary_modules(
        {
            "torch": torch_module,
            "transformers": transformers_module,
        }
    ):
        first = provider._load_embedding_runtime(
            model_id="hf-embed",
            model_path="/models/hf-embed",
            instance_key="transformers:hf-embed:hash-a",
            load_profile_hash="hash-a",
        )
        second = provider._load_embedding_runtime(
            model_id="hf-embed",
            model_path="/models/hf-embed",
            instance_key="transformers:hf-embed:hash-b",
            load_profile_hash="hash-b",
        )

    assert first["instance_key"] == "transformers:hf-embed:hash-a"
    assert second["instance_key"] == "transformers:hf-embed:hash-b"
    assert first["load_profile_hash"] == "hash-a"
    assert second["load_profile_hash"] == "hash-b"
    assert first["model"] is not second["model"]
    assert len(provider._embedding_model_cache) == 2


def _write_bench_fixture_pack(path: str) -> None:
    write_json(
        path,
        {
            "schemaVersion": "xhub.local_bench_fixture_pack.v1",
            "fixtures": [
                {
                    "id": "text_short_prompt",
                    "taskKind": "text_generate",
                    "title": "Short Text Prompt",
                    "description": "compat text fixture",
                    "input": {
                        "prompt": "Write one short sentence about keeping local AI observable.",
                    },
                    "options": {
                        "max_new_tokens": 48,
                    },
                },
                {
                    "id": "embed_small_docs",
                    "taskKind": "embedding",
                    "title": "Small Document Batch",
                    "description": "compat fixture",
                    "input": {
                        "texts": [
                            "one offline note",
                            "second offline note",
                            "third offline note",
                        ]
                    },
                    "options": {
                        "max_length": 128,
                    },
                },
                {
                    "id": "vision_single_image",
                    "taskKind": "vision_understand",
                    "title": "Single Image Vision",
                    "description": "compat vision fixture",
                    "input": {
                        "image": {
                            "generator": "png_header",
                            "width": 48,
                            "height": 32,
                        },
                        "prompt": "Describe the image layout.",
                    },
                },
                {
                    "id": "voice_status_reply",
                    "taskKind": "text_to_speech",
                    "title": "Short Voice Reply",
                    "description": "compat tts fixture",
                    "input": {
                        "text": "Project status is green. No blockers need escalation right now.",
                        "locale": "en-US",
                        "voice_color": "neutral",
                        "speech_rate": 1.0,
                    },
                }
            ],
        },
    )


def _test_run_local_bench_embedding_contract_persists_result() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_bench_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )
        pack_path = os.path.join(base_dir, "bench_fixture_pack.json")
        _write_bench_fixture_pack(pack_path)

        result = run_local_bench(
            {
                "provider": "transformers",
                "model_id": "hf-embed",
                "task_kind": "embedding",
                "fixture_profile": "embed_small_docs",
                "fixture_pack_path": pack_path,
                "allow_bench_fallback": True,
            },
            base_dir=base_dir,
        )

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "embedding"
        assert result["fixtureProfile"] == "embed_small_docs"
        assert result["resultKind"] == "task_aware_quick_bench"
        assert result["throughputUnit"] == "items_per_sec"
        assert result["reasonCode"] in {"ready", "fallback_only"}

        with open(os.path.join(base_dir, "models_bench.json"), "r", encoding="utf-8") as handle:
            bench_snapshot = json.load(handle)
        assert bench_snapshot["schemaVersion"] == "xhub.models_bench.v2"
        assert len(bench_snapshot["results"]) == 1
        assert bench_snapshot["results"][0]["taskKind"] == "embedding"
        assert bench_snapshot["results"][0]["fixtureProfile"] == "embed_small_docs"


def _test_run_local_bench_runtime_failure_exposes_runtime_resolution_fields() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_bench_runtime_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )
        pack_path = os.path.join(base_dir, "bench_fixture_pack.json")
        _write_bench_fixture_pack(pack_path)
        resolution = make_runtime_resolution(
            runtime_source="hub_py_deps",
            runtime_source_path=os.path.join(base_dir, "py_deps", "site-packages"),
            runtime_resolution_state="runtime_missing",
            runtime_reason_code="missing_runtime",
            import_error="missing_module:torch",
            runtime_hint="transformers runtime is missing required dependencies (python_module:torch).",
            missing_requirements=["python_module:torch"],
            ready_python_modules=["transformers"],
        )

        with patched_transformers_runtime_resolution(resolution):
            result = run_local_bench(
                {
                    "provider": "transformers",
                    "model_id": "hf-embed",
                    "task_kind": "embedding",
                    "fixture_profile": "embed_small_docs",
                    "fixture_pack_path": pack_path,
                    "allow_bench_fallback": False,
                },
                base_dir=base_dir,
            )

        assert result["ok"] is False
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "embedding"
        assert result["fixtureProfile"] == "embed_small_docs"
        assert result["resultKind"] == "task_aware_quick_bench"
        assert result["reasonCode"] == "missing_runtime"
        assert result["runtimeReasonCode"] == "missing_runtime"
        assert result["runtimeSource"] == "hub_py_deps"
        assert result["runtimeResolutionState"] == "runtime_missing"
        assert "python_module:torch" in result["runtimeMissingRequirements"]
        assert result.get("runtimeMissingOptionalRequirements", []) == []
        assert "missing required dependencies" in result["runtimeHint"]

        with open(os.path.join(base_dir, "models_bench.json"), "r", encoding="utf-8") as handle:
            bench_snapshot = json.load(handle)
        assert bench_snapshot["results"][0]["reasonCode"] == "missing_runtime"
        assert bench_snapshot["results"][0]["runtimeReasonCode"] == "missing_runtime"
        assert bench_snapshot["results"][0]["runtimeSource"] == "hub_py_deps"
        assert bench_snapshot["results"][0]["runtimeResolutionState"] == "runtime_missing"
        assert "python_module:torch" in bench_snapshot["results"][0]["runtimeMissingRequirements"]


def _test_run_local_bench_vision_contract_persists_result() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_bench_vision_") as base_dir:
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
        _write_bench_fixture_pack(pack_path)

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

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "vision_understand"
        assert result["fixtureProfile"] == "vision_single_image"
        assert result["resultKind"] == "task_aware_quick_bench"
        assert result["throughputUnit"] == "images_per_sec"
        assert result["reasonCode"] == "ready"

        with open(os.path.join(base_dir, "models_bench.json"), "r", encoding="utf-8") as handle:
            bench_snapshot = json.load(handle)
        assert bench_snapshot["schemaVersion"] == "xhub.models_bench.v2"
        assert len(bench_snapshot["results"]) == 1
        assert bench_snapshot["results"][0]["taskKind"] == "vision_understand"
        assert bench_snapshot["results"][0]["fixtureProfile"] == "vision_single_image"


def _test_run_local_bench_tts_contract_fails_closed_when_system_fallback_is_disabled() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_bench_tts_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-tts",
                        "name": "HF TTS",
                        "backend": "transformers",
                        "modelPath": "/models/hf-tts",
                        "taskKinds": ["text_to_speech"],
                    }
                ]
            },
        )
        pack_path = os.path.join(base_dir, "bench_fixture_pack.json")
        _write_bench_fixture_pack(pack_path)

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "0"):
            with temporary_transformers_runtime_modules():
                result = run_local_bench(
                    {
                        "provider": "transformers",
                        "model_id": "hf-tts",
                        "task_kind": "text_to_speech",
                        "fixture_profile": "voice_status_reply",
                        "fixture_pack_path": pack_path,
                        "allow_bench_fallback": False,
                    },
                    base_dir=base_dir,
                )

        assert result["ok"] is False
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "text_to_speech"
        assert result["fixtureProfile"] == "voice_status_reply"
        assert result["resultKind"] == "task_aware_quick_bench"
        assert result["reasonCode"] == "tts_native_engine_not_supported"
        assert result["error"] == "tts_native_engine_not_supported"
        assert result["runtimeReasonCode"] == "tts_native_engine_not_supported"

        with open(os.path.join(base_dir, "models_bench.json"), "r", encoding="utf-8") as handle:
            bench_snapshot = json.load(handle)
        assert bench_snapshot["schemaVersion"] == "xhub.models_bench.v2"
        assert len(bench_snapshot["results"]) == 1
        assert bench_snapshot["results"][0]["taskKind"] == "text_to_speech"
        assert bench_snapshot["results"][0]["fixtureProfile"] == "voice_status_reply"
        assert bench_snapshot["results"][0]["reasonCode"] == "tts_native_engine_not_supported"


def _test_run_local_bench_tts_reports_fallback_ready_when_system_fallback_is_enabled() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_bench_tts_fallback_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-tts",
                        "name": "HF TTS",
                        "backend": "transformers",
                        "modelPath": "/models/hf-tts",
                        "taskKinds": ["text_to_speech"],
                    }
                ]
            },
        )
        pack_path = os.path.join(base_dir, "bench_fixture_pack.json")
        _write_bench_fixture_pack(pack_path)
        fake_say = os.path.join(base_dir, "fake_say.py")
        write_fake_say(fake_say)

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK", "1"):
            with temporary_env("XHUB_TRANSFORMERS_TTS_SAY_BINARY", fake_say):
                with temporary_transformers_runtime_modules():
                    result = run_local_bench(
                        {
                            "provider": "transformers",
                            "model_id": "hf-tts",
                            "task_kind": "text_to_speech",
                            "fixture_profile": "voice_status_reply",
                            "fixture_pack_path": pack_path,
                            "allow_bench_fallback": False,
                        },
                        base_dir=base_dir,
                    )

        assert result["ok"] is True
        assert result["provider"] == "transformers"
        assert result["taskKind"] == "text_to_speech"
        assert result["fixtureProfile"] == "voice_status_reply"
        assert result["resultKind"] == "task_aware_quick_bench"
        assert result["reasonCode"] == "fallback_only"
        assert result["fallbackMode"] == "system_voice_compatibility"
        assert result["verdict"] == "Fallback"
        assert result["latencyMs"] >= 0

        with open(os.path.join(base_dir, "models_bench.json"), "r", encoding="utf-8") as handle:
            bench_snapshot = json.load(handle)
        assert bench_snapshot["schemaVersion"] == "xhub.models_bench.v2"
        assert len(bench_snapshot["results"]) == 1
        assert bench_snapshot["results"][0]["taskKind"] == "text_to_speech"
        assert bench_snapshot["results"][0]["fixtureProfile"] == "voice_status_reply"
        assert bench_snapshot["results"][0]["reasonCode"] == "fallback_only"
        assert bench_snapshot["results"][0]["fallbackMode"] == "system_voice_compatibility"


def _test_run_local_bench_fails_closed_when_fixture_missing() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_lpr_bench_missing_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-embed",
                        "name": "HF Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )
        pack_path = os.path.join(base_dir, "bench_fixture_pack.json")
        _write_bench_fixture_pack(pack_path)

        result = run_local_bench(
            {
                "provider": "transformers",
                "model_id": "hf-embed",
                "task_kind": "embedding",
                "fixture_profile": "missing_fixture",
                "fixture_pack_path": pack_path,
                "allow_bench_fallback": True,
            },
            base_dir=base_dir,
        )

        assert result["ok"] is False
        assert result["reasonCode"] == "fixture_missing"
        assert result["resultKind"] == "task_aware_quick_bench"


def _write_fake_lms_helper(path: str, *, daemon_status: str, daemon_status_json: str | None = None) -> None:
    json_status = daemon_status_json
    if json_status is None:
        json_status = (
            '{"status":"not-running"}'
            if "not running" in daemon_status.lower()
            else '{"status":"running"}'
        )
    write_executable(
        path,
        f"""#!/bin/sh
if [ "$1" = "daemon" ] && [ "$2" = "status" ] && [ "$3" = "--json" ]; then
  printf '%s\\n' '{json_status}'
  exit 0
fi
if [ "$1" = "daemon" ] && [ "$2" = "status" ]; then
  printf '%s\\n' '{daemon_status}'
  exit 0
fi
if [ "$1" = "ls" ] && [ "$2" = "--json" ]; then
  printf '%s\\n' '[{{"modelKey":"glm-4.6v-flash","type":"llm","arch":"glm4v"}}]'
  exit 0
fi
if [ "$1" = "ps" ] && [ "$2" = "--json" ]; then
  printf '%s\\n' '[{{"identifier":"glm-4.6v","modelKey":"glm-4.6v-flash","contextLength":4096}}]'
  exit 0
fi
printf '%s\\n' 'unsupported'
exit 1
""",
    )


def _write_fake_lmstudio_settings(
    base_dir: str,
    *,
    enable_local_service: bool,
    cli_installed: bool = False,
    app_first_load: bool = False,
    attempted_install_lms_cli_on_startup: bool = True,
) -> None:
    write_json(
        os.path.join(base_dir, "settings.json"),
        {
            "enableLocalService": enable_local_service,
            "cliInstalled": cli_installed,
            "appFirstLoad": app_first_load,
            "developer": {
                "attemptedInstallLmsCliOnStartup": attempted_install_lms_cli_on_startup,
            },
        },
    )


def _write_stateful_fake_lms_helper(path: str) -> None:
    write_executable(
        path,
        """#!/bin/sh
STATE_FILE="$(dirname "$0")/lms_state.tsv"
cmd="$1"
shift

case "$cmd" in
  daemon)
    if [ "$1" = "status" ] && [ "$2" = "--json" ]; then
      printf '%s\\n' '{"status":"running"}'
      exit 0
    fi
    if [ "$1" = "status" ]; then
      printf '%s\\n' 'LM Studio daemon is running'
      exit 0
    fi
    ;;
  ls)
    if [ "$1" = "--json" ]; then
      printf '%s\\n' '[]'
      exit 0
    fi
    ;;
  load)
    model_key=""
    identifier=""
    context_length="0"
    while [ $# -gt 0 ]; do
      case "$1" in
        --identifier)
          identifier="$2"
          shift 2
          ;;
        --context-length|-c)
          context_length="$2"
          shift 2
          ;;
        --gpu|--parallel|--ttl)
          shift 2
          ;;
        --estimate-only|--yes)
          shift 1
          ;;
        *)
          if [ -z "$model_key" ]; then
            model_key="$1"
          fi
          shift 1
          ;;
      esac
    done
    [ -n "$identifier" ] || identifier="default"
    tmp="${STATE_FILE}.tmp"
    if [ -f "$STATE_FILE" ]; then
      grep -v "^${identifier}|" "$STATE_FILE" > "$tmp" || true
    else
      : > "$tmp"
    fi
    printf '%s|%s|%s\\n' "$identifier" "$model_key" "${context_length:-0}" >> "$tmp"
    mv "$tmp" "$STATE_FILE"
    printf '%s\\n' "loaded ${identifier}"
    exit 0
    ;;
  ps)
    if [ "$1" = "--json" ]; then
      printf '['
      first=1
      if [ -f "$STATE_FILE" ]; then
        while IFS='|' read -r identifier model_key context_length; do
          [ -n "$identifier" ] || continue
          if [ $first -eq 0 ]; then
            printf ','
          fi
          first=0
          printf '{"identifier":"%s","modelKey":"%s","path":"%s","type":"llm","vision":true,"contextLength":%s,"lastUsedTime":1742083200000}' "$identifier" "$model_key" "$model_key" "${context_length:-0}"
        done < "$STATE_FILE"
      fi
      printf ']\\n'
      exit 0
    fi
    ;;
  unload)
    unload_all=0
    identifier=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -a|--all)
          unload_all=1
          shift 1
          ;;
        *)
          identifier="$1"
          shift 1
          ;;
      esac
    done
    tmp="${STATE_FILE}.tmp"
    if [ $unload_all -eq 1 ]; then
      : > "$tmp"
    elif [ -f "$STATE_FILE" ]; then
      grep -v "^${identifier}|" "$STATE_FILE" > "$tmp" || true
    else
      : > "$tmp"
    fi
    mv "$tmp" "$STATE_FILE"
    printf '%s\\n' 'unloaded'
    exit 0
    ;;
esac

printf '%s\\n' 'unsupported'
exit 1
""",
    )


def _write_stateful_fake_lms_helper_with_server(
    path: str,
    *,
    server_port: int,
    loaded_type: str,
    loaded_vision: bool,
    daemon_requires_up: bool = False,
    server_requires_start: bool = False,
    load_wakes_service_once: bool = False,
    load_requires_server_start: bool = False,
) -> None:
    write_executable(
        path,
        f"""#!/bin/sh
STATE_FILE="$(dirname "$0")/lms_state.tsv"
DAEMON_FILE="$(dirname "$0")/lms_daemon.ready"
SERVER_FILE="$(dirname "$0")/lms_server.ready"
WAKE_FILE="$(dirname "$0")/lms_wakeup.ready"
cmd="$1"
shift

daemon_running=1
server_running=1
[ "{1 if daemon_requires_up else 0}" -eq 1 ] && daemon_running=0
[ "{1 if server_requires_start else 0}" -eq 1 ] && server_running=0
[ -f "$DAEMON_FILE" ] && daemon_running=1
[ -f "$SERVER_FILE" ] && server_running=1

case "$cmd" in
  daemon)
    if [ "$1" = "up" ]; then
      : > "$DAEMON_FILE"
      printf '%s\\n' '{{"status":"running"}}'
      exit 0
    fi
    if [ "$1" = "status" ] && [ "$2" = "--json" ]; then
      if [ "$daemon_running" -eq 1 ]; then
        printf '%s\\n' '{{"status":"running"}}'
      else
        printf '%s\\n' '{{"status":"not-running"}}'
      fi
      exit 0
    fi
    if [ "$1" = "status" ]; then
      if [ "$daemon_running" -eq 1 ]; then
        printf '%s\\n' 'LM Studio daemon is running'
      else
        printf '%s\\n' 'LM Studio is not running'
      fi
      exit 0
    fi
    ;;
  server)
    if [ "$1" = "status" ] && [ "$2" = "--json" ]; then
      if [ "$server_running" -eq 1 ]; then
        printf '%s\\n' '{{"running":true,"port":{server_port},"host":"127.0.0.1"}}'
      else
        printf '%s\\n' '{{"running":false}}'
      fi
      exit 0
    fi
    if [ "$1" = "start" ]; then
      : > "$SERVER_FILE"
      printf '%s\\n' 'started'
      exit 0
    fi
    ;;
  ls)
    if [ "$1" = "--json" ]; then
      printf '%s\\n' '[]'
      exit 0
    fi
    ;;
  load)
    model_key=""
    identifier=""
    context_length="0"
    while [ $# -gt 0 ]; do
      case "$1" in
        --identifier)
          identifier="$2"
          shift 2
          ;;
        --context-length|-c)
          context_length="$2"
          shift 2
          ;;
        --gpu|--parallel|--ttl)
          shift 2
          ;;
        --estimate-only|--yes)
          shift 1
          ;;
        *)
          if [ -z "$model_key" ]; then
            model_key="$1"
          fi
          shift 1
          ;;
      esac
    done
    [ -n "$identifier" ] || identifier="default"
    if [ "{1 if load_wakes_service_once else 0}" -eq 1 ] && [ ! -f "$WAKE_FILE" ]; then
      : > "$WAKE_FILE"
      printf '%s\\n' 'Waking up LM Studio service...'
      exit 1
    fi
    if [ "{1 if load_requires_server_start else 0}" -eq 1 ] && [ "$server_running" -ne 1 ]; then
      printf '%s\\n' 'Waking up LM Studio service...'
      exit 1
    fi
    tmp="${{STATE_FILE}}.tmp"
    if [ -f "$STATE_FILE" ]; then
      grep -v "^${{identifier}}|" "$STATE_FILE" > "$tmp" || true
    else
      : > "$tmp"
    fi
    printf '%s|%s|%s\\n' "$identifier" "$model_key" "${{context_length:-0}}" >> "$tmp"
    mv "$tmp" "$STATE_FILE"
    printf '%s\\n' "loaded $identifier"
    exit 0
    ;;
  ps)
    if [ "$1" = "--json" ]; then
      printf '['
      first=1
      if [ -f "$STATE_FILE" ]; then
        while IFS='|' read -r identifier model_key context_length; do
          [ -n "$identifier" ] || continue
          if [ $first -eq 0 ]; then
            printf ','
          fi
          first=0
          printf '{{"identifier":"%s","modelKey":"%s","path":"%s","type":"{loaded_type}","vision":{str(loaded_vision).lower()},"contextLength":%s,"lastUsedTime":1742083200000}}' "$identifier" "$model_key" "$model_key" "${{context_length:-0}}"
        done < "$STATE_FILE"
      fi
      printf ']\\n'
      exit 0
    fi
    ;;
  unload)
    unload_all=0
    identifier=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -a|--all)
          unload_all=1
          shift 1
          ;;
        *)
          identifier="$1"
          shift 1
          ;;
      esac
    done
    tmp="${{STATE_FILE}}.tmp"
    if [ $unload_all -eq 1 ]; then
      : > "$tmp"
    elif [ -f "$STATE_FILE" ]; then
      grep -v "^${{identifier}}|" "$STATE_FILE" > "$tmp" || true
    else
      : > "$tmp"
    fi
    mv "$tmp" "$STATE_FILE"
    printf '%s\\n' 'unloaded'
    exit 0
    ;;
esac

printf '%s\\n' 'unsupported'
exit 1
""",
    )


def _test_helper_binary_bridge_probe_detects_lms_service_down() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_down_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_fake_lms_helper(helper_path, daemon_status="LM Studio is not running")

        probe = probe_helper_binary_bridge(helper_path)

        assert probe.binary_found is True
        assert probe.helper_kind == "lmstudio"
        assert probe.reason_code == "helper_service_down"
        assert probe.service_state == "down"
        assert probe.ready is False
        assert "background service is not running" in probe.runtime_hint
        assert list_helper_bridge_downloaded_models(probe) == []
        assert list_helper_bridge_loaded_models(probe) == []


def _test_helper_binary_bridge_probe_detects_lms_local_service_disabled() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_disabled_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_fake_lms_helper(helper_path, daemon_status="LM Studio is not running")
        _write_fake_lmstudio_settings(
            base_dir,
            enable_local_service=False,
            cli_installed=False,
            app_first_load=True,
        )

        probe = probe_helper_binary_bridge(helper_path)

        assert probe.binary_found is True
        assert probe.helper_kind == "lmstudio"
        assert probe.reason_code == "helper_local_service_disabled"
        assert probe.service_state == "disabled"
        assert probe.ready is False
        assert probe.import_error == "helper_local_service_disabled:lms"
        assert "Enable Local Service" in probe.runtime_hint
        assert probe.missing_requirements == ["helper_service:lms_local_service_enabled"]
        lmstudio_environment = probe.metadata.get("lmStudioEnvironment") or {}
        assert lmstudio_environment.get("settingsPath", "").endswith("settings.json")
        assert (lmstudio_environment.get("settingsFlags") or {}).get("enableLocalService") is False


def _test_helper_binary_bridge_probe_lists_models_when_lms_is_ready() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_ready_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_fake_lms_helper(helper_path, daemon_status="LM Studio daemon is running")

        probe = probe_helper_binary_bridge(helper_path)
        downloaded = list_helper_bridge_downloaded_models(probe)
        loaded = list_helper_bridge_loaded_models(probe)

        assert probe.binary_found is True
        assert probe.helper_kind == "lmstudio"
        assert probe.reason_code == "helper_bridge_ready"
        assert probe.service_state == "running"
        assert probe.ready is True
        assert "context_length" in probe.load_parameter_fields
        assert downloaded[0]["modelKey"] == "glm-4.6v-flash"
        assert loaded[0]["identifier"] == "glm-4.6v"
        assert loaded[0]["contextLength"] == 4096


def _test_helper_binary_bridge_probe_prefers_json_running_status_over_stale_text_status() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_json_wins_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_fake_lms_helper(
            helper_path,
            daemon_status="LM Studio is not running",
            daemon_status_json='{"status":"running","pid":62130,"isDaemon":true}',
        )

        probe = probe_helper_binary_bridge(helper_path)
        downloaded = list_helper_bridge_downloaded_models(probe)
        loaded = list_helper_bridge_loaded_models(probe)

        assert probe.binary_found is True
        assert probe.helper_kind == "lmstudio"
        assert probe.reason_code == "helper_bridge_ready"
        assert probe.service_state == "running"
        assert probe.ready is True
        assert probe.metadata.get("probeJSONStatus") == "running"
        assert downloaded[0]["modelKey"] == "glm-4.6v-flash"
        assert loaded[0]["identifier"] == "glm-4.6v"


def _test_xhub_local_service_probe_reports_config_missing() -> None:
    with temporary_env_map(
        {
            "XHUB_LOCAL_SERVICE_BASE_URL": None,
            "AX_XHUB_LOCAL_SERVICE_BASE_URL": None,
            "XHUB_LOCAL_SERVICE_HOST": None,
            "AX_XHUB_LOCAL_SERVICE_HOST": None,
            "XHUB_LOCAL_SERVICE_PORT": None,
            "AX_XHUB_LOCAL_SERVICE_PORT": None,
        }
    ):
        probe = probe_xhub_local_service("")

    assert probe.ready is False
    assert probe.base_url == ""
    assert probe.service_state == "missing_config"
    assert probe.reason_code == "xhub_local_service_config_missing"
    assert probe.missing_requirements == ["xhub_local_service:base_url"]
    assert "serviceBaseUrl" in probe.runtime_hint


def _test_xhub_local_service_probe_reports_unreachable_service() -> None:
    base_url = "http://127.0.0.1:50171"
    with fake_xhub_local_service_health(
        {
            "ok": False,
            "status": 0,
            "body": {},
            "text": "",
            "error": "ConnectionRefusedError:[Errno 61] Connection refused",
        }
    ):
        probe = probe_xhub_local_service(base_url)

    assert probe.ready is False
    assert probe.base_url == base_url
    assert probe.service_state == "down"
    assert probe.reason_code == "xhub_local_service_unreachable"
    assert probe.missing_requirements == [f"xhub_local_service:{base_url}"]
    assert probe.metadata["probeUrl"] == f"{base_url}/health"


def _test_xhub_local_service_probe_reports_ready_service() -> None:
    base_url = "http://127.0.0.1:50171"
    with fake_xhub_local_service_health(
        {
            "ok": True,
            "status": 200,
            "body": {
                "ok": True,
                "status": "ready",
                "version": "xhub-local-service-dev",
                "capabilities": ["health", "list_models", "embeddings", "chat_completions"],
            },
            "text": "",
            "error": "",
        }
    ):
        probe = probe_xhub_local_service(base_url)

    assert probe.ready is True
    assert probe.base_url == base_url
    assert probe.service_state == "ready"
    assert probe.reason_code == "xhub_local_service_ready"
    assert probe.supported_operations == ["health", "list_models", "embeddings", "chat_completions"]
    assert probe.metadata["reportedVersion"] == "xhub-local-service-dev"


def _test_resolve_provider_runtime_reports_xhub_local_service_config_missing() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_local_service_config_missing_") as base_dir:
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "xhub_local_service",
                        },
                    },
                ],
            },
        )

        with temporary_env_map(
            {
                "XHUB_LOCAL_SERVICE_BASE_URL": None,
                "AX_XHUB_LOCAL_SERVICE_BASE_URL": None,
                "XHUB_LOCAL_SERVICE_HOST": None,
                "AX_XHUB_LOCAL_SERVICE_HOST": None,
                "XHUB_LOCAL_SERVICE_PORT": None,
                "AX_XHUB_LOCAL_SERVICE_PORT": None,
            }
        ):
            resolution = resolve_provider_runtime("transformers", base_dir=base_dir)

        assert resolution.runtime_source == "xhub_local_service"
        assert resolution.runtime_source_path == ""
        assert resolution.runtime_resolution_state == "runtime_missing"
        assert resolution.runtime_reason_code == "xhub_local_service_config_missing"
        assert resolution.ok is False
        assert resolution.missing_requirements == ["xhub_local_service:base_url"]
        assert "serviceBaseUrl" in resolution.runtime_hint


def _test_resolve_provider_runtime_marks_xhub_local_service_ready() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_local_service_ready_") as base_dir:
        base_url = "http://127.0.0.1:50171"
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "xhub_local_service",
                            "serviceBaseUrl": base_url,
                        },
                    },
                ],
            },
        )

        with fake_xhub_local_service_health(
            {
                "ok": True,
                "status": 200,
                "body": {
                    "ok": True,
                    "status": "ready",
                    "version": "xhub-local-service-dev",
                    "capabilities": ["health", "chat_completions", "embeddings"],
                },
                "text": "",
                "error": "",
            }
        ):
            resolution = resolve_provider_runtime("transformers", base_dir=base_dir)

        assert resolution.runtime_source == "xhub_local_service"
        assert resolution.runtime_source_path == base_url
        assert resolution.runtime_resolution_state == "pack_runtime_ready"
        assert resolution.runtime_reason_code == "xhub_local_service_ready"
        assert resolution.ok is True
        assert resolution.import_error == ""
        assert resolution.missing_requirements == []
        assert "reachable" in resolution.runtime_hint


def _test_resolve_provider_runtime_autostarts_xhub_local_service_and_persists_state() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_local_service_autostart_") as base_dir:
        base_url = "http://127.0.0.1:50171"
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "xhub_local_service",
                            "serviceBaseUrl": base_url,
                        },
                    },
                ],
            },
        )

        with fake_xhub_local_service_autostart() as state:
            resolution = resolve_provider_runtime("transformers", base_dir=base_dir)
            managed_state = xhub_local_service_bridge_module.read_xhub_local_service_state(base_dir)

        assert resolution.runtime_source == "xhub_local_service"
        assert resolution.runtime_source_path == base_url
        assert resolution.runtime_resolution_state == "pack_runtime_ready"
        assert resolution.runtime_reason_code == "xhub_local_service_ready"
        assert resolution.ok is True
        assert len(state["spawn_calls"]) == 1
        assert state["spawn_calls"][0]["bind_host"] == "127.0.0.1"
        assert state["spawn_calls"][0]["bind_port"] == 50171
        assert managed_state["baseUrl"] == base_url
        assert managed_state["bindHost"] == "127.0.0.1"
        assert managed_state["bindPort"] == 50171
        assert managed_state["pid"] == 43001
        assert managed_state["processState"] == "ready"
        assert managed_state["startAttemptCount"] == 1
        assert managed_state["lastProbeAtMs"] > 0
        assert managed_state["lastReadyAtMs"] >= managed_state["lastProbeAtMs"]
        assert resolution.managed_service_state["pid"] == 43001
        assert resolution.managed_service_state["processState"] == "ready"


def _test_resolve_provider_runtime_fail_closes_nonlocal_xhub_local_service_endpoint() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_local_service_nonlocal_") as base_dir:
        base_url = "http://192.168.1.9:50171"
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "xhub_local_service",
                            "serviceBaseUrl": base_url,
                        },
                    },
                ],
            },
        )

        with fake_xhub_local_service_autostart() as state:
            resolution = resolve_provider_runtime("transformers", base_dir=base_dir)
            managed_state = xhub_local_service_bridge_module.read_xhub_local_service_state(base_dir)

        assert resolution.runtime_source == "xhub_local_service"
        assert resolution.runtime_source_path == base_url
        assert resolution.runtime_resolution_state == "runtime_missing"
        assert resolution.runtime_reason_code == "xhub_local_service_nonlocal_endpoint"
        assert resolution.ok is False
        assert resolution.missing_requirements == [f"xhub_local_service:loopback_http_endpoint:{base_url}"]
        assert "loopback" in resolution.runtime_hint.lower()
        assert state["spawn_calls"] == []
        assert managed_state["processState"] == "unsafe_endpoint"
        assert managed_state["lastProbeError"] == "xhub_local_service_nonlocal_endpoint"


def _test_resolve_provider_runtime_reuses_existing_xhub_local_service_state_when_ready() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_local_service_reuse_") as base_dir:
        base_url = "http://127.0.0.1:50171"
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "xhub_local_service",
                            "serviceBaseUrl": base_url,
                        },
                    },
                ],
            },
        )

        with fake_xhub_local_service_autostart() as state:
            first = resolve_provider_runtime("transformers", base_dir=base_dir)
            second = resolve_provider_runtime("transformers", base_dir=base_dir)
            managed_state = xhub_local_service_bridge_module.read_xhub_local_service_state(base_dir)

        assert first.ok is True
        assert second.ok is True
        assert first.runtime_reason_code == "xhub_local_service_ready"
        assert second.runtime_reason_code == "xhub_local_service_ready"
        assert len(state["spawn_calls"]) == 1
        assert managed_state["pid"] == 43001
        assert managed_state["startAttemptCount"] == 1
        assert second.managed_service_state["pid"] == 43001
        assert second.managed_service_state["processState"] == "ready"


def _test_resolve_provider_runtime_reports_missing_helper_binary_bridge() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_missing_") as base_dir:
        missing_path = os.path.join(base_dir, "missing-lms")
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "helper_binary_bridge",
                            "helperBinary": missing_path,
                        },
                    },
                ],
            },
        )

        resolution = resolve_provider_runtime("transformers", base_dir=base_dir)

        assert resolution.runtime_source == "helper_binary_bridge"
        assert resolution.runtime_source_path == missing_path
        assert resolution.runtime_resolution_state == "runtime_missing"
        assert resolution.runtime_reason_code == "helper_binary_missing"
        assert resolution.ok is False
        assert resolution.import_error.startswith("missing_helper_binary:")
        assert resolution.missing_requirements
        assert resolution.missing_requirements[0].startswith("helper_binary:")


def _test_resolve_provider_runtime_reports_helper_service_down() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_service_down_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_fake_lms_helper(helper_path, daemon_status="LM Studio is not running")
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "helper_binary_bridge",
                            "helperBinary": helper_path,
                        },
                    },
                ],
            },
        )

        resolution = resolve_provider_runtime("transformers", base_dir=base_dir)

        assert resolution.runtime_source == "helper_binary_bridge"
        assert resolution.runtime_source_path == helper_path
        assert resolution.runtime_resolution_state == "runtime_missing"
        assert resolution.runtime_reason_code == "helper_service_down"
        assert resolution.ok is False
        assert resolution.import_error == "helper_service_down:lms"
        assert "background service is not running" in resolution.runtime_hint
        assert resolution.missing_requirements == ["helper_service:lms_daemon"]


def _test_resolve_provider_runtime_reports_helper_local_service_disabled() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_service_disabled_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_fake_lms_helper(helper_path, daemon_status="LM Studio is not running")
        _write_fake_lmstudio_settings(
            base_dir,
            enable_local_service=False,
            cli_installed=False,
            app_first_load=True,
        )
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "helper_binary_bridge",
                            "helperBinary": helper_path,
                        },
                    },
                ],
            },
        )

        resolution = resolve_provider_runtime("transformers", base_dir=base_dir)

        assert resolution.runtime_source == "helper_binary_bridge"
        assert resolution.runtime_source_path == helper_path
        assert resolution.runtime_resolution_state == "runtime_missing"
        assert resolution.runtime_reason_code == "helper_local_service_disabled"
        assert resolution.ok is False
        assert resolution.import_error == "helper_local_service_disabled:lms"
        assert "Enable Local Service" in resolution.runtime_hint
        assert resolution.missing_requirements == ["helper_service:lms_local_service_enabled"]


def _test_resolve_provider_runtime_reports_helper_bridge_ready() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_resolver_ready_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_fake_lms_helper(helper_path, daemon_status="LM Studio daemon is running")
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "helper_binary_bridge",
                            "helperBinary": helper_path,
                        },
                    },
                ],
            },
        )

        resolution = resolve_provider_runtime("transformers", base_dir=base_dir)

        assert resolution.runtime_source == "helper_binary_bridge"
        assert resolution.runtime_source_path == helper_path
        assert resolution.runtime_resolution_state == "pack_runtime_ready"
        assert resolution.runtime_reason_code == "helper_bridge_ready"
        assert resolution.ok is True
        assert resolution.import_error == ""
        assert resolution.missing_requirements == []
        assert "Downloaded-model listing and load routing can use this bridge" in resolution.runtime_hint


def _test_resolve_provider_runtime_autostarts_helper_bridge_daemon() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_resolver_autostart_") as base_dir:
        with fake_helper_http_server() as server_port:
            helper_path = os.path.join(base_dir, "lms")
            daemon_ready_path = os.path.join(base_dir, "lms_daemon.ready")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="embedding",
                loaded_vision=False,
                daemon_requires_up=True,
                server_requires_start=False,
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "llama.cpp",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        }
                    ],
                },
            )

            resolution = resolve_provider_runtime(
                "llama.cpp",
                base_dir=base_dir,
                auto_start_runtime_services=True,
            )

        assert resolution.runtime_source == "helper_binary_bridge"
        assert resolution.runtime_source_path == helper_path
        assert resolution.runtime_resolution_state == "pack_runtime_ready"
        assert resolution.runtime_reason_code == "helper_bridge_ready"
        assert resolution.ok is True
        assert resolution.import_error == ""
        assert resolution.missing_requirements == []
        assert os.path.isfile(daemon_ready_path)
        assert "Downloaded-model listing and load routing can use this bridge" in resolution.runtime_hint


def _test_manage_local_model_warmup_supports_helper_bridge_vision_model() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_warmup_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_stateful_fake_lms_helper(helper_path)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "glm4v-local",
                        "name": "GLM4V Local",
                        "backend": "mlx",
                        "runtimeProviderID": "mlx_vlm",
                        "modelPath": "/models/glm4v-local",
                        "taskKinds": ["vision_understand"],
                        "max_context_length": 65536,
                        "default_load_config": {
                            "context_length": 8192,
                            "ttl": 600,
                            "parallel": 2,
                            "identifier": "glm4v-default",
                            "vision": {"image_max_dimension": 3072},
                        },
                    }
                ]
            },
        )
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "mlx_vlm",
                        "runtimeRequirements": {
                            "executionMode": "helper_binary_bridge",
                            "helperBinary": helper_path,
                        },
                    },
                ],
            },
        )

        result = manage_local_model(
            {
                "action": "warmup_local_model",
                "provider": "mlx_vlm",
                "task_kind": "vision_understand",
                "model_id": "glm4v-local",
                "load_profile_override": {
                    "context_length": 4096,
                    "parallel": 4,
                    "identifier": "glm4v-vision-a",
                    "vision": {"image_max_dimension": 2048},
                },
            },
            base_dir=base_dir,
        )
        snapshot = provider_status_snapshot(base_dir)

        assert result["ok"] is True
        assert result["provider"] == "mlx_vlm"
        assert result["action"] == "warmup_local_model"
        assert result["taskKinds"] == ["vision_understand"]
        assert result["deviceBackend"] == "helper_binary_bridge"
        assert result["residencyScope"] == "runtime_process"
        assert result["processScoped"] is False
        assert result["effectiveContextLength"] == 4096
        assert isinstance(result["instanceKey"], str) and result["instanceKey"].startswith("mlx_vlm:glm4v-local:")

        assert snapshot["mlx_vlm"]["ok"] is True
        assert snapshot["mlx_vlm"]["reasonCode"] == "helper_bridge_loaded"
        assert snapshot["mlx_vlm"]["runtimeReasonCode"] == "helper_bridge_ready"
        assert snapshot["mlx_vlm"]["deviceBackend"] == "helper_binary_bridge"
        assert snapshot["mlx_vlm"]["warmupTaskKinds"] == ["vision_understand"]
        assert snapshot["mlx_vlm"]["availableTaskKinds"] == ["vision_understand"]
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["instanceKey"] == result["instanceKey"]
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["modelId"] == "glm4v-local"
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["taskKinds"] == ["vision_understand"]
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["effectiveContextLength"] == 4096
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["maxContextLength"] == 65536
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["ttl"] == 600
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["effectiveLoadProfile"]["ttl"] == 600
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["effectiveLoadProfile"]["parallel"] == 1
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["effectiveLoadProfile"]["identifier"] == "glm4v-vision-a"
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["effectiveLoadProfile"]["vision"]["image_max_dimension"] == 2048
        assert snapshot["mlx_vlm"]["loadedInstances"][0]["deviceBackend"] == "helper_binary_bridge"


def _test_manage_local_model_warmup_prefers_indexed_model_identifier_for_helper_bridge_load() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_indexed_model_ref_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        state_file = os.path.join(base_dir, "lms_state.tsv")
        write_executable(
            helper_path,
            """#!/bin/sh
STATE_FILE="$(dirname "$0")/lms_state.tsv"
cmd="$1"
shift

case "$cmd" in
  daemon)
    if [ "$1" = "status" ]; then
      printf '%s\\n' 'LM Studio daemon is running'
      exit 0
    fi
    ;;
  ls)
    if [ "$1" = "--json" ]; then
      printf '%s\\n' '[{"modelKey":"glm-4.6v-flash","path":"mlx-community/GLM-4.6V-Flash-MLX-4bit","indexedModelIdentifier":"mlx-community/GLM-4.6V-Flash-MLX-4bit","type":"llm","vision":true}]'
      exit 0
    fi
    ;;
  load)
    model_key=""
    identifier=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --identifier)
          identifier="$2"
          shift 2
          ;;
        --context-length|-c|--gpu|--parallel|--ttl)
          shift 2
          ;;
        --estimate-only|--yes)
          shift 1
          ;;
        *)
          if [ -z "$model_key" ]; then
            model_key="$1"
          fi
          shift 1
          ;;
      esac
    done
    [ -n "$identifier" ] || identifier="default"
    printf '%s|%s|0\\n' "$identifier" "$model_key" > "$STATE_FILE"
    printf '%s\\n' 'loaded'
    exit 0
    ;;
  ps)
    if [ "$1" = "--json" ]; then
      if [ -f "$STATE_FILE" ]; then
        IFS='|' read -r identifier model_key context_length < "$STATE_FILE"
        printf '[{"identifier":"%s","modelKey":"%s","path":"%s","type":"llm","vision":true,"contextLength":4096,"lastUsedTime":1742083200000}]\\n' "$identifier" "$model_key" "$model_key"
      else
        printf '[]\\n'
      fi
      exit 0
    fi
    ;;
esac

printf '%s\\n' 'unsupported'
exit 1
""",
        )
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "glm4v-indexed-ref",
                        "name": "GLM4V Indexed Ref",
                        "backend": "mlx",
                        "runtimeProviderID": "mlx_vlm",
                        "modelPath": "/models/glm4v-indexed-ref",
                        "indexedModelIdentifier": "mlx-community/GLM-4.6V-Flash-MLX-4bit",
                        "taskKinds": ["vision_understand"],
                    }
                ]
            },
        )
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "mlx_vlm",
                        "runtimeRequirements": {
                            "executionMode": "helper_binary_bridge",
                            "helperBinary": helper_path,
                        },
                    },
                ],
            },
        )

        result = manage_local_model(
            {
                "action": "warmup_local_model",
                "provider": "mlx_vlm",
                "task_kind": "vision_understand",
                "model_id": "glm4v-indexed-ref",
            },
            base_dir=base_dir,
        )

        assert result["ok"] is True
        with open(state_file, "r", encoding="utf-8") as handle:
            state_rows = [line.strip().split("|") for line in handle if line.strip()]
        assert len(state_rows) == 1
        assert state_rows[0][1] == "glm-4.6v-flash"


def _test_manage_local_model_helper_bridge_unload_and_evict_instances() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_unload_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_stateful_fake_lms_helper(helper_path)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "hf-helper-embed",
                        "name": "HF Helper Embed",
                        "backend": "transformers",
                        "modelPath": "/models/hf-helper-embed",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "helper_binary_bridge",
                            "helperBinary": helper_path,
                        },
                    },
                ],
            },
        )

        first = manage_local_model(
            {
                "action": "warmup_local_model",
                "provider": "transformers",
                "task_kind": "embedding",
                "model_id": "hf-helper-embed",
                "load_profile_override": {
                    "context_length": 8192,
                },
            },
            base_dir=base_dir,
        )
        second = manage_local_model(
            {
                "action": "warmup_local_model",
                "provider": "transformers",
                "task_kind": "embedding",
                "model_id": "hf-helper-embed",
                "load_profile_override": {
                    "context_length": 12288,
                },
            },
            base_dir=base_dir,
        )
        evicted = manage_local_model(
            {
                "action": "evict_local_instance",
                "instance_key": first["instanceKey"],
            },
            base_dir=base_dir,
        )
        after_evict = provider_status_snapshot(base_dir)
        unloaded = manage_local_model(
            {
                "action": "unload_local_model",
                "provider": "transformers",
                "model_id": "hf-helper-embed",
            },
            base_dir=base_dir,
        )
        after_unload = provider_status_snapshot(base_dir)

        assert first["ok"] is True
        assert second["ok"] is True
        assert first["instanceKey"] != second["instanceKey"]

        assert evicted["ok"] is True
        assert evicted["instanceKey"] == first["instanceKey"]
        assert evicted["evictedInstanceCount"] == 1
        assert evicted["processScoped"] is False
        assert len(after_evict["transformers"]["loadedInstances"]) == 1
        remaining = after_evict["transformers"]["loadedInstances"][0]
        assert remaining["instanceKey"] == second["instanceKey"]
        assert remaining["modelId"] == "hf-helper-embed"
        assert remaining["taskKinds"] == ["embedding"]
        assert remaining["loadProfileHash"] == second["loadProfileHash"]
        assert remaining["effectiveContextLength"] == 12288
        assert remaining["maxContextLength"] == 0
        assert remaining["effectiveLoadProfile"]["context_length"] == 12288
        assert remaining["loadedAt"] >= 0.0
        assert remaining["lastUsedAt"] > 0.0
        assert remaining["residency"] == "resident"
        assert remaining["residencyScope"] == "runtime_process"
        assert remaining["deviceBackend"] == "helper_binary_bridge"

        assert unloaded["ok"] is True
        assert unloaded["modelId"] == "hf-helper-embed"
        assert unloaded["unloadedInstanceCount"] == 1
        assert unloaded["processScoped"] is False
        assert after_unload["transformers"]["loadedInstances"] == []
        assert after_unload["transformers"]["ok"] is True
        assert after_unload["transformers"]["reasonCode"] == "helper_bridge_ready"


def _test_manage_local_model_helper_bridge_warmup_infers_task_kinds_without_role() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_infer_role_") as base_dir:
        with fake_helper_http_server() as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="llm",
                loaded_vision=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "glm4v-roleless",
                            "name": "GLM4V Roleless",
                            "backend": "mlx",
                            "runtimeProviderID": "mlx_vlm",
                            "modelPath": "/models/glm4v-roleless",
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "mlx_vlm",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )

            result = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "mlx_vlm",
                    "model_id": "glm4v-roleless",
                },
                base_dir=base_dir,
            )
            snapshot = provider_status_snapshot(base_dir)

            assert result["ok"] is True
            assert result["taskKind"] == "vision_understand"
            assert result["taskKinds"] == ["vision_understand", "ocr"]
            assert set(snapshot["mlx_vlm"]["availableTaskKinds"]) == {"vision_understand", "ocr"}
            assert snapshot["mlx_vlm"]["loadedInstances"][0]["taskKinds"] == ["vision_understand", "ocr"]


def _test_manage_local_model_warmup_supports_helper_bridge_text_model() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_text_warmup_") as base_dir:
        with fake_helper_http_server(vision_text="helper-text-warmup") as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="llm",
                loaded_vision=False,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "helper-text-local",
                            "name": "Helper Text Local",
                            "backend": "transformers",
                            "modelPath": "/models/helper-text-local",
                            "taskKinds": ["text_generate"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "transformers",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )

            result = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "text_generate",
                    "model_id": "helper-text-local",
                    "load_profile_override": {
                        "context_length": 6144,
                    },
                },
                base_dir=base_dir,
            )
            snapshot = provider_status_snapshot(base_dir)

            assert result["ok"] is True
            assert result["taskKind"] == "text_generate"
            assert result["taskKinds"] == ["text_generate"]
            assert result["effectiveContextLength"] == 6144
            assert result["deviceBackend"] == "helper_binary_bridge"

            assert snapshot["transformers"]["ok"] is True
            assert snapshot["transformers"]["reasonCode"] == "helper_bridge_loaded"
            assert snapshot["transformers"]["warmupTaskKinds"] == ["text_generate"]
            assert snapshot["transformers"]["availableTaskKinds"] == ["text_generate"]
            assert snapshot["transformers"]["loadedInstances"][0]["taskKinds"] == ["text_generate"]
            assert snapshot["transformers"]["loadedInstances"][0]["effectiveContextLength"] == 6144


def _test_manage_local_model_warmup_supports_llama_cpp_text_model() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_llama_cpp_text_warmup_") as base_dir:
        with fake_helper_http_server(vision_text="llama-cpp-text-warmup") as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="llm",
                loaded_vision=False,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "qwen3-gguf-local",
                            "name": "Qwen3 GGUF Local",
                            "backend": "llama.cpp",
                            "runtimeProviderID": "llama.cpp",
                            "modelPath": "/models/qwen3-gguf-local",
                            "taskKinds": ["text_generate"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "llama.cpp",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )

            result = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "llama.cpp",
                    "task_kind": "text_generate",
                    "model_id": "qwen3-gguf-local",
                    "load_profile_override": {
                        "context_length": 6144,
                    },
                },
                base_dir=base_dir,
            )
            snapshot = provider_status_snapshot(base_dir)

            assert result["ok"] is True
            assert result["provider"] == "llama.cpp"
            assert result["taskKind"] == "text_generate"
            assert result["taskKinds"] == ["text_generate"]
            assert result["effectiveContextLength"] == 6144
            assert result["deviceBackend"] == "llama.cpp"

            assert snapshot["llama.cpp"]["ok"] is True
            assert snapshot["llama.cpp"]["reasonCode"] == "helper_bridge_loaded"
            assert snapshot["llama.cpp"]["runtimeReasonCode"] == "helper_bridge_ready"
            assert snapshot["llama.cpp"]["deviceBackend"] == "llama.cpp"
            assert snapshot["llama.cpp"]["warmupTaskKinds"] == ["text_generate"]
            assert snapshot["llama.cpp"]["availableTaskKinds"] == ["text_generate"]
            assert snapshot["llama.cpp"]["loadedInstances"][0]["taskKinds"] == ["text_generate"]
            assert snapshot["llama.cpp"]["loadedInstances"][0]["effectiveContextLength"] == 6144
            assert snapshot["llama.cpp"]["loadedInstances"][0]["deviceBackend"] == "llama.cpp"


def _test_manage_local_model_warmup_retries_after_lms_service_wakeup_for_llama_cpp() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_llama_cpp_wakeup_retry_") as base_dir:
        with fake_helper_http_server(embedding_dims=4) as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="embedding",
                loaded_vision=False,
                daemon_requires_up=False,
                server_requires_start=True,
                load_wakes_service_once=True,
                load_requires_server_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "nomic-embed-gguf-local",
                            "name": "Nomic Embed GGUF Local",
                            "backend": "llama.cpp",
                            "runtimeProviderID": "llama.cpp",
                            "modelPath": "/models/nomic-embed-gguf-local.gguf",
                            "indexedModelIdentifier": "nomic-ai/nomic-embed-text-v1.5-GGUF/nomic-embed-text-v1.5.Q4_K_M.gguf",
                            "taskKinds": ["embedding"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "llama.cpp",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )

            result = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "llama.cpp",
                    "task_kind": "embedding",
                    "model_id": "nomic-embed-gguf-local",
                },
                base_dir=base_dir,
            )
            snapshot = provider_status_snapshot(base_dir)

            assert result["ok"] is True
            assert result["provider"] == "llama.cpp"
            assert result["taskKinds"] == ["embedding"]
            assert result["deviceBackend"] == "llama.cpp"
            assert snapshot["llama.cpp"]["ok"] is True
            assert snapshot["llama.cpp"]["availableTaskKinds"] == ["embedding"]
            assert snapshot["llama.cpp"]["loadedInstances"][0]["taskKinds"] == ["embedding"]


def _test_run_local_task_helper_bridge_embedding_autostarts_daemon_and_server() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_embed_task_") as base_dir:
        with fake_helper_http_server(embedding_dims=4) as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="embedding",
                loaded_vision=False,
                daemon_requires_up=True,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "helper-embed-local",
                            "name": "Helper Embed Local",
                            "backend": "transformers",
                            "modelPath": "/models/helper-embed-local",
                            "taskKinds": ["embedding"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "transformers",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )

            warmup = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "embedding",
                    "model_id": "helper-embed-local",
                },
                base_dir=base_dir,
            )
            task = run_local_task(
                {
                    "provider": "transformers",
                    "model_id": "helper-embed-local",
                    "task_kind": "embedding",
                    "texts": ["helper bridge embedding"],
                },
                base_dir=base_dir,
            )

            assert warmup["ok"] is True
            assert task["ok"] is True
            assert task["deviceBackend"] == "helper_binary_bridge"
            assert task["vectorCount"] == 1
            assert task["dims"] == 4
            assert task["fallbackMode"] == ""


def _test_run_local_task_llama_cpp_embedding_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_llama_cpp_embed_task_") as base_dir:
        with fake_helper_http_server(embedding_dims=4) as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="embedding",
                loaded_vision=False,
                daemon_requires_up=True,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "qwen-embed-gguf-local",
                            "name": "Qwen Embed GGUF Local",
                            "backend": "llama.cpp",
                            "runtimeProviderID": "llama.cpp",
                            "modelPath": "/models/qwen-embed-gguf-local",
                            "taskKinds": ["embedding"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "llama.cpp",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )

            warmup = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "llama.cpp",
                    "task_kind": "embedding",
                    "model_id": "qwen-embed-gguf-local",
                },
                base_dir=base_dir,
            )
            task = run_local_task(
                {
                    "provider": "llama.cpp",
                    "model_id": "qwen-embed-gguf-local",
                    "task_kind": "embedding",
                    "texts": ["llama.cpp embedding"],
                },
                base_dir=base_dir,
            )

            assert warmup["ok"] is True
            assert task["ok"] is True
            assert task["provider"] == "llama.cpp"
            assert task["deviceBackend"] == "llama.cpp"
            assert task["vectorCount"] == 1
            assert task["dims"] == 4
            assert task["fallbackMode"] == ""


def _test_run_local_task_llama_cpp_embedding_uses_helper_binary_when_probe_reports_service_down() -> None:
    provider = llama_cpp_provider_module.LlamaCppProvider()
    runtime_resolution = ProviderRuntimeResolution(
        provider_id="llama.cpp",
        runtime_source="helper_binary_bridge",
        runtime_source_path="/tmp/fake-lms",
        runtime_resolution_state="runtime_missing",
        runtime_reason_code="helper_service_down",
        fallback_used=False,
    )
    original_embeddings = llama_cpp_provider_module.helper_bridge_embeddings
    try:
        llama_cpp_provider_module.helper_bridge_embeddings = lambda helper_binary, *, identifier, texts, timeout_sec=20.0: {
            "ok": True,
            "reasonCode": "helper_embedding_ready",
            "error": "",
            "errorDetail": "",
            "vectors": [[0.1, 0.2, 0.3, 0.4]],
            "dims": 4,
            "usage": {},
            "serverBaseUrl": "http://127.0.0.1:1234",
            "model": identifier,
            "autoStartedServer": True,
        }
        provider._runtime_resolution = lambda *, base_dir, request=None: runtime_resolution
        provider._ensure_process_local_tracking = lambda *, base_dir: None
        provider._resolve_model_info = lambda request: {
            "model_id": "qwen-embed-gguf-local",
            "model_path": "/models/qwen-embed-gguf-local.gguf",
        }
        provider._validate_embedding_request = lambda request, *, model_info: ("", {"texts": ["llama.cpp embedding"]})
        provider._helper_bridge_resolve_instance_row = lambda **kwargs: {
            "instanceKey": "llama.cpp:qwen-embed-gguf-local:hash1234",
        }

        task = provider._run_embedding_task(
            {
                "provider": "llama.cpp",
                "model_id": "qwen-embed-gguf-local",
                "task_kind": "embedding",
                "texts": ["llama.cpp embedding"],
                "_base_dir": "/tmp",
            }
        )

        assert task["ok"] is True
        assert task["provider"] == "llama.cpp"
        assert task["deviceBackend"] == "llama.cpp"
        assert task["vectorCount"] == 1
        assert task["dims"] == 4
    finally:
        llama_cpp_provider_module.helper_bridge_embeddings = original_embeddings


def _test_run_local_task_helper_bridge_text_generation_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_text_task_") as base_dir:
        with fake_helper_http_server(vision_text="helper-text-task") as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="llm",
                loaded_vision=False,
                daemon_requires_up=True,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "helper-text-local",
                            "name": "Helper Text Local",
                            "backend": "transformers",
                            "modelPath": "/models/helper-text-local",
                            "taskKinds": ["text_generate"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "transformers",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )

            warmup = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "text_generate",
                    "model_id": "helper-text-local",
                },
                base_dir=base_dir,
            )
            task = run_local_task(
                {
                    "provider": "transformers",
                    "model_id": "helper-text-local",
                    "task_kind": "text_generate",
                    "prompt": "Say hello in one short sentence.",
                },
                base_dir=base_dir,
            )

            assert warmup["ok"] is True
            assert task["ok"] is True
            assert task["taskKind"] == "text_generate"
            assert task["text"] == "helper-text-task"
            assert task["deviceBackend"] == "helper_binary_bridge"
            assert task["fallbackMode"] == ""
            assert task["usage"]["promptTokens"] >= 1
            assert task["usage"]["completionTokens"] >= 1


def _test_run_local_task_helper_bridge_vision_contract_for_mlx_vlm() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_mlx_vlm_vision_task_") as base_dir:
        image_path = os.path.join(base_dir, "scene.png")
        write_png(image_path, width=40, height=22)
        with fake_helper_http_server(
            vision_text="helper-vision-task",
            ocr_text="helper-ocr-task",
        ) as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="llm",
                loaded_vision=True,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "glm4v-helper-local",
                            "name": "GLM4V Helper Local",
                            "backend": "mlx",
                            "runtimeProviderID": "mlx_vlm",
                            "modelPath": "/models/glm4v-helper-local",
                            "taskKinds": ["vision_understand", "ocr"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "mlx_vlm",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )

            warmup = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "mlx_vlm",
                    "model_id": "glm4v-helper-local",
                },
                base_dir=base_dir,
            )
            task = run_local_task(
                {
                    "provider": "mlx_vlm",
                    "model_id": "glm4v-helper-local",
                    "task_kind": "vision_understand",
                    "multimodal_messages": [
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "Summarize the scene briefly."},
                                {"type": "image", "image_path": image_path},
                            ],
                        }
                    ],
                },
                base_dir=base_dir,
            )

            assert warmup["ok"] is True
            assert warmup["taskKinds"] == ["vision_understand", "ocr"]
            assert task["ok"] is True
            assert task["provider"] == "mlx_vlm"
            assert task["taskKind"] == "vision_understand"
            assert task["modelId"] == "glm4v-helper-local"
            assert task["text"] == "helper-vision-task"
            assert task["deviceBackend"] == "helper_binary_bridge"
            assert task["fallbackMode"] == ""
            assert task["usage"]["inputImageWidth"] == 40
            assert task["usage"]["inputImageHeight"] == 22
            assert task["usage"]["inputImagePixels"] == 880
            assert task["routeTrace"]["executionPath"] == "helper_bridge"
            assert task["routeTrace"]["helperBridgeReady"] is True
            assert task["routeTrace"]["multimodalMessageCount"] == 1
            assert task["routeTrace"]["imageCount"] == 1


def _test_run_local_task_helper_bridge_ocr_contract_for_mlx_vlm() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_mlx_vlm_ocr_task_") as base_dir:
        image_path = os.path.join(base_dir, "page.png")
        write_png(image_path, width=64, height=32)
        with fake_helper_http_server(
            vision_text="helper-vision-task",
            ocr_text="helper-ocr-task",
        ) as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="llm",
                loaded_vision=True,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "glm4v-helper-local",
                            "name": "GLM4V Helper Local",
                            "backend": "mlx",
                            "runtimeProviderID": "mlx_vlm",
                            "modelPath": "/models/glm4v-helper-local",
                            "taskKinds": ["vision_understand", "ocr"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "mlx_vlm",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )

            warmup = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "mlx_vlm",
                    "model_id": "glm4v-helper-local",
                },
                base_dir=base_dir,
            )
            task = run_local_task(
                {
                    "provider": "mlx_vlm",
                    "model_id": "glm4v-helper-local",
                    "task_kind": "ocr",
                    "input": {
                        "image_path": image_path,
                    },
                    "options": {
                        "language": "en",
                    },
                },
                base_dir=base_dir,
            )

            assert warmup["ok"] is True
            assert warmup["taskKinds"] == ["vision_understand", "ocr"]
            assert task["ok"] is True
            assert task["provider"] == "mlx_vlm"
            assert task["taskKind"] == "ocr"
            assert task["modelId"] == "glm4v-helper-local"
            assert task["text"] == "helper-ocr-task"
            assert len(task["spans"]) == 1
            assert task["spans"][0]["bbox"]["width"] == 64
            assert task["spans"][0]["bbox"]["height"] == 32
            assert task["deviceBackend"] == "helper_binary_bridge"
            assert task["fallbackMode"] == ""
            assert task["usage"]["inputImageWidth"] == 64
            assert task["usage"]["inputImageHeight"] == 32
            assert task["usage"]["inputImagePixels"] == 2048
            assert task["routeTrace"]["executionPath"] == "helper_bridge"
            assert task["routeTrace"]["helperBridgeReady"] is True
            assert task["routeTrace"]["imageCount"] == 1


def _test_run_local_bench_helper_bridge_vision_infers_task_kind_after_role_free_warmup() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_vision_bench_") as base_dir:
        with fake_helper_http_server(vision_text="helper-vision-bench") as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="llm",
                loaded_vision=True,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "glm4v-bench-roleless",
                            "name": "GLM4V Bench Roleless",
                            "backend": "mlx",
                            "runtimeProviderID": "mlx_vlm",
                            "modelPath": "/models/glm4v-bench-roleless",
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "mlx_vlm",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )
            pack_path = os.path.join(base_dir, "bench_fixture_pack.json")
            _write_bench_fixture_pack(pack_path)

            warmup = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "mlx_vlm",
                    "model_id": "glm4v-bench-roleless",
                },
                base_dir=base_dir,
            )
            result = run_local_bench(
                {
                    "provider": "mlx_vlm",
                    "model_id": "glm4v-bench-roleless",
                    "fixture_pack_path": pack_path,
                    "allow_bench_fallback": False,
                },
                base_dir=base_dir,
            )

            assert warmup["ok"] is True
            assert result["ok"] is True
            assert result["taskKind"] == "vision_understand"
            assert result["reasonCode"] == "ready"
            assert result["fallbackMode"] == ""
            assert "helper-vision-bench" in result["notes"][0]


def _test_manage_local_model_resolves_mlx_vlm_provider_from_catalog_runtime_provider_id() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_mlx_vlm_provider_resolution_") as base_dir:
        helper_path = os.path.join(base_dir, "lms")
        _write_stateful_fake_lms_helper(helper_path)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "glm4v-auto-provider",
                        "name": "GLM4V Auto Provider",
                        "backend": "mlx",
                        "runtimeProviderID": "mlx_vlm",
                        "modelPath": "/models/glm4v-auto-provider",
                        "taskKinds": ["vision_understand"],
                    }
                ]
            },
        )
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "updatedAt": 1742083200.0,
                "packs": [
                    {
                        "providerId": "mlx_vlm",
                        "runtimeRequirements": {
                            "executionMode": "helper_binary_bridge",
                            "helperBinary": helper_path,
                        },
                    },
                ],
            },
        )

        result = manage_local_model(
            {
                "action": "warmup_local_model",
                "model_id": "glm4v-auto-provider",
            },
            base_dir=base_dir,
        )

        assert result["ok"] is True
        assert result["provider"] == "mlx_vlm"
        assert result["taskKinds"] == ["vision_understand"]


def _test_run_local_bench_helper_bridge_text_generation_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_helper_bridge_text_bench_") as base_dir:
        with fake_helper_http_server(vision_text="helper-text-bench") as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="llm",
                loaded_vision=False,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "helper-text-bench-local",
                            "name": "Helper Text Bench Local",
                            "backend": "transformers",
                            "modelPath": "/models/helper-text-bench-local",
                            "taskKinds": ["text_generate"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "transformers",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )
            pack_path = os.path.join(base_dir, "bench_fixture_pack.json")
            _write_bench_fixture_pack(pack_path)

            warmup = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "transformers",
                    "task_kind": "text_generate",
                    "model_id": "helper-text-bench-local",
                },
                base_dir=base_dir,
            )
            result = run_local_bench(
                {
                    "provider": "transformers",
                    "model_id": "helper-text-bench-local",
                    "fixture_pack_path": pack_path,
                    "allow_bench_fallback": False,
                },
                base_dir=base_dir,
            )

            assert warmup["ok"] is True
            assert result["ok"] is True
            assert result["taskKind"] == "text_generate"
            assert result["reasonCode"] == "ready"
            assert result["throughputUnit"] == "tokens_per_sec"
            assert result["generationTokens"] >= 1
            assert result["generationTPS"] > 0
            assert "helper-text-bench" in result["notes"][0]


def _test_run_local_bench_llama_cpp_text_generation_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_py_llama_cpp_text_bench_") as base_dir:
        with fake_helper_http_server(vision_text="llama-cpp-text-bench") as server_port:
            helper_path = os.path.join(base_dir, "lms")
            _write_stateful_fake_lms_helper_with_server(
                helper_path,
                server_port=server_port,
                loaded_type="llm",
                loaded_vision=False,
                server_requires_start=True,
            )
            write_json(
                os.path.join(base_dir, "models_catalog.json"),
                {
                    "models": [
                        {
                            "id": "qwen3-gguf-bench-local",
                            "name": "Qwen3 GGUF Bench Local",
                            "backend": "llama.cpp",
                            "runtimeProviderID": "llama.cpp",
                            "modelPath": "/models/qwen3-gguf-bench-local",
                            "taskKinds": ["text_generate"],
                        }
                    ]
                },
            )
            write_json(
                os.path.join(base_dir, "provider_pack_registry.json"),
                {
                    "schemaVersion": "xhub.provider_pack_registry.v1",
                    "updatedAt": 1742083200.0,
                    "packs": [
                        {
                            "providerId": "llama.cpp",
                            "runtimeRequirements": {
                                "executionMode": "helper_binary_bridge",
                                "helperBinary": helper_path,
                            },
                        },
                    ],
                },
            )
            pack_path = os.path.join(base_dir, "bench_fixture_pack.json")
            _write_bench_fixture_pack(pack_path)

            warmup = manage_local_model(
                {
                    "action": "warmup_local_model",
                    "provider": "llama.cpp",
                    "task_kind": "text_generate",
                    "model_id": "qwen3-gguf-bench-local",
                },
                base_dir=base_dir,
            )
            result = run_local_bench(
                {
                    "provider": "llama.cpp",
                    "model_id": "qwen3-gguf-bench-local",
                    "fixture_pack_path": pack_path,
                    "allow_bench_fallback": False,
                },
                base_dir=base_dir,
            )

            assert warmup["ok"] is True
            assert result["ok"] is True
            assert result["provider"] == "llama.cpp"
            assert result["taskKind"] == "text_generate"
            assert result["reasonCode"] == "ready"
            assert result["fallbackMode"] == ""
            assert result["throughputUnit"] == "tokens_per_sec"
            assert result["generationTokens"] >= 1
            assert result["generationTPS"] > 0
            assert "llama-cpp-text-bench" in result["notes"][0]


def _test_run_legacy_runtime_treats_none_exit_code_as_success() -> None:
    fake_runtime = types.SimpleNamespace(main=lambda: None)
    with temporary_modules({"relflowhub_mlx_runtime": fake_runtime}):
        assert run_legacy_runtime() == 0


def _test_sync_state_from_provider_statuses_reconciles_stale_mlx_loaded_models() -> None:
    state = {
        "models": [
            {
                "id": "qwen-local",
                "backend": "mlx",
                "runtimeProviderID": "mlx",
                "modelPath": "/models/qwen-local",
                "state": "loaded",
                "memoryBytes": 2048,
                "tokensPerSec": 18.0,
            }
        ]
    }

    synced, changed = _sync_state_from_provider_statuses(
        state,
        {
            "mlx": {
                "loadedModels": [],
                "loadedInstances": [],
            }
        },
    )

    assert changed is True
    assert synced["models"][0]["state"] == "available"
    assert synced["models"][0]["memoryBytes"] is None
    assert synced["models"][0]["tokensPerSec"] is None
    assert synced["models"][0]["offlineReady"] is False
    assert synced["models"][0]["reasonCode"] == "model_path_missing"


def _test_sync_state_from_provider_statuses_keeps_existing_local_paths_offline_ready() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_sync_state_model_path_") as model_dir:
        state = {
            "models": [
                {
                    "id": "qwen-local",
                    "backend": "mlx",
                    "runtimeProviderID": "mlx",
                    "modelPath": model_dir,
                    "state": "available",
                    "memoryBytes": None,
                    "tokensPerSec": None,
                    "offlineReady": False,
                    "reasonCode": "model_path_missing",
                }
            ]
        }

        synced, changed = _sync_state_from_provider_statuses(
            state,
            {
                "mlx": {
                    "loadedModels": [],
                    "loadedInstances": [],
                }
            },
        )

    assert changed is True
    assert synced["models"][0]["state"] == "available"
    assert synced["models"][0]["offlineReady"] is True
    assert "reasonCode" not in synced["models"][0]


def _test_bridge_base_dir_prefers_fresh_writable_public_ipc_when_group_dir_is_read_only() -> None:
    import relflowhub_mlx_runtime as mlx_runtime_entry

    with tempfile.TemporaryDirectory(prefix="xhub_py_bridge_base_dir_") as temp_root:
        group_dir = os.path.join(temp_root, "group.rel.flowhub")
        public_dir = os.path.join(temp_root, "RELFlowHub")
        os.makedirs(group_dir, exist_ok=True)
        os.makedirs(public_dir, exist_ok=True)

        now = time.time()
        write_json(
            os.path.join(group_dir, "bridge_status.json"),
            {
                "updatedAt": now,
                "enabledUntil": now + 60.0,
            },
        )
        write_json(
            os.path.join(public_dir, "bridge_status.json"),
            {
                "updatedAt": now,
                "enabledUntil": now + 60.0,
            },
        )

        original_group = mlx_runtime_entry._group_base_dir
        original_public = mlx_runtime_entry._public_base_dir
        os.chmod(group_dir, 0o555)
        try:
            mlx_runtime_entry._group_base_dir = lambda: group_dir
            mlx_runtime_entry._public_base_dir = lambda: public_dir
            resolved = mlx_runtime_entry._bridge_base_dir(group_dir)
        finally:
            mlx_runtime_entry._group_base_dir = original_group
            mlx_runtime_entry._public_base_dir = original_public
            os.chmod(group_dir, 0o755)

        assert resolved == public_dir


def _test_bridge_ai_generate_uses_public_ipc_when_group_dir_is_read_only() -> None:
    import relflowhub_mlx_runtime as mlx_runtime_entry

    with tempfile.TemporaryDirectory(prefix="xhub_py_bridge_ai_generate_") as temp_root:
        group_dir = os.path.join(temp_root, "group.rel.flowhub")
        public_dir = os.path.join(temp_root, "RELFlowHub")
        os.makedirs(group_dir, exist_ok=True)
        os.makedirs(public_dir, exist_ok=True)

        now = time.time()
        status_payload = {
            "updatedAt": now,
            "enabledUntil": now + 60.0,
        }
        write_json(os.path.join(group_dir, "bridge_status.json"), status_payload)
        write_json(os.path.join(public_dir, "bridge_status.json"), status_payload)

        original_group = mlx_runtime_entry._group_base_dir
        original_public = mlx_runtime_entry._public_base_dir
        os.chmod(group_dir, 0o555)

        def respond() -> None:
            req_dir = os.path.join(public_dir, "bridge_requests")
            resp_dir = os.path.join(public_dir, "bridge_responses")
            deadline = time.time() + 2.0
            while time.time() < deadline:
                if os.path.isdir(req_dir):
                    for name in os.listdir(req_dir):
                        if not name.startswith("req_") or not name.endswith(".json"):
                            continue
                        req_path = os.path.join(req_dir, name)
                        with open(req_path, "r", encoding="utf-8") as handle:
                            req_obj = json.load(handle)
                        os.makedirs(resp_dir, exist_ok=True)
                        write_json(
                            os.path.join(resp_dir, f"resp_{req_obj['req_id']}.json"),
                            {
                                "ok": True,
                                "text": "bridge-ok",
                                "usage": {"output_tokens": 12},
                                "error": "",
                            },
                        )
                        return
                time.sleep(0.02)

        responder = threading.Thread(target=respond, daemon=True)
        responder.start()
        try:
            mlx_runtime_entry._group_base_dir = lambda: group_dir
            mlx_runtime_entry._public_base_dir = lambda: public_dir
            ok, text, usage, error = mlx_runtime_entry._bridge_ai_generate(
                group_dir,
                req_id="req-bridge-public",
                model_id="gpt-5.4",
                prompt="hello",
                max_tokens=32,
                temperature=0.0,
                top_p=1.0,
                timeout_sec=1.5,
            )
        finally:
            mlx_runtime_entry._group_base_dir = original_group
            mlx_runtime_entry._public_base_dir = original_public
            os.chmod(group_dir, 0o755)
            responder.join(timeout=1.0)

        assert ok is True
        assert text == "bridge-ok"
        assert usage["output_tokens"] == 12
        assert error == ""
        assert os.path.isdir(os.path.join(public_dir, "bridge_requests"))
        assert os.path.isdir(os.path.join(public_dir, "bridge_responses"))
        assert not os.path.exists(os.path.join(group_dir, "bridge_requests"))
        assert not os.path.exists(os.path.join(group_dir, "bridge_responses"))


run("provider_status_snapshot keeps MLX compatibility and exposes provider registry", lambda: _test_provider_status_snapshot())
run("run_legacy_runtime treats None exit codes as success", lambda: _test_run_legacy_runtime_treats_none_exit_code_as_success())
run("helper binary bridge probe detects installed LM Studio helper when its service is down", lambda: _test_helper_binary_bridge_probe_detects_lms_service_down())
run("helper binary bridge probe reports LM Studio local service disabled from settings", lambda: _test_helper_binary_bridge_probe_detects_lms_local_service_disabled())
run("helper binary bridge probe lists local and loaded models when LM Studio helper is ready", lambda: _test_helper_binary_bridge_probe_lists_models_when_lms_is_ready())
run("helper binary bridge probe trusts LM Studio JSON daemon status over stale text status", lambda: _test_helper_binary_bridge_probe_prefers_json_running_status_over_stale_text_status())
run("xhub_local_service probe reports config missing without default endpoint assumptions", lambda: _test_xhub_local_service_probe_reports_config_missing())
run("xhub_local_service probe reports an unreachable Hub-managed local service endpoint", lambda: _test_xhub_local_service_probe_reports_unreachable_service())
run("xhub_local_service probe marks a ready Hub-managed local service endpoint usable", lambda: _test_xhub_local_service_probe_reports_ready_service())
run("resolve_provider_runtime reports missing xhub_local_service configuration explicitly", lambda: _test_resolve_provider_runtime_reports_xhub_local_service_config_missing())
run("resolve_provider_runtime marks xhub_local_service execution mode ready when /health passes", lambda: _test_resolve_provider_runtime_marks_xhub_local_service_ready())
run("resolve_provider_runtime can autostart xhub_local_service and persist managed state", lambda: _test_resolve_provider_runtime_autostarts_xhub_local_service_and_persists_state())
run("resolve_provider_runtime fail-closes non-loopback xhub_local_service endpoints", lambda: _test_resolve_provider_runtime_fail_closes_nonlocal_xhub_local_service_endpoint())
run("resolve_provider_runtime reuses an already managed xhub_local_service state when ready", lambda: _test_resolve_provider_runtime_reuses_existing_xhub_local_service_state_when_ready())
run("manage_local_model resolves mlx_vlm from catalog runtime provider override", lambda: _test_manage_local_model_resolves_mlx_vlm_provider_from_catalog_runtime_provider_id())
run("resolve_provider_runtime reports missing helper binary bridge explicitly", lambda: _test_resolve_provider_runtime_reports_missing_helper_binary_bridge())
run("resolve_provider_runtime reports helper service down without falling back to missing_module", lambda: _test_resolve_provider_runtime_reports_helper_service_down())
run("resolve_provider_runtime reports LM Studio local service disabled explicitly", lambda: _test_resolve_provider_runtime_reports_helper_local_service_disabled())
run("resolve_provider_runtime marks helper bridge execution mode ready when daemon probe passes", lambda: _test_resolve_provider_runtime_reports_helper_bridge_ready())
run("resolve_provider_runtime can autostart a helper bridge daemon before declaring the provider unavailable", lambda: _test_resolve_provider_runtime_autostarts_helper_bridge_daemon())
run("manage_local_model warmup can load a vision model through helper bridge and expose it in snapshot", lambda: _test_manage_local_model_warmup_supports_helper_bridge_vision_model())
run("manage_local_model warmup prefers indexedModelIdentifier for helper bridge load routing", lambda: _test_manage_local_model_warmup_prefers_indexed_model_identifier_for_helper_bridge_load())
run("manage_local_model can evict and unload helper bridge instances without process-local cache", lambda: _test_manage_local_model_helper_bridge_unload_and_evict_instances())
run("manage_local_model warmup can infer helper bridge task kinds without a role hint", lambda: _test_manage_local_model_helper_bridge_warmup_infers_task_kinds_without_role())
run("manage_local_model warmup can load a text-generation model through helper bridge and expose it in snapshot", lambda: _test_manage_local_model_warmup_supports_helper_bridge_text_model())
run("manage_local_model warmup can load a llama.cpp text model through helper bridge and expose it in snapshot", lambda: _test_manage_local_model_warmup_supports_llama_cpp_text_model())
run("run_local_task executes helper bridge embedding through an auto-started helper server", lambda: _test_run_local_task_helper_bridge_embedding_autostarts_daemon_and_server())
run("run_local_task executes llama.cpp embedding through helper bridge", lambda: _test_run_local_task_llama_cpp_embedding_contract())
run("run_local_task keeps llama.cpp helper embedding available when runtime probe is stale", lambda: _test_run_local_task_llama_cpp_embedding_uses_helper_binary_when_probe_reports_service_down())
run("run_local_task executes helper bridge text generation through chat completion", lambda: _test_run_local_task_helper_bridge_text_generation_contract())
run("run_local_task executes mlx_vlm vision_understand through helper bridge multimodal chat", lambda: _test_run_local_task_helper_bridge_vision_contract_for_mlx_vlm())
run("run_local_task executes mlx_vlm ocr through helper bridge multimodal chat", lambda: _test_run_local_task_helper_bridge_ocr_contract_for_mlx_vlm())
run("run_local_bench infers helper bridge vision task kind after role-free warmup and records a real result", lambda: _test_run_local_bench_helper_bridge_vision_infers_task_kind_after_role_free_warmup())
run("run_local_bench executes helper bridge text generation quick bench and records a real result", lambda: _test_run_local_bench_helper_bridge_text_generation_contract())
run("run_local_bench executes llama.cpp text generation quick bench and records a real result", lambda: _test_run_local_bench_llama_cpp_text_generation_contract())
run("provider pack inventory exposes builtin llama.cpp helper manifest", lambda: _test_provider_pack_inventory_exposes_builtin_llama_cpp_manifest())
run("provider pack registry can disable providers fail-closed while preserving version truth", lambda: _test_provider_pack_registry_overrides_version_and_disables_provider_execution())
run("provider_status_snapshot exposes llama.cpp helper runtime truth for gguf models", lambda: _test_provider_status_snapshot_exposes_llama_cpp_helper_runtime_truth_for_gguf_models())
run("run_local_task preserves MLX legacy delegation contract", lambda: _test_run_local_task_mlx_delegate())
run("mlx provider healthcheck preserves import error diagnostics", lambda: _test_mlx_provider_import_error())
run("mlx provider healthcheck without runtime uses safe probe instead of module presence", lambda: _test_mlx_provider_without_runtime_uses_safe_probe_result())
run("legacy runtime status writer keeps mlxOk while merging provider statuses", lambda: _test_runtime_status_writer_merge())
run("local runtime status mirror paths only publish from home runtimes", lambda: _test_runtime_status_mirror_paths_skip_container_and_public_bases())
run("local runtime status publisher mirrors home snapshots into sandbox-visible fallback locations", lambda: _test_publish_runtime_status_mirrors_home_runtime_snapshot_into_fallback_locations())
run("provider status sync clears stale MLX loaded state when runtime inventory is empty", lambda: _test_sync_state_from_provider_statuses_reconciles_stale_mlx_loaded_models())
run("provider status sync restores offline readiness when a local model path is present again", lambda: _test_sync_state_from_provider_statuses_keeps_existing_local_paths_offline_ready())
run("bridge base dir prefers fresh writable public IPC when app-group dir is read-only", lambda: _test_bridge_base_dir_prefers_fresh_writable_public_ipc_when_group_dir_is_read_only())
run("bridge ai_generate uses public IPC when app-group dir is read-only", lambda: _test_bridge_ai_generate_uses_public_ipc_when_group_dir_is_read_only())
run("mlx runtime probe failure stays fail-closed without killing provider-aware startup", lambda: _test_mlx_runtime_probe_failure_stays_fail_closed_without_importing_runtime())
run("mlx runtime probe skips unsafe Xcode python before spawning a child probe", lambda: _test_mlx_runtime_probe_skips_unsafe_xcode_python_without_spawning_probe())
run("mlx runtime keeps load-profile instances isolated while sharing one physical load", lambda: _test_mlx_runtime_load_profile_instances_share_physical_load())
run("mlx runtime applies effective context length to generate and bench max_kv_size", lambda: _test_mlx_runtime_generate_and_bench_apply_effective_context_length())
run("mlx provider healthcheck exposes loaded instance inventory machine-readably", lambda: _test_mlx_provider_healthcheck_exposes_loaded_instances_machine_readably())
run("transformers embedding contract executes with explicit offline hash fallback", lambda: _test_transformers_embedding_hash_fallback_contract())
run("transformers embedding runtime failure exposes resolver metadata on task results", lambda: _test_transformers_embedding_runtime_failure_exposes_runtime_resolution_fields())
run("transformers embedding runtime surfaces unsupported quantization configs fail-closed", lambda: _test_transformers_embedding_quantization_config_failure_classifies_reason_code())
run("transformers speech_to_text contract executes with explicit offline wav fallback", lambda: _test_transformers_asr_fallback_contract())
run("transformers speech_to_text validator rejects overlong audio fail-closed", lambda: _test_transformers_asr_guard_rejects_overlong_audio())
run("transformers speech_to_text real runtime coerces wav samples to numpy arrays for pipeline compatibility", lambda: _test_transformers_asr_real_runtime_coerces_samples_to_numpy_array_when_available())
run("transformers speech_to_text runtime strips loader-only forward params before first real call", lambda: _test_transformers_asr_runtime_strips_loader_only_forward_params())
run("transformers text_to_speech stays fail-closed when system fallback is disabled", lambda: _test_transformers_tts_contract_fails_closed_when_system_fallback_is_disabled())
run("transformers text_to_speech returns an audio path when system fallback is enabled", lambda: _test_transformers_tts_contract_returns_audio_path_when_system_fallback_is_enabled())
run("transformers text_to_speech executes Kokoro natively when runtime is available", lambda: _test_transformers_tts_kokoro_native_contract())
run("transformers text_to_speech preserves fallback reason when Kokoro deps are missing", lambda: _test_transformers_tts_kokoro_missing_dependency_falls_back_when_allowed())
run("transformers text_to_speech routes zh bright requests to Kokoro clear speaker candidates", lambda: _test_transformers_tts_kokoro_routes_zh_bright_to_clear_speaker_from_filesystem())
run("transformers text_to_speech routes en calm requests to Kokoro calm speaker candidates", lambda: _test_transformers_tts_kokoro_routes_en_calm_to_expected_speaker())
run("transformers text_to_speech health stays unavailable when system fallback is disabled", lambda: _test_transformers_tts_healthcheck_reports_unavailable_when_system_fallback_is_disabled())
run("transformers text_to_speech health reports ready when Kokoro runtime is available", lambda: _test_transformers_tts_healthcheck_reports_native_ready_when_kokoro_runtime_is_available())
run("transformers text_to_speech health reports fallback_ready when system fallback is enabled", lambda: _test_transformers_tts_healthcheck_reports_fallback_ready_when_system_fallback_is_enabled())
run("transformers vision readiness requires real runtime by default and can still advertise explicit fallback", lambda: _test_transformers_vision_healthcheck_requires_real_runtime_by_default())
run("transformers warmup runtime failure preserves task kinds and optional runtime requirements", lambda: _test_transformers_warmup_runtime_failure_preserves_task_kinds_and_optional_runtime_requirements())
run("transformers vision_understand contract executes through the real image runtime when available", lambda: _test_transformers_vision_real_contract())
run("transformers ocr contract executes through the real image runtime when available", lambda: _test_transformers_ocr_real_contract())
run("transformers image validator rejects oversize dimensions fail-closed", lambda: _test_transformers_image_guard_rejects_overlarge_dimensions())
run("transformers image validator honors effective load-profile image max dimension", lambda: _test_transformers_image_guard_uses_effective_load_profile_image_dimension())
run("provider_status_snapshot exposes resource policy and scheduler telemetry", lambda: _test_provider_status_snapshot_exposes_resource_policy_and_scheduler_state())
run("provider_status_snapshot exposes real and fallback task metadata for monitor views", lambda: _test_provider_status_snapshot_exposes_real_and_fallback_task_metadata())
run("provider_status_snapshot exposes lifecycle contract metadata for MLX legacy and warmable transformers", lambda: _test_provider_status_snapshot_exposes_lifecycle_contract_metadata())
run("provider_status_snapshot exposes runtime resolution state and install hint", lambda: _test_provider_status_snapshot_exposes_runtime_resolution_state_and_hint())
run("provider_status_snapshot marks Hub py_deps modules as pack runtime ready", lambda: _test_provider_status_snapshot_marks_hub_py_deps_runtime_as_pack_ready())
run("provider_status_snapshot can mark transformers as runtime-resident when the daemon owns them", lambda: _test_provider_status_snapshot_marks_runtime_resident_transformers_when_requested())
run("runtime status proxy support requires a fresh local command IPC marker", lambda: _test_runtime_status_proxy_support_requires_fresh_ipc_marker())
run("runtime command proxy round-trips requests and responses through file IPC", lambda: _test_proxy_runtime_command_round_trip_through_file_ipc())
run("main manage-local-model command prefers daemon proxy when the runtime marker is fresh", lambda: _test_main_manage_local_model_prefers_daemon_proxy_when_available())
run("main run-local-bench command bypasses daemon proxy when the request disables it", lambda: _test_main_run_local_bench_skips_daemon_proxy_when_request_disables_it())
run("run_local_task rejects new work when provider slot is already occupied", lambda: _test_run_local_task_rejects_when_provider_slot_is_busy())
run("run_local_task returns queue timeout when provider slot stays busy", lambda: _test_run_local_task_queue_timeout_when_provider_slot_stays_busy())
run("run_local_task can wait for a provider slot and then execute", lambda: _test_run_local_task_waits_then_executes_when_provider_slot_frees())
run("run_local_task resolves device-scoped load profile identity and runtime instance key", lambda: _test_run_local_task_resolves_device_scoped_load_profile_identity())
run("scheduler telemetry exposes device-scoped load profile identity for active leases", lambda: _test_scheduler_telemetry_tracks_instance_key_and_load_profile_hash())
run("scheduler telemetry exposes oldest waiter age for queue monitor", lambda: _test_scheduler_telemetry_exposes_oldest_waiter_age())
run("runtime status payload exposes monitor snapshot contract", lambda: _test_runtime_status_payload_exposes_monitor_snapshot())
run("transformers embedding cache uses instance_key to isolate load profile variants", lambda: _test_transformers_embedding_cache_isolated_by_instance_key())
run("run_local_bench executes task-aware embedding quick bench and persists schema v2 result", lambda: _test_run_local_bench_embedding_contract_persists_result())
run("run_local_bench exposes resolver metadata when transformers runtime is missing", lambda: _test_run_local_bench_runtime_failure_exposes_runtime_resolution_fields())
run("run_local_bench executes task-aware vision quick bench and persists schema v2 result", lambda: _test_run_local_bench_vision_contract_persists_result())
run("run_local_bench keeps text_to_speech quick bench fail-closed when system fallback is disabled", lambda: _test_run_local_bench_tts_contract_fails_closed_when_system_fallback_is_disabled())
run("run_local_bench reports text_to_speech fallback-ready when system fallback is enabled", lambda: _test_run_local_bench_tts_reports_fallback_ready_when_system_fallback_is_enabled())
run("run_local_bench fails closed when requested fixture profile is missing", lambda: _test_run_local_bench_fails_closed_when_fixture_missing())
run("manage_local_model warmup contract succeeds for warmable transformers embedding models", lambda: _test_manage_local_model_warmup_contract_for_transformers_embedding())
run("manage_local_model can evict one instance and unload remaining transformers model caches", lambda: _test_manage_local_model_unload_and_evict_transformers_instances())
run("transformers loaded instance inventory exposes manual eviction semantics machine-readably", lambda: _test_transformers_loaded_instance_inventory_and_idle_eviction_state())
run("transformers process-local inventory marks process exit as explicit eviction", lambda: _test_transformers_process_exit_marks_inventory_as_evicted())
run("manage_local_model warmup supports transformers vision when the runtime is available", lambda: _test_manage_local_model_warmup_supports_transformers_vision_when_runtime_is_available())
run("manage_local_model keeps MLX legacy lifecycle paths fail-closed", lambda: _test_manage_local_model_mlx_legacy_fails_closed())
run("routing_settings schema v2 resolves device override before hub default", lambda: _test_routing_settings_schema_v2_resolves_device_and_hub_defaults())
run("routing_settings legacy map remains backward compatible", lambda: _test_routing_settings_legacy_map_stays_backward_compatible())
