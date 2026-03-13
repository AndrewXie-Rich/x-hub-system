from __future__ import annotations

import atexit
import array
import hashlib
import importlib.util
import json
import math
import os
import re
import sys
import time
import wave
from typing import Any

from local_provider_scheduler import build_provider_resource_policy, read_provider_scheduler_telemetry
from .base import LocalProvider, ProviderHealth


TRANSFORMERS_PROVIDER_RUNTIME_VERSION = "2026-03-12-transformers-vision-v1"
EMBED_TASK_KIND = "embedding"
ASR_TASK_KIND = "speech_to_text"
VISION_TASK_KIND = "vision_understand"
OCR_TASK_KIND = "ocr"
HASH_FALLBACK_ENV = "XHUB_TRANSFORMERS_ALLOW_HASH_EMBED_FALLBACK"
ASR_FALLBACK_ENV = "XHUB_TRANSFORMERS_ALLOW_ASR_FALLBACK"
VISION_FALLBACK_ENV = "XHUB_TRANSFORMERS_ALLOW_VISION_FALLBACK"
MAX_BATCH_TEXTS = 32
MAX_TEXT_CHARS = 4096
MAX_TOTAL_TEXT_CHARS = 32768
DEFAULT_HASH_FALLBACK_DIMS = 64
DEFAULT_ASR_FALLBACK_TEXT_PREFIX = "offline_asr_fallback"
DEFAULT_VISION_FALLBACK_TEXT_PREFIX = "offline_vision_preview"
DEFAULT_OCR_FALLBACK_TEXT_PREFIX = "offline_ocr_preview"
MAX_AUDIO_BYTES = 25 * 1024 * 1024
MAX_AUDIO_SECONDS = 15 * 60
SUPPORTED_AUDIO_EXTENSIONS = {".wav"}
MAX_IMAGE_BYTES = 12 * 1024 * 1024
MAX_IMAGE_PIXELS = 20_000_000
MAX_IMAGE_DIMENSION = 8192
SUPPORTED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg"}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
JPEG_SOF_MARKERS = {
    0xC0, 0xC1, 0xC2, 0xC3,
    0xC5, 0xC6, 0xC7,
    0xC9, 0xCA, 0xCB,
    0xCD, 0xCE, 0xCF,
}

SECRET_TEXT_PATTERNS = [
    re.compile(r"\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)", re.IGNORECASE),
    re.compile(r"\b(api[_\s-]*key|private[_\s-]*key|secret[_\s-]*token|access[_\s-]*token|jwt|otp)\b", re.IGNORECASE),
    re.compile(r"\b(password|passcode|payment[_\s-]*(pin|code)|authorization[_\s-]*code)\b", re.IGNORECASE),
    re.compile(r"[0-9a-f]{32,}", re.IGNORECASE),
]
PROCESS_LOCAL_STATE_SCHEMA_VERSION = "xhub.transformers.process_local_state.v1"
PROCESS_LOCAL_STATE_FILENAME = "xhub_transformers_process_local_state.v1.json"


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_int(value: Any, fallback: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return int(fallback)


def _string_list(raw: Any) -> list[str]:
    if raw is None:
        return []
    items = raw if isinstance(raw, list) else str(raw or "").split(",")
    out: list[str] = []
    seen: set[str] = set()
    for item in items:
        text = _safe_str(item).lower()
        if not text or text in seen:
            continue
        seen.add(text)
        out.append(text)
    return out


def _normalize_task_kinds(raw: Any, *, backend: str = "") -> list[str]:
    task_kinds = _string_list(raw)
    if task_kinds:
        return task_kinds
    return ["text_generate"] if _safe_str(backend).lower() == "mlx" else []


def _env_flag_enabled(name: str, *, request_value: Any = None) -> bool:
    if isinstance(request_value, bool):
        return request_value
    if request_value is not None and _safe_str(request_value).lower() in {"1", "true", "yes", "on"}:
        return True
    token = _safe_str(os.environ.get(name))
    return token in {"1", "true", "yes", "on"}


def _hash_fallback_enabled(request: dict[str, Any] | None = None) -> bool:
    request_obj = request if isinstance(request, dict) else {}
    return _env_flag_enabled(HASH_FALLBACK_ENV, request_value=request_obj.get("allow_hash_fallback"))


def _asr_fallback_enabled(request: dict[str, Any] | None = None) -> bool:
    request_obj = request if isinstance(request, dict) else {}
    return _env_flag_enabled(ASR_FALLBACK_ENV, request_value=request_obj.get("allow_asr_fallback"))


def _vision_fallback_enabled(request: dict[str, Any] | None = None) -> bool:
    request_obj = request if isinstance(request, dict) else {}
    return _env_flag_enabled(VISION_FALLBACK_ENV, request_value=request_obj.get("allow_vision_fallback"))


def _has_transformers_runtime() -> tuple[bool, bool]:
    has_transformers = "transformers" in sys.modules or importlib.util.find_spec("transformers") is not None
    has_torch = "torch" in sys.modules or importlib.util.find_spec("torch") is not None
    return has_transformers, has_torch

def _write_json_atomic(path: str, payload: dict[str, Any]) -> None:
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False)
    os.replace(tmp, path)


def _process_local_state_path(base_dir: str) -> str:
    return os.path.join(os.path.abspath(str(base_dir or "")), PROCESS_LOCAL_STATE_FILENAME)


def _pid_is_alive(pid: int) -> bool:
    candidate = max(0, int(pid or 0))
    if candidate <= 1:
        return False
    try:
        os.kill(candidate, 0)
    except OSError:
        return False
    return True


def _contains_sensitive_text(text: str) -> bool:
    src = str(text or "")
    return any(pattern.search(src) for pattern in SECRET_TEXT_PATTERNS)


def _deterministic_unit_vector(*, model_id: str, text: str, dims: int) -> list[float]:
    dims_safe = max(8, min(4096, int(dims or DEFAULT_HASH_FALLBACK_DIMS)))
    seed = hashlib.sha256(f"{model_id}\0{text}".encode("utf-8")).digest()
    values: list[float] = []
    counter = 0
    while len(values) < dims_safe:
        block = hashlib.sha256(seed + counter.to_bytes(4, "big", signed=False)).digest()
        counter += 1
        for idx in range(0, len(block), 4):
            if len(values) >= dims_safe:
                break
            chunk = block[idx : idx + 4]
            if len(chunk) < 4:
                break
            raw = int.from_bytes(chunk, "big", signed=False)
            values.append(((raw / 4294967295.0) * 2.0) - 1.0)
    norm = math.sqrt(sum(value * value for value in values)) or 1.0
    return [round(value / norm, 8) for value in values]


def _safe_float(value: Any, fallback: float = 0.0) -> float:
    try:
        number = float(value)
    except Exception:
        return float(fallback)
    return number if math.isfinite(number) else float(fallback)


