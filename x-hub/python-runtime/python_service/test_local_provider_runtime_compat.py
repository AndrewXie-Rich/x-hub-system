from __future__ import annotations

import json
import os
import sys
import tempfile
import threading
import time
import wave
from contextlib import contextmanager
from typing import Any


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if THIS_DIR not in sys.path:
    sys.path.insert(0, THIS_DIR)

from providers.mlx_provider import MLXProvider
from local_provider_scheduler import acquire_provider_slot, release_provider_slot
from relflowhub_local_runtime import provider_status_snapshot, run_local_task
from relflowhub_mlx_runtime import _runtime_status_path, _write_runtime_status


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
    payload = bytearray()
    payload.extend(b"\x89PNG\r\n\x1a\n")
    payload.extend((13).to_bytes(4, "big", signed=False))
    payload.extend(b"IHDR")
    payload.extend(int(width).to_bytes(4, "big", signed=False))
    payload.extend(int(height).to_bytes(4, "big", signed=False))
    payload.extend(b"\x08\x02\x00\x00\x00")
    payload.extend(b"\x00\x00\x00\x00")
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


class StubMLXRuntime:
    def __init__(
        self,
        *,
        ok: bool,
        import_error: str = "",
        loaded: dict[str, Any] | None = None,
        memory_pair: tuple[int, int] = (0, 0),
    ) -> None:
        self._mlx_ok = ok
        self._import_error = import_error
        self._loaded = dict(loaded or {})
        self._memory_pair = tuple(memory_pair)

    def memory_bytes(self) -> tuple[int, int]:
        return self._memory_pair


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
        assert snapshot["transformers"]["provider"] == "transformers"
        assert "hf-embed" in snapshot["transformers"]["registeredModels"]


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


def _test_transformers_vision_preview_healthcheck_requires_explicit_fallback() -> None:
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
        assert without_env["transformers"]["reasonCode"] == "preview_disabled"

        with temporary_env("XHUB_TRANSFORMERS_ALLOW_VISION_FALLBACK", "1"):
            with_env = provider_status_snapshot(base_dir)

        assert "vision_understand" in list(with_env["transformers"].get("availableTaskKinds") or [])
        assert with_env["transformers"]["reasonCode"] == "fallback_ready"


def _test_transformers_vision_preview_contract() -> None:
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
        with temporary_env("XHUB_TRANSFORMERS_ALLOW_VISION_FALLBACK", "1"):
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
        assert result["fallbackMode"] == "image_hash_preview"
        assert isinstance(result["text"], str) and result["text"].startswith("[offline_vision_preview:")
        assert "24x18" in result["text"]
        assert result["usage"]["inputImageWidth"] == 24
        assert result["usage"]["inputImageHeight"] == 18
        assert result["usage"]["inputImagePixels"] == 432


def _test_transformers_ocr_preview_contract() -> None:
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
        with temporary_env("XHUB_TRANSFORMERS_ALLOW_VISION_FALLBACK", "1"):
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
        assert result["fallbackMode"] == "image_hash_preview"
        assert isinstance(result["text"], str) and result["text"].startswith("[offline_ocr_preview:")
        assert len(result["spans"]) == 1
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


run("provider_status_snapshot keeps MLX compatibility and exposes provider registry", lambda: _test_provider_status_snapshot())
run("run_local_task preserves MLX legacy delegation contract", lambda: _test_run_local_task_mlx_delegate())
run("mlx provider healthcheck preserves import error diagnostics", lambda: _test_mlx_provider_import_error())
run("legacy runtime status writer keeps mlxOk while merging provider statuses", lambda: _test_runtime_status_writer_merge())
run("transformers embedding contract executes with explicit offline hash fallback", lambda: _test_transformers_embedding_hash_fallback_contract())
run("transformers speech_to_text contract executes with explicit offline wav fallback", lambda: _test_transformers_asr_fallback_contract())
run("transformers speech_to_text validator rejects overlong audio fail-closed", lambda: _test_transformers_asr_guard_rejects_overlong_audio())
run("transformers vision readiness stays fail-closed until explicit preview fallback is enabled", lambda: _test_transformers_vision_preview_healthcheck_requires_explicit_fallback())
run("transformers vision_understand contract executes with explicit offline image preview fallback", lambda: _test_transformers_vision_preview_contract())
run("transformers ocr contract executes with explicit offline image preview fallback", lambda: _test_transformers_ocr_preview_contract())
run("transformers image validator rejects oversize dimensions fail-closed", lambda: _test_transformers_image_guard_rejects_overlarge_dimensions())
run("provider_status_snapshot exposes resource policy and scheduler telemetry", lambda: _test_provider_status_snapshot_exposes_resource_policy_and_scheduler_state())
run("run_local_task rejects new work when provider slot is already occupied", lambda: _test_run_local_task_rejects_when_provider_slot_is_busy())
run("run_local_task returns queue timeout when provider slot stays busy", lambda: _test_run_local_task_queue_timeout_when_provider_slot_stays_busy())
run("run_local_task can wait for a provider slot and then execute", lambda: _test_run_local_task_waits_then_executes_when_provider_slot_frees())
