from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
import math
from typing import Any


def _safe_int(value: Any, fallback: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return int(fallback)


def _safe_float(value: Any, fallback: float = 0.0) -> float:
    try:
        number = float(value)
    except Exception:
        return float(fallback)
    return float(number) if math.isfinite(number) else float(fallback)


def _normalize_progress(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    number = _safe_float(value, float("nan"))
    if not math.isfinite(number):
        return None
    return min(1.0, max(0.0, number))


def _extract_profile_ttl(profile: Any) -> int | None:
    row = profile if isinstance(profile, dict) else {}
    raw_value = (
        row.get("ttl")
        if row.get("ttl") is not None
        else row.get("ttl_sec")
        if row.get("ttl_sec") is not None
        else row.get("ttlSec")
    )
    ttl = max(0, _safe_int(raw_value, 0))
    return ttl if ttl > 0 else None


def _normalize_loaded_instance(item: dict[str, Any]) -> dict[str, Any]:
    row = dict(item)
    effective_profile = (
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
    raw_ttl = (
        row.get("ttl")
        if row.get("ttl") is not None
        else row.get("ttl_sec")
        if row.get("ttl_sec") is not None
        else row.get("ttlSec")
        if row.get("ttlSec") is not None
        else _extract_profile_ttl(effective_profile)
    )
    ttl = max(0, _safe_int(raw_ttl, 0))
    if ttl > 0:
        row["ttl"] = ttl
    progress = _normalize_progress(row.get("progress"))
    if progress is not None:
        row["progress"] = progress
    return row


def _normalize_scheduler_state(value: dict[str, Any]) -> dict[str, Any]:
    out = dict(value)
    active_tasks = out.get("activeTasks")
    if not isinstance(active_tasks, list):
        return out
    normalized_rows: list[dict[str, Any]] = []
    for item in active_tasks:
        if not isinstance(item, dict):
            continue
        row = dict(item)
        started_at = _safe_float(row.get("startedAt") or row.get("started_at"), 0.0)
        expires_at = _safe_float(row.get("expiresAt") or row.get("expires_at"), 0.0)
        raw_lease_ttl = (
            row.get("leaseTtlSec")
            if row.get("leaseTtlSec") is not None
            else row.get("lease_ttl_sec")
            if row.get("lease_ttl_sec") is not None
            else row.get("ttlSec")
            if row.get("ttlSec") is not None
            else row.get("ttl_sec")
        )
        lease_ttl_sec = max(0, _safe_int(raw_lease_ttl, 0))
        if lease_ttl_sec <= 0 and expires_at > 0 and started_at > 0 and expires_at >= started_at:
            lease_ttl_sec = max(0, int(round(expires_at - started_at)))
        raw_remaining_ttl = (
            row.get("leaseRemainingTtlSec")
            if row.get("leaseRemainingTtlSec") is not None
            else row.get("lease_remaining_ttl_sec")
            if row.get("lease_remaining_ttl_sec") is not None
            else row.get("ttlRemainingSec")
            if row.get("ttlRemainingSec") is not None
            else row.get("ttl_remaining_sec")
        )
        lease_remaining_ttl_sec = max(0, _safe_int(raw_remaining_ttl, 0))
        if lease_ttl_sec > 0:
            row["leaseTtlSec"] = lease_ttl_sec
        if lease_remaining_ttl_sec > 0 or expires_at > 0:
            row["leaseRemainingTtlSec"] = lease_remaining_ttl_sec
        if expires_at > 0:
            row["expiresAt"] = expires_at
        progress = _normalize_progress(row.get("progress"))
        if progress is not None:
            row["progress"] = progress
        normalized_rows.append(row)
    out["activeTasks"] = normalized_rows
    return out


@dataclass
class ProviderHealth:
    provider: str
    ok: bool
    reason_code: str
    runtime_version: str
    available_task_kinds: list[str]
    loaded_models: list[str]
    device_backend: str
    updated_at: float
    import_error: str = ""
    active_memory_bytes: int | None = None
    peak_memory_bytes: int | None = None
    loaded_model_count: int | None = None
    registered_models: list[str] | None = None
    resource_policy: dict[str, Any] | None = None
    scheduler_state: dict[str, Any] | None = None
    lifecycle_mode: str | None = None
    supported_lifecycle_actions: list[str] | None = None
    warmup_task_kinds: list[str] | None = None
    residency_scope: str | None = None
    loaded_instances: list[dict[str, Any]] | None = None
    idle_eviction: dict[str, Any] | None = None
    real_task_kinds: list[str] | None = None
    fallback_task_kinds: list[str] | None = None
    unavailable_task_kinds: list[str] | None = None
    runtime_source: str | None = None
    runtime_source_path: str | None = None
    runtime_resolution_state: str | None = None
    runtime_reason_code: str | None = None
    fallback_used: bool | None = None
    runtime_hint: str | None = None
    runtime_missing_requirements: list[str] | None = None
    runtime_missing_optional_requirements: list[str] | None = None
    managed_service_state: dict[str, Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        data: dict[str, Any] = {
            "provider": self.provider,
            "ok": bool(self.ok),
            "reasonCode": self.reason_code,
            "runtimeVersion": self.runtime_version,
            "availableTaskKinds": list(self.available_task_kinds),
            "loadedModels": list(self.loaded_models),
            "deviceBackend": self.device_backend,
            "updatedAt": float(self.updated_at),
        }
        if self.import_error:
            data["importError"] = self.import_error
        if self.active_memory_bytes is not None:
            data["activeMemoryBytes"] = int(self.active_memory_bytes)
        if self.peak_memory_bytes is not None:
            data["peakMemoryBytes"] = int(self.peak_memory_bytes)
        if self.loaded_model_count is not None:
            data["loadedModelCount"] = int(self.loaded_model_count)
        if self.registered_models is not None:
            data["registeredModels"] = [str(model_id) for model_id in self.registered_models if str(model_id or "").strip()]
        if self.resource_policy is not None:
            data["resourcePolicy"] = dict(self.resource_policy)
        if self.scheduler_state is not None:
            data["schedulerState"] = _normalize_scheduler_state(dict(self.scheduler_state))
        if self.lifecycle_mode is not None:
            data["lifecycleMode"] = str(self.lifecycle_mode)
        if self.supported_lifecycle_actions is not None:
            data["supportedLifecycleActions"] = [
                str(action) for action in self.supported_lifecycle_actions if str(action or "").strip()
            ]
        if self.warmup_task_kinds is not None:
            data["warmupTaskKinds"] = [
                str(task_kind) for task_kind in self.warmup_task_kinds if str(task_kind or "").strip()
            ]
        if self.residency_scope is not None:
            data["residencyScope"] = str(self.residency_scope)
        if self.loaded_instances is not None:
            data["loadedInstances"] = [
                _normalize_loaded_instance(item) for item in self.loaded_instances if isinstance(item, dict)
            ]
        if self.idle_eviction is not None:
            data["idleEviction"] = dict(self.idle_eviction)
        if self.real_task_kinds is not None:
            data["realTaskKinds"] = [
                str(task_kind) for task_kind in self.real_task_kinds if str(task_kind or "").strip()
            ]
        if self.fallback_task_kinds is not None:
            data["fallbackTaskKinds"] = [
                str(task_kind) for task_kind in self.fallback_task_kinds if str(task_kind or "").strip()
            ]
        if self.unavailable_task_kinds is not None:
            data["unavailableTaskKinds"] = [
                str(task_kind) for task_kind in self.unavailable_task_kinds if str(task_kind or "").strip()
            ]
        if self.runtime_source is not None:
            data["runtimeSource"] = str(self.runtime_source).strip().lower()
        if self.runtime_source_path is not None:
            data["runtimeSourcePath"] = str(self.runtime_source_path).strip()
        if self.runtime_resolution_state is not None:
            data["runtimeResolutionState"] = str(self.runtime_resolution_state).strip().lower()
        if self.runtime_reason_code is not None:
            data["runtimeReasonCode"] = str(self.runtime_reason_code).strip()
        if self.fallback_used is not None:
            data["fallbackUsed"] = bool(self.fallback_used)
        if self.runtime_hint is not None:
            data["runtimeHint"] = str(self.runtime_hint).strip()
        if self.runtime_missing_requirements is not None:
            data["runtimeMissingRequirements"] = [
                str(requirement).strip().lower()
                for requirement in self.runtime_missing_requirements
                if str(requirement or "").strip()
            ]
        if self.runtime_missing_optional_requirements is not None:
            data["runtimeMissingOptionalRequirements"] = [
                str(requirement).strip().lower()
                for requirement in self.runtime_missing_optional_requirements
                if str(requirement or "").strip()
            ]
        if self.managed_service_state is not None:
            data["managedServiceState"] = dict(self.managed_service_state)
        return data


class LocalProvider(ABC):
    @abstractmethod
    def provider_id(self) -> str:
        raise NotImplementedError

    @abstractmethod
    def supported_task_kinds(self) -> list[str]:
        raise NotImplementedError

    @abstractmethod
    def supported_input_modalities(self) -> list[str]:
        raise NotImplementedError

    @abstractmethod
    def supported_output_modalities(self) -> list[str]:
        raise NotImplementedError

    @abstractmethod
    def healthcheck(self, *, base_dir: str, catalog_models: list[dict[str, Any]]) -> ProviderHealth:
        raise NotImplementedError

    def list_registered_models(self, *, catalog_models: list[dict[str, Any]]) -> list[dict[str, Any]]:
        provider = self.provider_id()
        out: list[dict[str, Any]] = []
        for model in catalog_models:
            if not isinstance(model, dict):
                continue
            runtime_provider = str(
                model.get("runtimeProviderID")
                or model.get("runtime_provider_id")
                or ""
            ).strip().lower()
            backend = str(model.get("backend") or "").strip().lower()
            if (runtime_provider or backend) != provider:
                continue
            out.append(model)
        return out

    def run_task(self, request: dict[str, Any]) -> dict[str, Any]:
        return {
            "ok": False,
            "provider": self.provider_id(),
            "error": f"task_not_implemented:{self.provider_id()}",
            "request": dict(request or {}),
        }

    def run_bench(self, request: dict[str, Any]) -> dict[str, Any]:
        return {
            "ok": False,
            "provider": self.provider_id(),
            "error": f"bench_not_implemented:{self.provider_id()}",
            "request": dict(request or {}),
        }

    def lifecycle_mode(self) -> str:
        return "unsupported"

    def supported_lifecycle_actions(self) -> list[str]:
        return []

    def warmup_task_kinds(self) -> list[str]:
        return []

    def residency_scope(self) -> str:
        return "none"

    def loaded_instances(self) -> list[dict[str, Any]]:
        return []

    def warmup_model(self, request: dict[str, Any]) -> dict[str, Any]:
        return {
            "ok": False,
            "provider": self.provider_id(),
            "action": "warmup_local_model",
            "lifecycleMode": self.lifecycle_mode(),
            "supportedLifecycleActions": self.supported_lifecycle_actions(),
            "warmupTaskKinds": self.warmup_task_kinds(),
            "error": f"unsupported_lifecycle:{self.provider_id()}",
            "request": dict(request or {}),
        }

    def unload_model(self, request: dict[str, Any]) -> dict[str, Any]:
        return {
            "ok": False,
            "provider": self.provider_id(),
            "action": "unload_local_model",
            "lifecycleMode": self.lifecycle_mode(),
            "supportedLifecycleActions": self.supported_lifecycle_actions(),
            "warmupTaskKinds": self.warmup_task_kinds(),
            "error": f"unsupported_lifecycle:{self.provider_id()}",
            "request": dict(request or {}),
        }

    def evict_instance(self, request: dict[str, Any]) -> dict[str, Any]:
        return {
            "ok": False,
            "provider": self.provider_id(),
            "action": "evict_local_instance",
            "lifecycleMode": self.lifecycle_mode(),
            "supportedLifecycleActions": self.supported_lifecycle_actions(),
            "warmupTaskKinds": self.warmup_task_kinds(),
            "error": f"unsupported_lifecycle:{self.provider_id()}",
            "request": dict(request or {}),
        }


class LocalProviderRegistry:
    def __init__(self) -> None:
        self._providers: dict[str, LocalProvider] = {}

    def register(self, provider: LocalProvider) -> None:
        provider_id = provider.provider_id().strip().lower()
        if not provider_id:
            raise ValueError("provider_id must not be empty")
        self._providers[provider_id] = provider

    def get(self, provider_id: str) -> LocalProvider | None:
        return self._providers.get(str(provider_id or "").strip().lower())

    def all(self) -> list[LocalProvider]:
        return [self._providers[k] for k in sorted(self._providers.keys())]

    def provider_ids(self) -> list[str]:
        return sorted(self._providers.keys())

    def health_snapshot(self, *, base_dir: str, catalog_models: list[dict[str, Any]]) -> dict[str, ProviderHealth]:
        out: dict[str, ProviderHealth] = {}
        for provider in self.all():
            health = provider.healthcheck(base_dir=base_dir, catalog_models=catalog_models)
            out[provider.provider_id()] = health
        return out
