"""Canonical local provider runtime entrypoint for X-Hub.

This entrypoint is intentionally low-risk in v1:
- it owns provider registry / status aggregation
- it keeps the runtime offline-only
- the default execution path still delegates to the proven MLX runtime loop
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import sys
import time
from typing import Any

from local_provider_scheduler import acquire_provider_slot, release_provider_slot
from providers import LocalProviderRegistry, MLXProvider, TransformersProvider
from providers.mlx_provider import run_legacy_runtime


# Keep this aligned with the legacy runtime version so Hub's runtime-version
# watchdog does not trigger restart loops during the delegate phase.
RUNTIME_VERSION = "2026-02-21-constitution-trigger-v2"
LOCAL_RUNTIME_ENTRY_VERSION = "2026-03-13-lpr-scheduler-v1"
LOCAL_RUNTIME_STATUS_SCHEMA_VERSION = "xhub.local_provider_runtime.entry.v1"
PAIRED_TERMINAL_LOCAL_MODEL_PROFILES_FILENAME = "hub_paired_terminal_local_model_profiles.json"
_REGISTRIES_BY_BASE_DIR: dict[str, LocalProviderRegistry] = {}
LOAD_PROFILE_FIELD_ALIASES = {
    "context_length": ("context_length", "contextLength"),
    "gpu_offload_ratio": ("gpu_offload_ratio", "gpuOffloadRatio"),
    "rope_frequency_base": ("rope_frequency_base", "ropeFrequencyBase"),
    "rope_frequency_scale": ("rope_frequency_scale", "ropeFrequencyScale"),
    "eval_batch_size": ("eval_batch_size", "evalBatchSize"),
}


def _group_base_dir() -> str:
    return os.path.expanduser("~/Library/Group Containers/group.rel.flowhub")


def _base_dir() -> str:
    env = (os.environ.get("REL_FLOW_HUB_BASE_DIR") or "").strip()
    return os.path.expanduser(env) if env else _group_base_dir()


def _catalog_path(base_dir: str) -> str:
    return os.path.join(base_dir, "models_catalog.json")


def _paired_terminal_local_model_profiles_path(base_dir: str) -> str:
    return os.path.join(base_dir, PAIRED_TERMINAL_LOCAL_MODEL_PROFILES_FILENAME)


def _now() -> float:
    return time.time()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_int(value: Any, fallback: int = 0) -> int:
    if isinstance(value, bool):
        return int(fallback)
    try:
        return int(value)
    except Exception:
        return int(fallback)


def _safe_float(value: Any, fallback: float = 0.0) -> float:
    if isinstance(value, bool):
        return float(fallback)
    try:
        number = float(value)
    except Exception:
        return float(fallback)
    return float(number) if math.isfinite(number) else float(fallback)


def _safe_string_list(values: Any) -> list[str]:
    if values is None:
        return []
    items = values if isinstance(values, list) else str(values or "").split(",")
    out: list[str] = []
    seen: set[str] = set()
    for raw in items:
        cleaned = str(raw or "").strip().lower()
        if not cleaned or cleaned in seen:
            continue
        seen.add(cleaned)
        out.append(cleaned)
    return out


def _request_instance_key(request: dict[str, Any]) -> str:
    return _safe_str(request.get("instance_key") or request.get("instanceKey"))


def _request_load_profile_hash(request: dict[str, Any]) -> str:
    return _safe_str(request.get("load_profile_hash") or request.get("loadProfileHash"))


def _parse_instance_key(instance_key: str) -> tuple[str, str, str]:
    token = _safe_str(instance_key)
    if not token:
        return "", "", ""
    parts = token.split(":", 2)
    if len(parts) < 3:
        return "", "", ""
    return _safe_str(parts[0]).lower(), _safe_str(parts[1]), _safe_str(parts[2])


def _normalize_model_task_kinds(model: dict[str, Any] | None) -> list[str]:
    row = model if isinstance(model, dict) else {}
    task_kinds = _safe_string_list(row.get("taskKinds") or row.get("task_kinds"))
    if task_kinds:
        return task_kinds
    backend = str(row.get("backend") or "").strip().lower()
    return ["text_generate"] if backend == "mlx" else []


def _find_catalog_model(model_id: str, *, catalog_models: list[dict[str, Any]]) -> dict[str, Any] | None:
    needle = _safe_str(model_id)
    if not needle:
        return None
    for model in catalog_models:
        if not isinstance(model, dict):
            continue
        if _safe_str(model.get("id")) != needle:
            continue
        return model
    return None


def _sanitize_json_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, bool):
        return bool(value)
    if isinstance(value, int):
        return int(value)
    if isinstance(value, float):
        return float(value) if math.isfinite(value) else None
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return [_sanitize_json_value(item) for item in value]
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for raw_key, raw_value in value.items():
            key = _safe_str(raw_key)
            if not key:
                continue
            out[key] = _sanitize_json_value(raw_value)
        return out
    return str(value)


def _load_profile_field_present(profile: dict[str, Any], field: str) -> tuple[bool, Any]:
    aliases = LOAD_PROFILE_FIELD_ALIASES.get(field) or ()
    for alias in aliases:
        if alias in profile:
            return True, profile.get(alias)
    return False, None


def _unknown_load_profile_fields(profile: dict[str, Any]) -> dict[str, Any]:
    known_aliases = {
        alias
        for aliases in LOAD_PROFILE_FIELD_ALIASES.values()
        for alias in aliases
    }
    out: dict[str, Any] = {}
    for raw_key, raw_value in profile.items():
        key = _safe_str(raw_key)
        if not key or key in known_aliases:
            continue
        out[key] = _sanitize_json_value(raw_value)
    return out


def _normalize_default_load_profile(
    model: dict[str, Any] | None,
    *,
    max_context_length: int,
) -> dict[str, Any]:
    row = model if isinstance(model, dict) else {}
    raw_profile = row.get("default_load_profile") if isinstance(row.get("default_load_profile"), dict) else row.get("defaultLoadProfile")
    profile = raw_profile if isinstance(raw_profile, dict) else {}
    legacy_context_length = max(
        0,
        _safe_int(row.get("context_length") if row.get("context_length") is not None else row.get("contextLength"), 0),
    )
    effective_context_length = max(512, legacy_context_length or 8192)
    present, raw_context_length = _load_profile_field_present(profile, "context_length")
    if present:
        effective_context_length = max(512, _safe_int(raw_context_length, effective_context_length))
    if max_context_length > 0:
        effective_context_length = min(effective_context_length, max_context_length)

    out = _unknown_load_profile_fields(profile)
    out["context_length"] = effective_context_length

    present, raw_gpu_offload_ratio = _load_profile_field_present(profile, "gpu_offload_ratio")
    if present and raw_gpu_offload_ratio is not None:
        out["gpu_offload_ratio"] = min(1.0, max(0.0, _safe_float(raw_gpu_offload_ratio, 0.0)))

    present, raw_rope_frequency_base = _load_profile_field_present(profile, "rope_frequency_base")
    if present and raw_rope_frequency_base is not None:
        value = _safe_float(raw_rope_frequency_base, 0.0)
        if value > 0:
            out["rope_frequency_base"] = value

    present, raw_rope_frequency_scale = _load_profile_field_present(profile, "rope_frequency_scale")
    if present and raw_rope_frequency_scale is not None:
        value = _safe_float(raw_rope_frequency_scale, 0.0)
        if value > 0:
            out["rope_frequency_scale"] = value

    present, raw_eval_batch_size = _load_profile_field_present(profile, "eval_batch_size")
    if present and raw_eval_batch_size is not None:
        value = _safe_int(raw_eval_batch_size, 0)
        if value > 0:
            out["eval_batch_size"] = value

    return out


def _apply_load_profile_override(
    base_profile: dict[str, Any],
    override_profile: dict[str, Any] | None,
    *,
    max_context_length: int,
) -> dict[str, Any]:
    out = dict(base_profile or {})
    profile = override_profile if isinstance(override_profile, dict) else {}

    for key, value in _unknown_load_profile_fields(profile).items():
        out[key] = value

    present, raw_context_length = _load_profile_field_present(profile, "context_length")
    if present and raw_context_length is not None:
        out["context_length"] = max(512, _safe_int(raw_context_length, int(out.get("context_length") or 8192)))

    present, raw_gpu_offload_ratio = _load_profile_field_present(profile, "gpu_offload_ratio")
    if present and raw_gpu_offload_ratio is not None:
        out["gpu_offload_ratio"] = min(1.0, max(0.0, _safe_float(raw_gpu_offload_ratio, 0.0)))

    present, raw_rope_frequency_base = _load_profile_field_present(profile, "rope_frequency_base")
    if present and raw_rope_frequency_base is not None:
        value = _safe_float(raw_rope_frequency_base, 0.0)
        if value > 0:
            out["rope_frequency_base"] = value
        else:
            out.pop("rope_frequency_base", None)

    present, raw_rope_frequency_scale = _load_profile_field_present(profile, "rope_frequency_scale")
    if present and raw_rope_frequency_scale is not None:
        value = _safe_float(raw_rope_frequency_scale, 0.0)
        if value > 0:
            out["rope_frequency_scale"] = value
        else:
            out.pop("rope_frequency_scale", None)

    present, raw_eval_batch_size = _load_profile_field_present(profile, "eval_batch_size")
    if present and raw_eval_batch_size is not None:
        value = _safe_int(raw_eval_batch_size, 0)
        if value > 0:
            out["eval_batch_size"] = value
        else:
            out.pop("eval_batch_size", None)

    context_length = max(512, _safe_int(out.get("context_length"), 8192))
    if max_context_length > 0:
        context_length = min(context_length, max_context_length)
    out["context_length"] = context_length
    return out


def _model_max_context_length(model: dict[str, Any] | None) -> int:
    row = model if isinstance(model, dict) else {}
    raw_limit = row.get("max_context_length") if row.get("max_context_length") is not None else row.get("maxContextLength")
    limit = max(0, _safe_int(raw_limit, 0))
    if limit > 0:
        return limit
    legacy_context_length = max(
        0,
        _safe_int(row.get("context_length") if row.get("context_length") is not None else row.get("contextLength"), 0),
    )
    return legacy_context_length


def _read_paired_terminal_local_model_profiles(base_dir: str) -> list[dict[str, Any]]:
    path = _paired_terminal_local_model_profiles_path(base_dir)
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as handle:
            obj = json.load(handle)
    except Exception:
        return []

    if isinstance(obj, dict) and isinstance(obj.get("profiles"), list):
        return [item for item in obj.get("profiles") if isinstance(item, dict)]
    if isinstance(obj, list):
        return [item for item in obj if isinstance(item, dict)]
    return []


def _find_device_load_profile_override(base_dir: str, *, device_id: str, model_id: str) -> dict[str, Any]:
    wanted_device_id = _safe_str(device_id)
    wanted_model_id = _safe_str(model_id)
    if not wanted_device_id or not wanted_model_id:
        return {}
    for item in _read_paired_terminal_local_model_profiles(base_dir):
        if _safe_str(item.get("device_id") or item.get("deviceId")) != wanted_device_id:
            continue
        if _safe_str(item.get("model_id") or item.get("modelId")) != wanted_model_id:
            continue
        override_profile = item.get("override_profile") if isinstance(item.get("override_profile"), dict) else item.get("overrideProfile")
        return dict(override_profile) if isinstance(override_profile, dict) else {}
    return {}


def _request_load_profile_override(request: dict[str, Any]) -> dict[str, Any]:
    explicit_override = request.get("load_profile_override") if isinstance(request.get("load_profile_override"), dict) else request.get("loadProfileOverride")
    return dict(explicit_override) if isinstance(explicit_override, dict) else {}


def _resolve_model_load_profile_context(
    request: dict[str, Any],
    *,
    base_dir: str,
    provider_id: str,
    model_id: str,
    catalog_model: dict[str, Any] | None,
) -> dict[str, Any]:
    model_source = dict(catalog_model or {})
    for key in ("context_length", "contextLength", "max_context_length", "maxContextLength", "default_load_profile", "defaultLoadProfile"):
        if key in model_source:
            continue
        if request.get(key) is not None:
            model_source[key] = request.get(key)

    max_context_length = _model_max_context_length(model_source)
    default_profile = _normalize_default_load_profile(model_source, max_context_length=max_context_length)

    device_id = _safe_str(request.get("device_id") or request.get("deviceId"))
    device_override = _find_device_load_profile_override(
        base_dir,
        device_id=device_id,
        model_id=model_id,
    )
    explicit_override = _request_load_profile_override(request)

    effective_profile = _apply_load_profile_override(
        default_profile,
        device_override,
        max_context_length=max_context_length,
    )
    effective_profile = _apply_load_profile_override(
        effective_profile,
        explicit_override,
        max_context_length=max_context_length,
    )

    requested_context_length = None
    for profile in (explicit_override, device_override):
        present, raw_context_length = _load_profile_field_present(profile, "context_length")
        if present and raw_context_length is not None:
            requested_context_length = max(512, _safe_int(raw_context_length, 512))
            break

    has_override = bool(device_override or explicit_override)
    effective_context_length = max(512, _safe_int(effective_profile.get("context_length"), 8192))
    effective_context_source = "device_override" if has_override else "hub_default"
    if requested_context_length is not None and requested_context_length != effective_context_length:
        effective_context_source = "runtime_clamped"

    canonical_json = json.dumps(
        _sanitize_json_value(effective_profile),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    load_profile_hash = hashlib.sha256(canonical_json.encode("utf-8")).hexdigest()
    instance_key = f"{provider_id}:{model_id or 'unknown'}:{load_profile_hash}"

    return {
        "device_id": device_id,
        "max_context_length": max_context_length,
        "device_override": dict(device_override),
        "explicit_override": dict(explicit_override),
        "effective_load_profile": dict(effective_profile),
        "effective_context_length": effective_context_length,
        "effective_context_source": effective_context_source,
        "load_profile_hash": load_profile_hash,
        "instance_key": instance_key,
    }


def _attach_task_identity(output: dict[str, Any], identity: dict[str, Any]) -> dict[str, Any]:
    out = dict(output or {})
    effective_load_profile = identity.get("effective_load_profile")
    if isinstance(effective_load_profile, dict) and effective_load_profile:
        out.setdefault("effectiveLoadProfile", dict(effective_load_profile))
    if identity.get("effective_context_length") is not None:
        out.setdefault("effectiveContextLength", max(0, _safe_int(identity.get("effective_context_length"), 0)))
    if identity.get("effective_context_source"):
        out.setdefault("effectiveContextSource", _safe_str(identity.get("effective_context_source")))
    if identity.get("load_profile_hash"):
        out.setdefault("loadProfileHash", _safe_str(identity.get("load_profile_hash")))
    if identity.get("instance_key"):
        out.setdefault("instanceKey", _safe_str(identity.get("instance_key")))
    if identity.get("device_id"):
        out.setdefault("deviceId", _safe_str(identity.get("device_id")))
    return out


def apply_offline_env() -> None:
    defaults = {
        "PYTHONUNBUFFERED": "1",
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "HF_DATASETS_OFFLINE": "1",
        "TOKENIZERS_PARALLELISM": "false",
    }
    for key, value in defaults.items():
        os.environ.setdefault(key, value)


def read_catalog_models(base_dir: str) -> list[dict[str, Any]]:
    path = _catalog_path(base_dir)
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as handle:
            obj = json.load(handle)
    except Exception:
        return []

    if isinstance(obj, dict) and isinstance(obj.get("models"), list):
        return [item for item in obj.get("models") if isinstance(item, dict)]
    if isinstance(obj, list):
        return [item for item in obj if isinstance(item, dict)]
    return []


def build_registry(*, base_dir: str | None = None, runtime: Any | None = None) -> LocalProviderRegistry:
    base = os.path.abspath(str(base_dir or _base_dir()))
    registry = _REGISTRIES_BY_BASE_DIR.get(base)
    if registry is None:
        registry = LocalProviderRegistry()
        registry.register(MLXProvider(runtime=runtime, runtime_version=RUNTIME_VERSION))
        registry.register(TransformersProvider())
        _REGISTRIES_BY_BASE_DIR[base] = registry
        return registry

    mlx_provider = registry.get("mlx")
    if isinstance(mlx_provider, MLXProvider):
        mlx_provider._runtime = runtime
        mlx_provider._runtime_version = RUNTIME_VERSION
    return registry


def provider_status_snapshot(base_dir: str, *, runtime: Any | None = None) -> dict[str, dict[str, Any]]:
    catalog_models = read_catalog_models(base_dir)
    snapshot = build_registry(base_dir=base_dir, runtime=runtime).health_snapshot(
        base_dir=base_dir,
        catalog_models=catalog_models,
    )
    return {provider_id: health.to_dict() for provider_id, health in snapshot.items()}


def _flatten_loaded_instances(provider_statuses: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for provider_id, status in (provider_statuses or {}).items():
        if not isinstance(status, dict):
            continue
        residency_scope = _safe_str(status.get("residencyScope") or status.get("residency_scope"))
        for raw_entry in status.get("loadedInstances") or status.get("loaded_instances") or []:
            if not isinstance(raw_entry, dict):
                continue
            instance_key = _safe_str(raw_entry.get("instanceKey") or raw_entry.get("instance_key"))
            dedupe_key = f"{provider_id}:{instance_key}"
            if not instance_key or dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            row = dict(raw_entry)
            row.setdefault("provider", provider_id)
            if residency_scope and not _safe_str(row.get("residencyScope") or row.get("residency_scope")):
                row["residencyScope"] = residency_scope
            rows.append(row)
    rows.sort(
        key=lambda item: (
            _safe_str(item.get("provider")),
            _safe_str(item.get("modelId") or item.get("model_id")),
            _safe_str(item.get("instanceKey") or item.get("instance_key")),
        )
    )
    return rows


def _idle_eviction_by_provider(provider_statuses: dict[str, dict[str, Any]]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for provider_id, status in (provider_statuses or {}).items():
        if not isinstance(status, dict):
            continue
        idle_eviction = status.get("idleEviction") or status.get("idle_eviction")
        if isinstance(idle_eviction, dict):
            out[str(provider_id).strip().lower()] = dict(idle_eviction)
    return out


def _publish_runtime_status(base_dir: str) -> None:
    try:
        from relflowhub_mlx_runtime import _write_runtime_status
    except Exception:
        return
    providers = provider_status_snapshot(base_dir)
    mlx_status = providers.get("mlx") if isinstance(providers.get("mlx"), dict) else {}
    try:
        _write_runtime_status(
            base_dir,
            mlx_ok=bool(mlx_status.get("ok")),
            import_error=_safe_str(mlx_status.get("importError") or mlx_status.get("import_error")),
            active_memory_bytes=_safe_int(mlx_status.get("activeMemoryBytes") or mlx_status.get("active_memory_bytes"), 0)
            if "activeMemoryBytes" in mlx_status or "active_memory_bytes" in mlx_status
            else None,
            peak_memory_bytes=_safe_int(mlx_status.get("peakMemoryBytes") or mlx_status.get("peak_memory_bytes"), 0)
            if "peakMemoryBytes" in mlx_status or "peak_memory_bytes" in mlx_status
            else None,
            loaded_model_count=_safe_int(mlx_status.get("loadedModelCount") or mlx_status.get("loaded_model_count"), 0)
            if "loadedModelCount" in mlx_status or "loaded_model_count" in mlx_status
            else None,
            loaded_model_ids=[
                _safe_str(model_id)
                for model_id in (mlx_status.get("loadedModels") or mlx_status.get("loaded_models") or [])
                if _safe_str(model_id)
            ],
            provider_statuses=providers,
        )
    except Exception:
        return


def _resolve_provider_id(request: dict[str, Any], *, catalog_models: list[dict[str, Any]]) -> str:
    explicit_provider = _safe_str(request.get("provider") or request.get("backend")).lower()
    if explicit_provider:
        return explicit_provider

    model_id = _safe_str(request.get("model_id") or request.get("modelId"))
    if model_id:
        for model in catalog_models:
            if _safe_str(model.get("id")) != model_id:
                continue
            backend = _safe_str(model.get("backend")).lower()
            if backend:
                return backend

    task_kind = _safe_str(request.get("task_kind") or request.get("taskKind")).lower()
    if task_kind == "text_generate":
        return "mlx"
    instance_provider, _, _ = _parse_instance_key(_request_instance_key(request))
    if instance_provider:
        return instance_provider
    return ""


def _resolve_request_model_id(request: dict[str, Any]) -> str:
    explicit_model_id = _safe_str(request.get("model_id") or request.get("modelId"))
    if explicit_model_id:
        return explicit_model_id
    _, instance_model_id, _ = _parse_instance_key(_request_instance_key(request))
    return instance_model_id


def _normalize_lifecycle_action(value: Any) -> str:
    token = _safe_str(value).lower().replace("-", "_")
    if token in {"warmup_local_model", "unload_local_model", "evict_local_instance"}:
        return token
    return ""


def _resolve_provider_request_context(
    request: dict[str, Any],
    *,
    base_dir: str,
) -> dict[str, Any]:
    catalog_models = read_catalog_models(base_dir)
    provider_id = _resolve_provider_id(request, catalog_models=catalog_models)
    task_kind = _safe_str(request.get("task_kind") or request.get("taskKind")).lower()
    model_id = _resolve_request_model_id(request)
    catalog_model = _find_catalog_model(model_id, catalog_models=catalog_models)
    registry = build_registry(base_dir=base_dir)
    provider = registry.get(provider_id) if provider_id else None
    provider_request = dict(request or {})
    if catalog_model is not None:
        provider_request.setdefault("_resolved_model", dict(catalog_model))
    identity = _resolve_model_load_profile_context(
        provider_request,
        base_dir=base_dir,
        provider_id=provider_id or _safe_str(request.get("provider") or request.get("backend")).lower(),
        model_id=model_id,
        catalog_model=catalog_model,
    )
    explicit_instance_key = _request_instance_key(request)
    explicit_load_profile_hash = _request_load_profile_hash(request)
    parsed_instance_provider, parsed_instance_model_id, parsed_instance_hash = _parse_instance_key(explicit_instance_key)
    if explicit_load_profile_hash:
        identity["load_profile_hash"] = explicit_load_profile_hash
    elif parsed_instance_hash:
        identity["load_profile_hash"] = parsed_instance_hash
    if explicit_instance_key:
        identity["instance_key"] = explicit_instance_key
    elif parsed_instance_provider and parsed_instance_model_id and parsed_instance_hash:
        identity["instance_key"] = explicit_instance_key
    if identity.get("device_id"):
        provider_request["device_id"] = _safe_str(identity.get("device_id"))
    provider_request["_base_dir"] = base_dir
    provider_request["effective_load_profile"] = dict(identity.get("effective_load_profile") or {})
    provider_request["effective_context_length"] = max(0, _safe_int(identity.get("effective_context_length"), 0))
    provider_request["effective_context_source"] = _safe_str(identity.get("effective_context_source"))
    provider_request["load_profile_hash"] = _safe_str(identity.get("load_profile_hash"))
    provider_request["instance_key"] = _safe_str(identity.get("instance_key"))
    return {
        "catalog_models": catalog_models,
        "provider_id": provider_id,
        "task_kind": task_kind,
        "model_id": model_id,
        "catalog_model": catalog_model,
        "registry": registry,
        "provider": provider,
        "provider_request": provider_request,
        "identity": identity,
    }


def _scheduler_reject_result(
    request: dict[str, Any],
    *,
    provider_id: str,
    task_kind: str,
    model_id: str,
    action: str = "",
    error: str,
    slot: dict[str, Any],
) -> dict[str, Any]:
    out = {
        "ok": False,
        "provider": provider_id,
        "taskKind": task_kind,
        "modelId": model_id,
        "error": error,
        "scheduler": dict(slot.get("scheduler") or {}),
        "request": dict(request or {}),
    }
    if action:
        out["action"] = action
    out.setdefault("runtimeVersion", RUNTIME_VERSION)
    out.setdefault("localRuntimeEntryVersion", LOCAL_RUNTIME_ENTRY_VERSION)
    out.setdefault("updatedAt", _now())
    return out


def run_local_task(request: dict[str, Any], *, base_dir: str | None = None) -> dict[str, Any]:
    base = str(base_dir or _base_dir())
    context = _resolve_provider_request_context(request, base_dir=base)
    catalog_models = list(context.get("catalog_models") or [])
    provider_id = _safe_str(context.get("provider_id")).lower()
    task_kind = _safe_str(context.get("task_kind")).lower()
    model_id = _safe_str(context.get("model_id"))
    catalog_model = context.get("catalog_model") if isinstance(context.get("catalog_model"), dict) else None
    provider = context.get("provider")
    provider_request = dict(context.get("provider_request") or {})
    identity = dict(context.get("identity") or {})

    if not provider_id:
        return {
            "ok": False,
            "error": "provider_not_resolved",
            "taskKind": task_kind,
            "request": dict(request or {}),
        }

    if provider is None:
        return {
            "ok": False,
            "provider": provider_id,
            "taskKind": task_kind,
            "error": f"unknown_provider:{provider_id}",
            "request": dict(request or {}),
        }

    if task_kind and task_kind not in provider.supported_task_kinds():
        return {
            "ok": False,
            "provider": provider_id,
            "taskKind": task_kind,
            "error": f"unsupported_task_kind:{task_kind}",
            "request": dict(request or {}),
        }

    if catalog_model is not None and task_kind:
        task_kinds = _normalize_model_task_kinds(catalog_model)
        if task_kinds and task_kind not in task_kinds:
            return {
                "ok": False,
                "provider": provider_id,
                "taskKind": task_kind,
                "modelId": model_id,
                "error": f"model_task_unsupported:{task_kind}",
                "request": dict(request or {}),
            }

    slot = acquire_provider_slot(
        base,
        provider_id,
        request=provider_request,
        catalog_models=catalog_models,
    )
    if not bool(slot.get("ok")):
        out = _scheduler_reject_result(
            request,
            provider_id=provider_id,
            task_kind=task_kind,
            model_id=model_id,
            error=str(slot.get("error") or "provider_busy"),
            slot=slot,
        )
        return _attach_task_identity(out, identity)

    lease_id = str(slot.get("lease_id") or "").strip()
    try:
        out = provider.run_task(provider_request)
    finally:
        release_provider_slot(base, provider_id, lease_id)

    scheduler = dict(slot.get("scheduler") or {})
    if scheduler:
        out.setdefault("scheduler", scheduler)
    out.setdefault("provider", provider_id)
    if task_kind:
        out.setdefault("taskKind", task_kind)
    if model_id:
        out.setdefault("modelId", model_id)
    out.setdefault("runtimeVersion", RUNTIME_VERSION)
    out.setdefault("localRuntimeEntryVersion", LOCAL_RUNTIME_ENTRY_VERSION)
    out.setdefault("updatedAt", _now())
    _publish_runtime_status(base)
    return _attach_task_identity(out, identity)


def manage_local_model(request: dict[str, Any], *, base_dir: str | None = None) -> dict[str, Any]:
    base = str(base_dir or _base_dir())
    action = _normalize_lifecycle_action(
        request.get("action")
        or request.get("command")
        or request.get("operation")
    )
    context = _resolve_provider_request_context(request, base_dir=base)
    catalog_models = list(context.get("catalog_models") or [])
    provider_id = _safe_str(context.get("provider_id")).lower()
    task_kind = _safe_str(context.get("task_kind")).lower()
    model_id = _safe_str(context.get("model_id"))
    provider = context.get("provider")
    provider_request = dict(context.get("provider_request") or {})
    identity = dict(context.get("identity") or {})

    if not action:
        out = {
            "ok": False,
            "action": "",
            "error": "missing_lifecycle_action",
            "request": dict(request or {}),
            "runtimeVersion": RUNTIME_VERSION,
            "localRuntimeEntryVersion": LOCAL_RUNTIME_ENTRY_VERSION,
            "updatedAt": _now(),
        }
        return _attach_task_identity(out, identity)

    if not provider_id:
        out = {
            "ok": False,
            "action": action,
            "error": "provider_not_resolved",
            "taskKind": task_kind,
            "modelId": model_id,
            "request": dict(request or {}),
            "runtimeVersion": RUNTIME_VERSION,
            "localRuntimeEntryVersion": LOCAL_RUNTIME_ENTRY_VERSION,
            "updatedAt": _now(),
        }
        return _attach_task_identity(out, identity)

    if provider is None:
        out = {
            "ok": False,
            "provider": provider_id,
            "action": action,
            "taskKind": task_kind,
            "modelId": model_id,
            "error": f"unknown_provider:{provider_id}",
            "request": dict(request or {}),
            "runtimeVersion": RUNTIME_VERSION,
            "localRuntimeEntryVersion": LOCAL_RUNTIME_ENTRY_VERSION,
            "updatedAt": _now(),
        }
        return _attach_task_identity(out, identity)

    slot = acquire_provider_slot(
        base,
        provider_id,
        request=provider_request,
        catalog_models=catalog_models,
    )
    if not bool(slot.get("ok")):
        out = _scheduler_reject_result(
            request,
            provider_id=provider_id,
            task_kind=task_kind,
            model_id=model_id,
            action=action,
            error=str(slot.get("error") or "provider_busy"),
            slot=slot,
        )
        return _attach_task_identity(out, identity)

    lease_id = str(slot.get("lease_id") or "").strip()
    try:
        if action == "warmup_local_model":
            out = provider.warmup_model(provider_request)
        elif action == "unload_local_model":
            out = provider.unload_model(provider_request)
        elif action == "evict_local_instance":
            out = provider.evict_instance(provider_request)
        else:
            out = {
                "ok": False,
                "provider": provider_id,
                "action": action,
                "taskKind": task_kind,
                "modelId": model_id,
                "error": f"unsupported_lifecycle_action:{action}",
                "request": dict(request or {}),
            }
    finally:
        release_provider_slot(base, provider_id, lease_id)

    scheduler = dict(slot.get("scheduler") or {})
    if scheduler:
        out.setdefault("scheduler", scheduler)
    out.setdefault("provider", provider_id)
    out.setdefault("action", action)
    if task_kind:
        out.setdefault("taskKind", task_kind)
    if model_id:
        out.setdefault("modelId", model_id)
    out.setdefault("runtimeVersion", RUNTIME_VERSION)
    out.setdefault("localRuntimeEntryVersion", LOCAL_RUNTIME_ENTRY_VERSION)
    out.setdefault("updatedAt", _now())
    _publish_runtime_status(base)
    return _attach_task_identity(out, identity)


def _load_request_arg(raw: str) -> dict[str, Any]:
    token = str(raw or "").strip()
    if not token:
        return {}
    if token == "-":
        data = sys.stdin.read()
        return json.loads(data) if data.strip() else {}
    if os.path.exists(token):
        with open(token, "r", encoding="utf-8") as handle:
            obj = json.load(handle)
        return obj if isinstance(obj, dict) else {}
    obj = json.loads(token)
    return obj if isinstance(obj, dict) else {}


def _status_payload(base_dir: str) -> dict[str, Any]:
    providers = provider_status_snapshot(base_dir)
    loaded_instances = _flatten_loaded_instances(providers)
    idle_eviction_by_provider = _idle_eviction_by_provider(providers)
    ready_provider_ids = sorted(
        provider_id
        for provider_id, status in providers.items()
        if isinstance(status, dict) and bool(status.get("ok"))
    )
    return {
        "schemaVersion": LOCAL_RUNTIME_STATUS_SCHEMA_VERSION,
        "runtimeVersion": RUNTIME_VERSION,
        "localRuntimeEntryVersion": LOCAL_RUNTIME_ENTRY_VERSION,
        "baseDir": base_dir,
        "providerIds": sorted(providers.keys()),
        "readyProviderIds": ready_provider_ids,
        "catalogModelCount": len(read_catalog_models(base_dir)),
        "loadedInstances": loaded_instances,
        "loadedInstanceCount": len(loaded_instances),
        "idleEvictionByProvider": idle_eviction_by_provider,
        "providers": providers,
        "updatedAt": _now(),
    }


def _print_status(base_dir: str) -> None:
    print(json.dumps(_status_payload(base_dir), ensure_ascii=False, indent=2), flush=True)


def main(argv: list[str] | None = None) -> int:
    apply_offline_env()
    args = list(sys.argv[1:] if argv is None else argv)
    base_dir = _base_dir()
    os.makedirs(base_dir, exist_ok=True)

    if args:
        cmd = str(args[0] or "").strip().lower()
        if cmd in {"status", "--status", "--status-json", "providers"}:
            _print_status(base_dir)
            return 0
        if cmd == "run-local-task":
            request = _load_request_arg(args[1] if len(args) > 1 else "-")
            print(json.dumps(run_local_task(request, base_dir=base_dir), ensure_ascii=False, indent=2), flush=True)
            return 0
        if cmd in {"manage-local-model", "warmup-local-model", "unload-local-model", "evict-local-instance"}:
            request = _load_request_arg(args[1] if len(args) > 1 else "-")
            if cmd != "manage-local-model":
                action = cmd.replace("-", "_")
                request = dict(request or {})
                request.setdefault("action", action)
            print(json.dumps(manage_local_model(request, base_dir=base_dir), ensure_ascii=False, indent=2), flush=True)
            return 0

    snapshot = _status_payload(base_dir)
    ready = snapshot.get("readyProviderIds") or []
    ready_text = ",".join(str(provider_id) for provider_id in ready) if ready else "none"
    print(
        f"[local_runtime] start pid={os.getpid()} version={RUNTIME_VERSION} "
        f"entry={LOCAL_RUNTIME_ENTRY_VERSION} ready={ready_text}",
        flush=True,
    )
    return run_legacy_runtime()


if __name__ == "__main__":
    raise SystemExit(main())
