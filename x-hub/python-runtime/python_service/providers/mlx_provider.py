from __future__ import annotations

import re
import time
from typing import Any

from local_provider_scheduler import build_provider_resource_policy, read_provider_scheduler_telemetry
from provider_runtime_resolver import resolve_provider_runtime
from .base import LocalProvider, ProviderHealth

TEXT_TASK_KIND = "text_generate"
EMBED_TASK_KIND = "embedding"
MAX_BATCH_TEXTS = 32
MAX_TEXT_CHARS = 4096
MAX_TOTAL_TEXT_CHARS = 32768
SECRET_TEXT_PATTERNS = [
    re.compile(r"\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)", re.IGNORECASE),
    re.compile(r"\b(api[_-]?key|secret|password|token)\s*[:=]\s*\S+", re.IGNORECASE),
]


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_int(value: Any, fallback: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return int(fallback)


def _safe_bool(value: Any, fallback: bool = False) -> bool:
    if value is None:
        return bool(fallback)
    if isinstance(value, bool):
        return value
    token = str(value).strip().lower()
    if token in {"1", "true", "yes", "on"}:
        return True
    if token in {"0", "false", "no", "off"}:
        return False
    return bool(fallback)


def _safe_string_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [
            str(item).strip().lower()
            for item in value
            if str(item or "").strip()
        ]
    token = str(value or "").strip().lower()
    return [token] if token else []


def _contains_sensitive_text(text: Any) -> bool:
    value = str(text or "")
    return any(pattern.search(value) for pattern in SECRET_TEXT_PATTERNS)


def _request_instance_key(request: dict[str, Any]) -> str:
    return _safe_str(request.get("instance_key") or request.get("instanceKey"))


def _request_load_profile_hash(request: dict[str, Any]) -> str:
    return _safe_str(request.get("load_profile_hash") or request.get("loadProfileHash"))


def _request_effective_context_length(request: dict[str, Any]) -> int:
    return max(0, _safe_int(request.get("effective_context_length") or request.get("effectiveContextLength"), 0))


def _request_effective_load_profile(request: dict[str, Any]) -> dict[str, Any]:
    profile = request.get("effective_load_profile") or request.get("effectiveLoadProfile")
    return dict(profile) if isinstance(profile, dict) else {}


def _extract_texts(request: dict[str, Any]) -> list[str]:
    input_obj = request.get("input") if isinstance(request.get("input"), dict) else {}
    candidates = [
        request.get("texts"),
        request.get("input_texts"),
        request.get("inputTexts"),
        input_obj.get("texts"),
        input_obj.get("input_texts"),
        input_obj.get("inputTexts"),
    ]
    for raw in candidates:
        if isinstance(raw, list):
            return [str(item or "") for item in raw]
    scalar = (
        request.get("text")
        or request.get("input_text")
        or request.get("inputText")
        or input_obj.get("text")
        or input_obj.get("input_text")
        or input_obj.get("inputText")
    )
    if scalar is not None:
        return [str(scalar or "")]
    raw_input = request.get("input")
    if isinstance(raw_input, str):
        return [raw_input]
    return []


def _model_task_kinds(model: dict[str, Any] | None) -> list[str]:
    row = model if isinstance(model, dict) else {}
    return _safe_string_list(row.get("taskKinds") or row.get("task_kinds"))


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
        return [TEXT_TASK_KIND, EMBED_TASK_KIND]

    def supported_input_modalities(self) -> list[str]:
        return ["text"]

    def supported_output_modalities(self) -> list[str]:
        return ["text", "embedding"]

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
        idle_eviction: dict[str, Any] | None = None

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
            task_kinds_by_model: dict[str, list[str]] = {}
            for model in catalog_models:
                if not isinstance(model, dict):
                    continue
                model_id = _safe_str(model.get("id"))
                if not model_id:
                    continue
                task_kinds = _model_task_kinds(model)
                if task_kinds:
                    task_kinds_by_model[model_id] = task_kinds

            normalized_loaded_instances: list[dict[str, Any]] = []
            for row in loaded_instances:
                normalized = dict(row)
                model_id = _safe_str(normalized.get("modelId") or normalized.get("model_id"))
                task_kinds = _safe_string_list(normalized.get("taskKinds") or normalized.get("task_kinds"))
                if not task_kinds:
                    task_kinds = task_kinds_by_model.get(model_id) or [TEXT_TASK_KIND]
                normalized["taskKinds"] = task_kinds
                normalized_loaded_instances.append(normalized)
            loaded_instances = normalized_loaded_instances

            if not loaded_instances and loaded_models:
                loaded_instances = [
                    {
                        "instanceKey": f"mlx:{model_id}:legacy_runtime",
                        "modelId": model_id,
                        "taskKinds": task_kinds_by_model.get(model_id) or [TEXT_TASK_KIND],
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
            idle_eviction_state = getattr(runtime, "idle_eviction_state", None)
            if callable(idle_eviction_state):
                try:
                    row = idle_eviction_state()
                    if isinstance(row, dict):
                        idle_eviction = dict(row)
                except Exception:
                    idle_eviction = None
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
            if import_error:
                reason_code = "import_error"
            elif runtime_resolution.runtime_reason_code != "ready":
                reason_code = runtime_resolution.runtime_reason_code
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
            idle_eviction=idle_eviction,
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
        if task_kind == EMBED_TASK_KIND:
            return self._run_embedding_task(request)
        return {
            "ok": False,
            "provider": self.provider_id(),
            "taskKind": task_kind or TEXT_TASK_KIND,
            "error": "delegate_to_runtime_loop:mlx",
            "request": dict(request or {}),
        }

    def _resolve_model_info(self, request: dict[str, Any]) -> dict[str, Any]:
        model = request.get("_resolved_model") if isinstance(request.get("_resolved_model"), dict) else {}
        model_id = _safe_str(
            request.get("model_id")
            or request.get("modelId")
            or model.get("id")
        )
        model_path = _safe_str(
            request.get("model_path")
            or request.get("modelPath")
            or model.get("modelPath")
            or model.get("model_path")
        )
        task_kinds = _model_task_kinds(model)
        if not task_kinds:
            task_kinds = _safe_string_list(request.get("taskKinds") or request.get("task_kinds"))
        return {
            "model_id": model_id,
            "model_path": model_path,
            "task_kinds": task_kinds,
        }

    def _validate_embedding_request(self, request: dict[str, Any], *, model_info: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        model_id = _safe_str(model_info.get("model_id"))
        if not model_id:
            return "missing_model_id", {}
        task_kinds = _safe_string_list(model_info.get("task_kinds"))
        if task_kinds and EMBED_TASK_KIND not in task_kinds:
            return "model_task_unsupported:embedding", {}

        texts = _extract_texts(request)
        if not texts:
            return "missing_texts", {}
        if len(texts) > MAX_BATCH_TEXTS:
            return "embedding_batch_too_large", {}

        total_chars = 0
        max_text_chars = 0
        input_sanitized = _safe_bool(request.get("input_sanitized") or request.get("inputSanitized"), False)
        for text in texts:
            text_chars = len(str(text or ""))
            max_text_chars = max(max_text_chars, text_chars)
            total_chars += text_chars
            if text_chars > MAX_TEXT_CHARS:
                return "embedding_text_too_large", {}
            if not input_sanitized and _contains_sensitive_text(text):
                return "policy_blocked_sensitive_text", {}
        if total_chars > MAX_TOTAL_TEXT_CHARS:
            return "embedding_total_input_too_large", {}

        return "", {
            "texts": [str(text or "") for text in texts],
            "text_count": len(texts),
            "total_chars": total_chars,
            "max_text_chars": max_text_chars,
            "input_sanitized": input_sanitized,
        }

    def _run_embedding_task(self, request: dict[str, Any]) -> dict[str, Any]:
        started_at = time.time()
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        error_code, validated = self._validate_embedding_request(request, model_info=model_info)
        if error_code:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": EMBED_TASK_KIND,
                "modelId": model_id,
                "modelPath": model_path,
                "error": error_code,
                "request": dict(request or {}),
            }

        runtime = self._runtime
        if runtime is None or not hasattr(runtime, "run_embedding"):
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": EMBED_TASK_KIND,
                "modelId": model_id,
                "modelPath": model_path,
                "error": "legacy_runtime_loop_required",
                "request": dict(request or {}),
            }
        if not bool(getattr(runtime, "_mlx_ok", False)):
            import_error = _safe_str(getattr(runtime, "_import_error", ""))
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": EMBED_TASK_KIND,
                "modelId": model_id,
                "modelPath": model_path,
                "error": f"mlx_lm_unavailable:{import_error}" if import_error else "mlx_lm_unavailable",
                "request": dict(request or {}),
            }
        if not model_path:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": EMBED_TASK_KIND,
                "modelId": model_id,
                "error": "missing_model_path",
                "request": dict(request or {}),
            }

        instance_key = _request_instance_key(request)
        load_profile_hash = _request_load_profile_hash(request)
        effective_context_length = _request_effective_context_length(request)
        effective_load_profile = _request_effective_load_profile(request)

        try:
            is_loaded = bool(
                runtime.is_loaded(
                    model_id,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                )
            )
        except Exception:
            is_loaded = False
        if not is_loaded:
            try:
                ok_load, msg_load, _ = runtime.load(
                    model_id,
                    model_path,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                    effective_context_length=effective_context_length,
                    effective_load_profile=effective_load_profile,
                    task_kinds=[EMBED_TASK_KIND],
                )
            except TypeError:
                ok_load, msg_load, _ = runtime.load(
                    model_id,
                    model_path,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                    effective_context_length=effective_context_length,
                    effective_load_profile=effective_load_profile,
                )
            if not ok_load:
                return {
                    "ok": False,
                    "provider": self.provider_id(),
                    "taskKind": EMBED_TASK_KIND,
                    "modelId": model_id,
                    "modelPath": model_path,
                    "error": _safe_str(msg_load) or "load_failed",
                    "request": dict(request or {}),
                }

        max_length = max(32, min(4096, _safe_int(request.get("max_length") or request.get("maxLength"), 512)))
        try:
            vectors, dims, meta = runtime.run_embedding(
                model_id,
                list(validated.get("texts") or []),
                instance_key=instance_key,
                load_profile_hash=load_profile_hash,
                max_length=max_length,
            )
        except Exception as exc:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": EMBED_TASK_KIND,
                "modelId": model_id,
                "modelPath": model_path,
                "error": "embedding_runtime_failed",
                "errorDetail": f"{type(exc).__name__}: {exc}",
                "request": dict(request or {}),
            }

        meta_obj = meta if isinstance(meta, dict) else {}
        latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
        return {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": EMBED_TASK_KIND,
            "modelId": model_id,
            "modelPath": model_path,
            "vectorCount": len(vectors),
            "dims": max(0, int(dims or 0)),
            "vectors": vectors,
            "normalized": True,
            "latencyMs": latency_ms,
            "deviceBackend": "mps",
            "fallbackMode": "",
            "usage": {
                "textCount": int(validated.get("text_count") or len(vectors)),
                "totalChars": int(validated.get("total_chars") or 0),
                "maxTextChars": int(validated.get("max_text_chars") or 0),
                "inputSanitized": bool(validated.get("input_sanitized")),
                "promptTokens": max(0, _safe_int(meta_obj.get("promptTokens") or meta_obj.get("prompt_tokens"), 0)),
                "totalTokens": max(0, _safe_int(meta_obj.get("totalTokens") or meta_obj.get("total_tokens"), 0)),
            },
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
