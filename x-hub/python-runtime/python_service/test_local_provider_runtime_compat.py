from __future__ import annotations

import json
import os
import sys
import tempfile
from typing import Any


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if THIS_DIR not in sys.path:
    sys.path.insert(0, THIS_DIR)

from providers.mlx_provider import MLXProvider
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
        assert "embedding" in snapshot["transformers"]["availableTaskKinds"]


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


run("provider_status_snapshot keeps MLX compatibility and exposes provider registry", lambda: _test_provider_status_snapshot())
run("run_local_task preserves MLX legacy delegation contract", lambda: _test_run_local_task_mlx_delegate())
run("mlx provider healthcheck preserves import error diagnostics", lambda: _test_mlx_provider_import_error())
run("legacy runtime status writer keeps mlxOk while merging provider statuses", lambda: _test_runtime_status_writer_merge())
