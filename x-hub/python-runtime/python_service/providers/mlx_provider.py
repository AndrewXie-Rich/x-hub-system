from __future__ import annotations

import time
from typing import Any

from local_provider_scheduler import build_provider_resource_policy, read_provider_scheduler_telemetry
from provider_runtime_resolver import resolve_provider_runtime
from .base import LocalProvider, ProviderHealth


def _legacy_runtime_version() -> str:
    try:
        from relflowhub_mlx_runtime import RUNTIME_VERSION

        return str(RUNTIME_VERSION)
    except Exception:
        return "unknown"


def _legacy_bench_verdict(generation_tps: float) -> str:
    speed = float(generation_tps or 0.0)
    if speed >= 30.0:
        return "Fast"
    if speed >= 12.0:
        return "Balanced"
    return "Heavy"


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

    def lifecycle_mode(self) -> str:
        return "mlx_legacy"

    def residency_scope(self) -> str:
        return "legacy_runtime"

    def healthcheck(self, *, base_dir: str, catalog_models: list[dict[str, Any]]) -> ProviderHealth:
        runtime_resolution = resolve_provider_runtime(
            self.provider_id(),
            base_dir=base_dir,
            eager_import=False,
        )
        runtime = self._runtime
        import_error = ""
        ok = False
        loaded_models: list[str] = []
        loaded_instances: list[dict[str, Any]] = []
        active_memory_bytes: int | None = None
        peak_memory_bytes: int | None = None
        loaded_model_count: int | None = None

        if runtime is not None:
            ok = bool(getattr(runtime, "_mlx_ok", False))
            import_error = str(getattr(runtime, "_import_error", "") or "").strip() or runtime_resolution.import_error
            loaded_rows = getattr(runtime, "loaded_instance_rows", None)
            if callable(loaded_rows):
                try:
                    loaded_instances = [
                        dict(row) for row in loaded_rows()
                        if isinstance(row, dict)
                    ]
                except Exception:
                    loaded_instances = []
            loaded_model_ids = getattr(runtime, "loaded_model_ids", None)
            if callable(loaded_model_ids):
                try:
                    loaded_models = sorted(
                        str(model_id) for model_id in loaded_model_ids()
                        if str(model_id or "").strip()
                    )
                except Exception:
                    loaded_models = []
            if not loaded_models:
                loaded = getattr(runtime, "_loaded", {}) or {}
                if isinstance(loaded, dict):
                    loaded_models = sorted(
                        str(
                            (value.get("model_id") if isinstance(value, dict) else model_id) or ""
                        ).strip()
                        for model_id, value in loaded.items()
                        if str(
                            (value.get("model_id") if isinstance(value, dict) else model_id) or ""
                        ).strip()
                    )
            if not loaded_instances and loaded_models:
                loaded_instances = [
                    {
                        "instanceKey": f"mlx:{model_id}:legacy_runtime",
                        "modelId": model_id,
                        "taskKinds": ["text_generate"],
                        "loadProfileHash": "legacy_runtime",
                        "effectiveContextLength": 0,
                        "loadedAt": 0.0,
                        "lastUsedAt": 0.0,
                        "residency": "resident",
                        "residencyScope": self.residency_scope(),
                        "deviceBackend": "mps",
                    }
                    for model_id in loaded_models
                ]
            loaded_model_count = len(loaded_models)
            memory_bytes = getattr(runtime, "memory_bytes", None)
            if callable(memory_bytes):
                try:
                    active_memory_bytes, peak_memory_bytes = memory_bytes()
                except Exception:
                    active_memory_bytes = None
                    peak_memory_bytes = None
        else:
            if not runtime_resolution.ok:
                import_error = runtime_resolution.import_error
            else:
                try:
                    from relflowhub_mlx_runtime import probe_mlx_runtime_support

                    ok, import_error = probe_mlx_runtime_support()
                except Exception as exc:
                    ok = False
                    import_error = f"mlx_probe_unavailable:{type(exc).__name__}:{exc}"
            loaded_model_count = 0

        runtime_version = self._runtime_version or _legacy_runtime_version()
        registered_models = [
            str(model.get("id") or "").strip()
            for model in self.list_registered_models(catalog_models=catalog_models)
            if str(model.get("id") or "").strip()
        ]
        resource_policy = build_provider_resource_policy(
            self.provider_id(),
            catalog_models=catalog_models,
        )
        scheduler_state = read_provider_scheduler_telemetry(
            base_dir,
            self.provider_id(),
            policy=resource_policy,
        )
        reason_code = "ready"
        if not ok:
            if runtime_resolution.runtime_reason_code != "ready":
                reason_code = runtime_resolution.runtime_reason_code
            elif import_error:
                reason_code = "import_error"
            else:
                reason_code = "unavailable"

        return ProviderHealth(
            provider=self.provider_id(),
            ok=ok,
            reason_code=reason_code,
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
            resource_policy=resource_policy,
            scheduler_state=scheduler_state,
            lifecycle_mode=self.lifecycle_mode(),
            supported_lifecycle_actions=self.supported_lifecycle_actions(),
            warmup_task_kinds=self.warmup_task_kinds(),
            residency_scope=self.residency_scope(),
            loaded_instances=loaded_instances,
            real_task_kinds=self.supported_task_kinds() if ok else [],
            fallback_task_kinds=[],
            unavailable_task_kinds=[],
            runtime_source=runtime_resolution.runtime_source,
            runtime_source_path=runtime_resolution.runtime_source_path,
            runtime_resolution_state=runtime_resolution.runtime_resolution_state,
            runtime_reason_code=runtime_resolution.runtime_reason_code,
            fallback_used=runtime_resolution.fallback_used,
            runtime_hint=runtime_resolution.runtime_hint,
            runtime_missing_requirements=runtime_resolution.missing_requirements,
            runtime_missing_optional_requirements=runtime_resolution.missing_optional_requirements,
            managed_service_state=runtime_resolution.managed_service_state,
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

    def run_bench(self, request: dict[str, Any]) -> dict[str, Any]:
        task_kind = str(request.get("task_kind") or request.get("taskKind") or "text_generate").strip().lower()
        model_id = str(
            request.get("model_id")
            or request.get("modelId")
            or request.get("_resolved_model", {}).get("id")
            or ""
        ).strip()
        fixture_profile = str(request.get("fixture_profile") or request.get("fixtureProfile") or "legacy_mlx_text_default").strip()
        fixture_title = str(request.get("fixture_title") or request.get("fixtureTitle") or "Legacy MLX text loop").strip()
        if task_kind and task_kind not in self.supported_task_kinds():
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "modelId": model_id,
                "fixtureProfile": fixture_profile,
                "fixtureTitle": fixture_title,
                "resultKind": "legacy_text_bench",
                "reasonCode": "unsupported_task",
                "error": f"unsupported_task_kind:{task_kind}",
                "request": dict(request or {}),
            }

        runtime = self._runtime
        if runtime is None or not hasattr(runtime, "bench"):
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": task_kind or "text_generate",
                "modelId": model_id,
                "fixtureProfile": fixture_profile,
                "fixtureTitle": fixture_title,
                "resultKind": "legacy_text_bench",
                "reasonCode": "legacy_runtime_loop_required",
                "error": "legacy_runtime_loop_required",
                "request": dict(request or {}),
            }
        if not model_id:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": task_kind or "text_generate",
                "fixtureProfile": fixture_profile,
                "fixtureTitle": fixture_title,
                "resultKind": "legacy_text_bench",
                "reasonCode": "missing_model_id",
                "error": "missing_model_id",
                "request": dict(request or {}),
            }

        prompt_tokens = max(16, int(request.get("prompt_tokens") or request.get("promptTokens") or 256))
        generation_tokens = max(16, int(request.get("generation_tokens") or request.get("generationTokens") or 256))
        instance_key = str(request.get("instance_key") or request.get("instanceKey") or "").strip()
        load_profile_hash = str(request.get("load_profile_hash") or request.get("loadProfileHash") or "").strip()
        effective_context_length = max(
            0,
            int(request.get("effective_context_length") or request.get("effectiveContextLength") or 0),
        )
        ok, message, meta = runtime.bench(
            model_id,
            prompt_tokens=prompt_tokens,
            generation_tokens=generation_tokens,
            instance_key=instance_key,
            load_profile_hash=load_profile_hash,
            effective_context_length=effective_context_length,
        )
        meta_obj = meta if isinstance(meta, dict) else {}
        if not ok:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": task_kind or "text_generate",
                "modelId": model_id,
                "fixtureProfile": fixture_profile,
                "fixtureTitle": fixture_title,
                "resultKind": "legacy_text_bench",
                "reasonCode": str(message or "bench_failed"),
                "error": str(message or "bench_failed"),
                "request": dict(request or {}),
            }

        generation_tps = float(meta_obj.get("generationTPS") or 0.0)
        generation_token_count = int(meta_obj.get("generationTokens") or 0)
        latency_ms = 0
        if generation_tps > 0 and generation_token_count > 0:
            latency_ms = max(0, int((generation_token_count / generation_tps) * 1000.0))
        return {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": task_kind or "text_generate",
            "modelId": model_id,
            "instanceKey": str(meta_obj.get("instanceKey") or instance_key),
            "loadProfileHash": str(meta_obj.get("loadProfileHash") or load_profile_hash),
            "fixtureProfile": fixture_profile,
            "fixtureTitle": fixture_title,
            "resultKind": "legacy_text_bench",
            "reasonCode": "legacy_text_bench",
            "verdict": _legacy_bench_verdict(generation_tps),
            "fallbackMode": "",
            "coldStartMs": None,
            "latencyMs": latency_ms,
            "peakMemoryBytes": int(meta_obj.get("peakMemoryBytes") or 0),
            "throughputValue": generation_tps,
            "throughputUnit": "tokens_per_sec",
            "promptTokens": int(meta_obj.get("promptTokens") or 0),
            "generationTokens": generation_token_count,
            "promptTPS": float(meta_obj.get("promptTPS") or 0.0),
            "generationTPS": generation_tps,
            "effectiveContextLength": max(
                0,
                int(meta_obj.get("effectiveContextLength") or effective_context_length or 0),
            ),
            "notes": ["legacy_text_bench"],
        }

    def warmup_model(self, request: dict[str, Any]) -> dict[str, Any]:
        return {
            "ok": False,
            "provider": self.provider_id(),
            "action": "warmup_local_model",
            "lifecycleMode": self.lifecycle_mode(),
            "residencyScope": self.residency_scope(),
            "supportedLifecycleActions": self.supported_lifecycle_actions(),
            "warmupTaskKinds": self.warmup_task_kinds(),
            "error": "unsupported_lifecycle:mlx_legacy",
            "request": dict(request or {}),
        }

    def unload_model(self, request: dict[str, Any]) -> dict[str, Any]:
        return {
            "ok": False,
            "provider": self.provider_id(),
            "action": "unload_local_model",
            "lifecycleMode": self.lifecycle_mode(),
            "residencyScope": self.residency_scope(),
            "supportedLifecycleActions": self.supported_lifecycle_actions(),
            "warmupTaskKinds": self.warmup_task_kinds(),
            "error": "unsupported_lifecycle:mlx_legacy",
            "request": dict(request or {}),
        }

    def evict_instance(self, request: dict[str, Any]) -> dict[str, Any]:
        return {
            "ok": False,
            "provider": self.provider_id(),
            "action": "evict_local_instance",
            "lifecycleMode": self.lifecycle_mode(),
            "residencyScope": self.residency_scope(),
            "supportedLifecycleActions": self.supported_lifecycle_actions(),
            "warmupTaskKinds": self.warmup_task_kinds(),
            "error": "unsupported_lifecycle:mlx_legacy",
            "request": dict(request or {}),
        }


def run_legacy_runtime() -> int:
    from relflowhub_mlx_runtime import main as legacy_main

    result = legacy_main()
    if result is None:
        return 0
    return int(result)
