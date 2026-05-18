from __future__ import annotations

from typing import Any

from provider_runtime_resolver import resolve_provider_runtime
from .transformers_provider import (
    OCR_TASK_KIND,
    VISION_TASK_KIND,
    TransformersProvider,
    _safe_int,
    _safe_str,
)


class MLXVLMProvider(TransformersProvider):
    def provider_id(self) -> str:
        return "mlx_vlm"

    def supported_task_kinds(self) -> list[str]:
        return [VISION_TASK_KIND, OCR_TASK_KIND]

    def warmup_task_kinds(self) -> list[str]:
        return [VISION_TASK_KIND, OCR_TASK_KIND]

    def _helper_bridge_executable_task_kinds(self) -> list[str]:
        return [VISION_TASK_KIND, OCR_TASK_KIND]

    def _runtime_resolution(self, *, base_dir: str, request: dict[str, Any] | None = None) -> Any:
        _ = request
        return resolve_provider_runtime(
            self.provider_id(),
            base_dir=base_dir,
            optional_python_modules=["tokenizers"],
            eager_import=True,
            auto_start_runtime_services=False,
        )

    def _mlx_device_backend(self) -> str:
        return "mps"

    def _core_runtime_ready(self, runtime_resolution: Any) -> bool:
        return bool(runtime_resolution.supports_modules("mlx", "mlx_vlm", "transformers"))

    def _load_image_runtime(
        self,
        *,
        model_id: str,
        model_path: str,
        task_kinds: list[str],
        instance_key: str = "",
        load_profile_hash: str = "",
        effective_context_length: int = 0,
        max_context_length: int = 0,
        effective_load_profile: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        cache_key = _safe_str(instance_key) or model_path or model_id
        cached = self._image_model_cache.get(cache_key)
        if cached:
            return self._touch_cache_entry(
                cached,
                task_kinds=task_kinds,
                effective_context_length=effective_context_length,
                max_context_length=max_context_length,
                effective_load_profile=effective_load_profile,
            )

        from mlx_vlm import load as mlx_vlm_load  # type: ignore

        model, processor, _weights = mlx_vlm_load(model_path)
        if hasattr(model, "eval"):
            model.eval()

        now = __import__("time").time()
        out = {
            "processor": processor,
            "model": model,
            "device": self._mlx_device_backend(),
            "model_id": model_id,
            "model_path": model_path,
            "instance_key": _safe_str(instance_key),
            "load_profile_hash": _safe_str(load_profile_hash),
            "task_kinds": list(task_kinds or []),
            "effective_context_length": max(0, int(effective_context_length or 0)),
            "max_context_length": max(0, int(max_context_length or 0)),
            "effective_load_profile": dict(effective_load_profile or {}),
            "loaded_at": now,
            "last_used_at": now,
            "residency": "resident",
            "residency_scope": self.residency_scope(),
        }
        self._image_model_cache[cache_key] = out
        return out

    def _run_real_image(
        self,
        *,
        task_kind: str,
        model_id: str,
        model_path: str,
        instance_key: str,
        load_profile_hash: str,
        effective_context_length: int,
        max_context_length: int,
        effective_load_profile: dict[str, Any] | None,
        validated: dict[str, Any],
        request: dict[str, Any],
    ) -> tuple[str, list[dict[str, Any]], str]:
        from mlx_vlm import apply_chat_template as mlx_apply_chat_template  # type: ignore
        from mlx_vlm import generate as mlx_generate  # type: ignore

        runtime = self._load_image_runtime(
            model_id=model_id,
            model_path=model_path,
            task_kinds=[task_kind],
            instance_key=instance_key,
            load_profile_hash=load_profile_hash,
            effective_context_length=effective_context_length,
            max_context_length=max_context_length,
            effective_load_profile=effective_load_profile,
        )
        processor = runtime["processor"]
        model = runtime["model"]
        image_paths = [
            _safe_str(item.get("image_path"))
            for item in list(validated.get("image_items") or [])
            if isinstance(item, dict) and _safe_str(item.get("image_path"))
        ]
        if not image_paths and _safe_str(validated.get("image_path")):
            image_paths = [_safe_str(validated.get("image_path"))]
        if not image_paths:
            raise RuntimeError("missing_image_path")

        raw_multimodal_messages = (
            list(validated.get("multimodal_messages") or [])
            if isinstance(validated.get("multimodal_messages"), list)
            else []
        )
        prompt_input: Any
        if raw_multimodal_messages:
            prompt_input = raw_multimodal_messages
        else:
            prompt_input = self._default_image_prompt(
                task_kind=task_kind,
                prompt=_safe_str(validated.get("prompt")),
            )
        prompt = mlx_apply_chat_template(
            processor,
            getattr(model, "config", {}),
            prompt_input,
            add_generation_prompt=True,
            num_images=len(image_paths),
        )

        max_new_tokens = max(
            16,
            min(1024, _safe_int(request.get("max_new_tokens") or request.get("maxNewTokens"), 128)),
        )
        image_input: Any = image_paths[0] if len(image_paths) == 1 else image_paths
        try:
            generation = mlx_generate(
                model,
                processor,
                prompt,
                image=image_input,
                max_tokens=max_new_tokens,
                verbose=False,
            )
        except TypeError:
            generation = mlx_generate(
                model,
                processor,
                prompt,
                image=image_input,
                max_tokens=max_new_tokens,
            )

        text = _safe_str(
            generation.get("text")
            if isinstance(generation, dict)
            else getattr(generation, "text", "")
        ).strip()
        if not text:
            raise RuntimeError("empty_image_generation")

        spans: list[dict[str, Any]] = []
        if task_kind == OCR_TASK_KIND:
            spans = self._image_bbox_spans(validated, text)
        return text, spans, _safe_str(runtime.get("device")) or self._mlx_device_backend()
