from __future__ import annotations

from dataclasses import dataclass, field
import json
import os
from typing import Any


PROVIDER_PACK_REGISTRY_SCHEMA_VERSION = "xhub.provider_pack_registry.v1"
PROVIDER_PACK_REGISTRY_FILENAME = "provider_pack_registry.json"


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _string_list(values: Any) -> list[str]:
    if values is None:
        return []
    items = values if isinstance(values, list) else str(values or "").split(",")
    out: list[str] = []
    seen: set[str] = set()
    for raw in items:
        cleaned = _safe_str(raw).lower()
        if not cleaned or cleaned in seen:
            continue
        seen.add(cleaned)
        out.append(cleaned)
    return out


def _safe_float(value: Any, fallback: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return float(fallback)


def _runtime_requirements_dict(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {}
    return {
        "executionMode": _safe_str(value.get("executionMode") or value.get("execution_mode")),
        "pythonModules": _string_list(value.get("pythonModules") or value.get("python_modules")),
        "helperBinary": _safe_str(value.get("helperBinary") or value.get("helper_binary")),
        "nativeDylib": _safe_str(value.get("nativeDylib") or value.get("native_dylib")),
        "serviceBaseUrl": _safe_str(value.get("serviceBaseUrl") or value.get("service_base_url")),
        "notes": _string_list(value.get("notes")),
    }


def _merge_runtime_requirements(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    out = {
        "executionMode": _safe_str(base.get("executionMode") or base.get("execution_mode")),
        "pythonModules": _string_list(base.get("pythonModules") or base.get("python_modules")),
        "helperBinary": _safe_str(base.get("helperBinary") or base.get("helper_binary")),
        "nativeDylib": _safe_str(base.get("nativeDylib") or base.get("native_dylib")),
        "serviceBaseUrl": _safe_str(base.get("serviceBaseUrl") or base.get("service_base_url")),
        "notes": _string_list(base.get("notes")),
    }
    if override.get("executionMode"):
        out["executionMode"] = _safe_str(override.get("executionMode"))
    if override.get("pythonModules"):
        out["pythonModules"] = _string_list(override.get("pythonModules"))
    if override.get("helperBinary"):
        out["helperBinary"] = _safe_str(override.get("helperBinary"))
    if override.get("nativeDylib"):
        out["nativeDylib"] = _safe_str(override.get("nativeDylib"))
    if override.get("serviceBaseUrl"):
        out["serviceBaseUrl"] = _safe_str(override.get("serviceBaseUrl"))
    if override.get("notes"):
        out["notes"] = _string_list(override.get("notes"))
    return out


def provider_pack_registry_path(base_dir: str) -> str:
    return os.path.join(os.path.abspath(str(base_dir or "")), PROVIDER_PACK_REGISTRY_FILENAME)


@dataclass
class ProviderPackRuntimeRequirements:
    execution_mode: str
    python_modules: list[str] = field(default_factory=list)
    helper_binary: str = ""
    native_dylib: str = ""
    service_base_url: str = ""
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "executionMode": _safe_str(self.execution_mode),
            "pythonModules": _string_list(self.python_modules),
            "helperBinary": _safe_str(self.helper_binary),
            "nativeDylib": _safe_str(self.native_dylib),
            "serviceBaseUrl": _safe_str(self.service_base_url),
            "notes": _string_list(self.notes),
        }


@dataclass
class ProviderPackManifest:
    provider_id: str
    engine: str
    version: str
    supported_formats: list[str]
    supported_domains: list[str]
    runtime_requirements: ProviderPackRuntimeRequirements
    min_hub_version: str
    installed: bool = True
    enabled: bool = True
    pack_state: str = "installed"
    reason_code: str = "builtin_pack_registered"
    manifest_schema_version: str = "xhub.provider_pack_manifest.v1"

    def to_dict(self) -> dict[str, Any]:
        return {
            "schemaVersion": _safe_str(self.manifest_schema_version),
            "providerId": _safe_str(self.provider_id).lower(),
            "engine": _safe_str(self.engine),
            "version": _safe_str(self.version),
            "supportedFormats": _string_list(self.supported_formats),
            "supportedDomains": _string_list(self.supported_domains),
            "runtimeRequirements": self.runtime_requirements.to_dict(),
            "minHubVersion": _safe_str(self.min_hub_version),
            "installed": bool(self.installed),
            "enabled": bool(self.enabled),
            "packState": _safe_str(self.pack_state).lower(),
            "reasonCode": _safe_str(self.reason_code),
        }


DEFAULT_PROVIDER_PACKS: dict[str, ProviderPackManifest] = {
    "mlx": ProviderPackManifest(
        provider_id="mlx",
        engine="mlx-llm",
        version="builtin-2026-03-16",
        supported_formats=["mlx"],
        supported_domains=["text"],
        runtime_requirements=ProviderPackRuntimeRequirements(
            execution_mode="builtin_python",
            python_modules=["mlx", "mlx_lm"],
            notes=["offline_only", "legacy_runtime_compatible"],
        ),
        min_hub_version="2026.03",
    ),
    "mlx_vlm": ProviderPackManifest(
        provider_id="mlx_vlm",
        engine="mlx-vlm",
        version="builtin-2026-03-24",
        supported_formats=["mlx"],
        supported_domains=["vision", "ocr"],
        runtime_requirements=ProviderPackRuntimeRequirements(
            execution_mode="helper_binary_bridge",
            notes=["offline_only", "helper_bridge_required_for_mlx_multimodal"],
        ),
        min_hub_version="2026.03",
    ),
    "llama.cpp": ProviderPackManifest(
        provider_id="llama.cpp",
        engine="llama.cpp",
        version="builtin-2026-03-25-helper-v1",
        supported_formats=["gguf"],
        supported_domains=["text", "embedding"],
        runtime_requirements=ProviderPackRuntimeRequirements(
            execution_mode="helper_binary_bridge",
            notes=[
                "offline_only",
                "external_local_engine_required",
            ],
        ),
        min_hub_version="2026.03",
        pack_state="installed",
        reason_code="builtin_pack_registered",
    ),
    "transformers": ProviderPackManifest(
        provider_id="transformers",
        engine="hf-transformers",
        version="builtin-2026-03-16",
        supported_formats=["hf_transformers"],
        supported_domains=["embedding", "audio", "vision", "ocr"],
        runtime_requirements=ProviderPackRuntimeRequirements(
            execution_mode="builtin_python",
            python_modules=["transformers", "torch", "tokenizers", "PIL"],
            notes=["offline_only", "processor_required_for_multimodal"],
        ),
        min_hub_version="2026.03",
    ),
}


def _fallback_manifest(provider_id: str) -> ProviderPackManifest:
    normalized = _safe_str(provider_id).lower() or "unknown"
    return ProviderPackManifest(
        provider_id=normalized,
        engine=normalized,
        version="builtin-unknown",
        supported_formats=[],
        supported_domains=[],
        runtime_requirements=ProviderPackRuntimeRequirements(
            execution_mode="builtin_python",
            notes=["pack_manifest_not_yet_specialized"],
        ),
        min_hub_version="2026.03",
        pack_state="installed_unknown",
        reason_code="builtin_pack_without_manifest",
    )


def _normalize_registry_entry(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    provider_id = _safe_str(raw.get("providerId") or raw.get("provider_id")).lower()
    if not provider_id:
        return None
    return {
        "providerId": provider_id,
        "engine": _safe_str(raw.get("engine")),
        "version": _safe_str(raw.get("version")),
        "supportedFormats": _string_list(raw.get("supportedFormats") or raw.get("supported_formats")),
        "supportedDomains": _string_list(raw.get("supportedDomains") or raw.get("supported_domains")),
        "runtimeRequirements": _runtime_requirements_dict(raw.get("runtimeRequirements") or raw.get("runtime_requirements")),
        "minHubVersion": _safe_str(raw.get("minHubVersion") or raw.get("min_hub_version")),
        "installed": bool(raw.get("installed")) if ("installed" in raw) else None,
        "enabled": bool(raw.get("enabled")) if ("enabled" in raw) else None,
        "packState": _safe_str(raw.get("packState") or raw.get("pack_state")).lower(),
        "reasonCode": _safe_str(raw.get("reasonCode") or raw.get("reason_code")),
        "note": _safe_str(raw.get("note")),
    }


def load_provider_pack_registry(base_dir: str) -> dict[str, Any]:
    path = provider_pack_registry_path(base_dir)
    payload = {
        "schemaVersion": PROVIDER_PACK_REGISTRY_SCHEMA_VERSION,
        "updatedAt": 0.0,
        "path": path,
        "packs": [],
    }
    if not os.path.exists(path):
        return payload
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except Exception:
        return payload
    if not isinstance(raw, dict):
        return payload
    raw_packs = raw.get("packs") if isinstance(raw.get("packs"), list) else raw.get("providerPacks")
    normalized_packs = [
        entry
        for entry in (
            _normalize_registry_entry(item)
            for item in (raw_packs if isinstance(raw_packs, list) else [])
        )
        if isinstance(entry, dict)
    ]
    return {
        "schemaVersion": _safe_str(raw.get("schemaVersion") or raw.get("schema_version")) or PROVIDER_PACK_REGISTRY_SCHEMA_VERSION,
        "updatedAt": _safe_float(raw.get("updatedAt") or raw.get("updated_at"), 0.0),
        "path": path,
        "packs": sorted(normalized_packs, key=lambda item: _safe_str(item.get("providerId"))),
    }


def write_provider_pack_registry(
    base_dir: str,
    packs: list[dict[str, Any]],
    *,
    updated_at: float = 0.0,
) -> str:
    path = provider_pack_registry_path(base_dir)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    normalized_packs = [
        entry
        for entry in (_normalize_registry_entry(item) for item in (packs or []))
        if isinstance(entry, dict)
    ]
    payload = {
        "schemaVersion": PROVIDER_PACK_REGISTRY_SCHEMA_VERSION,
        "updatedAt": float(updated_at or 0.0),
        "packs": normalized_packs,
    }
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False)
    os.replace(tmp, path)
    return path


def _merged_manifest(manifest: dict[str, Any], override: dict[str, Any] | None) -> dict[str, Any]:
    pack = dict(manifest or {})
    override_obj = override if isinstance(override, dict) else {}

    if override_obj.get("engine"):
        pack["engine"] = _safe_str(override_obj.get("engine"))
    if override_obj.get("version"):
        pack["version"] = _safe_str(override_obj.get("version"))
    if override_obj.get("supportedFormats"):
        pack["supportedFormats"] = _string_list(override_obj.get("supportedFormats"))
    if override_obj.get("supportedDomains"):
        pack["supportedDomains"] = _string_list(override_obj.get("supportedDomains"))
    if override_obj.get("runtimeRequirements"):
        pack["runtimeRequirements"] = _merge_runtime_requirements(
            pack.get("runtimeRequirements") if isinstance(pack.get("runtimeRequirements"), dict) else {},
            override_obj.get("runtimeRequirements") if isinstance(override_obj.get("runtimeRequirements"), dict) else {},
        )
    if override_obj.get("minHubVersion"):
        pack["minHubVersion"] = _safe_str(override_obj.get("minHubVersion"))

    installed = bool(pack.get("installed"))
    if override_obj.get("installed") is not None:
        installed = bool(override_obj.get("installed"))
    enabled = bool(pack.get("enabled"))
    if override_obj.get("enabled") is not None:
        enabled = bool(override_obj.get("enabled"))

    if not installed:
        enabled = False
        pack_state = _safe_str(override_obj.get("packState")).lower() or "not_installed"
        reason_code = _safe_str(override_obj.get("reasonCode")) or "provider_pack_not_installed"
    elif not enabled:
        pack_state = _safe_str(override_obj.get("packState")).lower() or "disabled"
        reason_code = _safe_str(override_obj.get("reasonCode")) or "provider_pack_disabled"
    else:
        pack_state = _safe_str(override_obj.get("packState")).lower() or _safe_str(pack.get("packState") or pack.get("pack_state")).lower() or "installed"
        reason_code = _safe_str(override_obj.get("reasonCode")) or _safe_str(pack.get("reasonCode") or pack.get("reason_code")) or "builtin_pack_registered"

    pack["installed"] = installed
    pack["enabled"] = enabled
    pack["packState"] = pack_state
    pack["reasonCode"] = reason_code
    return pack


def provider_pack_inventory(
    provider_ids: list[str] | set[str] | tuple[str, ...],
    *,
    base_dir: str | None = None,
) -> list[dict[str, Any]]:
    registry = load_provider_pack_registry(base_dir) if base_dir else {
        "schemaVersion": PROVIDER_PACK_REGISTRY_SCHEMA_VERSION,
        "updatedAt": 0.0,
        "path": "",
        "packs": [],
    }
    registry_packs = registry.get("packs") if isinstance(registry.get("packs"), list) else []
    registry_by_provider = {
        _safe_str(pack.get("providerId")).lower(): pack
        for pack in registry_packs
        if isinstance(pack, dict) and _safe_str(pack.get("providerId"))
    }
    normalized_ids = sorted(
        {
            _safe_str(provider_id).lower()
            for provider_id in (provider_ids or [])
            if _safe_str(provider_id)
        } | set(registry_by_provider.keys())
    )
    out: list[dict[str, Any]] = []
    for provider_id in normalized_ids:
        manifest = DEFAULT_PROVIDER_PACKS.get(provider_id) or _fallback_manifest(provider_id)
        out.append(_merged_manifest(manifest.to_dict(), registry_by_provider.get(provider_id)))
    return out


def attach_provider_pack_truth(
    provider_statuses: dict[str, dict[str, Any]],
    provider_packs: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    pack_by_provider = {
        _safe_str(pack.get("providerId") or pack.get("provider_id")).lower(): pack
        for pack in (provider_packs or [])
        if isinstance(pack, dict)
    }
    out: dict[str, dict[str, Any]] = {}
    for raw_provider_id, raw_status in (provider_statuses or {}).items():
        provider_id = _safe_str(raw_provider_id).lower()
        status = dict(raw_status or {})
        pack = pack_by_provider.get(provider_id)
        if isinstance(pack, dict):
            status.setdefault("packId", _safe_str(pack.get("providerId") or pack.get("provider_id")).lower())
            status.setdefault("packEngine", _safe_str(pack.get("engine")))
            status.setdefault("packVersion", _safe_str(pack.get("version")))
            status.setdefault("packInstalled", bool(pack.get("installed")))
            status.setdefault("packEnabled", bool(pack.get("enabled")))
            status.setdefault("packState", _safe_str(pack.get("packState") or pack.get("pack_state")).lower())
            status.setdefault("packReasonCode", _safe_str(pack.get("reasonCode") or pack.get("reason_code")))
        out[provider_id] = status
    return out


def _pack_usable(pack: dict[str, Any]) -> bool:
    if not isinstance(pack, dict):
        return False
    installed = bool(pack.get("installed"))
    enabled = bool(pack.get("enabled"))
    state = _safe_str(pack.get("packState") or pack.get("pack_state")).lower()
    if not installed or not enabled:
        return False
    return state not in {"disabled", "not_installed"}


def _merged_task_kinds(*values: Any) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for value in values:
        for task_kind in _string_list(value):
            if task_kind in seen:
                continue
            seen.add(task_kind)
            out.append(task_kind)
    return out


def enforce_provider_pack_truth(
    provider_statuses: dict[str, dict[str, Any]],
    provider_packs: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    pack_by_provider = {
        _safe_str(pack.get("providerId") or pack.get("provider_id")).lower(): pack
        for pack in (provider_packs or [])
        if isinstance(pack, dict)
    }
    out: dict[str, dict[str, Any]] = {}
    for raw_provider_id, raw_status in (provider_statuses or {}).items():
        provider_id = _safe_str(raw_provider_id).lower()
        status = dict(raw_status or {})
        pack = pack_by_provider.get(provider_id)
        if not isinstance(pack, dict) or _pack_usable(pack):
            out[provider_id] = status
            continue

        unavailable_task_kinds = _merged_task_kinds(
            status.get("unavailableTaskKinds") or status.get("unavailable_task_kinds"),
            status.get("realTaskKinds") or status.get("real_task_kinds"),
            status.get("fallbackTaskKinds") or status.get("fallback_task_kinds"),
            status.get("availableTaskKinds") or status.get("available_task_kinds"),
        )
        status["ok"] = False
        status["reasonCode"] = _safe_str(pack.get("reasonCode") or pack.get("reason_code")) or "provider_pack_unavailable"
        status["availableTaskKinds"] = []
        status["realTaskKinds"] = []
        status["fallbackTaskKinds"] = []
        status["unavailableTaskKinds"] = unavailable_task_kinds
        out[provider_id] = status
    return out