def _safe_bool(value: Any, fallback: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    token = _safe_str(value).lower()
    if token in {"1", "true", "yes", "on"}:
        return True
    if token in {"0", "false", "no", "off"}:
        return False
    return bool(fallback)


def _request_load_profile_hash(request: dict[str, Any]) -> str:
    return _safe_str(request.get("load_profile_hash") or request.get("loadProfileHash"))


def _request_instance_key(request: dict[str, Any]) -> str:
    return _safe_str(request.get("instance_key") or request.get("instanceKey"))


def _request_base_dir(request: dict[str, Any]) -> str:
    return _safe_str(request.get("_base_dir") or request.get("base_dir") or request.get("baseDir"))


def _request_effective_context_length(request: dict[str, Any]) -> int:
    return max(0, _safe_int(request.get("effective_context_length") or request.get("effectiveContextLength"), 0))


def _normalize_audio_extension(audio_path: str) -> str:
    return os.path.splitext(_safe_str(audio_path))[1].lower()


def _normalize_image_extension(image_path: str) -> str:
    return os.path.splitext(_safe_str(image_path))[1].lower()


def _load_wav_audio(audio_path: str) -> dict[str, Any]:
    with wave.open(audio_path, "rb") as handle:
        channels = int(handle.getnchannels() or 0)
        sample_width = int(handle.getsampwidth() or 0)
        sample_rate = int(handle.getframerate() or 0)
        frame_count = int(handle.getnframes() or 0)
        compression = _safe_str(handle.getcomptype() or "NONE")
        frames = handle.readframes(frame_count)

    if channels <= 0:
        raise RuntimeError("invalid_audio_channels")
    if sample_rate <= 0:
        raise RuntimeError("invalid_audio_sample_rate")
    if frame_count <= 0:
        raise RuntimeError("empty_audio_frames")
    if compression and compression.lower() not in {"none", "not compressed"}:
        raise RuntimeError("unsupported_audio_compression")

    if sample_width == 1:
        pcm = array.array("B")
        pcm.frombytes(frames)
        values = [((int(v) - 128) / 128.0) for v in pcm]
    elif sample_width == 2:
        pcm = array.array("h")
        pcm.frombytes(frames)
        if sys.byteorder != "little":
            pcm.byteswap()
        values = [int(v) / 32768.0 for v in pcm]
    elif sample_width == 4:
        pcm = array.array("i")
        pcm.frombytes(frames)
        if sys.byteorder != "little":
            pcm.byteswap()
        values = [int(v) / 2147483648.0 for v in pcm]
    else:
        raise RuntimeError("unsupported_audio_sample_width")

    if channels == 1:
        mono = [round(_safe_float(value), 8) for value in values]
    else:
        mono = []
        for offset in range(0, len(values), channels):
            frame = values[offset : offset + channels]
            if not frame:
                continue
            mono.append(round(sum(frame) / len(frame), 8))

    duration_sec = max(0.0, frame_count / float(sample_rate))
    return {
        "samples": mono,
        "duration_sec": duration_sec,
        "sample_rate": sample_rate,
        "channels": channels,
        "sample_width": sample_width,
        "frame_count": frame_count,
    }


def _load_png_image_info(buffer: bytes) -> dict[str, Any]:
    if len(buffer) < 24 or buffer[:8] != PNG_SIGNATURE:
        raise RuntimeError("image_decode_failed")
    if buffer[12:16] != b"IHDR":
        raise RuntimeError("image_decode_failed")
    width = int.from_bytes(buffer[16:20], "big", signed=False)
    height = int.from_bytes(buffer[20:24], "big", signed=False)
    if width <= 0 or height <= 0:
        raise RuntimeError("image_decode_failed")
    return {
        "image_format": ".png",
        "image_width": width,
        "image_height": height,
    }


def _load_jpeg_image_info(buffer: bytes) -> dict[str, Any]:
    if len(buffer) < 4 or buffer[0] != 0xFF or buffer[1] != 0xD8:
        raise RuntimeError("image_decode_failed")

    offset = 2
    while offset + 4 <= len(buffer):
        while offset < len(buffer) and buffer[offset] == 0xFF:
            offset += 1
        if offset >= len(buffer):
            break
        marker = buffer[offset]
        offset += 1

        if marker == 0xD9:
            break
        if marker == 0x01 or 0xD0 <= marker <= 0xD7:
            continue
        if offset + 2 > len(buffer):
            break

        segment_length = int.from_bytes(buffer[offset : offset + 2], "big", signed=False)
        offset += 2
        if segment_length < 2 or offset + segment_length - 2 > len(buffer):
            break

        if marker in JPEG_SOF_MARKERS:
            if segment_length < 7:
                raise RuntimeError("image_decode_failed")
            height = int.from_bytes(buffer[offset + 1 : offset + 3], "big", signed=False)
            width = int.from_bytes(buffer[offset + 3 : offset + 5], "big", signed=False)
            if width <= 0 or height <= 0:
                raise RuntimeError("image_decode_failed")
            return {
                "image_format": ".jpeg",
                "image_width": width,
                "image_height": height,
            }

        offset += segment_length - 2

    raise RuntimeError("image_decode_failed")


def _load_image_info(image_path: str) -> dict[str, Any]:
    with open(image_path, "rb") as handle:
        data = handle.read()

    ext = _normalize_image_extension(image_path)
    if ext == ".png":
        info = _load_png_image_info(data)
    elif ext in {".jpg", ".jpeg"}:
        info = _load_jpeg_image_info(data)
    else:
        raise RuntimeError("unsupported_image_format")

    image_width = int(info.get("image_width") or 0)
    image_height = int(info.get("image_height") or 0)
    return {
        **info,
        "file_size_bytes": len(data),
        "image_pixels": image_width * image_height,
        "image_digest_prefix": hashlib.sha256(data).hexdigest()[:16],
    }


class TransformersProvider(LocalProvider):
    def __init__(self) -> None:
        self._embedding_model_cache: dict[str, dict[str, Any]] = {}
        self._asr_pipeline_cache: dict[str, dict[str, Any]] = {}
        self._tracked_base_dirs: set[str] = set()
        self._exit_hook_registered = False

    def provider_id(self) -> str:
        return "transformers"

    def supported_task_kinds(self) -> list[str]:
        return [
            EMBED_TASK_KIND,
            ASR_TASK_KIND,
            VISION_TASK_KIND,
            OCR_TASK_KIND,
        ]

    def supported_input_modalities(self) -> list[str]:
        return ["text", "audio", "image"]

    def supported_output_modalities(self) -> list[str]:
        return ["embedding", "text", "segments", "spans"]

    def lifecycle_mode(self) -> str:
        return "warmable"

    def supported_lifecycle_actions(self) -> list[str]:
        return [
            "warmup_local_model",
            "unload_local_model",
            "evict_local_instance",
        ]

    def warmup_task_kinds(self) -> list[str]:
        return [EMBED_TASK_KIND, ASR_TASK_KIND]

    def residency_scope(self) -> str:
        return "process_local"

    def _default_idle_eviction_state(self, *, owner_pid: int = 0) -> dict[str, Any]:
        return {
            "policy": "manual_or_process_exit",
            "automaticIdleEvictionEnabled": False,
            "idleTimeoutSec": 0,
            "processScoped": True,
            "lastEvictionReason": "none",
            "lastEvictionAt": 0.0,
            "lastEvictedInstanceKeys": [],
            "lastEvictedModelIds": [],
            "lastEvictedCount": 0,
            "totalEvictedInstanceCount": 0,
            "updatedAt": 0.0,
            "ownerPid": max(0, int(owner_pid or 0)),
        }

    def _normalize_loaded_instance_rows(self, rows: Any) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        seen: set[str] = set()
        for entry in rows if isinstance(rows, list) else []:
            if not isinstance(entry, dict):
                continue
            instance_key = _safe_str(entry.get("instanceKey") or entry.get("instance_key"))
            if not instance_key or instance_key in seen:
                continue
            seen.add(instance_key)
            out.append(
                {
                    "instanceKey": instance_key,
                    "modelId": _safe_str(entry.get("modelId") or entry.get("model_id")),
                    "taskKinds": _string_list(entry.get("taskKinds") or entry.get("task_kinds")),
                    "loadProfileHash": _safe_str(entry.get("loadProfileHash") or entry.get("load_profile_hash")),
                    "effectiveContextLength": max(0, _safe_int(entry.get("effectiveContextLength") or entry.get("effective_context_length"), 0)),
                    "loadedAt": _safe_float(entry.get("loadedAt") or entry.get("loaded_at"), 0.0),
                    "lastUsedAt": _safe_float(entry.get("lastUsedAt") or entry.get("last_used_at"), 0.0),
                    "residency": _safe_str(entry.get("residency")) or "resident",
                    "residencyScope": _safe_str(entry.get("residencyScope") or entry.get("residency_scope")) or self.residency_scope(),
                    "deviceBackend": _safe_str(entry.get("deviceBackend") or entry.get("device_backend") or entry.get("device")) or "cpu",
                }
            )
        out.sort(key=lambda item: (item.get("modelId") or "", item.get("instanceKey") or ""))
        return out

    def _normalize_idle_eviction_state(self, raw: Any) -> dict[str, Any]:
        row = raw if isinstance(raw, dict) else {}
        return {
            "policy": _safe_str(row.get("policy")) or "manual_or_process_exit",
            "automaticIdleEvictionEnabled": _safe_bool(
                row.get("automaticIdleEvictionEnabled", row.get("automatic_idle_eviction_enabled")),
                False,
            ),
            "idleTimeoutSec": max(0, _safe_int(row.get("idleTimeoutSec") or row.get("idle_timeout_sec"), 0)),
            "processScoped": _safe_bool(row.get("processScoped", row.get("process_scoped")), True),
            "lastEvictionReason": _safe_str(row.get("lastEvictionReason") or row.get("last_eviction_reason")) or "none",
            "lastEvictionAt": _safe_float(row.get("lastEvictionAt") or row.get("last_eviction_at"), 0.0),
            "lastEvictedInstanceKeys": [
                _safe_str(value)
                for value in (row.get("lastEvictedInstanceKeys") or row.get("last_evicted_instance_keys") or [])
                if _safe_str(value)
            ],
            "lastEvictedModelIds": [
                _safe_str(value)
                for value in (row.get("lastEvictedModelIds") or row.get("last_evicted_model_ids") or [])
                if _safe_str(value)
            ],
            "lastEvictedCount": max(0, _safe_int(row.get("lastEvictedCount") or row.get("last_evicted_count"), 0)),
            "totalEvictedInstanceCount": max(
                0,
                _safe_int(row.get("totalEvictedInstanceCount") or row.get("total_evicted_instance_count"), 0),
            ),
            "updatedAt": _safe_float(row.get("updatedAt") or row.get("updated_at"), 0.0),
            "ownerPid": max(0, _safe_int(row.get("ownerPid") or row.get("owner_pid"), 0)),
        }

    def _read_process_local_state(self, *, base_dir: str) -> dict[str, Any]:
        path = _process_local_state_path(base_dir)
        default_state = {
            "schemaVersion": PROCESS_LOCAL_STATE_SCHEMA_VERSION,
            "provider": self.provider_id(),
            "updatedAt": 0.0,
            "ownerPid": 0,
            "loadedInstances": [],
            "loadedInstanceCount": 0,
            "idleEviction": self._default_idle_eviction_state(),
        }
        if not os.path.exists(path):
            return dict(default_state)
        try:
            with open(path, "r", encoding="utf-8") as handle:
                raw = json.load(handle)
        except Exception:
            return dict(default_state)
        row = raw if isinstance(raw, dict) else {}
        loaded_instances = self._normalize_loaded_instance_rows(
            row.get("loadedInstances") if isinstance(row.get("loadedInstances"), list) else row.get("loaded_instances")
        )
        owner_pid = max(0, _safe_int(row.get("ownerPid") or row.get("owner_pid"), 0))
        idle_eviction = self._normalize_idle_eviction_state(row.get("idleEviction") or row.get("idle_eviction"))
        if owner_pid > 0 and idle_eviction.get("ownerPid", 0) == 0:
            idle_eviction["ownerPid"] = owner_pid
        return {
            "schemaVersion": _safe_str(row.get("schemaVersion") or row.get("schema_version")) or PROCESS_LOCAL_STATE_SCHEMA_VERSION,
            "provider": self.provider_id(),
            "updatedAt": _safe_float(row.get("updatedAt") or row.get("updated_at"), 0.0),
            "ownerPid": owner_pid,
            "loadedInstances": loaded_instances,
            "loadedInstanceCount": len(loaded_instances),
            "idleEviction": idle_eviction,
        }

    def _write_process_local_state(
        self,
        *,
        base_dir: str,
        loaded_instances: list[dict[str, Any]],
        idle_eviction: dict[str, Any],
        owner_pid: int,
    ) -> None:
        payload = {
            "schemaVersion": PROCESS_LOCAL_STATE_SCHEMA_VERSION,
            "provider": self.provider_id(),
            "updatedAt": time.time(),
            "ownerPid": max(0, int(owner_pid or 0)),
            "loadedInstances": self._normalize_loaded_instance_rows(loaded_instances),
            "loadedInstanceCount": len(self._normalize_loaded_instance_rows(loaded_instances)),
            "idleEviction": self._normalize_idle_eviction_state(idle_eviction),
        }
        _write_json_atomic(_process_local_state_path(base_dir), payload)

    def _ensure_process_local_tracking(self, *, base_dir: str) -> str:
        normalized = os.path.abspath(str(base_dir or ""))
        if not normalized:
            return ""
        self._tracked_base_dirs.add(normalized)
        if not self._exit_hook_registered:
            atexit.register(self._handle_process_exit)
            self._exit_hook_registered = True
        return normalized

    def _sync_process_local_state(
        self,
        *,
        base_dir: str,
        eviction_reason: str = "",
        evicted_instances: list[dict[str, Any]] | None = None,
    ) -> None:
        normalized_base_dir = self._ensure_process_local_tracking(base_dir=base_dir)
        if not normalized_base_dir:
            return
        previous = self._read_process_local_state(base_dir=normalized_base_dir)
        idle_eviction = self._normalize_idle_eviction_state(previous.get("idleEviction"))
        if eviction_reason:
            evicted_rows = self._normalize_loaded_instance_rows(evicted_instances or [])
            evicted_instance_keys = [row["instanceKey"] for row in evicted_rows if _safe_str(row.get("instanceKey"))]
            evicted_model_ids = sorted({_safe_str(row.get("modelId")) for row in evicted_rows if _safe_str(row.get("modelId"))})
            evicted_count = len(evicted_instance_keys)
            idle_eviction["lastEvictionReason"] = eviction_reason
            idle_eviction["lastEvictionAt"] = time.time()
            idle_eviction["lastEvictedInstanceKeys"] = evicted_instance_keys
            idle_eviction["lastEvictedModelIds"] = evicted_model_ids
            idle_eviction["lastEvictedCount"] = evicted_count
            idle_eviction["totalEvictedInstanceCount"] = max(
                0,
                _safe_int(idle_eviction.get("totalEvictedInstanceCount"), 0) + evicted_count,
            )
        idle_eviction["updatedAt"] = time.time()
        loaded_instances = self.loaded_instances()
        owner_pid = os.getpid() if loaded_instances else 0
        idle_eviction["ownerPid"] = owner_pid
        self._write_process_local_state(
            base_dir=normalized_base_dir,
            loaded_instances=loaded_instances,
            idle_eviction=idle_eviction,
            owner_pid=owner_pid,
        )

    def _reconcile_process_local_state(self, *, base_dir: str) -> dict[str, Any]:
        state = self._read_process_local_state(base_dir=base_dir)
        loaded_instances = self._normalize_loaded_instance_rows(state.get("loadedInstances"))
        owner_pid = max(0, _safe_int(state.get("ownerPid"), 0))
        idle_eviction = self._normalize_idle_eviction_state(state.get("idleEviction"))
        if loaded_instances and owner_pid > 1 and owner_pid != os.getpid() and not _pid_is_alive(owner_pid):
            idle_eviction["lastEvictionReason"] = "process_exit_reconciled"
            idle_eviction["lastEvictionAt"] = time.time()
            idle_eviction["lastEvictedInstanceKeys"] = [
                row["instanceKey"] for row in loaded_instances if _safe_str(row.get("instanceKey"))
            ]
            idle_eviction["lastEvictedModelIds"] = sorted(
                {_safe_str(row.get("modelId")) for row in loaded_instances if _safe_str(row.get("modelId"))}
            )
            idle_eviction["lastEvictedCount"] = len(idle_eviction["lastEvictedInstanceKeys"])
            idle_eviction["totalEvictedInstanceCount"] = max(
                0,
                _safe_int(idle_eviction.get("totalEvictedInstanceCount"), 0) + idle_eviction["lastEvictedCount"],
            )
            idle_eviction["updatedAt"] = time.time()
            idle_eviction["ownerPid"] = 0
            self._write_process_local_state(
                base_dir=base_dir,
                loaded_instances=[],
                idle_eviction=idle_eviction,
                owner_pid=0,
            )
            return self._read_process_local_state(base_dir=base_dir)
        return state

    def _handle_process_exit(self) -> None:
        if not self._tracked_base_dirs:
            return
        evicted_instances = self.loaded_instances()
        if evicted_instances:
            self._embedding_model_cache.clear()
            self._asr_pipeline_cache.clear()
        for base_dir in list(self._tracked_base_dirs):
            if evicted_instances:
                self._sync_process_local_state(
                    base_dir=base_dir,
                    eviction_reason="process_exit",
                    evicted_instances=evicted_instances,
                )
            elif os.path.exists(_process_local_state_path(base_dir)):
                reconciled = self._reconcile_process_local_state(base_dir=base_dir)
                idle_eviction = self._normalize_idle_eviction_state(reconciled.get("idleEviction"))
                idle_eviction["ownerPid"] = 0
                self._write_process_local_state(
                    base_dir=base_dir,
                    loaded_instances=[],
                    idle_eviction=idle_eviction,
                    owner_pid=0,
                )

    def loaded_instances(self) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for entry in list(self._embedding_model_cache.values()) + list(self._asr_pipeline_cache.values()):
            if not isinstance(entry, dict):
                continue
            row = {
                "instanceKey": _safe_str(entry.get("instance_key")),
                "modelId": _safe_str(entry.get("model_id")),
                "taskKinds": _string_list(entry.get("task_kinds")),
                "loadProfileHash": _safe_str(entry.get("load_profile_hash")),
                "effectiveContextLength": max(0, _safe_int(entry.get("effective_context_length"), 0)),
                "loadedAt": _safe_float(entry.get("loaded_at"), 0.0),
                "lastUsedAt": _safe_float(entry.get("last_used_at"), 0.0),
                "residency": _safe_str(entry.get("residency")) or "resident",
                "residencyScope": _safe_str(entry.get("residency_scope")) or self.residency_scope(),
                "deviceBackend": _safe_str(entry.get("device") or entry.get("device_backend")) or "cpu",
            }
            if not row["instanceKey"]:
                continue
            rows.append(row)
        rows.sort(key=lambda item: (item.get("modelId") or "", item.get("instanceKey") or ""))
        return rows

    def _implemented_task_kinds(self) -> list[str]:
        task_kinds = [EMBED_TASK_KIND, ASR_TASK_KIND]
        if _vision_fallback_enabled():
            task_kinds.extend([VISION_TASK_KIND, OCR_TASK_KIND])
        return task_kinds

    def _warmup_eligible_task_kinds(self, *, model_info: dict[str, Any]) -> list[str]:
        model_path = _safe_str(model_info.get("model_path"))
        if not model_path:
            return []
        task_kinds = _string_list(model_info.get("task_kinds"))
        if not task_kinds:
            return []
        has_transformers, has_torch = _has_transformers_runtime()
        if not has_transformers or not has_torch:
            return []
        return [
            task_kind
            for task_kind in task_kinds
            if task_kind in self.warmup_task_kinds()
        ]

    def _touch_cache_entry(
        self,
        entry: dict[str, Any],
        *,
        task_kinds: list[str],
        effective_context_length: int = 0,
    ) -> dict[str, Any]:
        now = time.time()
        if not isinstance(entry, dict):
            return {}
        normalized_task_kinds = _string_list(task_kinds)
        entry.setdefault("loaded_at", now)
        entry["last_used_at"] = now
        if normalized_task_kinds:
            entry["task_kinds"] = normalized_task_kinds
        if effective_context_length > 0:
            entry["effective_context_length"] = max(0, int(effective_context_length))
        entry.setdefault("residency", "resident")
        entry.setdefault("residency_scope", self.residency_scope())
        return entry

    def _collect_matching_cache_entries(
        self,
        *,
        model_id: str = "",
        instance_key: str = "",
    ) -> list[tuple[str, str, dict[str, Any]]]:
        wanted_model_id = _safe_str(model_id)
        wanted_instance_key = _safe_str(instance_key)
        out: list[tuple[str, str, dict[str, Any]]] = []
        caches = (
            ("embedding", self._embedding_model_cache),
            ("speech_to_text", self._asr_pipeline_cache),
        )
        for cache_name, cache in caches:
            for cache_key, entry in list(cache.items()):
                if not isinstance(entry, dict):
                    continue
                if wanted_instance_key and _safe_str(entry.get("instance_key")) != wanted_instance_key:
                    continue
                if wanted_model_id and _safe_str(entry.get("model_id")) != wanted_model_id:
                    continue
                out.append((cache_name, cache_key, entry))
        return out

    def healthcheck(self, *, base_dir: str, catalog_models: list[dict[str, Any]]) -> ProviderHealth:
        has_transformers, has_torch = _has_transformers_runtime()
        registered_model_rows = self.list_registered_models(catalog_models=catalog_models)
        registered_models = [
            _safe_str(model.get("id"))
            for model in registered_model_rows
            if _safe_str(model.get("id"))
        ]
        task_model_ids = {
            EMBED_TASK_KIND: [
                _safe_str(model.get("id"))
                for model in registered_model_rows
                if EMBED_TASK_KIND in _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds"))
            ],
            ASR_TASK_KIND: [
                _safe_str(model.get("id"))
                for model in registered_model_rows
                if ASR_TASK_KIND in _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds"))
            ],
            VISION_TASK_KIND: [
                _safe_str(model.get("id"))
                for model in registered_model_rows
                if VISION_TASK_KIND in _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds"))
            ],
            OCR_TASK_KIND: [
                _safe_str(model.get("id"))
                for model in registered_model_rows
                if OCR_TASK_KIND in _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds"))
            ],
        }

        available_task_kinds: list[str] = []
        real_task_kinds: list[str] = []
        fallback_task_kinds: list[str] = []
        import_error = ""
        needs_transformers_runtime = bool(task_model_ids[EMBED_TASK_KIND] or task_model_ids[ASR_TASK_KIND])
        if needs_transformers_runtime and (not has_transformers or not has_torch):
            if not has_transformers:
                import_error = "missing_module:transformers"
            elif not has_torch:
                import_error = "missing_module:torch"
        if task_model_ids[EMBED_TASK_KIND]:
            if has_transformers and has_torch:
                real_task_kinds.append(EMBED_TASK_KIND)
                available_task_kinds.append(EMBED_TASK_KIND)
            elif _hash_fallback_enabled():
                fallback_task_kinds.append(EMBED_TASK_KIND)
                available_task_kinds.append(EMBED_TASK_KIND)
        if task_model_ids[ASR_TASK_KIND]:
            if has_transformers and has_torch:
                real_task_kinds.append(ASR_TASK_KIND)
                available_task_kinds.append(ASR_TASK_KIND)
            elif _asr_fallback_enabled():
                fallback_task_kinds.append(ASR_TASK_KIND)
                available_task_kinds.append(ASR_TASK_KIND)
        if task_model_ids[VISION_TASK_KIND] and _vision_fallback_enabled():
            fallback_task_kinds.append(VISION_TASK_KIND)
            available_task_kinds.append(VISION_TASK_KIND)
        if task_model_ids[OCR_TASK_KIND] and _vision_fallback_enabled():
            fallback_task_kinds.append(OCR_TASK_KIND)
            available_task_kinds.append(OCR_TASK_KIND)

        unavailable_task_kinds = [
            task_kind
            for task_kind, model_ids in task_model_ids.items()
            if model_ids and task_kind not in available_task_kinds
        ]

        if available_task_kinds:
            ok = True
            if unavailable_task_kinds:
                reason_code = "partial_ready"
            elif real_task_kinds and not fallback_task_kinds:
                reason_code = "ready"
            elif fallback_task_kinds and not real_task_kinds:
                reason_code = "fallback_ready"
            else:
                reason_code = "partial_ready"
        elif registered_models:
            ok = False
            if import_error:
                reason_code = "import_error"
            elif not any(task_model_ids.values()):
                reason_code = "no_supported_models"
            elif unavailable_task_kinds and all(task_kind in {VISION_TASK_KIND, OCR_TASK_KIND} for task_kind in unavailable_task_kinds):
                reason_code = "preview_disabled"
            elif task_model_ids[ASR_TASK_KIND] and not task_model_ids[EMBED_TASK_KIND]:
                reason_code = "asr_unavailable"
            elif task_model_ids[EMBED_TASK_KIND] and not task_model_ids[ASR_TASK_KIND]:
                reason_code = "embedding_unavailable"
            elif task_model_ids[VISION_TASK_KIND] and not task_model_ids[OCR_TASK_KIND]:
                reason_code = "vision_unavailable"
            elif task_model_ids[OCR_TASK_KIND] and not task_model_ids[VISION_TASK_KIND]:
                reason_code = "ocr_unavailable"
            else:
                reason_code = "provider_unavailable"
        else:
            ok = False
            reason_code = "no_registered_models"

        current_loaded_instances = self.loaded_instances()
        if current_loaded_instances:
            self._sync_process_local_state(base_dir=base_dir)
        process_local_state = self._reconcile_process_local_state(base_dir=base_dir)
        loaded_instances = self._normalize_loaded_instance_rows(
            current_loaded_instances or process_local_state.get("loadedInstances")
        )
        loaded_models = sorted(
            {
                _safe_str(row.get("modelId"))
                for row in loaded_instances
                if _safe_str(row.get("modelId"))
            }
        )
        idle_eviction = self._normalize_idle_eviction_state(process_local_state.get("idleEviction"))
        warmup_task_kinds = sorted(
            {
                task_kind
                for model in registered_model_rows
                for task_kind in self._warmup_eligible_task_kinds(
                    model_info={
                        "model_id": _safe_str(model.get("id")),
                        "model_path": _safe_str(model.get("modelPath") or model.get("model_path")),
                        "task_kinds": _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds")),
                    }
                )
            }
        )
        lifecycle_mode = self.lifecycle_mode() if warmup_task_kinds else "ephemeral_on_demand"
        supported_lifecycle_actions = self.supported_lifecycle_actions() if warmup_task_kinds else []
        residency_scope = self.residency_scope() if warmup_task_kinds else "ephemeral"
        resource_policy = build_provider_resource_policy(
            self.provider_id(),
            catalog_models=catalog_models,
        )
        scheduler_state = read_provider_scheduler_telemetry(
            base_dir,
            self.provider_id(),
            policy=resource_policy,
        )

        return ProviderHealth(
            provider=self.provider_id(),
            ok=ok,
            reason_code=reason_code,
            runtime_version=TRANSFORMERS_PROVIDER_RUNTIME_VERSION,
            available_task_kinds=available_task_kinds,
            loaded_models=loaded_models,
            device_backend="mps_or_cpu",
            updated_at=time.time(),
            import_error=import_error,
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
        )

    def run_task(self, request: dict[str, Any]) -> dict[str, Any]:
        task_kind = _safe_str(request.get("task_kind") or request.get("taskKind")).lower()
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
        if task_kind == ASR_TASK_KIND:
            return self._run_asr_task(request)
        if task_kind in {VISION_TASK_KIND, OCR_TASK_KIND}:
            return self._run_image_task(request, task_kind=task_kind)
        if task_kind:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "error": f"task_not_implemented:transformers:{task_kind}",
                "request": dict(request or {}),
            }
        return {
            "ok": False,
            "provider": self.provider_id(),
            "taskKind": "unknown",
            "error": "missing_task_kind",
            "request": dict(request or {}),
        }

    def warmup_model(self, request: dict[str, Any]) -> dict[str, Any]:
        started_at = time.time()
        base_dir = _request_base_dir(request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        requested_task_kind = _safe_str(request.get("task_kind") or request.get("taskKind")).lower()
        model_task_kinds = _string_list(model_info.get("task_kinds"))
        if not model_id:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "warmup_local_model",
                "error": "missing_model_id",
                "request": dict(request or {}),
            }
        if requested_task_kind and model_task_kinds and requested_task_kind not in model_task_kinds:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "warmup_local_model",
                "modelId": model_id,
                "taskKind": requested_task_kind,
                "error": f"model_task_unsupported:{requested_task_kind}",
                "request": dict(request or {}),
            }
        selected_task_kinds = [requested_task_kind] if requested_task_kind else [
            task_kind for task_kind in model_task_kinds if task_kind in self.warmup_task_kinds()
        ]
        if not selected_task_kinds:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "warmup_local_model",
                "modelId": model_id,
                "error": (
                    f"warmup_unsupported_task_kind:{model_task_kinds[0]}"
                    if model_task_kinds else "missing_task_kind"
                ),
                "request": dict(request or {}),
            }
        unsupported_warmup_task = next(
            (task_kind for task_kind in selected_task_kinds if task_kind not in self.warmup_task_kinds()),
            "",
        )
        if unsupported_warmup_task:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "warmup_local_model",
                "modelId": model_id,
                "taskKind": unsupported_warmup_task,
                "taskKinds": selected_task_kinds,
                "error": f"warmup_unsupported_task_kind:{unsupported_warmup_task}",
                "request": dict(request or {}),
            }
        if not model_path:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "warmup_local_model",
                "modelId": model_id,
                "taskKinds": selected_task_kinds,
                "error": "missing_model_path",
                "request": dict(request or {}),
            }

        has_transformers, has_torch = _has_transformers_runtime()
        if not has_transformers:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "warmup_local_model",
                "modelId": model_id,
                "taskKinds": selected_task_kinds,
                "error": "missing_module:transformers",
                "request": dict(request or {}),
            }
        if not has_torch:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "warmup_local_model",
                "modelId": model_id,
                "taskKinds": selected_task_kinds,
                "error": "missing_module:torch",
                "request": dict(request or {}),
            }

        instance_key = _request_instance_key(request)
        load_profile_hash = _request_load_profile_hash(request)
        effective_context_length = _request_effective_context_length(request)
        device_backends: list[str] = []
        already_loaded = True

        try:
            for task_kind in selected_task_kinds:
                cache_key = _safe_str(instance_key) or model_path or model_id
                if task_kind == EMBED_TASK_KIND:
                    if cache_key not in self._embedding_model_cache:
                        already_loaded = False
                    runtime = self._load_embedding_runtime(
                        model_id=model_id,
                        model_path=model_path,
                        instance_key=instance_key,
                        load_profile_hash=load_profile_hash,
                        effective_context_length=effective_context_length,
                    )
                elif task_kind == ASR_TASK_KIND:
                    if cache_key not in self._asr_pipeline_cache:
                        already_loaded = False
                    runtime = self._load_asr_runtime(
                        model_id=model_id,
                        model_path=model_path,
                        instance_key=instance_key,
                        load_profile_hash=load_profile_hash,
                        effective_context_length=effective_context_length,
                    )
                else:
                    return {
                        "ok": False,
                        "provider": self.provider_id(),
                        "action": "warmup_local_model",
                        "modelId": model_id,
                        "taskKind": task_kind,
                        "taskKinds": selected_task_kinds,
                        "error": f"warmup_unsupported_task_kind:{task_kind}",
                        "request": dict(request or {}),
                    }
                device_backends.append(_safe_str(runtime.get("device")) or "cpu")
        except Exception as exc:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "warmup_local_model",
                "modelId": model_id,
                "taskKinds": selected_task_kinds,
                "error": "warmup_runtime_failed",
                "errorDetail": _safe_str(exc)[:240],
                "request": dict(request or {}),
            }

        cold_start_ms = 0 if already_loaded else max(0, int(round((time.time() - started_at) * 1000.0)))
        normalized_backends = sorted({backend for backend in device_backends if backend})
        if base_dir:
            self._sync_process_local_state(base_dir=base_dir)
        return {
            "ok": True,
            "provider": self.provider_id(),
            "action": "warmup_local_model",
            "modelId": model_id,
            "modelPath": model_path,
            "taskKind": requested_task_kind,
            "taskKinds": selected_task_kinds,
            "instanceKey": instance_key,
            "loadProfileHash": load_profile_hash,
            "effectiveContextLength": effective_context_length,
            "deviceBackend": normalized_backends[0] if len(normalized_backends) == 1 else ("mixed" if normalized_backends else "cpu"),
            "coldStartMs": cold_start_ms,
            "alreadyLoaded": already_loaded,
            "lifecycleMode": self.lifecycle_mode(),
            "supportedLifecycleActions": self.supported_lifecycle_actions(),
            "warmupTaskKinds": self.warmup_task_kinds(),
            "residencyScope": self.residency_scope(),
            "processScoped": True,
        }

    def unload_model(self, request: dict[str, Any]) -> dict[str, Any]:
        base_dir = _request_base_dir(request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        if not model_id:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "unload_local_model",
                "error": "missing_model_id",
                "request": dict(request or {}),
            }
        matches = self._collect_matching_cache_entries(model_id=model_id)
        if not matches:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "unload_local_model",
                "modelId": model_id,
                "error": "model_not_loaded",
                "request": dict(request or {}),
            }

        task_kinds: set[str] = set()
        evicted_rows: list[dict[str, Any]] = []
        for cache_name, cache_key, entry in matches:
            cache = self._embedding_model_cache if cache_name == EMBED_TASK_KIND else self._asr_pipeline_cache
            task_kinds.update(_string_list(entry.get("task_kinds")))
            if isinstance(entry, dict):
                evicted_rows.append(dict(entry))
            cache.pop(cache_key, None)
        if base_dir:
            self._sync_process_local_state(
                base_dir=base_dir,
                eviction_reason="manual_unload",
                evicted_instances=evicted_rows,
            )

        return {
            "ok": True,
            "provider": self.provider_id(),
            "action": "unload_local_model",
            "modelId": model_id,
            "taskKinds": sorted(task_kinds),
            "unloadedInstanceCount": len(matches),
            "lifecycleMode": self.lifecycle_mode(),
            "supportedLifecycleActions": self.supported_lifecycle_actions(),
            "warmupTaskKinds": self.warmup_task_kinds(),
            "residencyScope": self.residency_scope(),
            "processScoped": True,
        }

    def evict_instance(self, request: dict[str, Any]) -> dict[str, Any]:
        base_dir = _request_base_dir(request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        instance_key = _request_instance_key(request)
        if not instance_key:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "evict_local_instance",
                "error": "missing_instance_key",
                "request": dict(request or {}),
            }
        matches = self._collect_matching_cache_entries(instance_key=instance_key)
        if not matches:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "evict_local_instance",
                "instanceKey": instance_key,
                "error": "instance_not_loaded",
                "request": dict(request or {}),
            }

        task_kinds: set[str] = set()
        model_id = ""
        evicted_rows: list[dict[str, Any]] = []
        for cache_name, cache_key, entry in matches:
            cache = self._embedding_model_cache if cache_name == EMBED_TASK_KIND else self._asr_pipeline_cache
            task_kinds.update(_string_list(entry.get("task_kinds")))
            if not model_id:
                model_id = _safe_str(entry.get("model_id"))
            if isinstance(entry, dict):
                evicted_rows.append(dict(entry))
            cache.pop(cache_key, None)
        if base_dir:
            self._sync_process_local_state(
                base_dir=base_dir,
                eviction_reason="manual_evict_instance",
                evicted_instances=evicted_rows,
            )

        return {
            "ok": True,
            "provider": self.provider_id(),
            "action": "evict_local_instance",
            "modelId": model_id,
            "instanceKey": instance_key,
            "taskKinds": sorted(task_kinds),
            "evictedInstanceCount": len(matches),
            "lifecycleMode": self.lifecycle_mode(),
            "supportedLifecycleActions": self.supported_lifecycle_actions(),
            "warmupTaskKinds": self.warmup_task_kinds(),
            "residencyScope": self.residency_scope(),
            "processScoped": True,
        }

    def _resolve_model_info(self, request: dict[str, Any]) -> dict[str, Any]:
        resolved_model = request.get("_resolved_model") if isinstance(request.get("_resolved_model"), dict) else {}
        processor_requirements = (
            resolved_model.get("processorRequirements")
            if isinstance(resolved_model.get("processorRequirements"), dict)
            else resolved_model.get("processor_requirements")
        )
        trust_profile = (
            resolved_model.get("trustProfile")
            if isinstance(resolved_model.get("trustProfile"), dict)
            else resolved_model.get("trust_profile")
        )
        return {
            "model_id": _safe_str(
                request.get("model_id")
                or request.get("modelId")
                or resolved_model.get("id")
            ),
            "model_path": _safe_str(
                request.get("model_path")
                or request.get("modelPath")
                or resolved_model.get("modelPath")
                or resolved_model.get("model_path")
            ),
            "task_kinds": _normalize_task_kinds(
                request.get("task_kinds")
                or request.get("taskKinds")
                or resolved_model.get("taskKinds")
                or resolved_model.get("task_kinds")
            ),
            "processor_requirements": processor_requirements if isinstance(processor_requirements, dict) else {},
            "trust_profile": trust_profile if isinstance(trust_profile, dict) else {},
        }

    def _extract_texts(self, request: dict[str, Any]) -> list[str]:
        raw_texts = request.get("texts")
        if isinstance(raw_texts, list):
            return [str(item or "") for item in raw_texts]
        if request.get("text") is not None:
            return [str(request.get("text") or "")]
        return []

    def _validate_embedding_request(self, request: dict[str, Any], *, model_info: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        model_id = _safe_str(model_info.get("model_id"))
        if not model_id:
            return "missing_model_id", {}

        task_kinds = model_info.get("task_kinds")
        if isinstance(task_kinds, list) and task_kinds and EMBED_TASK_KIND not in task_kinds:
            return "model_task_unsupported:embedding", {}

        texts = self._extract_texts(request)
        if not texts:
            return "missing_texts", {}
        if len(texts) > MAX_BATCH_TEXTS:
            return "embedding_batch_too_large", {}

        total_chars = 0
        max_text_chars = 0
        input_sanitized = bool(request.get("input_sanitized"))
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

    def _extract_audio_input(self, request: dict[str, Any]) -> dict[str, Any]:
        input_obj = request.get("input") if isinstance(request.get("input"), dict) else {}
        options = request.get("options") if isinstance(request.get("options"), dict) else {}
        return {
            "audio_path": _safe_str(
                request.get("audio_path")
                or request.get("audioPath")
                or input_obj.get("audio_path")
                or input_obj.get("audioPath")
            ),
            "language": _safe_str(
                request.get("language")
                or request.get("lang")
                or options.get("language")
                or options.get("lang")
            ),
            "timestamps": _safe_bool(
                request.get("timestamps")
                if request.get("timestamps") is not None
                else options.get("timestamps"),
                fallback=False,
            ),
            "input_sensitivity": _safe_str(
                request.get("input_sensitivity")
                or request.get("inputSensitivity")
                or input_obj.get("sensitivity")
            ).lower(),
        }

    def _extract_image_input(self, request: dict[str, Any]) -> dict[str, Any]:
        input_obj = request.get("input") if isinstance(request.get("input"), dict) else {}
        options = request.get("options") if isinstance(request.get("options"), dict) else {}
        return {
            "image_path": _safe_str(
                request.get("image_path")
                or request.get("imagePath")
                or input_obj.get("image_path")
                or input_obj.get("imagePath")
                or input_obj.get("path")
            ),
            "prompt": _safe_str(
                request.get("prompt")
                or request.get("question")
                or options.get("prompt")
                or options.get("question")
                or input_obj.get("prompt")
                or input_obj.get("question")
            ),
            "language": _safe_str(
                request.get("language")
                or request.get("lang")
                or options.get("language")
                or options.get("lang")
                or input_obj.get("language")
                or input_obj.get("lang")
            ),
            "input_sensitivity": _safe_str(
                request.get("input_sensitivity")
                or request.get("inputSensitivity")
                or input_obj.get("sensitivity")
            ).lower(),
        }

    def _validate_asr_request(self, request: dict[str, Any], *, model_info: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        model_id = _safe_str(model_info.get("model_id"))
        if not model_id:
            return "missing_model_id", {}

        task_kinds = model_info.get("task_kinds")
        if isinstance(task_kinds, list) and task_kinds and ASR_TASK_KIND not in task_kinds:
            return "model_task_unsupported:speech_to_text", {}

        audio_input = self._extract_audio_input(request)
        audio_path = _safe_str(audio_input.get("audio_path"))
        if not audio_path:
            return "missing_audio_path", {}
        if "\x00" in audio_path:
            return "invalid_audio_path", {}
        if not os.path.exists(audio_path) or not os.path.isfile(audio_path):
            return "audio_path_not_found", {}

        ext = _normalize_audio_extension(audio_path)
        if ext not in SUPPORTED_AUDIO_EXTENSIONS:
            return "unsupported_audio_format", {
                "audio_path": audio_path,
                "audio_format": ext,
            }

        max_audio_bytes = max(1024, min(100 * 1024 * 1024, _safe_int(request.get("max_audio_bytes"), MAX_AUDIO_BYTES)))
        file_size_bytes = max(0, os.path.getsize(audio_path))
        if file_size_bytes > max_audio_bytes:
            return "audio_file_too_large", {
                "audio_path": audio_path,
                "audio_format": ext,
                "file_size_bytes": file_size_bytes,
                "max_audio_bytes": max_audio_bytes,
            }

        try:
            audio_meta = _load_wav_audio(audio_path)
        except RuntimeError as exc:
            return _safe_str(exc) or "audio_decode_failed", {
                "audio_path": audio_path,
                "audio_format": ext,
                "file_size_bytes": file_size_bytes,
            }

        max_audio_seconds = max(1, min(3600, _safe_int(request.get("max_audio_seconds"), MAX_AUDIO_SECONDS)))
        duration_sec = _safe_float(audio_meta.get("duration_sec"), 0.0)
        if duration_sec > float(max_audio_seconds):
            return "audio_duration_too_long", {
                "audio_path": audio_path,
                "audio_format": ext,
                "file_size_bytes": file_size_bytes,
                "duration_sec": round(duration_sec, 6),
                "max_audio_seconds": max_audio_seconds,
            }

        trust_profile = model_info.get("trust_profile") if isinstance(model_info.get("trust_profile"), dict) else {}
        allow_secret_value = request.get("allow_secret_input")
        if allow_secret_value is None:
            allow_secret_value = request.get("allowSecretInput")
        if allow_secret_value is None and isinstance(trust_profile, dict):
            allow_secret_value = trust_profile.get("allowSecretInput")
        allow_secret_input = _safe_bool(
            allow_secret_value,
            fallback=_safe_bool(trust_profile.get("allow_secret_input"), False) if isinstance(trust_profile, dict) else False,
        )
        if audio_input.get("input_sensitivity") == "secret" and not allow_secret_input:
            return "policy_blocked_secret_audio", {
                "audio_path": audio_path,
                "audio_format": ext,
                "file_size_bytes": file_size_bytes,
                "duration_sec": round(duration_sec, 6),
            }

        return "", {
            **audio_input,
            "audio_path": audio_path,
            "audio_format": ext,
            "file_size_bytes": file_size_bytes,
            "duration_sec": round(duration_sec, 6),
            "sample_rate": int(audio_meta.get("sample_rate") or 0),
            "channel_count": int(audio_meta.get("channels") or 0),
            "sample_width": int(audio_meta.get("sample_width") or 0),
            "samples": list(audio_meta.get("samples") or []),
            "max_audio_seconds": max_audio_seconds,
            "max_audio_bytes": max_audio_bytes,
        }

    def _validate_image_request(
        self,
        request: dict[str, Any],
        *,
        model_info: dict[str, Any],
        task_kind: str,
    ) -> tuple[str, dict[str, Any]]:
        model_id = _safe_str(model_info.get("model_id"))
        if not model_id:
            return "missing_model_id", {}

        task_kinds = model_info.get("task_kinds")
        if isinstance(task_kinds, list) and task_kinds and task_kind not in task_kinds:
            return f"model_task_unsupported:{task_kind}", {}

        image_input = self._extract_image_input(request)
        image_path = _safe_str(image_input.get("image_path"))
        if not image_path:
            return "missing_image_path", {}
        if "\x00" in image_path:
            return "invalid_image_path", {}
        if not os.path.exists(image_path) or not os.path.isfile(image_path):
            return "image_path_not_found", {}

        ext = _normalize_image_extension(image_path)
        if ext not in SUPPORTED_IMAGE_EXTENSIONS:
            return "unsupported_image_format", {
                "image_path": image_path,
                "image_format": ext,
            }

        max_image_bytes = max(1024, min(100 * 1024 * 1024, _safe_int(request.get("max_image_bytes"), MAX_IMAGE_BYTES)))
        file_size_bytes = max(0, os.path.getsize(image_path))
        if file_size_bytes > max_image_bytes:
            return "image_file_too_large", {
                "image_path": image_path,
                "image_format": ext,
                "file_size_bytes": file_size_bytes,
                "max_image_bytes": max_image_bytes,
            }

        try:
            image_meta = _load_image_info(image_path)
        except RuntimeError as exc:
            return _safe_str(exc) or "image_decode_failed", {
                "image_path": image_path,
                "image_format": ext,
                "file_size_bytes": file_size_bytes,
            }

        max_image_dimension = max(32, min(16384, _safe_int(request.get("max_image_dimension"), MAX_IMAGE_DIMENSION)))
        image_width = int(image_meta.get("image_width") or 0)
        image_height = int(image_meta.get("image_height") or 0)
        if image_width > max_image_dimension or image_height > max_image_dimension:
            return "image_dimensions_too_large", {
                "image_path": image_path,
                "image_format": ext,
                "file_size_bytes": file_size_bytes,
                "image_width": image_width,
                "image_height": image_height,
                "image_pixels": int(image_meta.get("image_pixels") or 0),
                "max_image_dimension": max_image_dimension,
            }

        max_image_pixels = max(1024, min(100_000_000, _safe_int(request.get("max_image_pixels"), MAX_IMAGE_PIXELS)))
        image_pixels = int(image_meta.get("image_pixels") or 0)
        if image_pixels > max_image_pixels:
            return "image_pixels_too_large", {
                "image_path": image_path,
                "image_format": ext,
                "file_size_bytes": file_size_bytes,
                "image_width": image_width,
                "image_height": image_height,
                "image_pixels": image_pixels,
                "max_image_pixels": max_image_pixels,
            }

        trust_profile = model_info.get("trust_profile") if isinstance(model_info.get("trust_profile"), dict) else {}
        allow_secret_value = request.get("allow_secret_input")
        if allow_secret_value is None:
            allow_secret_value = request.get("allowSecretInput")
        if allow_secret_value is None and isinstance(trust_profile, dict):
            allow_secret_value = trust_profile.get("allowSecretInput")
        allow_secret_input = _safe_bool(
            allow_secret_value,
            fallback=_safe_bool(trust_profile.get("allow_secret_input"), False) if isinstance(trust_profile, dict) else False,
        )
        if image_input.get("input_sensitivity") == "secret" and not allow_secret_input:
            return "policy_blocked_secret_image", {
                "image_path": image_path,
                "image_format": ext,
                "file_size_bytes": file_size_bytes,
                "image_width": image_width,
                "image_height": image_height,
                "image_pixels": image_pixels,
            }

        return "", {
            **image_input,
            "image_path": image_path,
            "image_format": _safe_str(image_meta.get("image_format")) or ext,
            "file_size_bytes": file_size_bytes,
            "image_width": image_width,
            "image_height": image_height,
            "image_pixels": image_pixels,
            "image_digest_prefix": _safe_str(image_meta.get("image_digest_prefix")),
            "max_image_bytes": max_image_bytes,
            "max_image_pixels": max_image_pixels,
            "max_image_dimension": max_image_dimension,
        }

    def _hash_fallback_dims(self, request: dict[str, Any], *, model_info: dict[str, Any]) -> int:
        processor_requirements = (
            model_info.get("processor_requirements")
            if isinstance(model_info.get("processor_requirements"), dict)
            else {}
        )
        raw_dims = (
            request.get("fallback_dims")
            or processor_requirements.get("embeddingDims")
            or processor_requirements.get("embedding_dims")
            or DEFAULT_HASH_FALLBACK_DIMS
        )
        return max(8, min(4096, _safe_int(raw_dims, DEFAULT_HASH_FALLBACK_DIMS)))

    def _load_asr_runtime(
        self,
        *,
        model_id: str,
        model_path: str,
        instance_key: str = "",
        load_profile_hash: str = "",
        effective_context_length: int = 0,
    ) -> dict[str, Any]:
        cache_key = _safe_str(instance_key) or model_path or model_id
        cached = self._asr_pipeline_cache.get(cache_key)
        if cached:
            return self._touch_cache_entry(
                cached,
                task_kinds=[ASR_TASK_KIND],
                effective_context_length=effective_context_length,
            )

        from transformers import pipeline  # type: ignore

        pipe = None
        load_errors: list[str] = []
        for kwargs in (
            {"local_files_only": True, "trust_remote_code": False},
            {"trust_remote_code": False},
            {},
        ):
            try:
                pipe = pipeline(
                    "automatic-speech-recognition",
                    model=model_path,
                    **kwargs,
                )
                break
            except TypeError as exc:
                load_errors.append(_safe_str(exc))
                continue
        if pipe is None:
            raise RuntimeError(load_errors[-1] if load_errors else "asr_pipeline_init_failed")

        now = time.time()
        out = {
            "pipeline": pipe,
            "model_id": model_id,
            "model_path": model_path,
            "instance_key": _safe_str(instance_key),
            "load_profile_hash": _safe_str(load_profile_hash),
            "device": _safe_str(getattr(pipe, "device", "cpu")) or "cpu",
            "task_kinds": [ASR_TASK_KIND],
            "effective_context_length": max(0, int(effective_context_length or 0)),
            "loaded_at": now,
            "last_used_at": now,
            "residency": "resident",
            "residency_scope": self.residency_scope(),
        }
        self._asr_pipeline_cache[cache_key] = out
        return out

    def _load_embedding_runtime(
        self,
        *,
        model_id: str,
        model_path: str,
        instance_key: str = "",
        load_profile_hash: str = "",
        effective_context_length: int = 0,
    ) -> dict[str, Any]:
        cache_key = _safe_str(instance_key) or model_path or model_id
        cached = self._embedding_model_cache.get(cache_key)
        if cached:
            return self._touch_cache_entry(
                cached,
                task_kinds=[EMBED_TASK_KIND],
                effective_context_length=effective_context_length,
            )

        import torch  # type: ignore
        from transformers import AutoModel, AutoTokenizer  # type: ignore

        device = "mps" if bool(getattr(torch.backends, "mps", None)) and torch.backends.mps.is_available() else "cpu"
        tokenizer = AutoTokenizer.from_pretrained(
            model_path,
            local_files_only=True,
            trust_remote_code=False,
        )
        model = AutoModel.from_pretrained(
            model_path,
            local_files_only=True,
            trust_remote_code=False,
        )
        model.eval()
        model.to(device)

        dims = 0
        config = getattr(model, "config", None)
        for attr in ("projection_dim", "sentence_embedding_dimension", "hidden_size", "d_model", "dim"):
            raw_value = getattr(config, attr, None) if config is not None else None
            if isinstance(raw_value, int) and raw_value > 0:
                dims = int(raw_value)
                break

        now = time.time()
        out = {
            "tokenizer": tokenizer,
            "model": model,
            "device": device,
            "dims": dims,
            "model_id": model_id,
            "model_path": model_path,
            "instance_key": _safe_str(instance_key),
            "load_profile_hash": _safe_str(load_profile_hash),
            "task_kinds": [EMBED_TASK_KIND],
            "effective_context_length": max(0, int(effective_context_length or 0)),
            "loaded_at": now,
            "last_used_at": now,
            "residency": "resident",
            "residency_scope": self.residency_scope(),
        }
        self._embedding_model_cache[cache_key] = out
        return out

    def _run_real_embedding(
        self,
        *,
        model_id: str,
        model_path: str,
        instance_key: str,
        load_profile_hash: str,
        effective_context_length: int,
        texts: list[str],
        max_length: int,
    ) -> tuple[list[list[float]], int, str]:
        import torch  # type: ignore
        import torch.nn.functional as torch_f  # type: ignore

        runtime = self._load_embedding_runtime(
            model_id=model_id,
            model_path=model_path,
            instance_key=instance_key,
            load_profile_hash=load_profile_hash,
            effective_context_length=effective_context_length,
        )
        tokenizer = runtime["tokenizer"]
        model = runtime["model"]
        device = str(runtime.get("device") or "cpu")

        encoded = tokenizer(
            texts,
            padding=True,
            truncation=True,
            max_length=max(32, min(2048, int(max_length or 512))),
            return_tensors="pt",
        )
        encoded = {
            key: value.to(device) if hasattr(value, "to") else value
            for key, value in encoded.items()
        }
        with torch.no_grad():
            outputs = model(**encoded)
            hidden = getattr(outputs, "last_hidden_state", None)
            if hidden is None and isinstance(outputs, (tuple, list)) and outputs:
                hidden = outputs[0]
            if hidden is None:
                raise RuntimeError("missing_last_hidden_state")
            attention_mask = encoded.get("attention_mask")
            if attention_mask is None:
                pooled = hidden.mean(dim=1)
            else:
                mask = attention_mask.unsqueeze(-1).expand(hidden.size()).float()
                pooled = (hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1e-9)
            normalized = torch_f.normalize(pooled, p=2, dim=1)
            vectors = normalized.detach().cpu().tolist()

        dims = len(vectors[0]) if vectors else _safe_int(runtime.get("dims"), 0)
        normalized_vectors = [
            [round(float(value), 8) for value in vector]
            for vector in vectors
        ]
        return normalized_vectors, dims, device

    def _run_real_asr(
        self,
        *,
        model_id: str,
        model_path: str,
        instance_key: str,
        load_profile_hash: str,
        effective_context_length: int,
        audio_meta: dict[str, Any],
        language: str,
        timestamps: bool,
    ) -> tuple[str, list[dict[str, Any]], str]:
        runtime = self._load_asr_runtime(
            model_id=model_id,
            model_path=model_path,
            instance_key=instance_key,
            load_profile_hash=load_profile_hash,
            effective_context_length=effective_context_length,
        )
        pipe = runtime["pipeline"]
        call_kwargs: dict[str, Any] = {}
        if timestamps:
            call_kwargs["return_timestamps"] = True
        if language:
            call_kwargs["generate_kwargs"] = {"language": language}
        result = pipe(
            {
                "raw": list(audio_meta.get("samples") or []),
                "sampling_rate": int(audio_meta.get("sample_rate") or 0),
            },
            **call_kwargs,
        )

        if isinstance(result, str):
            text = _safe_str(result)
            segments: list[dict[str, Any]] = []
        else:
            result_obj = result if isinstance(result, dict) else {}
            text = _safe_str(result_obj.get("text"))
            segments = []
            chunks = result_obj.get("chunks")
            if isinstance(chunks, list):
                for idx, chunk in enumerate(chunks):
                    if not isinstance(chunk, dict):
                        continue
                    timestamp = chunk.get("timestamp") if isinstance(chunk.get("timestamp"), (list, tuple)) else ()
                    start_sec = _safe_float(timestamp[0], 0.0) if len(timestamp) > 0 else 0.0
                    end_sec = _safe_float(timestamp[1], _safe_float(audio_meta.get("duration_sec"), 0.0)) if len(timestamp) > 1 else _safe_float(audio_meta.get("duration_sec"), 0.0)
                    segments.append(
                        {
                            "index": idx,
                            "startSec": round(start_sec, 6),
                            "endSec": round(end_sec, 6),
                            "text": _safe_str(chunk.get("text")),
                        }
                    )

        if text and not segments:
            duration_sec = round(_safe_float(audio_meta.get("duration_sec"), 0.0), 6)
            segments = [
                {
                    "index": 0,
                    "startSec": 0.0,
                    "endSec": duration_sec,
                    "text": text,
                }
            ]

        return text, segments, _safe_str(runtime.get("device")) or "cpu"

    def _build_asr_fallback_output(
        self,
        *,
        model_id: str,
        validated: dict[str, Any],
        latency_ms: int,
    ) -> dict[str, Any]:
        audio_path = _safe_str(validated.get("audio_path"))
        with open(audio_path, "rb") as handle:
            digest = hashlib.sha256(handle.read()).hexdigest()[:16]
        transcript = f"[{DEFAULT_ASR_FALLBACK_TEXT_PREFIX}:{digest}]"
        duration_sec = round(_safe_float(validated.get("duration_sec"), 0.0), 6)
        return {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": ASR_TASK_KIND,
            "modelId": model_id,
            "modelPath": _safe_str(validated.get("model_path")),
            "text": transcript,
            "segments": [
                {
                    "index": 0,
                    "startSec": 0.0,
                    "endSec": duration_sec,
                    "text": transcript,
                }
            ],
            "language": _safe_str(validated.get("language")),
            "latencyMs": latency_ms,
            "deviceBackend": "cpu_hash",
            "fallbackMode": "wav_hash",
            "usage": {
                "inputAudioSec": duration_sec,
                "inputAudioBytes": int(validated.get("file_size_bytes") or 0),
                "sampleRate": int(validated.get("sample_rate") or 0),
                "channelCount": int(validated.get("channel_count") or 0),
                "timestampsRequested": bool(validated.get("timestamps")),
            },
        }

    def _image_usage_payload(self, validated: dict[str, Any]) -> dict[str, Any]:
        return {
            "inputImageBytes": int(validated.get("file_size_bytes") or 0),
            "inputImageWidth": int(validated.get("image_width") or 0),
            "inputImageHeight": int(validated.get("image_height") or 0),
            "inputImagePixels": int(validated.get("image_pixels") or 0),
            "promptChars": len(_safe_str(validated.get("prompt"))),
        }

    def _build_vision_fallback_output(
        self,
        *,
        task_kind: str,
        model_id: str,
        validated: dict[str, Any],
        latency_ms: int,
    ) -> dict[str, Any]:
        digest = _safe_str(validated.get("image_digest_prefix"))
        width = int(validated.get("image_width") or 0)
        height = int(validated.get("image_height") or 0)
        prompt = _safe_str(validated.get("prompt"))

        if task_kind == OCR_TASK_KIND:
            text = f"[{DEFAULT_OCR_FALLBACK_TEXT_PREFIX}:{digest}]"
            spans = [
                {
                    "index": 0,
                    "text": text,
                    "bbox": {
                        "x": 0,
                        "y": 0,
                        "width": width,
                        "height": height,
                    },
                }
            ]
        else:
            text = f"[{DEFAULT_VISION_FALLBACK_TEXT_PREFIX}:{digest}] image={width}x{height}"
            if prompt:
                text = f"{text} prompt={prompt[:120]}"
            spans = []

        return {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": task_kind,
            "modelId": model_id,
            "modelPath": _safe_str(validated.get("model_path")),
            "text": text,
            "spans": spans,
            "language": _safe_str(validated.get("language")),
            "latencyMs": latency_ms,
            "deviceBackend": "cpu_hash",
            "fallbackMode": "image_hash_preview",
            "usage": self._image_usage_payload(validated),
        }

    def _run_embedding_task(self, request: dict[str, Any]) -> dict[str, Any]:
        started_at = time.time()
        base_dir = _request_base_dir(request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
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

        texts = list(validated.get("texts") or [])
        model_path = _safe_str(model_info.get("model_path"))
        instance_key = _request_instance_key(request)
        load_profile_hash = _request_load_profile_hash(request)
        effective_context_length = _request_effective_context_length(request)
        max_length = max(32, min(2048, _safe_int(request.get("max_length"), 512)))
        allow_hash_fallback = _hash_fallback_enabled(request)
        has_transformers, has_torch = _has_transformers_runtime()

        vectors: list[list[float]] = []
        dims = 0
        device_backend = "cpu"
        fallback_mode = ""
        error_detail = ""

        if has_transformers and has_torch and model_path:
            try:
                vectors, dims, device_backend = self._run_real_embedding(
                    model_id=model_id,
                    model_path=model_path,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                    effective_context_length=effective_context_length,
                    texts=texts,
                    max_length=max_length,
                )
            except Exception as exc:
                error_detail = _safe_str(exc)
                if not allow_hash_fallback:
                    return {
                        "ok": False,
                        "provider": self.provider_id(),
                        "taskKind": EMBED_TASK_KIND,
                        "modelId": model_id,
                        "modelPath": model_path,
                        "error": "embedding_runtime_failed",
                        "errorDetail": error_detail[:240],
                        "request": dict(request or {}),
                    }

        if not vectors:
            if not allow_hash_fallback:
                if not model_path:
                    error_code = "missing_model_path"
                elif not has_transformers:
                    error_code = "missing_module:transformers"
                elif not has_torch:
                    error_code = "missing_module:torch"
                else:
                    error_code = "embedding_runtime_failed"
                out = {
                    "ok": False,
                    "provider": self.provider_id(),
                    "taskKind": EMBED_TASK_KIND,
                    "modelId": model_id,
                    "modelPath": model_path,
                    "error": error_code,
                    "request": dict(request or {}),
                }
                if error_detail:
                    out["errorDetail"] = error_detail[:240]
                return out
            dims = self._hash_fallback_dims(request, model_info=model_info)
            vectors = [
                _deterministic_unit_vector(model_id=model_id, text=text, dims=dims)
                for text in texts
            ]
            device_backend = "cpu_hash"
            fallback_mode = "hash"

        latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
        if base_dir and not fallback_mode and has_transformers and has_torch and model_path:
            self._sync_process_local_state(base_dir=base_dir)
        return {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": EMBED_TASK_KIND,
            "modelId": model_id,
            "modelPath": model_path,
            "vectorCount": len(vectors),
            "dims": dims,
            "vectors": vectors,
            "normalized": True,
            "latencyMs": latency_ms,
            "deviceBackend": device_backend,
            "fallbackMode": fallback_mode,
            "usage": {
                "textCount": int(validated.get("text_count") or len(texts)),
                "totalChars": int(validated.get("total_chars") or 0),
                "maxTextChars": int(validated.get("max_text_chars") or 0),
                "inputSanitized": bool(validated.get("input_sanitized")),
            },
        }

    def _run_asr_task(self, request: dict[str, Any]) -> dict[str, Any]:
        started_at = time.time()
        base_dir = _request_base_dir(request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        error_code, validated = self._validate_asr_request(request, model_info=model_info)
        if error_code:
            out = {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": ASR_TASK_KIND,
                "modelId": model_id,
                "modelPath": model_path,
                "error": error_code,
                "request": dict(request or {}),
            }
            out["usage"] = {
                "inputAudioBytes": int(validated.get("file_size_bytes") or 0),
                "inputAudioSec": round(_safe_float(validated.get("duration_sec"), 0.0), 6),
            }
            return out

        has_transformers, has_torch = _has_transformers_runtime()
        allow_asr_fallback = _asr_fallback_enabled(request)
        instance_key = _request_instance_key(request)
        load_profile_hash = _request_load_profile_hash(request)
        effective_context_length = _request_effective_context_length(request)
        error_detail = ""
        text = ""
        segments: list[dict[str, Any]] = []
        device_backend = "cpu"
        fallback_mode = ""

        if has_transformers and has_torch and model_path:
            try:
                text, segments, device_backend = self._run_real_asr(
                    model_id=model_id,
                    model_path=model_path,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                    effective_context_length=effective_context_length,
                    audio_meta=validated,
                    language=_safe_str(validated.get("language")),
                    timestamps=bool(validated.get("timestamps")),
                )
            except Exception as exc:
                error_detail = _safe_str(exc)
                if not allow_asr_fallback:
                    return {
                        "ok": False,
                        "provider": self.provider_id(),
                        "taskKind": ASR_TASK_KIND,
                        "modelId": model_id,
                        "modelPath": model_path,
                        "error": "speech_to_text_runtime_failed",
                        "errorDetail": error_detail[:240],
                        "request": dict(request or {}),
                        "usage": {
                            "inputAudioBytes": int(validated.get("file_size_bytes") or 0),
                            "inputAudioSec": round(_safe_float(validated.get("duration_sec"), 0.0), 6),
                            "sampleRate": int(validated.get("sample_rate") or 0),
                            "channelCount": int(validated.get("channel_count") or 0),
                            "timestampsRequested": bool(validated.get("timestamps")),
                        },
                    }

        if not text and not segments:
            if not allow_asr_fallback:
                if not model_path:
                    error_code = "missing_model_path"
                elif not has_transformers:
                    error_code = "missing_module:transformers"
                elif not has_torch:
                    error_code = "missing_module:torch"
                else:
                    error_code = "speech_to_text_runtime_failed"
                out = {
                    "ok": False,
                    "provider": self.provider_id(),
                    "taskKind": ASR_TASK_KIND,
                    "modelId": model_id,
                    "modelPath": model_path,
                    "error": error_code,
                    "request": dict(request or {}),
                    "usage": {
                        "inputAudioBytes": int(validated.get("file_size_bytes") or 0),
                        "inputAudioSec": round(_safe_float(validated.get("duration_sec"), 0.0), 6),
                        "sampleRate": int(validated.get("sample_rate") or 0),
                        "channelCount": int(validated.get("channel_count") or 0),
                        "timestampsRequested": bool(validated.get("timestamps")),
                    },
                }
                if error_detail:
                    out["errorDetail"] = error_detail[:240]
                return out

            latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
            validated_with_model = {
                **validated,
                "model_path": model_path,
            }
            return self._build_asr_fallback_output(
                model_id=model_id,
                validated=validated_with_model,
                latency_ms=latency_ms,
            )

        latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
        duration_sec = round(_safe_float(validated.get("duration_sec"), 0.0), 6)
        if base_dir and not fallback_mode and has_transformers and has_torch and model_path:
            self._sync_process_local_state(base_dir=base_dir)
        return {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": ASR_TASK_KIND,
            "modelId": model_id,
            "modelPath": model_path,
            "text": (_safe_str(text) or _safe_str(segments[0].get("text"))) if segments else _safe_str(text),
            "segments": segments,
            "language": _safe_str(validated.get("language")),
            "latencyMs": latency_ms,
            "deviceBackend": device_backend,
            "fallbackMode": fallback_mode,
            "usage": {
                "inputAudioSec": duration_sec,
                "inputAudioBytes": int(validated.get("file_size_bytes") or 0),
                "sampleRate": int(validated.get("sample_rate") or 0),
                "channelCount": int(validated.get("channel_count") or 0),
                "timestampsRequested": bool(validated.get("timestamps")),
            },
        }

    def _run_image_task(self, request: dict[str, Any], *, task_kind: str) -> dict[str, Any]:
        started_at = time.time()
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        error_code, validated = self._validate_image_request(
            request,
            model_info=model_info,
            task_kind=task_kind,
        )
        if error_code:
            out = {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "modelId": model_id,
                "modelPath": model_path,
                "error": error_code,
                "request": dict(request or {}),
            }
            out["usage"] = self._image_usage_payload(validated)
            return out

        if not _vision_fallback_enabled(request):
            return {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "modelId": model_id,
                "modelPath": model_path,
                "error": "provider_not_ready",
                "errorDetail": f"{task_kind}_preview_disabled",
                "request": dict(request or {}),
                "usage": self._image_usage_payload(validated),
            }

        latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
        validated_with_model = {
            **validated,
            "model_path": model_path,
        }
        return self._build_vision_fallback_output(
            task_kind=task_kind,
            model_id=model_id,
            validated=validated_with_model,
            latency_ms=latency_ms,
        )
