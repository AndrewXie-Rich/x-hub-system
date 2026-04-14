from __future__ import annotations

import time
from typing import Any

from helper_binary_bridge import helper_bridge_embeddings
from local_provider_scheduler import build_provider_resource_policy, read_provider_scheduler_telemetry

from .base import ProviderHealth
from .transformers_provider import (
    EMBED_TASK_KIND,
    TEXT_TASK_KIND,
    TRANSFORMERS_PROVIDER_RUNTIME_VERSION,
    TransformersProvider,
    _normalize_task_kinds,
    _request_instance_key,
    _safe_int,
    _safe_str,
    _string_list,
)


LLAMA_CPP_PROVIDER_RUNTIME_VERSION = f"{TRANSFORMERS_PROVIDER_RUNTIME_VERSION}+llama_cpp_helper_v1"


class LlamaCppProvider(TransformersProvider):
    def provider_id(self) -> str:
        return "llama.cpp"

    def supported_task_kinds(self) -> list[str]:
        return [TEXT_TASK_KIND, EMBED_TASK_KIND]

    def supported_input_modalities(self) -> list[str]:
        return ["text"]

    def supported_output_modalities(self) -> list[str]:
        return ["text", "embedding"]

    def warmup_task_kinds(self) -> list[str]:
        return [TEXT_TASK_KIND, EMBED_TASK_KIND]

    def _helper_bridge_device_backend(self) -> str:
        return "llama.cpp"

    def _helper_bridge_executable_task_kinds(self) -> list[str]:
        return [TEXT_TASK_KIND, EMBED_TASK_KIND]

    def healthcheck(self, *, base_dir: str, catalog_models: list[dict[str, Any]]) -> ProviderHealth:
        runtime_resolution = self._runtime_resolution(base_dir=base_dir)
        helper_bridge_ready = self._helper_bridge_ready(runtime_resolution)
        registered_model_rows = self.list_registered_models(catalog_models=catalog_models)
        process_local_state = self._reconcile_process_local_state(base_dir=base_dir)
        recorded_instances_by_key = {
            _safe_str(row.get("instanceKey")): dict(row)
            for row in self._normalize_loaded_instance_rows(process_local_state.get("loadedInstances"))
            if _safe_str(row.get("instanceKey"))
        }
        helper_loaded_instances = self._helper_bridge_loaded_instance_rows(
            runtime_resolution=runtime_resolution,
            registered_model_rows=registered_model_rows,
            recorded_instances_by_key=recorded_instances_by_key,
        )
        registered_models = [
            _safe_str(model.get("id"))
            for model in registered_model_rows
            if _safe_str(model.get("id"))
        ]
        task_model_ids = {
            TEXT_TASK_KIND: [
                _safe_str(model.get("id"))
                for model in registered_model_rows
                if TEXT_TASK_KIND in _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds"))
            ],
            EMBED_TASK_KIND: [
                _safe_str(model.get("id"))
                for model in registered_model_rows
                if EMBED_TASK_KIND in _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds"))
            ],
        }
        if helper_bridge_ready:
            for row in helper_loaded_instances:
                model_id = _safe_str(row.get("modelId"))
                if not model_id:
                    continue
                for task_kind in _string_list(row.get("taskKinds")):
                    if (
                        task_kind in {TEXT_TASK_KIND, EMBED_TASK_KIND}
                        and model_id not in task_model_ids.get(task_kind, [])
                    ):
                        task_model_ids.setdefault(task_kind, []).append(model_id)

        available_task_kinds: list[str] = []
        real_task_kinds: list[str] = []
        unavailable_task_kinds: list[str] = []
        for task_kind in [TEXT_TASK_KIND, EMBED_TASK_KIND]:
            if not task_model_ids.get(task_kind):
                continue
            if helper_bridge_ready:
                real_task_kinds.append(task_kind)
                available_task_kinds.append(task_kind)
            else:
                unavailable_task_kinds.append(task_kind)

        loaded_instances = (
            helper_loaded_instances
            if helper_bridge_ready
            else self._normalize_loaded_instance_rows(process_local_state.get("loadedInstances"))
        )
        loaded_models = sorted(
            {
                _safe_str(row.get("modelId"))
                for row in loaded_instances
                if _safe_str(row.get("modelId"))
            }
        )
        warmup_task_kinds = sorted(
            {
                task_kind
                for model in registered_model_rows
                for task_kind in self._warmup_eligible_task_kinds(
                    model_info={
                        "model_id": _safe_str(model.get("id")),
                        "model_path": _safe_str(model.get("modelPath") or model.get("model_path")),
                        "task_kinds": _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds")),
                        "runtime_resolution": runtime_resolution,
                    }
                )
            }
        )

        if available_task_kinds:
            ok = True
            reason_code = "helper_bridge_loaded" if loaded_instances else "helper_bridge_ready"
        elif registered_models:
            ok = False
            if not any(task_model_ids.values()):
                reason_code = "no_supported_models"
            else:
                reason_code = _safe_str(runtime_resolution.runtime_reason_code) or "provider_unavailable"
        else:
            ok = False
            reason_code = "no_registered_models"

        lifecycle_mode = self.lifecycle_mode() if warmup_task_kinds else "ephemeral_on_demand"
        supported_lifecycle_actions = self.supported_lifecycle_actions() if warmup_task_kinds else []
        residency_scope = (
            self._helper_bridge_residency_scope()
            if helper_bridge_ready and warmup_task_kinds
            else (self.residency_scope() if warmup_task_kinds else "ephemeral")
        )
        resource_policy = build_provider_resource_policy(
            self.provider_id(),
            catalog_models=catalog_models,
        )
        scheduler_state = read_provider_scheduler_telemetry(
            base_dir,
            self.provider_id(),
            policy=resource_policy,
        )
        idle_eviction = (
            self._helper_bridge_idle_eviction_state()
            if helper_bridge_ready
            else self._normalize_idle_eviction_state(process_local_state.get("idleEviction"))
        )

        return ProviderHealth(
            provider=self.provider_id(),
            ok=ok,
            reason_code=reason_code,
            runtime_version=LLAMA_CPP_PROVIDER_RUNTIME_VERSION,
            available_task_kinds=available_task_kinds,
            loaded_models=loaded_models,
            device_backend=self._helper_bridge_device_backend(),
            updated_at=time.time(),
            import_error=_safe_str(runtime_resolution.import_error),
            loaded_model_count=len(loaded_models),
            registered_models=registered_models,
            resource_policy=resource_policy,
            scheduler_state=scheduler_state,
            lifecycle_mode=lifecycle_mode,
            supported_lifecycle_actions=supported_lifecycle_actions,
            warmup_task_kinds=warmup_task_kinds,
            residency_scope=residency_scope,
            loaded_instances=loaded_instances,
            idle_eviction=idle_eviction,
            real_task_kinds=real_task_kinds,
            fallback_task_kinds=[],
            unavailable_task_kinds=unavailable_task_kinds,
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

    def _run_embedding_task(self, request: dict[str, Any]) -> dict[str, Any]:
        started_at = time.time()
        base_dir = _safe_str(request.get("_base_dir"))
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        runtime_resolution = self._runtime_resolution(base_dir=base_dir or "", request=request)
        error_code, validated = self._validate_embedding_request(request, model_info=model_info)
        if error_code:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": EMBED_TASK_KIND,
                "modelId": model_id,
                "error": error_code,
                "request": dict(request or {}),
            }

        helper_binary = self._helper_bridge_binary_path(runtime_resolution)
        if not self._uses_helper_bridge(runtime_resolution) or not helper_binary:
            helper_reason = _safe_str(runtime_resolution.runtime_reason_code) or "helper_bridge_unavailable"
            return self._runtime_failure_output(
                request=request,
                runtime_resolution=runtime_resolution,
                error="embedding_runtime_unavailable",
                task_kind=EMBED_TASK_KIND,
                task_kinds=[EMBED_TASK_KIND],
                model_id=model_id,
                model_path=model_path,
                reason_code_override=helper_reason,
                runtime_reason_code_override=helper_reason,
            )

        loaded_row = self._helper_bridge_resolve_instance_row(
            request=request,
            model_info=model_info,
            runtime_resolution=runtime_resolution,
            task_kind=EMBED_TASK_KIND,
        )
        helper_identifier = _safe_str(loaded_row.get("instanceKey")) or _request_instance_key(request)
        if not helper_identifier:
            return self._runtime_failure_output(
                request=request,
                runtime_resolution=runtime_resolution,
                error="helper_model_not_loaded",
                task_kind=EMBED_TASK_KIND,
                task_kinds=[EMBED_TASK_KIND],
                model_id=model_id,
                model_path=model_path,
                reason_code_override="helper_model_not_loaded",
                runtime_reason_code_override="helper_model_not_loaded",
            )

        helper_result = helper_bridge_embeddings(
            helper_binary,
            identifier=helper_identifier,
            texts=list(validated.get("texts") or []),
            timeout_sec=20.0,
        )
        if not bool(helper_result.get("ok")):
            helper_reason = _safe_str(helper_result.get("reasonCode") or helper_result.get("error")) or "helper_embedding_failed"
            return self._runtime_failure_output(
                request=request,
                runtime_resolution=runtime_resolution,
                error="helper_embedding_failed",
                task_kind=EMBED_TASK_KIND,
                task_kinds=[EMBED_TASK_KIND],
                model_id=model_id,
                model_path=model_path,
                error_detail=_safe_str(helper_result.get("errorDetail")),
                reason_code_override=helper_reason,
                runtime_reason_code_override=helper_reason,
            )

        helper_usage = helper_result.get("usage") if isinstance(helper_result.get("usage"), dict) else {}
        vectors = [
            list(vector)
            for vector in (helper_result.get("vectors") or [])
            if isinstance(vector, list)
        ]
        latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
        return {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": EMBED_TASK_KIND,
            "modelId": model_id,
            "modelPath": model_path,
            "vectorCount": len(vectors),
            "dims": max(0, _safe_int(helper_result.get("dims"), 0)),
            "vectors": vectors,
            "normalized": True,
            "latencyMs": latency_ms,
            "deviceBackend": self._helper_bridge_device_backend(),
            "fallbackMode": "",
            "usage": {
                "textCount": int(validated.get("text_count") or len(vectors)),
                "totalChars": int(validated.get("total_chars") or 0),
                "maxTextChars": int(validated.get("max_text_chars") or 0),
                "inputSanitized": bool(validated.get("input_sanitized")),
                "promptTokens": max(0, _safe_int(helper_usage.get("prompt_tokens"), 0)),
                "totalTokens": max(0, _safe_int(helper_usage.get("total_tokens"), 0)),
            },
        }
