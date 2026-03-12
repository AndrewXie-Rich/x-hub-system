from __future__ import annotations

import importlib.util
import time
from typing import Any

from .base import LocalProvider, ProviderHealth


def _legacy_runtime_version() -> str:
    try:
        from relflowhub_mlx_runtime import RUNTIME_VERSION

        return str(RUNTIME_VERSION)
    except Exception:
        return "unknown"


class MLXProvider(LocalProvider):
    def __init__(self, *, runtime: Any | None = None, runtime_version: str = "") -> None:
        self._runtime = runtime
        self._runtime_version = str(runtime_version or "").strip()

    def provider_id(self) -> str:
        return "mlx"

    def supported_task_kinds(self) -> list[str]:
        return ["text_generate"]

    def supported_input_modalities(self) -> list[str]:
        return ["text"]

    def supported_output_modalities(self) -> list[str]:
        return ["text"]

    def healthcheck(self, *, base_dir: str, catalog_models: list[dict[str, Any]]) -> ProviderHealth:
        del base_dir

        runtime = self._runtime
        import_error = ""
        ok = False
        loaded_models: list[str] = []
        active_memory_bytes: int | None = None
        peak_memory_bytes: int | None = None
        loaded_model_count: int | None = None

        if runtime is not None:
            ok = bool(getattr(runtime, "_mlx_ok", False))
            import_error = str(getattr(runtime, "_import_error", "") or "").strip()
            loaded = getattr(runtime, "_loaded", {}) or {}
            if isinstance(loaded, dict):
                loaded_models = sorted(str(model_id) for model_id in loaded.keys() if str(model_id or "").strip())
                loaded_model_count = len(loaded_models)
            memory_bytes = getattr(runtime, "memory_bytes", None)
            if callable(memory_bytes):
                try:
                    active_memory_bytes, peak_memory_bytes = memory_bytes()
                except Exception:
                    active_memory_bytes = None
                    peak_memory_bytes = None
        else:
            missing_modules = [
                module_name
                for module_name in ("mlx", "mlx_lm")
                if importlib.util.find_spec(module_name) is None
            ]
            if missing_modules:
                import_error = f"missing_modules:{','.join(missing_modules)}"
            else:
                ok = True
            loaded_model_count = 0

        runtime_version = self._runtime_version or _legacy_runtime_version()
        registered_models = [
            str(model.get("id") or "").strip()
            for model in self.list_registered_models(catalog_models=catalog_models)
            if str(model.get("id") or "").strip()
        ]

        return ProviderHealth(
            provider=self.provider_id(),
            ok=ok,
            reason_code="ready" if ok else ("import_error" if import_error else "unavailable"),
            runtime_version=runtime_version,
            available_task_kinds=self.supported_task_kinds() if ok else [],
            loaded_models=loaded_models,
            device_backend="mps",
            updated_at=time.time(),
            import_error=import_error,
            active_memory_bytes=active_memory_bytes,
            peak_memory_bytes=peak_memory_bytes,
            loaded_model_count=loaded_model_count,
            registered_models=registered_models,
        )

    def run_task(self, request: dict[str, Any]) -> dict[str, Any]:
        task_kind = str(request.get("task_kind") or request.get("taskKind") or "").strip().lower()
        if task_kind and task_kind not in self.supported_task_kinds():
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "error": f"unsupported_task_kind:{task_kind}",
                "request": dict(request or {}),
            }
        return {
            "ok": False,
            "provider": self.provider_id(),
            "taskKind": task_kind or "text_generate",
            "error": "delegate_to_runtime_loop:mlx",
            "request": dict(request or {}),
        }


def run_legacy_runtime() -> int:
    from relflowhub_mlx_runtime import main as legacy_main

    return int(legacy_main())
