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
import uuid
from typing import Any

from local_provider_scheduler import acquire_provider_slot, release_provider_slot
from provider_pack_registry import (
    attach_provider_pack_truth,
    enforce_provider_pack_truth,
    provider_pack_inventory,
)
from providers import LlamaCppProvider, LocalProviderRegistry, MLXProvider, MLXVLMProvider, TransformersProvider
from providers.mlx_provider import run_legacy_runtime


# Keep this aligned with the legacy runtime version so Hub's runtime-version
# watchdog does not trigger restart loops during the delegate phase.
RUNTIME_VERSION = "2026-03-14-mlx-instance-identity-v1"
LOCAL_RUNTIME_ENTRY_VERSION = "2026-03-13-lpr-scheduler-v1"
LOCAL_RUNTIME_STATUS_SCHEMA_VERSION = "xhub.local_provider_runtime.entry.v1"
LOCAL_RUNTIME_COMMAND_IPC_VERSION = "xhub.local_runtime_command_ipc.v1"
PAIRED_TERMINAL_LOCAL_MODEL_PROFILES_FILENAME = "hub_paired_terminal_local_model_profiles.json"
MODELS_BENCH_SCHEMA_VERSION = "xhub.models_bench.v2"
ROUTE_TRACE_SUMMARY_SCHEMA_VERSION = "xhub.local_runtime.route_trace_summary.v1"
RECENT_BENCH_RESULT_LIMIT = 8
_REGISTRIES_BY_BASE_DIR: dict[str, LocalProviderRegistry] = {}
LOAD_PROFILE_FIELD_ALIASES = {
    "context_length": ("context_length", "contextLength"),
    "gpu_offload_ratio": ("gpu_offload_ratio", "gpuOffloadRatio", "gpu_offload", "gpuOffload"),
    "rope_frequency_base": ("rope_frequency_base", "ropeFrequencyBase"),
    "rope_frequency_scale": ("rope_frequency_scale", "ropeFrequencyScale"),
    "eval_batch_size": ("eval_batch_size", "evalBatchSize"),
    "ttl": ("ttl", "ttl_sec", "ttlSec"),
    "parallel": ("parallel",),
    "identifier": ("identifier", "deviceIdentifier"),
}
VISION_LOAD_PROFILE_FIELD_ALIASES = {
    "image_max_dimension": (
        "image_max_dimension",
        "imageMaxDimension",
        "vision_image_max_dimension",
        "visionImageMaxDimension",
    ),
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


def _safe_bool(value: Any, fallback: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    token = _safe_str(value).lower()
    if token in {"1", "true", "yes", "on"}:
        return True
    if token in {"0", "false", "no", "off"}:
        return False
    return bool(fallback)


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


def _normalize_progress(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    number = _safe_float(value, float("nan"))
    if not math.isfinite(number):
        return None
    return min(1.0, max(0.0, number))


def _request_instance_key(request: dict[str, Any]) -> str:
    return _safe_str(request.get("instance_key") or request.get("instanceKey"))


def _request_load_profile_hash(request: dict[str, Any]) -> str:
    return _safe_str(request.get("load_profile_hash") or request.get("loadProfileHash"))


def _request_allows_daemon_proxy(request: dict[str, Any]) -> bool:
    return _safe_bool(
        request.get("allow_daemon_proxy", request.get("allowDaemonProxy")),
        True,
    )


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


def _normalize_route_trace_payload(raw: Any) -> dict[str, Any] | None:
    value = _sanitize_json_value(raw)
    return value if isinstance(value, dict) and value else None


def _extract_route_trace(result: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(result, dict):
        return None
    return _normalize_route_trace_payload(result.get("routeTrace") or result.get("route_trace"))


def _route_trace_summary_payload(raw: Any) -> dict[str, Any] | None:
    trace = _normalize_route_trace_payload(raw)
    if trace is None:
        return None
    resolved_images = trace.get("resolvedImages") if isinstance(trace.get("resolvedImages"), list) else []
    image_files = [file_name for file_name in _safe_string_list(trace.get("imageFiles") or trace.get("image_files")) if file_name]
    for item in resolved_images:
        if not isinstance(item, dict):
            continue
        file_name = _safe_str(item.get("fileName") or item.get("file_name"))
        if file_name and file_name not in image_files:
            image_files.append(file_name)
    out = {
        "schemaVersion": ROUTE_TRACE_SUMMARY_SCHEMA_VERSION,
        "traceSchemaVersion": _safe_str(trace.get("schemaVersion") or trace.get("schema_version")),
        "requestMode": _safe_str(trace.get("requestMode") or trace.get("request_mode")),
        "selectedTaskKind": _safe_str(trace.get("selectedTaskKind") or trace.get("selected_task_kind") or trace.get("taskKind") or trace.get("task_kind")),
        "selectionReason": _safe_str(trace.get("selectionReason") or trace.get("selection_reason")),
        "explicitTaskKind": _safe_str(trace.get("explicitTaskKind") or trace.get("explicit_task_kind")),
        "imageCount": max(0, _safe_int(trace.get("imageCount") or trace.get("image_count"), 0)),
        "resolvedImageCount": max(0, _safe_int(trace.get("resolvedImageCount") or trace.get("resolved_image_count"), 0)),
        "blockedReasonCode": _safe_str(trace.get("blockedReasonCode") or trace.get("blocked_reason_code")),
        "blockedImageIndex": max(0, _safe_int(trace.get("blockedImageIndex") or trace.get("blocked_image_index"), 0))
        if (trace.get("blockedImageIndex") is not None or trace.get("blocked_image_index") is not None)
        else None,
        "promptChars": max(0, _safe_int(trace.get("promptChars") or trace.get("prompt_chars"), 0)),
        "executionPath": _safe_str(trace.get("executionPath") or trace.get("execution_path")),
        "fallbackMode": _safe_str(trace.get("fallbackMode") or trace.get("fallback_mode")),
        "imageFiles": image_files,
    }
    normalized: dict[str, Any] = {}
    for key, value in out.items():
        if value is None:
            continue
        if isinstance(value, str) and not value:
            continue
        if isinstance(value, list) and not value:
            continue
        normalized[key] = value
    return normalized


def _load_profile_field_present(profile: dict[str, Any], field: str) -> tuple[bool, Any]:
    aliases = LOAD_PROFILE_FIELD_ALIASES.get(field) or ()
    for alias in aliases:
        if alias in profile:
            return True, profile.get(alias)
    return False, None


def _load_profile_vision_field_present(profile: dict[str, Any], field: str) -> tuple[bool, Any]:
    aliases = VISION_LOAD_PROFILE_FIELD_ALIASES.get(field) or ()
    vision = profile.get("vision") if isinstance(profile.get("vision"), dict) else {}
    for alias in aliases:
        if alias in vision:
            return True, vision.get(alias)
    for alias in aliases:
        if alias in profile:
            return True, profile.get(alias)
    return False, None


def _normalize_vision_profile_value(raw_value: Any) -> int | None:
    value = _safe_int(raw_value, 0)
    if value <= 0:
        return None
    return min(16_384, max(32, value))


def _normalized_vision_profile_unknown_fields(profile: dict[str, Any]) -> dict[str, Any]:
    vision = profile.get("vision") if isinstance(profile.get("vision"), dict) else {}
    known_aliases = {
        alias
        for aliases in VISION_LOAD_PROFILE_FIELD_ALIASES.values()
        for alias in aliases
    }
    out: dict[str, Any] = {}
    for raw_key, raw_value in vision.items():
        key = _safe_str(raw_key)
        if not key or key in known_aliases:
            continue
        out[key] = _sanitize_json_value(raw_value)
    return out


def _normalized_load_profile_vision(profile: dict[str, Any]) -> dict[str, Any]:
    out = _normalized_vision_profile_unknown_fields(profile)
    present, raw_image_max_dimension = _load_profile_vision_field_present(profile, "image_max_dimension")
    if present and raw_image_max_dimension is not None:
        value = _normalize_vision_profile_value(raw_image_max_dimension)
        if value is not None:
            out["image_max_dimension"] = value
    return out


def _unknown_load_profile_fields(profile: dict[str, Any]) -> dict[str, Any]:
    known_aliases = {
        alias
        for aliases in LOAD_PROFILE_FIELD_ALIASES.values()
        for alias in aliases
    }
    known_aliases.update({"vision"})
    known_aliases.update(
        alias
        for aliases in VISION_LOAD_PROFILE_FIELD_ALIASES.values()
        for alias in aliases
    )
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
    raw_profile = (
        row.get("default_load_config")
        if isinstance(row.get("default_load_config"), dict)
        else row.get("defaultLoadConfig")
    )
    if not isinstance(raw_profile, dict):
        raw_profile = (
            row.get("default_load_profile")
            if isinstance(row.get("default_load_profile"), dict)
            else row.get("defaultLoadProfile")
        )
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

    present, raw_ttl = _load_profile_field_present(profile, "ttl")
    if present and raw_ttl is not None:
        value = _safe_int(raw_ttl, 0)
        if value > 0:
            out["ttl"] = value

    present, raw_parallel = _load_profile_field_present(profile, "parallel")
    if present and raw_parallel is not None:
        value = _safe_int(raw_parallel, 0)
        if value > 0:
            out["parallel"] = value

    present, raw_identifier = _load_profile_field_present(profile, "identifier")
    if present and raw_identifier is not None:
        value = _safe_str(raw_identifier)
        if value:
            out["identifier"] = value

    vision = _normalized_load_profile_vision(profile)
    if vision:
        out["vision"] = vision

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

    present, raw_ttl = _load_profile_field_present(profile, "ttl")
    if present and raw_ttl is not None:
        value = _safe_int(raw_ttl, 0)
        if value > 0:
            out["ttl"] = value
        else:
            out.pop("ttl", None)

    present, raw_parallel = _load_profile_field_present(profile, "parallel")
    if present and raw_parallel is not None:
        value = _safe_int(raw_parallel, 0)
        if value > 0:
            out["parallel"] = value
        else:
            out.pop("parallel", None)

    present, raw_identifier = _load_profile_field_present(profile, "identifier")
    if present and raw_identifier is not None:
        value = _safe_str(raw_identifier)
        if value:
            out["identifier"] = value
        else:
            out.pop("identifier", None)

    vision = dict(out.get("vision")) if isinstance(out.get("vision"), dict) else {}
    for key, value in _normalized_vision_profile_unknown_fields(profile).items():
        vision[key] = value
    present, raw_image_max_dimension = _load_profile_vision_field_present(profile, "image_max_dimension")
    if present:
        value = _normalize_vision_profile_value(raw_image_max_dimension)
        if value is not None:
            vision["image_max_dimension"] = value
        else:
            vision.pop("image_max_dimension", None)
    if vision:
        out["vision"] = vision
    else:
        out.pop("vision", None)

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


def _clamp_provider_specific_load_profile(
    profile: dict[str, Any],
    *,
    provider_id: str,
    request: dict[str, Any],
    catalog_model: dict[str, Any] | None,
) -> dict[str, Any]:
    out = dict(profile or {})
    requested_task_kind = _safe_str(request.get("task_kind") or request.get("taskKind")).lower()
    task_kinds = [requested_task_kind] if requested_task_kind else _normalize_model_task_kinds(catalog_model)
    if provider_id == "mlx_vlm" and any(task_kind in {"vision_understand", "ocr"} for task_kind in task_kinds):
        parallel = max(0, _safe_int(out.get("parallel"), 0))
        if parallel > 1:
            # LM Studio helper-backed vision models currently reject continuous batching.
            out["parallel"] = 1
    return out


def _resolve_model_load_profile_context(
    request: dict[str, Any],
    *,
    base_dir: str,
    provider_id: str,
    model_id: str,
    catalog_model: dict[str, Any] | None,
) -> dict[str, Any]:
    model_source = dict(catalog_model or {})
    for key in (
        "context_length",
        "contextLength",
        "max_context_length",
        "maxContextLength",
        "default_load_config",
        "defaultLoadConfig",
        "default_load_profile",
        "defaultLoadProfile",
    ):
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
    effective_profile = _clamp_provider_specific_load_profile(
        effective_profile,
        provider_id=provider_id,
        request=request,
        catalog_model=catalog_model,
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


def build_registry(
    *,
    base_dir: str | None = None,
    runtime: Any | None = None,
    resident_transformers: bool | None = None,
) -> LocalProviderRegistry:
    base = os.path.abspath(str(base_dir or _base_dir()))
    registry = _REGISTRIES_BY_BASE_DIR.get(base)
    if registry is None:
        registry = LocalProviderRegistry()
        _REGISTRIES_BY_BASE_DIR[base] = registry

    mlx_provider = registry.get("mlx")
    if isinstance(mlx_provider, MLXProvider):
        mlx_provider._runtime = runtime
        mlx_provider._runtime_version = RUNTIME_VERSION
    else:
        registry.register(MLXProvider(runtime=runtime, runtime_version=RUNTIME_VERSION))

    transformers_provider = registry.get("transformers")
    resolved_resident_transformers = (
        bool(resident_transformers)
        if resident_transformers is not None
        else (
            isinstance(transformers_provider, TransformersProvider)
            and transformers_provider.residency_scope() == "runtime_process"
        )
    )
    if isinstance(transformers_provider, TransformersProvider):
        if resident_transformers is not None:
            transformers_provider.set_resident_runtime_mode(bool(resident_transformers))
    else:
        registry.register(TransformersProvider(resident_runtime_mode=resolved_resident_transformers))

    mlx_vlm_provider = registry.get("mlx_vlm")
    if isinstance(mlx_vlm_provider, MLXVLMProvider):
        if resident_transformers is not None:
            mlx_vlm_provider.set_resident_runtime_mode(bool(resident_transformers))
    else:
        registry.register(MLXVLMProvider(resident_runtime_mode=resolved_resident_transformers))

    llama_cpp_provider = registry.get("llama.cpp")
    if not isinstance(llama_cpp_provider, LlamaCppProvider):
        registry.register(LlamaCppProvider())

    return registry


def provider_status_snapshot(
    base_dir: str,
    *,
    runtime: Any | None = None,
    resident_transformers: bool | None = None,
) -> dict[str, dict[str, Any]]:
    catalog_models = read_catalog_models(base_dir)
    snapshot = build_registry(
        base_dir=base_dir,
        runtime=runtime,
        resident_transformers=resident_transformers,
    ).health_snapshot(
        base_dir=base_dir,
        catalog_models=catalog_models,
    )
    statuses = {provider_id: health.to_dict() for provider_id, health in snapshot.items()}
    packs = provider_pack_inventory(statuses.keys(), base_dir=base_dir)
    statuses = attach_provider_pack_truth(statuses, packs)
    return enforce_provider_pack_truth(statuses, packs)


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
            if row.get("ttl") is None:
                ttl_profile = (
                    row.get("effectiveLoadProfile")
                    if isinstance(row.get("effectiveLoadProfile"), dict)
                    else row.get("effective_load_profile")
                    if isinstance(row.get("effective_load_profile"), dict)
                    else row.get("loadConfig")
                    if isinstance(row.get("loadConfig"), dict)
                    else row.get("load_config")
                    if isinstance(row.get("load_config"), dict)
                    else {}
                )
                ttl = _safe_int(ttl_profile.get("ttl") if isinstance(ttl_profile, dict) else None, 0)
                if ttl > 0:
                    row["ttl"] = ttl
            progress = _normalize_progress(row.get("progress"))
            if progress is not None:
                row["progress"] = progress
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


def _runtime_status_path(base_dir: str) -> str:
    return os.path.join(base_dir, "ai_runtime_status.json")


def _runtime_status_mirror_paths(base_dir: str) -> list[str]:
    normalized_base = os.path.abspath(os.path.expanduser(base_dir or ""))
    if not normalized_base:
        return []

    # Only home/public runtimes mirror their status out. Container-hosted runtimes
    # already publish directly into the sandbox-visible base dir, so mirroring them
    # would overwrite the higher-signal home runtime fallback we want to preserve.
    if "/Library/Containers/" in normalized_base or normalized_base.startswith("/private/tmp/"):
        return []

    home = os.path.expanduser("~")
    candidates = [
        os.path.join("/private/tmp", "XHub", "ai_runtime_status.json"),
        os.path.join("/private/tmp", "RELFlowHub", "ai_runtime_status.json"),
        os.path.join(home, "Library", "Containers", "com.rel.flowhub", "Data", "XHub", "ai_runtime_status.json"),
    ]

    out: list[str] = []
    seen: set[str] = set()
    for raw_path in candidates:
        normalized = os.path.abspath(os.path.expanduser(raw_path))
        if not normalized or normalized == _runtime_status_path(base_dir) or normalized in seen:
            continue
        seen.add(normalized)
        out.append(normalized)
    return out


def _runtime_command_req_dir(base_dir: str) -> str:
    return os.path.join(base_dir, "local_runtime_commands")


def _runtime_command_resp_dir(base_dir: str) -> str:
    return os.path.join(base_dir, "local_runtime_command_results")


def _runtime_command_resp_path(base_dir: str, req_id: str) -> str:
    return os.path.join(_runtime_command_resp_dir(base_dir), f"resp_{req_id}.json")


def _write_json_atomic(path: str, obj: Any) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(obj, handle, ensure_ascii=False)
    os.replace(tmp, path)


def _models_bench_path(base_dir: str) -> str:
    return os.path.join(base_dir, "models_bench.json")


def _runtime_supports_command_proxy(base_dir: str, *, max_age_sec: float = 5.0) -> bool:
    path = _runtime_status_path(base_dir)
    if not os.path.exists(path):
        return False
    try:
        with open(path, "r", encoding="utf-8") as handle:
            obj = json.load(handle)
    except Exception:
        return False

    version = _safe_str(obj.get("localCommandIpcVersion") or obj.get("local_command_ipc_version"))
    if version != LOCAL_RUNTIME_COMMAND_IPC_VERSION:
        return False
    updated_at = _safe_float(obj.get("updatedAt") or obj.get("updated_at"), 0.0)
    if updated_at <= 0:
        return False
    if (_now() - updated_at) > max(1.0, float(max_age_sec or 0.0)):
        return False
    runtime_pid = max(0, _safe_int(obj.get("pid"), 0))
    return runtime_pid > 1 and runtime_pid != os.getpid()


def _proxy_runtime_command(
    base_dir: str,
    *,
    command: str,
    request: dict[str, Any],
    timeout_sec: float,
) -> dict[str, Any]:
    req_id = uuid.uuid4().hex
    req_dir = _runtime_command_req_dir(base_dir)
    resp_dir = _runtime_command_resp_dir(base_dir)
    os.makedirs(req_dir, exist_ok=True)
    os.makedirs(resp_dir, exist_ok=True)
    req_path = os.path.join(req_dir, f"cmd_{req_id}.json")
    resp_path = _runtime_command_resp_path(base_dir, req_id)
    try:
        if os.path.exists(resp_path):
            os.remove(resp_path)
    except Exception:
        pass
    _write_json_atomic(
        req_path,
        {
            "type": "local_runtime_command",
            "req_id": req_id,
            "command": _safe_str(command),
            "request": dict(request or {}),
            "requested_at": _now(),
        },
    )

    deadline = _now() + max(1.0, float(timeout_sec or 0.0))
    while _now() < deadline:
        if os.path.exists(resp_path):
            try:
                with open(resp_path, "r", encoding="utf-8") as handle:
                    obj = json.load(handle)
                return obj if isinstance(obj, dict) else {
                    "ok": False,
                    "error": "invalid_runtime_command_response",
                }
            finally:
                try:
                    os.remove(resp_path)
                except Exception:
                    pass
        time.sleep(0.03)

    try:
        if os.path.exists(req_path):
            os.remove(req_path)
    except Exception:
        pass
    return {
        "ok": False,
        "error": f"runtime_command_timeout:{_safe_str(command) or 'unknown'}",
        "runtimeVersion": RUNTIME_VERSION,
        "localRuntimeEntryVersion": LOCAL_RUNTIME_ENTRY_VERSION,
        "updatedAt": _now(),
    }


def _normalize_bench_result_id(result: dict[str, Any]) -> str:
    explicit = _safe_str(result.get("resultID") or result.get("resultId") or result.get("result_id"))
    if explicit:
        return explicit
    model_id = _safe_str(result.get("modelId") or result.get("model_id"))
    task_kind = _safe_str(result.get("taskKind") or result.get("task_kind")).lower()
    load_profile_hash = _safe_str(result.get("loadProfileHash") or result.get("load_profile_hash"))
    fixture_profile = _safe_str(result.get("fixtureProfile") or result.get("fixture_profile"))
    return "::".join([model_id, task_kind, load_profile_hash, fixture_profile])


def _normalize_bench_result_payload(result: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(result, dict):
        return None
    model_id = _safe_str(result.get("modelId") or result.get("model_id"))
    task_kind = _safe_str(result.get("taskKind") or result.get("task_kind")).lower()
    fixture_profile = _safe_str(result.get("fixtureProfile") or result.get("fixture_profile"))
    if not model_id or not task_kind or not fixture_profile:
        return None
    notes = result.get("notes")
    route_trace = _extract_route_trace(result)
    route_trace_summary = _route_trace_summary_payload(
        result.get("routeTraceSummary") or result.get("route_trace_summary") or route_trace
    )
    out = {
        "resultID": _normalize_bench_result_id(result),
        "modelId": model_id,
        "providerID": _safe_str(result.get("provider") or result.get("providerID") or result.get("provider_id")).lower(),
        "taskKind": task_kind,
        "loadProfileHash": _safe_str(result.get("loadProfileHash") or result.get("load_profile_hash")),
        "fixtureProfile": fixture_profile,
        "fixtureTitle": _safe_str(result.get("fixtureTitle") or result.get("fixture_title")),
        "measuredAt": _safe_float(result.get("measuredAt") or result.get("measured_at") or result.get("updatedAt") or result.get("updated_at"), _now()),
        "runtimeVersion": _safe_str(result.get("runtimeVersion") or result.get("runtime_version")),
        "schemaVersion": _safe_str(result.get("schemaVersion") or result.get("schema_version")) or MODELS_BENCH_SCHEMA_VERSION,
        "resultKind": _safe_str(result.get("resultKind") or result.get("result_kind")) or "task_aware_quick_bench",
        "ok": bool(result.get("ok")),
        "reasonCode": _safe_str(result.get("reasonCode") or result.get("reason_code") or result.get("error")),
        "runtimeSource": _safe_str(result.get("runtimeSource") or result.get("runtime_source")),
        "runtimeSourcePath": _safe_str(result.get("runtimeSourcePath") or result.get("runtime_source_path")),
        "runtimeResolutionState": _safe_str(result.get("runtimeResolutionState") or result.get("runtime_resolution_state")).lower(),
        "runtimeReasonCode": _safe_str(result.get("runtimeReasonCode") or result.get("runtime_reason_code")),
        "fallbackUsed": bool(result.get("fallbackUsed") if result.get("fallbackUsed") is not None else result.get("fallback_used")),
        "runtimeHint": _safe_str(result.get("runtimeHint") or result.get("runtime_hint")),
        "runtimeMissingRequirements": _safe_string_list(
            result.get("runtimeMissingRequirements") or result.get("runtime_missing_requirements")
        ),
        "runtimeMissingOptionalRequirements": _safe_string_list(
            result.get("runtimeMissingOptionalRequirements") or result.get("runtime_missing_optional_requirements")
        ),
        "verdict": _safe_str(result.get("verdict")),
        "fallbackMode": _safe_str(result.get("fallbackMode") or result.get("fallback_mode")),
        "notes": [str(item or "").strip() for item in notes] if isinstance(notes, list) else [],
        "coldStartMs": result.get("coldStartMs") if result.get("coldStartMs") is not None else result.get("cold_start_ms"),
        "latencyMs": result.get("latencyMs") if result.get("latencyMs") is not None else result.get("latency_ms"),
        "peakMemoryBytes": result.get("peakMemoryBytes") if result.get("peakMemoryBytes") is not None else result.get("peak_memory_bytes"),
        "throughputValue": result.get("throughputValue") if result.get("throughputValue") is not None else result.get("throughput_value"),
        "throughputUnit": _safe_str(result.get("throughputUnit") or result.get("throughput_unit")),
        "effectiveContextLength": result.get("effectiveContextLength") if result.get("effectiveContextLength") is not None else result.get("effective_context_length"),
        "promptTokens": result.get("promptTokens") if result.get("promptTokens") is not None else result.get("prompt_tokens"),
        "generationTokens": result.get("generationTokens") if result.get("generationTokens") is not None else result.get("generation_tokens"),
        "promptTPS": result.get("promptTPS") if result.get("promptTPS") is not None else result.get("prompt_tps"),
        "generationTPS": result.get("generationTPS") if result.get("generationTPS") is not None else result.get("generation_tps"),
    }
    if route_trace is not None:
        out["routeTrace"] = route_trace
    if route_trace_summary is not None:
        out["routeTraceSummary"] = route_trace_summary
    return out


def _load_models_bench_snapshot(base_dir: str) -> dict[str, Any]:
    path = _models_bench_path(base_dir)
    if not os.path.exists(path):
        return {
            "schemaVersion": MODELS_BENCH_SCHEMA_VERSION,
            "results": [],
            "updatedAt": _now(),
        }
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except Exception:
        return {
            "schemaVersion": MODELS_BENCH_SCHEMA_VERSION,
            "results": [],
            "updatedAt": _now(),
        }
    if isinstance(raw, dict) and isinstance(raw.get("results"), list):
        return {
            "schemaVersion": _safe_str(raw.get("schemaVersion") or raw.get("schema_version")) or MODELS_BENCH_SCHEMA_VERSION,
            "results": [item for item in raw.get("results") if isinstance(item, dict)],
            "updatedAt": _safe_float(raw.get("updatedAt") or raw.get("updated_at"), _now()),
        }
    if isinstance(raw, list):
        return {
            "schemaVersion": MODELS_BENCH_SCHEMA_VERSION,
            "results": [item for item in raw if isinstance(item, dict)],
            "updatedAt": _now(),
        }
    if isinstance(raw, dict) and isinstance(raw.get("models"), dict):
        results: list[dict[str, Any]] = []
        for model_id, row in raw.get("models", {}).items():
            if not isinstance(row, dict):
                continue
            legacy = dict(row)
            legacy.setdefault("modelId", _safe_str(model_id))
            results.append(legacy)
        return {
            "schemaVersion": MODELS_BENCH_SCHEMA_VERSION,
            "results": results,
            "updatedAt": _safe_float(raw.get("updatedAt") or raw.get("updated_at"), _now()),
        }
    return {
        "schemaVersion": MODELS_BENCH_SCHEMA_VERSION,
        "results": [],
        "updatedAt": _now(),
    }


def _persist_bench_result(base_dir: str, result: dict[str, Any]) -> None:
    normalized = _normalize_bench_result_payload(result)
    if normalized is None:
        return
    snapshot = _load_models_bench_snapshot(base_dir)
    existing = [item for item in snapshot.get("results", []) if isinstance(item, dict)]
    result_id = _normalize_bench_result_id(normalized)
    retained = [item for item in existing if _normalize_bench_result_id(item) != result_id]
    retained.append(normalized)
    retained.sort(
        key=lambda item: (
            -_safe_float(item.get("measuredAt") or item.get("measured_at"), 0.0),
            _normalize_bench_result_id(item),
        )
    )
    _write_json_atomic(
        _models_bench_path(base_dir),
        {
            "schemaVersion": MODELS_BENCH_SCHEMA_VERSION,
            "results": retained,
            "updatedAt": _now(),
        },
    )


def _recent_bench_results(base_dir: str, *, limit: int = RECENT_BENCH_RESULT_LIMIT) -> list[dict[str, Any]]:
    snapshot = _load_models_bench_snapshot(base_dir)
    rows: list[dict[str, Any]] = []
    for raw in snapshot.get("results", []):
        if not isinstance(raw, dict):
            continue
        normalized = _normalize_bench_result_payload(raw)
        if normalized is None:
            continue
        rows.append(normalized)
    rows.sort(
        key=lambda item: (
            -_safe_float(item.get("measuredAt") or item.get("measured_at"), 0.0),
            _normalize_bench_result_id(item),
        )
    )
    return rows[: max(1, int(limit or RECENT_BENCH_RESULT_LIMIT))]


def _provider_task_sets(status: dict[str, Any]) -> tuple[list[str], list[str], list[str], list[str]]:
    available = _safe_string_list(status.get("availableTaskKinds") or status.get("available_task_kinds"))
    real = _safe_string_list(status.get("realTaskKinds") or status.get("real_task_kinds"))
    fallback = _safe_string_list(status.get("fallbackTaskKinds") or status.get("fallback_task_kinds"))
    unavailable = _safe_string_list(status.get("unavailableTaskKinds") or status.get("unavailable_task_kinds"))
    reason_code = _safe_str(status.get("reasonCode") or status.get("reason_code")).lower()
    provider_id = _safe_str(status.get("provider")).lower()

    if not real and not fallback:
        if reason_code == "fallback_ready":
            fallback = list(available)
        else:
            real = list(available)
    if provider_id == "mlx" and not real and not fallback and available:
        real = list(available)
    return available, real, fallback, unavailable


def _provider_last_error_record(provider_id: str, status: dict[str, Any]) -> dict[str, Any] | None:
    ok = bool(status.get("ok"))
    reason_code = _safe_str(status.get("reasonCode") or status.get("reason_code"))
    import_error = _safe_str(status.get("importError") or status.get("import_error"))
    if ok and not import_error:
        return None
    message = import_error or reason_code or "provider_unavailable"
    if not message:
        return None
    return {
        "provider": _safe_str(provider_id).lower(),
        "code": reason_code or ("import_error" if import_error else "provider_unavailable"),
        "message": message,
        "severity": "error" if not ok else "warn",
        "updatedAt": _safe_float(status.get("updatedAt") or status.get("updated_at"), 0.0),
    }


def build_runtime_monitor_snapshot(
    provider_statuses: dict[str, dict[str, Any]],
    *,
    loaded_instances: list[dict[str, Any]] | None = None,
    idle_eviction_by_provider: dict[str, dict[str, Any]] | None = None,
    recent_bench_results: list[dict[str, Any]] | None = None,
    updated_at: float | None = None,
) -> dict[str, Any]:
    providers = provider_statuses if isinstance(provider_statuses, dict) else {}
    flattened_loaded_instances = loaded_instances if isinstance(loaded_instances, list) else _flatten_loaded_instances(providers)
    eviction_snapshot = idle_eviction_by_provider if isinstance(idle_eviction_by_provider, dict) else _idle_eviction_by_provider(providers)
    recent_bench_rows = [dict(item) for item in (recent_bench_results or []) if isinstance(item, dict)]
    generated_at = _safe_float(updated_at, 0.0) or _now()

    monitor_provider_rows: list[dict[str, Any]] = []
    active_tasks: list[dict[str, Any]] = []
    last_errors: list[dict[str, Any]] = []
    queue_rows: list[dict[str, Any]] = []
    fallback_task_kind_counts: dict[str, int] = {}
    fallback_ready_provider_count = 0
    fallback_only_provider_count = 0
    fallback_ready_task_count = 0
    fallback_only_task_count = 0
    total_active_task_count = 0
    total_queued_task_count = 0
    total_contention_count = 0
    providers_busy_count = 0
    providers_with_queued_tasks_count = 0
    max_oldest_wait_ms = 0
    last_contention_at = 0.0

    for provider_id in sorted(providers.keys()):
        status = providers.get(provider_id)
        if not isinstance(status, dict):
            continue
        normalized_provider_id = _safe_str(provider_id).lower()
        available_task_kinds, real_task_kinds, fallback_task_kinds, unavailable_task_kinds = _provider_task_sets(status)
        scheduler_state = status.get("schedulerState") or status.get("scheduler_state") or {}
        if not isinstance(scheduler_state, dict):
            scheduler_state = {}
        provider_loaded_instances = [
            row for row in flattened_loaded_instances
            if _safe_str(row.get("provider")).lower() == normalized_provider_id
        ]
        active_memory_bytes_raw = status.get("activeMemoryBytes") if "activeMemoryBytes" in status else status.get("active_memory_bytes")
        peak_memory_bytes_raw = status.get("peakMemoryBytes") if "peakMemoryBytes" in status else status.get("peak_memory_bytes")
        active_memory_known = active_memory_bytes_raw is not None
        peak_memory_known = peak_memory_bytes_raw is not None
        active_memory_bytes = max(0, _safe_int(active_memory_bytes_raw, 0)) if active_memory_known else 0
        peak_memory_bytes = max(0, _safe_int(peak_memory_bytes_raw, 0)) if peak_memory_known else 0
        loaded_model_count = max(
            len(_safe_string_list(status.get("loadedModels") or status.get("loaded_models"))),
            _safe_int(status.get("loadedModelCount") or status.get("loaded_model_count"), 0),
        )
        active_task_count = max(0, _safe_int(scheduler_state.get("activeTaskCount") or scheduler_state.get("active_task_count"), 0))
        queued_task_count = max(0, _safe_int(scheduler_state.get("queuedTaskCount") or scheduler_state.get("queued_task_count"), 0))
        concurrency_limit = max(1, _safe_int(scheduler_state.get("concurrencyLimit") or scheduler_state.get("concurrency_limit"), 1))
        queue_mode = _safe_str(scheduler_state.get("queueMode") or scheduler_state.get("queue_mode")) or "unknown"
        queueing_supported = bool(scheduler_state.get("queueingSupported") if "queueingSupported" in scheduler_state else scheduler_state.get("queueing_supported"))
        oldest_waiter_started_at = _safe_float(
            scheduler_state.get("oldestWaiterStartedAt") if "oldestWaiterStartedAt" in scheduler_state else scheduler_state.get("oldest_waiter_started_at"),
            0.0,
        )
        oldest_waiter_age_ms = max(
            0,
            _safe_int(scheduler_state.get("oldestWaiterAgeMs") if "oldestWaiterAgeMs" in scheduler_state else scheduler_state.get("oldest_waiter_age_ms"), 0),
        )
        contention_count = max(0, _safe_int(scheduler_state.get("contentionCount") or scheduler_state.get("contention_count"), 0))
        last_contention_for_provider = _safe_float(
            scheduler_state.get("lastContentionAt") if "lastContentionAt" in scheduler_state else scheduler_state.get("last_contention_at"),
            0.0,
        )
        provider_updated_at = _safe_float(status.get("updatedAt") or status.get("updated_at"), generated_at)
        provider_idle_eviction = eviction_snapshot.get(normalized_provider_id) if isinstance(eviction_snapshot.get(normalized_provider_id), dict) else {}
        memory_state = "reported" if active_memory_known or peak_memory_known else "unknown"

        for raw_task in scheduler_state.get("activeTasks") or scheduler_state.get("active_tasks") or []:
            if not isinstance(raw_task, dict):
                continue
            task_row = {
                "provider": normalized_provider_id,
                "leaseId": _safe_str(raw_task.get("leaseId") or raw_task.get("lease_id")),
                "taskKind": _safe_str(raw_task.get("taskKind") or raw_task.get("task_kind")).lower(),
                "modelId": _safe_str(raw_task.get("modelId") or raw_task.get("model_id")),
                "requestId": _safe_str(raw_task.get("requestId") or raw_task.get("request_id")),
                "deviceId": _safe_str(raw_task.get("deviceId") or raw_task.get("device_id")),
                "loadProfileHash": _safe_str(raw_task.get("loadProfileHash") or raw_task.get("load_profile_hash")),
                "instanceKey": _safe_str(raw_task.get("instanceKey") or raw_task.get("instance_key")),
                "effectiveContextLength": max(0, _safe_int(raw_task.get("effectiveContextLength") or raw_task.get("effective_context_length"), 0)),
                "startedAt": _safe_float(raw_task.get("startedAt") or raw_task.get("started_at"), 0.0),
            }
            lease_ttl_sec = max(
                0,
                _safe_int(
                    raw_task.get("leaseTtlSec")
                    if raw_task.get("leaseTtlSec") is not None
                    else raw_task.get("lease_ttl_sec")
                    if raw_task.get("lease_ttl_sec") is not None
                    else raw_task.get("ttlSec")
                    if raw_task.get("ttlSec") is not None
                    else raw_task.get("ttl_sec"),
                    0,
                ),
            )
            lease_remaining_ttl_sec = max(
                0,
                _safe_int(
                    raw_task.get("leaseRemainingTtlSec")
                    if raw_task.get("leaseRemainingTtlSec") is not None
                    else raw_task.get("lease_remaining_ttl_sec")
                    if raw_task.get("lease_remaining_ttl_sec") is not None
                    else raw_task.get("ttlRemainingSec")
                    if raw_task.get("ttlRemainingSec") is not None
                    else raw_task.get("ttl_remaining_sec"),
                    0,
                ),
            )
            expires_at = _safe_float(raw_task.get("expiresAt") or raw_task.get("expires_at"), 0.0)
            progress = _normalize_progress(raw_task.get("progress"))
            if lease_ttl_sec > 0:
                task_row["leaseTtlSec"] = lease_ttl_sec
            if lease_remaining_ttl_sec > 0 or expires_at > 0:
                task_row["leaseRemainingTtlSec"] = lease_remaining_ttl_sec
            if expires_at > 0:
                task_row["expiresAt"] = expires_at
            if progress is not None:
                task_row["progress"] = progress
            active_tasks.append(task_row)

        last_error = _provider_last_error_record(normalized_provider_id, status)
        if last_error is not None:
            last_errors.append(last_error)

        if fallback_task_kinds:
            fallback_ready_provider_count += 1
            fallback_ready_task_count += len(fallback_task_kinds)
            if not real_task_kinds:
                fallback_only_provider_count += 1
                fallback_only_task_count += len(fallback_task_kinds)
            for task_kind in fallback_task_kinds:
                fallback_task_kind_counts[task_kind] = int(fallback_task_kind_counts.get(task_kind) or 0) + 1

        total_active_task_count += active_task_count
        total_queued_task_count += queued_task_count
        total_contention_count += contention_count
        providers_busy_count += 1 if active_task_count >= concurrency_limit else 0
        providers_with_queued_tasks_count += 1 if queued_task_count > 0 else 0
        max_oldest_wait_ms = max(max_oldest_wait_ms, oldest_waiter_age_ms)
        last_contention_at = max(last_contention_at, last_contention_for_provider)

        queue_rows.append({
            "provider": normalized_provider_id,
            "concurrencyLimit": concurrency_limit,
            "activeTaskCount": active_task_count,
            "queuedTaskCount": queued_task_count,
            "queueMode": queue_mode,
            "queueingSupported": queueing_supported,
            "oldestWaiterStartedAt": oldest_waiter_started_at,
            "oldestWaiterAgeMs": oldest_waiter_age_ms,
            "contentionCount": contention_count,
            "lastContentionAt": last_contention_for_provider,
            "updatedAt": _safe_float(scheduler_state.get("updatedAt") or scheduler_state.get("updated_at"), provider_updated_at),
        })

        monitor_provider_rows.append({
            "provider": normalized_provider_id,
            "ok": bool(status.get("ok")),
            "reasonCode": _safe_str(status.get("reasonCode") or status.get("reason_code")),
            "importError": _safe_str(status.get("importError") or status.get("import_error")),
            "availableTaskKinds": available_task_kinds,
            "realTaskKinds": real_task_kinds,
            "fallbackTaskKinds": fallback_task_kinds,
            "unavailableTaskKinds": unavailable_task_kinds,
            "deviceBackend": _safe_str(status.get("deviceBackend") or status.get("device_backend")) or "unknown",
            "lifecycleMode": _safe_str(status.get("lifecycleMode") or status.get("lifecycle_mode")),
            "residencyScope": _safe_str(status.get("residencyScope") or status.get("residency_scope")),
            "loadedInstanceCount": len(provider_loaded_instances),
            "loadedModelCount": loaded_model_count,
            "activeTaskCount": active_task_count,
            "queuedTaskCount": queued_task_count,
            "concurrencyLimit": concurrency_limit,
            "queueMode": queue_mode,
            "queueingSupported": queueing_supported,
            "oldestWaiterStartedAt": oldest_waiter_started_at,
            "oldestWaiterAgeMs": oldest_waiter_age_ms,
            "contentionCount": contention_count,
            "lastContentionAt": last_contention_for_provider,
            "activeMemoryBytes": active_memory_bytes,
            "peakMemoryBytes": peak_memory_bytes,
            "memoryState": memory_state,
            "idleEvictionPolicy": _safe_str(provider_idle_eviction.get("policy")) or "unknown",
            "lastIdleEvictionReason": _safe_str(provider_idle_eviction.get("lastEvictionReason") or provider_idle_eviction.get("last_eviction_reason")),
            "updatedAt": provider_updated_at,
        })

    active_tasks.sort(
        key=lambda item: (
            _safe_str(item.get("provider")),
            _safe_str(item.get("taskKind")),
            _safe_str(item.get("modelId")),
            _safe_str(item.get("leaseId")),
        )
    )
    last_errors.sort(
        key=lambda item: (
            _safe_str(item.get("provider")),
            _safe_str(item.get("code")),
        )
    )

    return {
        "schemaVersion": "xhub.local_runtime_monitor.v1",
        "updatedAt": generated_at,
        "providers": monitor_provider_rows,
        "activeTasks": active_tasks,
        "loadedInstances": [dict(row) for row in flattened_loaded_instances if isinstance(row, dict)],
        "recentBenchResults": recent_bench_rows,
        "queue": {
            "providerCount": len(queue_rows),
            "activeTaskCount": total_active_task_count,
            "queuedTaskCount": total_queued_task_count,
            "providersBusyCount": providers_busy_count,
            "providersWithQueuedTasksCount": providers_with_queued_tasks_count,
            "maxOldestWaitMs": max_oldest_wait_ms,
            "contentionCount": total_contention_count,
            "lastContentionAt": last_contention_at,
            "updatedAt": generated_at,
            "providers": queue_rows,
        },
        "lastErrors": last_errors,
        "fallbackCounters": {
            "providerCount": len(monitor_provider_rows),
            "fallbackReadyProviderCount": fallback_ready_provider_count,
            "fallbackOnlyProviderCount": fallback_only_provider_count,
            "fallbackReadyTaskCount": fallback_ready_task_count,
            "fallbackOnlyTaskCount": fallback_only_task_count,
            "taskKindCounts": fallback_task_kind_counts,
        },
    }


def _publish_runtime_status(base_dir: str) -> None:
    try:
        payload = _status_payload(base_dir)
        _write_json_atomic(_runtime_status_path(base_dir), payload)
        for mirror_path in _runtime_status_mirror_paths(base_dir):
            try:
                os.makedirs(os.path.dirname(mirror_path), exist_ok=True)
                _write_json_atomic(mirror_path, payload)
            except Exception:
                continue
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
            runtime_provider = _safe_str(
                model.get("runtimeProviderID") or model.get("runtime_provider_id")
            ).lower()
            if runtime_provider:
                return runtime_provider
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


def _provider_pack_for_provider(base_dir: str, provider_id: str) -> dict[str, Any]:
    target_provider_id = _safe_str(provider_id).lower()
    if not target_provider_id:
        return {}
    for pack in provider_pack_inventory([target_provider_id], base_dir=base_dir):
        candidate_provider_id = _safe_str(pack.get("providerId") or pack.get("provider_id")).lower()
        if candidate_provider_id == target_provider_id:
            return dict(pack)
    return {}


def _provider_pack_guard_reason(pack: dict[str, Any]) -> str:
    if not isinstance(pack, dict):
        return ""
    installed = bool(pack.get("installed"))
    enabled = bool(pack.get("enabled"))
    state = _safe_str(pack.get("packState") or pack.get("pack_state")).lower()
    reason = _safe_str(pack.get("reasonCode") or pack.get("reason_code"))
    if installed and enabled and state not in {"disabled", "not_installed"}:
        return ""
    if reason:
        return reason
    if not installed:
        return "provider_pack_not_installed"
    if not enabled or state == "disabled":
        return "provider_pack_disabled"
    return "provider_pack_unavailable"


def _attach_provider_pack_fields(output: dict[str, Any], pack: dict[str, Any]) -> dict[str, Any]:
    out = dict(output or {})
    if not isinstance(pack, dict) or not pack:
        return out
    out.setdefault("packId", _safe_str(pack.get("providerId") or pack.get("provider_id")).lower())
    out.setdefault("packEngine", _safe_str(pack.get("engine")))
    out.setdefault("packVersion", _safe_str(pack.get("version")))
    out.setdefault("packInstalled", bool(pack.get("installed")))
    out.setdefault("packEnabled", bool(pack.get("enabled")))
    out.setdefault("packState", _safe_str(pack.get("packState") or pack.get("pack_state")).lower())
    out.setdefault("packReasonCode", _safe_str(pack.get("reasonCode") or pack.get("reason_code")))
    return out


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
    provider_request["max_context_length"] = max(0, _safe_int(identity.get("max_context_length"), 0))
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

    provider_pack = _provider_pack_for_provider(base, provider_id)
    provider_pack_reason = _provider_pack_guard_reason(provider_pack)
    if provider_pack_reason:
        out = {
            "ok": False,
            "provider": provider_id,
            "taskKind": task_kind,
            "modelId": model_id,
            "error": provider_pack_reason,
            "request": dict(request or {}),
        }
        out.setdefault("runtimeVersion", RUNTIME_VERSION)
        out.setdefault("localRuntimeEntryVersion", LOCAL_RUNTIME_ENTRY_VERSION)
        out.setdefault("updatedAt", _now())
        _publish_runtime_status(base)
        return _attach_task_identity(_attach_provider_pack_fields(out, provider_pack), identity)

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
    return _attach_task_identity(_attach_provider_pack_fields(out, provider_pack), identity)


def run_local_bench(request: dict[str, Any], *, base_dir: str | None = None) -> dict[str, Any]:
    base = str(base_dir or _base_dir())
    context = _resolve_provider_request_context(request, base_dir=base)
    catalog_models = list(context.get("catalog_models") or [])
    provider_id = _safe_str(context.get("provider_id")).lower()
    model_id = _safe_str(context.get("model_id"))
    provider = context.get("provider")
    provider_request = dict(context.get("provider_request") or {})
    identity = dict(context.get("identity") or {})
    task_kind = _safe_str(provider_request.get("task_kind") or provider_request.get("taskKind")).lower()

    if not provider_id:
        out = {
            "ok": False,
            "error": "provider_not_resolved",
            "taskKind": task_kind,
            "modelId": model_id,
            "reasonCode": "provider_not_resolved",
        }
        out.setdefault("runtimeVersion", RUNTIME_VERSION)
        out.setdefault("localRuntimeEntryVersion", LOCAL_RUNTIME_ENTRY_VERSION)
        out.setdefault("updatedAt", _now())
        return _attach_task_identity(out, identity)

    if provider is None:
        out = {
            "ok": False,
            "provider": provider_id,
            "taskKind": task_kind,
            "modelId": model_id,
            "reasonCode": f"unknown_provider:{provider_id}",
            "error": f"unknown_provider:{provider_id}",
        }
        out.setdefault("runtimeVersion", RUNTIME_VERSION)
        out.setdefault("localRuntimeEntryVersion", LOCAL_RUNTIME_ENTRY_VERSION)
        out.setdefault("updatedAt", _now())
        return _attach_task_identity(out, identity)

    provider_pack = _provider_pack_for_provider(base, provider_id)
    provider_pack_reason = _provider_pack_guard_reason(provider_pack)
    if provider_pack_reason:
        out = {
            "ok": False,
            "provider": provider_id,
            "taskKind": task_kind,
            "modelId": model_id,
            "reasonCode": provider_pack_reason,
            "error": provider_pack_reason,
            "resultKind": "task_aware_quick_bench",
        }
        out.setdefault("runtimeVersion", RUNTIME_VERSION)
        out.setdefault("localRuntimeEntryVersion", LOCAL_RUNTIME_ENTRY_VERSION)
        out.setdefault("updatedAt", _now())
        _publish_runtime_status(base)
        return _attach_task_identity(_attach_provider_pack_fields(out, provider_pack), identity)

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
        out["reasonCode"] = _safe_str(out.get("error"))
        out["resultKind"] = "task_aware_quick_bench"
        return _attach_task_identity(out, identity)

    lease_id = str(slot.get("lease_id") or "").strip()
    try:
        out = provider.run_bench(provider_request)
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
    out.setdefault("resultKind", "task_aware_quick_bench")
    out.setdefault("runtimeVersion", RUNTIME_VERSION)
    out.setdefault("localRuntimeEntryVersion", LOCAL_RUNTIME_ENTRY_VERSION)
    out.setdefault("updatedAt", _now())
    out = _attach_task_identity(_attach_provider_pack_fields(out, provider_pack), identity)
    _persist_bench_result(base, out)
    _publish_runtime_status(base)
    return out


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

    provider_pack = _provider_pack_for_provider(base, provider_id)
    provider_pack_reason = _provider_pack_guard_reason(provider_pack)
    if provider_pack_reason:
        out = {
            "ok": False,
            "provider": provider_id,
            "action": action,
            "taskKind": task_kind,
            "modelId": model_id,
            "error": provider_pack_reason,
            "request": dict(request or {}),
            "runtimeVersion": RUNTIME_VERSION,
            "localRuntimeEntryVersion": LOCAL_RUNTIME_ENTRY_VERSION,
            "updatedAt": _now(),
        }
        _publish_runtime_status(base)
        return _attach_task_identity(_attach_provider_pack_fields(out, provider_pack), identity)

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
    return _attach_task_identity(_attach_provider_pack_fields(out, provider_pack), identity)


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
    provider_packs = provider_pack_inventory(providers.keys(), base_dir=base_dir)
    loaded_instances = _flatten_loaded_instances(providers)
    idle_eviction_by_provider = _idle_eviction_by_provider(providers)
    recent_bench_results = _recent_bench_results(base_dir)
    updated_at = _now()
    ready_provider_ids = sorted(
        provider_id
        for provider_id, status in providers.items()
        if isinstance(status, dict) and bool(status.get("ok"))
    )
    mlx_status = providers.get("mlx") if isinstance(providers.get("mlx"), dict) else {}
    monitor_snapshot = build_runtime_monitor_snapshot(
        providers,
        loaded_instances=loaded_instances,
        idle_eviction_by_provider=idle_eviction_by_provider,
        recent_bench_results=recent_bench_results,
        updated_at=updated_at,
    )
    active_memory_bytes = None
    if isinstance(mlx_status, dict) and ("activeMemoryBytes" in mlx_status or "active_memory_bytes" in mlx_status):
        active_memory_bytes = max(0, _safe_int(mlx_status.get("activeMemoryBytes") or mlx_status.get("active_memory_bytes"), 0))
    peak_memory_bytes = None
    if isinstance(mlx_status, dict) and ("peakMemoryBytes" in mlx_status or "peak_memory_bytes" in mlx_status):
        peak_memory_bytes = max(0, _safe_int(mlx_status.get("peakMemoryBytes") or mlx_status.get("peak_memory_bytes"), 0))
    loaded_model_count = None
    if isinstance(mlx_status, dict) and ("loadedModelCount" in mlx_status or "loaded_model_count" in mlx_status):
        loaded_model_count = max(0, _safe_int(mlx_status.get("loadedModelCount") or mlx_status.get("loaded_model_count"), 0))
    return {
        "schemaVersion": LOCAL_RUNTIME_STATUS_SCHEMA_VERSION,
        "schema_version": LOCAL_RUNTIME_STATUS_SCHEMA_VERSION,
        "runtimeVersion": RUNTIME_VERSION,
        "localRuntimeEntryVersion": LOCAL_RUNTIME_ENTRY_VERSION,
        "localCommandIpcVersion": LOCAL_RUNTIME_COMMAND_IPC_VERSION,
        "baseDir": base_dir,
        "providerIds": sorted(providers.keys()),
        "providerPacks": provider_packs,
        "readyProviderIds": ready_provider_ids,
        "catalogModelCount": len(read_catalog_models(base_dir)),
        "mlxOk": bool(mlx_status.get("ok")) if isinstance(mlx_status, dict) else False,
        "importError": _safe_str(mlx_status.get("importError") or mlx_status.get("import_error")) if isinstance(mlx_status, dict) else "",
        "activeMemoryBytes": active_memory_bytes,
        "peakMemoryBytes": peak_memory_bytes,
        "loadedModelCount": loaded_model_count,
        "loadedInstances": loaded_instances,
        "loadedInstanceCount": len(loaded_instances),
        "idleEvictionByProvider": idle_eviction_by_provider,
        "recentBenchResults": recent_bench_results,
        "monitorSnapshot": monitor_snapshot,
        "providers": providers,
        "updatedAt": updated_at,
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
            if _request_allows_daemon_proxy(request) and _runtime_supports_command_proxy(base_dir):
                result = _proxy_runtime_command(
                    base_dir,
                    command="run_local_task",
                    request=request,
                    timeout_sec=60.0,
                )
            else:
                result = run_local_task(request, base_dir=base_dir)
            print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
            return 0
        if cmd == "run-local-bench":
            request = _load_request_arg(args[1] if len(args) > 1 else "-")
            if _request_allows_daemon_proxy(request) and _runtime_supports_command_proxy(base_dir):
                result = _proxy_runtime_command(
                    base_dir,
                    command="run_local_bench",
                    request=request,
                    timeout_sec=90.0,
                )
            else:
                result = run_local_bench(request, base_dir=base_dir)
            print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
            return 0
        if cmd in {"manage-local-model", "warmup-local-model", "unload-local-model", "evict-local-instance"}:
            request = _load_request_arg(args[1] if len(args) > 1 else "-")
            if cmd != "manage-local-model":
                action = cmd.replace("-", "_")
                request = dict(request or {})
                request.setdefault("action", action)
            if _request_allows_daemon_proxy(request) and _runtime_supports_command_proxy(base_dir):
                result = _proxy_runtime_command(
                    base_dir,
                    command="manage_local_model",
                    request=request,
                    timeout_sec=60.0,
                )
            else:
                result = manage_local_model(request, base_dir=base_dir)
            print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
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
