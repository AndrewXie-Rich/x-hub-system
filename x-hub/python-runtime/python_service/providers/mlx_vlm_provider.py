from __future__ import annotations

from .transformers_provider import OCR_TASK_KIND, VISION_TASK_KIND, TransformersProvider


class MLXVLMProvider(TransformersProvider):
    def provider_id(self) -> str:
        return "mlx_vlm"

    def supported_task_kinds(self) -> list[str]:
        return [VISION_TASK_KIND, OCR_TASK_KIND]

    def warmup_task_kinds(self) -> list[str]:
        return [VISION_TASK_KIND, OCR_TASK_KIND]

    def _helper_bridge_executable_task_kinds(self) -> list[str]:
        return [VISION_TASK_KIND, OCR_TASK_KIND]
