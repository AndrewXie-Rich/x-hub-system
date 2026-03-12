from __future__ import annotations

import importlib.util
import time
from typing import Any

from .base import LocalProvider, ProviderHealth


TRANSFORMERS_PROVIDER_RUNTIME_VERSION = "2026-03-12-transformers-skeleton-v1"


class TransformersProvider(LocalProvider):
    def provider_id(self) -> str:
        return "transformers"

    def supported_task_kinds(self) -> list[str]:
        return [
            "embedding",
            "speech_to_text",
            "vision_understand",
            "ocr",
        ]

    def supported_input_modalities(self) -> list[str]:
        return ["text", "audio", "image"]

    def supported_output_modalities(self) -> list[str]:
        return ["embedding", "text", "segments", "spans"]

    def healthcheck(self, *, base_dir: str, catalog_models: list[dict[str, Any]]) -> ProviderHealth:
        del base_dir

        has_transformers = importlib.util.find_spec("transformers") is not None
        has_torch = importlib.util.find_spec("torch") is not None

        import_error = ""
        if not has_transformers:
            import_error = "missing_module:transformers"
        elif not has_torch:
            import_error = "missing_module:torch"

        registered_models = [
            str(model.get("id") or "").strip()
            for model in self.list_registered_models(catalog_models=catalog_models)
            if str(model.get("id") or "").strip()
        ]

        if import_error:
            reason_code = "import_error"
        elif registered_models:
            reason_code = "provider_skeleton_not_implemented"
        else:
            reason_code = "no_registered_models"

        return ProviderHealth(
            provider=self.provider_id(),
            ok=False,
            reason_code=reason_code,
            runtime_version=TRANSFORMERS_PROVIDER_RUNTIME_VERSION,
            available_task_kinds=self.supported_task_kinds() if has_transformers else [],
            loaded_models=[],
            device_backend="mps_or_cpu",
            updated_at=time.time(),
            import_error=import_error,
            loaded_model_count=0,
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
            "taskKind": task_kind or "unknown",
            "error": "task_not_implemented:transformers",
            "request": dict(request or {}),
        }
