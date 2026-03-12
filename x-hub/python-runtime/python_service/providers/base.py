from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any


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
            backend = str(model.get("backend") or "").strip().lower()
            if backend != provider:
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
