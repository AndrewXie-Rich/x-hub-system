from __future__ import annotations

import atexit
import array
from contextlib import ExitStack
import hashlib
import importlib.util
import json
import math
import os
import re
import resource
import shutil
import subprocess
import sys
import tempfile
import time
import wave
import zlib
from typing import Any

from helper_binary_bridge import (
    HelperBinaryBridgeLoadRequest,
    encode_helper_image_data_url,
    helper_bridge_chat_completion,
    helper_bridge_embeddings,
    list_helper_bridge_loaded_models,
    load_helper_bridge_model,
    unload_helper_bridge_model,
)
from local_provider_scheduler import build_provider_resource_policy, read_provider_scheduler_telemetry
from provider_runtime_resolver import resolve_provider_runtime
from .base import LocalProvider, ProviderHealth
from .tts_kokoro_adapter import KokoroSynthesisError, kokoro_runtime_available, synthesize_kokoro_to_file


TRANSFORMERS_PROVIDER_RUNTIME_VERSION = "2026-04-06-transformers-native-text-v1"
IMAGE_TASK_ROUTE_TRACE_SCHEMA_VERSION = "xhub.local_provider.image_task_route_trace.v1"
TEXT_TASK_KIND = "text_generate"
EMBED_TASK_KIND = "embedding"
ASR_TASK_KIND = "speech_to_text"
TTS_TASK_KIND = "text_to_speech"
VISION_TASK_KIND = "vision_understand"
OCR_TASK_KIND = "ocr"
HASH_FALLBACK_ENV = "XHUB_TRANSFORMERS_ALLOW_HASH_EMBED_FALLBACK"
ASR_FALLBACK_ENV = "XHUB_TRANSFORMERS_ALLOW_ASR_FALLBACK"
VISION_FALLBACK_ENV = "XHUB_TRANSFORMERS_ALLOW_VISION_FALLBACK"
TTS_SYSTEM_FALLBACK_ENV = "XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK"
TTS_SAY_BINARY_ENV = "XHUB_TRANSFORMERS_TTS_SAY_BINARY"
MAX_BATCH_TEXTS = 32
MAX_TEXT_CHARS = 4096
MAX_TOTAL_TEXT_CHARS = 32768
MAX_TTS_TEXT_CHARS = 6000
DEFAULT_HASH_FALLBACK_DIMS = 64
DEFAULT_ASR_FALLBACK_TEXT_PREFIX = "offline_asr_fallback"
DEFAULT_VISION_FALLBACK_TEXT_PREFIX = "offline_vision_preview"
DEFAULT_OCR_FALLBACK_TEXT_PREFIX = "offline_ocr_preview"
MLX_VLM_HELPER_LOAD_TIMEOUT_SEC = 180.0
MLX_VLM_HELPER_CHAT_TIMEOUT_SEC = 120.0
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
NATIVE_DEPENDENCY_ERROR_TOKENS = (
    "dlopen",
    "library not loaded",
    "image not found",
    "symbol not found",
    "mach-o",
    "native",
)
QUANTIZATION_CONFIG_ERROR_TOKENS = (
    "quantization config",
    "quantization_config",
    "quant_method",
    "correctly quantized",
)

SECRET_TEXT_PATTERNS = [
    re.compile(r"\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)", re.IGNORECASE),
    re.compile(r"\b(api[_\s-]*key|private[_\s-]*key|secret[_\s-]*token|access[_\s-]*token|jwt|otp)\b", re.IGNORECASE),
    re.compile(r"\b(password|passcode|payment[_\s-]*(pin|code)|authorization[_\s-]*code)\b", re.IGNORECASE),
    re.compile(r"[0-9a-f]{32,}", re.IGNORECASE),
]
PROCESS_LOCAL_STATE_SCHEMA_VERSION = "xhub.transformers.process_local_state.v1"
PROCESS_LOCAL_STATE_FILENAME = "xhub_transformers_process_local_state.v1.json"
BENCH_FIXTURE_SCHEMA_VERSION = "xhub.local_bench_fixture_pack.v1"
GENERATED_BENCH_FIXTURE_DIRNAME = "generated_bench_fixtures"
GENERATED_TTS_AUDIO_DIRNAME = "generated_tts_audio"
DEFAULT_TTS_RATE_WPM = 180
MIN_TTS_RATE_WPM = 110
MAX_TTS_RATE_WPM = 320
TTS_NATIVE_ENGINE_ALIASES = {
    "kokoro": ("kokoro",),
    "melotts": ("melotts", "melo", "melo_tts"),
    "cosyvoice": ("cosyvoice", "cosy_voice"),
}


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


def _value_list(raw: Any) -> list[str]:
    if raw is None:
        return []
    items = raw if isinstance(raw, list) else [raw]
    out: list[str] = []
    for item in items:
        text = _safe_str(item)
        if not text:
            continue
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


def _tts_system_fallback_enabled(request: dict[str, Any] | None = None) -> bool:
    request_obj = request if isinstance(request, dict) else {}
    request_value = request_obj.get("allow_tts_system_fallback")
    if request_value is None:
        request_value = request_obj.get("allowTTSSystemFallback")
    env_value = os.environ.get(TTS_SYSTEM_FALLBACK_ENV)
    if _safe_str(env_value):
        return _env_flag_enabled(TTS_SYSTEM_FALLBACK_ENV)
    if request_value is not None:
        return _safe_bool(request_value, fallback=False)
    return sys.platform == "darwin"


def _tts_say_binary_path() -> str:
    requested = _safe_str(os.environ.get(TTS_SAY_BINARY_ENV))
    candidates = [requested] if requested else []
    if not requested:
        candidates.append("say")
    for candidate in candidates:
        normalized = candidate
        if os.path.sep in candidate or candidate.startswith("."):
            normalized = os.path.abspath(os.path.expanduser(candidate))
        else:
            resolved = shutil.which(candidate)
            normalized = os.path.abspath(os.path.expanduser(resolved)) if resolved else ""
        if normalized and os.path.isfile(normalized) and os.access(normalized, os.X_OK):
            return normalized
    return ""


def _tts_system_fallback_available(request: dict[str, Any] | None = None) -> bool:
    return _tts_system_fallback_enabled(request) and bool(_tts_say_binary_path())


def _infer_tts_native_engine_name(model_info: dict[str, Any] | None = None) -> str:
    info = model_info if isinstance(model_info, dict) else {}
    candidates = list(_string_list(info.get("engine_hints")))
    candidates.append(_safe_str(info.get("model_id")).lower())
    candidates.append(_safe_str(info.get("model_path")).lower())
    for canonical, aliases in TTS_NATIVE_ENGINE_ALIASES.items():
        for candidate in candidates:
            if not candidate:
                continue
            if candidate == canonical or any(alias in candidate for alias in aliases):
                return canonical
    return ""


def _tts_system_voice_inventory(binary_path: str) -> list[dict[str, str]]:
    normalized_binary = _safe_str(binary_path)
    if not normalized_binary:
        return []
    try:
        completed = subprocess.run(
            [normalized_binary, "-v", "?"],
            capture_output=True,
            text=True,
            check=False,
            timeout=3.0,
        )
    except Exception:
        return []
    if completed.returncode != 0:
        return []
    rows: list[dict[str, str]] = []
    for raw_line in str(completed.stdout or "").splitlines():
        line = raw_line.strip()
        if not line or "#" not in line:
            continue
        parts = re.split(r"\s{2,}", line, maxsplit=2)
        if len(parts) < 2:
            continue
        name = _safe_str(parts[0])
        locale = _safe_str(parts[1]).replace("_", "-").lower()
        if name and locale:
            rows.append({"name": name, "locale": locale})
    return rows


def _tts_system_locale_group(locale: str) -> str:
    normalized = _safe_str(locale).replace("_", "-").lower()
    if normalized.startswith("zh-tw"):
        return "zh-tw"
    if normalized.startswith("zh"):
        return "zh-cn"
    if normalized.startswith("en-gb"):
        return "en-gb"
    if normalized.startswith("en"):
        return "en-us"
    return "default"


def _tts_system_voice_candidates(locale: str, voice_color: str) -> list[str]:
    locale_group = _tts_system_locale_group(locale)
    color = _safe_str(voice_color).lower() or "neutral"
    descriptors = {
        "zh-cn": "Chinese (China mainland)",
        "zh-tw": "Chinese (Taiwan)",
        "en-gb": "English (UK)",
        "en-us": "English (US)",
        "default": "English (US)",
    }
    descriptor = descriptors.get(locale_group, descriptors["default"])
    stems_by_color = {
        "neutral": ["Eddy", "Flo"],
        "warm": ["Flo", "Eddy"],
        "clear": ["Eddy", "Flo"],
        "bright": ["Flo", "Eddy"],
        "calm": ["Grandma", "Flo", "Eddy"],
    }
    stems = stems_by_color.get(color, stems_by_color["neutral"])
    names = [f"{stem} ({descriptor})" for stem in stems]
    if locale_group == "zh-tw":
        names.extend(["Meijia", "Mei-Jia"])
    return names + stems


def _tts_system_select_voice(binary_path: str, *, locale: str, voice_color: str) -> str:
    inventory = _tts_system_voice_inventory(binary_path)
    if not inventory:
        return ""
    available_names = {row["name"] for row in inventory if _safe_str(row.get("name"))}
    preferred_locale = _tts_system_locale_group(locale)
    candidates = _tts_system_voice_candidates(locale, voice_color)
    for candidate in candidates:
        if candidate in available_names:
            return candidate
    if preferred_locale != "default":
        matching_locale = [
            row["name"]
            for row in inventory
            if _safe_str(row.get("locale")).startswith(preferred_locale)
        ]
        if matching_locale:
            return matching_locale[0]
    return inventory[0]["name"]


def _tts_system_rate_wpm(speech_rate: float) -> int:
    normalized_rate = max(0.6, min(1.8, _safe_float(speech_rate, 1.0)))
    return max(
        MIN_TTS_RATE_WPM,
        min(MAX_TTS_RATE_WPM, int(round(DEFAULT_TTS_RATE_WPM * normalized_rate))),
    )


def _tts_output_path(base_dir: str, *, model_id: str, locale: str) -> str:
    safe_base_dir = os.path.abspath(str(base_dir or "")) if str(base_dir or "").strip() else tempfile.gettempdir()
    output_dir = os.path.join(safe_base_dir, GENERATED_TTS_AUDIO_DIRNAME)
    os.makedirs(output_dir, exist_ok=True)
    digest = hashlib.sha256(
        f"{_safe_str(model_id)}\0{_safe_str(locale)}\0{time.time_ns()}".encode("utf-8")
    ).hexdigest()[:16]
    return os.path.join(output_dir, f"tts_{digest}.aiff")


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


def _looks_like_native_dependency_error_detail(detail: Any) -> bool:
    token = _safe_str(detail).lower()
    return any(marker in token for marker in NATIVE_DEPENDENCY_ERROR_TOKENS)


def _looks_like_quantization_config_error_detail(detail: Any) -> bool:
    token = _safe_str(detail).lower()
    return any(marker in token for marker in QUANTIZATION_CONFIG_ERROR_TOKENS)


def _classify_runtime_failure_reason(detail: Any, default_reason: str) -> tuple[str, str]:
    if _looks_like_native_dependency_error_detail(detail):
        return "native_dependency_error", "native_dependency_error"
    if _looks_like_quantization_config_error_detail(detail):
        return "unsupported_quantization_config", "unsupported_quantization_config"
    return _safe_str(default_reason), ""


def _request_load_profile_hash(request: dict[str, Any]) -> str:
    return _safe_str(request.get("load_profile_hash") or request.get("loadProfileHash"))


def _request_instance_key(request: dict[str, Any]) -> str:
    return _safe_str(request.get("instance_key") or request.get("instanceKey"))


def _request_base_dir(request: dict[str, Any]) -> str:
    return _safe_str(request.get("_base_dir") or request.get("base_dir") or request.get("baseDir"))


def _request_xhub_local_service_internal(request: dict[str, Any]) -> bool:
    return _safe_bool(
        request.get("_xhub_local_service_internal")
        if request.get("_xhub_local_service_internal") is not None
        else request.get("xhubLocalServiceInternal"),
        False,
    )


def _request_effective_context_length(request: dict[str, Any]) -> int:
    return max(0, _safe_int(request.get("effective_context_length") or request.get("effectiveContextLength"), 0))


def _request_max_context_length(request: dict[str, Any]) -> int:
    return max(0, _safe_int(request.get("max_context_length") or request.get("maxContextLength"), 0))


def _request_effective_load_profile(request: dict[str, Any]) -> dict[str, Any]:
    raw = (
        request.get("effective_load_profile")
        if isinstance(request.get("effective_load_profile"), dict)
        else request.get("effectiveLoadProfile")
    )
    return dict(raw) if isinstance(raw, dict) else {}


def _request_gpu_offload_ratio(request: dict[str, Any]) -> float | None:
    profile = _request_effective_load_profile(request)
    raw_value = (
        profile.get("gpu_offload_ratio")
        if profile.get("gpu_offload_ratio") is not None
        else profile.get("gpuOffloadRatio")
        if profile.get("gpuOffloadRatio") is not None
        else request.get("gpu_offload_ratio")
        if request.get("gpu_offload_ratio") is not None
        else request.get("gpuOffloadRatio")
    )
    if raw_value is None:
        return None
    value = _safe_float(raw_value, -1.0)
    if value < 0:
        return None
    return min(1.0, max(0.0, value))


def _request_load_parallel(request: dict[str, Any]) -> int:
    profile = _request_effective_load_profile(request)
    raw_value = (
        profile.get("parallel")
        if profile.get("parallel") is not None
        else request.get("parallel")
    )
    return max(0, _safe_int(raw_value, 0))


def _request_load_ttl(request: dict[str, Any]) -> int:
    profile = _request_effective_load_profile(request)
    raw_value = (
        profile.get("ttl")
        if profile.get("ttl") is not None
        else profile.get("ttl_sec")
        if profile.get("ttl_sec") is not None
        else profile.get("ttlSec")
        if profile.get("ttlSec") is not None
        else request.get("ttl")
        if request.get("ttl") is not None
        else request.get("ttl_sec")
        if request.get("ttl_sec") is not None
        else request.get("ttlSec")
    )
    return max(0, _safe_int(raw_value, 0))


def _request_load_identifier(request: dict[str, Any]) -> str:
    profile = _request_effective_load_profile(request)
    return _safe_str(
        profile.get("identifier")
        if profile.get("identifier") is not None
        else request.get("identifier")
        if request.get("identifier") is not None
        else request.get("deviceIdentifier")
    )


def _request_max_image_dimension(request: dict[str, Any]) -> int:
    profile = _request_effective_load_profile(request)
    vision = profile.get("vision") if isinstance(profile.get("vision"), dict) else {}
    raw_value = (
        request.get("max_image_dimension")
        if request.get("max_image_dimension") is not None
        else request.get("maxImageDimension")
        if request.get("maxImageDimension") is not None
        else vision.get("image_max_dimension")
        if vision.get("image_max_dimension") is not None
        else vision.get("imageMaxDimension")
        if vision.get("imageMaxDimension") is not None
        else profile.get("vision_image_max_dimension")
        if profile.get("vision_image_max_dimension") is not None
        else profile.get("visionImageMaxDimension")
    )
    return max(32, min(16_384, _safe_int(raw_value, MAX_IMAGE_DIMENSION)))


def _parse_instance_key(instance_key: str) -> tuple[str, str, str]:
    token = _safe_str(instance_key)
    if not token:
        return "", "", ""
    parts = token.split(":", 2)
    if len(parts) < 3:
        return "", "", ""
    return _safe_str(parts[0]).lower(), _safe_str(parts[1]), _safe_str(parts[2])


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


def _process_peak_memory_bytes() -> int:
    try:
        peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    except Exception:
        return 0
    return max(0, int(peak)) * 1024


def _safe_slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "_", _safe_str(value).lower())
    normalized = normalized.strip("_")
    return normalized or "fixture"


def _write_generated_silence_wav(path: str, *, duration_sec: float, sample_rate: int) -> None:
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    frame_count = max(1, int(round(max(0.05, duration_sec) * max(8000, sample_rate))))
    silence = (b"\x00\x00") * frame_count
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(max(8000, sample_rate))
        handle.writeframes(silence)


def _write_generated_png_header(path: str, *, width: int, height: int) -> None:
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    safe_width = max(1, int(width or 1))
    safe_height = max(1, int(height or 1))

    def _chunk(chunk_type: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(chunk_type)
        crc = zlib.crc32(data, crc) & 0xFFFFFFFF
        return (
            len(data).to_bytes(4, "big", signed=False)
            + chunk_type
            + data
            + crc.to_bytes(4, "big", signed=False)
        )

    row = b"\x00" + (b"\xf2\xe7\xcf" * safe_width)
    raw = row * safe_height
    payload = bytearray(PNG_SIGNATURE)
    payload.extend(
        _chunk(
            b"IHDR",
            safe_width.to_bytes(4, "big", signed=False)
            + safe_height.to_bytes(4, "big", signed=False)
            + b"\x08\x02\x00\x00\x00",
        )
    )
    payload.extend(_chunk(b"IDAT", zlib.compress(raw, level=9)))
    payload.extend(_chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(bytes(payload))


class TransformersProvider(LocalProvider):
    def __init__(self, *, resident_runtime_mode: bool = False) -> None:
        self._text_model_cache: dict[str, dict[str, Any]] = {}
        self._embedding_model_cache: dict[str, dict[str, Any]] = {}
        self._asr_pipeline_cache: dict[str, dict[str, Any]] = {}
        self._image_model_cache: dict[str, dict[str, Any]] = {}
        self._tracked_base_dirs: set[str] = set()
        self._exit_hook_registered = False
        self._resident_runtime_mode = bool(resident_runtime_mode)

    def provider_id(self) -> str:
        return "transformers"

    def supported_task_kinds(self) -> list[str]:
        return [
            TEXT_TASK_KIND,
            EMBED_TASK_KIND,
            ASR_TASK_KIND,
            TTS_TASK_KIND,
            VISION_TASK_KIND,
            OCR_TASK_KIND,
        ]

    def supported_input_modalities(self) -> list[str]:
        return ["text", "audio", "image"]

    def supported_output_modalities(self) -> list[str]:
        return ["embedding", "text", "segments", "spans", "audio"]

    def lifecycle_mode(self) -> str:
        return "warmable"

    def supported_lifecycle_actions(self) -> list[str]:
        return [
            "warmup_local_model",
            "unload_local_model",
            "evict_local_instance",
        ]

    def warmup_task_kinds(self) -> list[str]:
        return [TEXT_TASK_KIND, EMBED_TASK_KIND, ASR_TASK_KIND, VISION_TASK_KIND, OCR_TASK_KIND]

    def residency_scope(self) -> str:
        return "runtime_process" if self._resident_runtime_mode else "process_local"

    def set_resident_runtime_mode(self, enabled: bool) -> None:
        self._resident_runtime_mode = bool(enabled)

    def _runtime_resolution(self, *, base_dir: str, request: dict[str, Any] | None = None) -> Any:
        return resolve_provider_runtime(
            self.provider_id(),
            base_dir=base_dir,
            optional_python_modules=["pil", "tokenizers"],
            service_hosted_runtime=_request_xhub_local_service_internal(request or {}),
            auto_start_runtime_services=bool(request),
        )

    def _uses_helper_bridge(self, runtime_resolution: Any) -> bool:
        return _safe_str(getattr(runtime_resolution, "runtime_source", "")) == "helper_binary_bridge"

    def _helper_bridge_ready(self, runtime_resolution: Any) -> bool:
        return self._uses_helper_bridge(runtime_resolution) and _safe_str(
            getattr(runtime_resolution, "runtime_reason_code", "")
        ) == "helper_bridge_ready"

    def _helper_bridge_binary_path(self, runtime_resolution: Any) -> str:
        return _safe_str(getattr(runtime_resolution, "runtime_source_path", ""))

    def _helper_bridge_residency_scope(self) -> str:
        return "runtime_process"

    def _helper_bridge_device_backend(self) -> str:
        return "helper_binary_bridge"

    def _helper_bridge_executable_task_kinds(self) -> list[str]:
        return [TEXT_TASK_KIND, EMBED_TASK_KIND, VISION_TASK_KIND, OCR_TASK_KIND]

    def _helper_bridge_supports_task_kind(self, task_kind: str) -> bool:
        return _safe_str(task_kind).lower() in set(self._helper_bridge_executable_task_kinds())

    def _helper_bridge_task_kinds_for_row(
        self,
        row: dict[str, Any],
        *,
        fallback_task_kinds: list[str] | None = None,
    ) -> list[str]:
        normalized_fallback = _string_list(fallback_task_kinds)
        if normalized_fallback:
            return normalized_fallback
        type_token = _safe_str(row.get("type")).lower()
        if type_token == "embedding":
            return [EMBED_TASK_KIND]
        if type_token == "transcription":
            return [ASR_TASK_KIND]
        if type_token == "llm" and _safe_bool(row.get("vision"), False):
            return [VISION_TASK_KIND, OCR_TASK_KIND]
        if type_token == "llm":
            return [TEXT_TASK_KIND]
        return []

    def _helper_bridge_idle_eviction_state(self) -> dict[str, Any]:
        state = self._default_idle_eviction_state(owner_pid=0)
        state["policy"] = "manual_or_external_runtime"
        state["processScoped"] = False
        state["ownerPid"] = 0
        return state

    def _helper_bridge_loaded_instance_rows(
        self,
        *,
        runtime_resolution: Any,
        registered_model_rows: list[dict[str, Any]],
        recorded_instances_by_key: dict[str, dict[str, Any]] | None = None,
    ) -> list[dict[str, Any]]:
        if not self._helper_bridge_ready(runtime_resolution):
            return []
        helper_binary = self._helper_bridge_binary_path(runtime_resolution)
        if not helper_binary:
            return []
        catalog_by_model_id = {
            _safe_str(model.get("id")): model
            for model in registered_model_rows
            if _safe_str(model.get("id"))
        }
        rows: list[dict[str, Any]] = []
        recorded_by_key = recorded_instances_by_key or {}
        for raw in list_helper_bridge_loaded_models(helper_binary):
            if not isinstance(raw, dict):
                continue
            identifier = _safe_str(raw.get("identifier"))
            provider_token, model_id, load_profile_hash = _parse_instance_key(identifier)
            if provider_token != self.provider_id() or not model_id:
                continue
            model_row = catalog_by_model_id.get(model_id) or {}
            recorded_row = recorded_by_key.get(identifier) or {}
            context_length = max(
                0,
                _safe_int(raw.get("contextLength") or raw.get("context_length"), 0),
            )
            rows.append(
                {
                    "instanceKey": identifier,
                    "modelId": model_id,
                    "taskKinds": self._helper_bridge_task_kinds_for_row(
                        raw,
                        fallback_task_kinds=_normalize_task_kinds(
                            model_row.get("taskKinds")
                            or model_row.get("task_kinds")
                            or recorded_row.get("taskKinds")
                            or recorded_row.get("task_kinds")
                        ),
                    ),
                    "loadProfileHash": load_profile_hash,
                    "effectiveContextLength": context_length,
                    "maxContextLength": max(
                        0,
                        _safe_int(
                            model_row.get("maxContextLength")
                            or model_row.get("max_context_length")
                            or recorded_row.get("maxContextLength")
                            or recorded_row.get("max_context_length"),
                            0,
                        ),
                    ),
                    "effectiveLoadProfile": dict(
                        recorded_row.get("effectiveLoadProfile")
                        if isinstance(recorded_row.get("effectiveLoadProfile"), dict)
                        else recorded_row.get("effective_load_profile")
                        if isinstance(recorded_row.get("effective_load_profile"), dict)
                        else {}
                    ),
                    "loadedAt": _safe_float(recorded_row.get("loadedAt") or recorded_row.get("loaded_at"), 0.0),
                    "lastUsedAt": max(
                        _safe_float(recorded_row.get("lastUsedAt") or recorded_row.get("last_used_at"), 0.0),
                        0.0,
                        _safe_float(raw.get("lastUsedTime") or raw.get("last_used_time"), 0.0) / 1000.0,
                    ),
                    "residency": "resident",
                    "residencyScope": self._helper_bridge_residency_scope(),
                    "deviceBackend": self._helper_bridge_device_backend(),
                }
            )
        return self._normalize_loaded_instance_rows(rows)

    def _helper_bridge_candidate_loaded_rows(
        self,
        *,
        runtime_resolution: Any,
        model_info: dict[str, Any],
    ) -> list[dict[str, Any]]:
        if not self._helper_bridge_ready(runtime_resolution):
            return []
        model_id = _safe_str(model_info.get("model_id"))
        pseudo_catalog_rows = []
        if model_id:
            pseudo_catalog_rows.append(
                {
                    "id": model_id,
                    "taskKinds": _string_list(model_info.get("task_kinds")),
                }
            )
        rows = self._helper_bridge_loaded_instance_rows(
            runtime_resolution=runtime_resolution,
            registered_model_rows=pseudo_catalog_rows,
        )
        if not model_id:
            return rows
        return [row for row in rows if _safe_str(row.get("modelId")) == model_id]

    def _helper_bridge_resolve_instance_row(
        self,
        *,
        request: dict[str, Any],
        model_info: dict[str, Any],
        runtime_resolution: Any,
        task_kind: str,
    ) -> dict[str, Any]:
        wanted_instance_key = _request_instance_key(request)
        rows = self._helper_bridge_candidate_loaded_rows(
            runtime_resolution=runtime_resolution,
            model_info=model_info,
        )
        if wanted_instance_key:
            exact = next(
                (
                    dict(row)
                    for row in rows
                    if _safe_str(row.get("instanceKey")) == wanted_instance_key
                ),
                {},
            )
            if exact:
                return exact
        wanted_task_kind = _safe_str(task_kind).lower()
        task_filtered = [
            dict(row)
            for row in rows
            if not wanted_task_kind or wanted_task_kind in _string_list(row.get("taskKinds"))
        ]
        if not task_filtered:
            return {}
        task_filtered.sort(
            key=lambda row: (
                _safe_float(row.get("lastUsedAt"), 0.0),
                _safe_int(row.get("effectiveContextLength"), 0),
            ),
            reverse=True,
        )
        return task_filtered[0]

    def _inferred_model_task_kinds(
        self,
        *,
        request: dict[str, Any],
        model_info: dict[str, Any],
        runtime_resolution: Any | None = None,
    ) -> list[str]:
        declared = _string_list(model_info.get("task_kinds"))
        if declared:
            return declared
        resolution = runtime_resolution
        if resolution is None:
            resolution = self._runtime_resolution(
                base_dir=_request_base_dir(request) or "",
                request=request,
            )
        inferred: list[str] = []
        for row in self._helper_bridge_candidate_loaded_rows(
            runtime_resolution=resolution,
            model_info=model_info,
        ):
            inferred.extend(_string_list(row.get("taskKinds")))
        return _string_list(inferred)

    def _core_runtime_ready(self, runtime_resolution: Any) -> bool:
        return bool(runtime_resolution.supports_modules("transformers", "torch"))

    def _image_runtime_ready(self, runtime_resolution: Any) -> bool:
        return self._core_runtime_ready(runtime_resolution) and bool(runtime_resolution.supports_modules("pil"))

    def _task_runtime_import_error(self, runtime_resolution: Any, *, task_kinds: list[str] | None = None) -> str:
        wanted = set(_string_list(task_kinds))
        if (
            wanted & {VISION_TASK_KIND, OCR_TASK_KIND}
            and self._core_runtime_ready(runtime_resolution)
            and not runtime_resolution.supports_modules("pil")
        ):
            return "missing_module:pil"
        return _safe_str(runtime_resolution.import_error)

    def _task_runtime_reason_code(self, runtime_resolution: Any, *, task_kinds: list[str] | None = None) -> str:
        wanted = set(_string_list(task_kinds))
        if (
            wanted & {VISION_TASK_KIND, OCR_TASK_KIND}
            and self._core_runtime_ready(runtime_resolution)
            and not runtime_resolution.supports_modules("pil")
        ):
            return "missing_runtime"
        return _safe_str(runtime_resolution.runtime_reason_code) or "ready"

    def _task_runtime_hint(self, runtime_resolution: Any, *, task_kinds: list[str] | None = None) -> str:
        wanted = set(_string_list(task_kinds))
        if (
            wanted & {VISION_TASK_KIND, OCR_TASK_KIND}
            and self._core_runtime_ready(runtime_resolution)
            and not runtime_resolution.supports_modules("pil")
        ):
            return (
                _safe_str(runtime_resolution.runtime_hint)
                or "Current transformers runtime is missing Pillow, which is required for vision and OCR tasks."
            )
        return _safe_str(runtime_resolution.runtime_hint)

    def _runtime_failure_output(
        self,
        *,
        request: dict[str, Any],
        runtime_resolution: Any,
        error: str,
        task_kind: str = "",
        task_kinds: list[str] | None = None,
        model_id: str = "",
        model_path: str = "",
        action: str = "",
        error_detail: str = "",
        usage: dict[str, Any] | None = None,
        reason_code_override: str = "",
        runtime_reason_code_override: str = "",
    ) -> dict[str, Any]:
        normalized_task_kinds = _string_list(task_kinds) or ([task_kind] if _safe_str(task_kind) else [])
        reason_code = _safe_str(reason_code_override) or self._task_runtime_reason_code(
            runtime_resolution,
            task_kinds=normalized_task_kinds,
        )
        runtime_reason_code = (
            _safe_str(runtime_reason_code_override)
            or _safe_str(runtime_resolution.runtime_reason_code)
            or reason_code
        )
        if reason_code == "missing_runtime" and runtime_reason_code == "ready":
            runtime_reason_code = "missing_runtime"
        out = {
            "ok": False,
            "provider": self.provider_id(),
            "error": _safe_str(error),
            "reasonCode": reason_code,
            "runtimeReasonCode": runtime_reason_code,
            "runtimeSource": _safe_str(runtime_resolution.runtime_source),
            "runtimeSourcePath": _safe_str(runtime_resolution.runtime_source_path),
            "runtimeResolutionState": _safe_str(runtime_resolution.runtime_resolution_state),
            "fallbackUsed": bool(runtime_resolution.fallback_used),
            "runtimeHint": self._task_runtime_hint(runtime_resolution, task_kinds=normalized_task_kinds),
            "runtimeMissingRequirements": _string_list(runtime_resolution.missing_requirements),
            "runtimeMissingOptionalRequirements": _string_list(runtime_resolution.missing_optional_requirements),
            "request": dict(request or {}),
        }
        if task_kind:
            out["taskKind"] = task_kind
        elif len(normalized_task_kinds) == 1:
            out["taskKind"] = normalized_task_kinds[0]
        if normalized_task_kinds:
            out["taskKinds"] = normalized_task_kinds
        if model_id:
            out["modelId"] = model_id
        if model_path:
            out["modelPath"] = model_path
        if action:
            out["action"] = action
        if usage is not None:
            out["usage"] = dict(usage)
        if error_detail:
            out["errorDetail"] = _safe_str(error_detail)[:240]
        return out

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
                    "maxContextLength": max(0, _safe_int(entry.get("maxContextLength") or entry.get("max_context_length"), 0)),
                    "effectiveLoadProfile": dict(
                        entry.get("effectiveLoadProfile")
                        if isinstance(entry.get("effectiveLoadProfile"), dict)
                        else entry.get("effective_load_profile")
                        if isinstance(entry.get("effective_load_profile"), dict)
                        else {}
                    ),
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

    def _helper_bridge_tracking_idle_eviction(self, state: dict[str, Any] | None = None) -> dict[str, Any]:
        source = state if isinstance(state, dict) else {}
        idle_eviction = self._normalize_idle_eviction_state(source.get("idleEviction"))
        idle_eviction["policy"] = "manual_or_external_runtime"
        idle_eviction["processScoped"] = False
        idle_eviction["ownerPid"] = 0
        idle_eviction["updatedAt"] = time.time()
        return idle_eviction

    def _record_helper_bridge_loaded_instance(self, *, base_dir: str, row: dict[str, Any]) -> None:
        normalized_base_dir = self._ensure_process_local_tracking(base_dir=base_dir)
        if not normalized_base_dir:
            return
        state = self._reconcile_process_local_state(base_dir=normalized_base_dir)
        instance_key = _safe_str(row.get("instanceKey") or row.get("instance_key"))
        if not instance_key:
            return
        loaded_instances = [
            dict(entry)
            for entry in self._normalize_loaded_instance_rows(state.get("loadedInstances"))
            if _safe_str(entry.get("instanceKey")) != instance_key
        ]
        loaded_instances.append(dict(row))
        self._write_process_local_state(
            base_dir=normalized_base_dir,
            loaded_instances=loaded_instances,
            idle_eviction=self._helper_bridge_tracking_idle_eviction(state),
            owner_pid=0,
        )

    def _remove_helper_bridge_tracked_instances(
        self,
        *,
        base_dir: str,
        instance_keys: list[str] | None = None,
        model_id: str = "",
        eviction_reason: str = "",
    ) -> list[dict[str, Any]]:
        normalized_base_dir = self._ensure_process_local_tracking(base_dir=base_dir)
        if not normalized_base_dir:
            return []
        state = self._reconcile_process_local_state(base_dir=normalized_base_dir)
        wanted_instance_keys = {
            _safe_str(value)
            for value in (instance_keys or [])
            if _safe_str(value)
        }
        wanted_model_id = _safe_str(model_id)
        current_rows = self._normalize_loaded_instance_rows(state.get("loadedInstances"))
        kept_rows: list[dict[str, Any]] = []
        removed_rows: list[dict[str, Any]] = []
        for row in current_rows:
            row_instance_key = _safe_str(row.get("instanceKey"))
            row_model_id = _safe_str(row.get("modelId"))
            matches_instance = bool(wanted_instance_keys) and row_instance_key in wanted_instance_keys
            matches_model = bool(wanted_model_id) and row_model_id == wanted_model_id
            if matches_instance or matches_model:
                removed_rows.append(dict(row))
            else:
                kept_rows.append(dict(row))

        if removed_rows or os.path.exists(_process_local_state_path(normalized_base_dir)):
            idle_eviction = self._helper_bridge_tracking_idle_eviction(state)
            if eviction_reason and removed_rows:
                removed_instance_keys = [
                    _safe_str(row.get("instanceKey"))
                    for row in removed_rows
                    if _safe_str(row.get("instanceKey"))
                ]
                removed_model_ids = sorted(
                    {_safe_str(row.get("modelId")) for row in removed_rows if _safe_str(row.get("modelId"))}
                )
                idle_eviction["lastEvictionReason"] = eviction_reason
                idle_eviction["lastEvictionAt"] = time.time()
                idle_eviction["lastEvictedInstanceKeys"] = removed_instance_keys
                idle_eviction["lastEvictedModelIds"] = removed_model_ids
                idle_eviction["lastEvictedCount"] = len(removed_instance_keys)
                idle_eviction["totalEvictedInstanceCount"] = max(
                    0,
                    _safe_int(idle_eviction.get("totalEvictedInstanceCount"), 0) + len(removed_instance_keys),
                )
            self._write_process_local_state(
                base_dir=normalized_base_dir,
                loaded_instances=kept_rows,
                idle_eviction=idle_eviction,
                owner_pid=0,
            )
        return removed_rows

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
            self._text_model_cache.clear()
            self._embedding_model_cache.clear()
            self._asr_pipeline_cache.clear()
            self._image_model_cache.clear()
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
        for entry in (
            list(self._text_model_cache.values())
            + list(self._embedding_model_cache.values())
            + list(self._asr_pipeline_cache.values())
            + list(self._image_model_cache.values())
        ):
            if not isinstance(entry, dict):
                continue
            row = {
                "instanceKey": _safe_str(entry.get("instance_key")),
                "modelId": _safe_str(entry.get("model_id")),
                "taskKinds": _string_list(entry.get("task_kinds")),
                "loadProfileHash": _safe_str(entry.get("load_profile_hash")),
                "effectiveContextLength": max(0, _safe_int(entry.get("effective_context_length"), 0)),
                "maxContextLength": max(0, _safe_int(entry.get("max_context_length"), 0)),
                "effectiveLoadProfile": dict(entry.get("effective_load_profile"))
                if isinstance(entry.get("effective_load_profile"), dict)
                else {},
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
        task_kinds = [TEXT_TASK_KIND, EMBED_TASK_KIND, ASR_TASK_KIND]
        if _tts_system_fallback_available() or kokoro_runtime_available():
            task_kinds.append(TTS_TASK_KIND)
        if _vision_fallback_enabled():
            task_kinds.extend([VISION_TASK_KIND, OCR_TASK_KIND])
        return task_kinds

    def _tts_native_runtime_available(self, *, model_info: dict[str, Any], runtime_resolution: Any) -> bool:
        engine_name = _infer_tts_native_engine_name(model_info)
        if engine_name == "kokoro":
            return self._core_runtime_ready(runtime_resolution) and kokoro_runtime_available()
        return False

    def _warmup_eligible_task_kinds(self, *, model_info: dict[str, Any]) -> list[str]:
        model_path = _safe_str(model_info.get("model_path"))
        if not model_path:
            return []
        task_kinds = _string_list(model_info.get("task_kinds"))
        if not task_kinds:
            return []
        runtime_resolution = model_info.get("runtime_resolution")
        if runtime_resolution is None:
            has_transformers, has_torch = _has_transformers_runtime()
            core_ready = has_transformers and has_torch
            image_ready = core_ready
        else:
            if self._helper_bridge_ready(runtime_resolution):
                return [
                    task_kind for task_kind in task_kinds
                    if task_kind in self.warmup_task_kinds()
                ]
            core_ready = self._core_runtime_ready(runtime_resolution)
            image_ready = self._image_runtime_ready(runtime_resolution)
        if not core_ready:
            return []
        out: list[str] = []
        for task_kind in task_kinds:
            if task_kind not in self.warmup_task_kinds():
                continue
            if task_kind in {VISION_TASK_KIND, OCR_TASK_KIND} and not image_ready:
                continue
            out.append(task_kind)
        return out

    def _touch_cache_entry(
        self,
        entry: dict[str, Any],
        *,
        task_kinds: list[str],
        effective_context_length: int = 0,
        max_context_length: int = 0,
        effective_load_profile: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        now = time.time()
        if not isinstance(entry, dict):
            return {}
        normalized_task_kinds = _string_list(task_kinds)
        existing_task_kinds = _string_list(entry.get("task_kinds"))
        entry.setdefault("loaded_at", now)
        entry["last_used_at"] = now
        if normalized_task_kinds:
            merged_task_kinds: list[str] = []
            seen_task_kinds: set[str] = set()
            for task_kind in existing_task_kinds + normalized_task_kinds:
                if task_kind in seen_task_kinds:
                    continue
                seen_task_kinds.add(task_kind)
                merged_task_kinds.append(task_kind)
            entry["task_kinds"] = merged_task_kinds
        if effective_context_length > 0:
            entry["effective_context_length"] = max(0, int(effective_context_length))
        if max_context_length > 0:
            entry["max_context_length"] = max(0, int(max_context_length))
        if isinstance(effective_load_profile, dict) and effective_load_profile:
            entry["effective_load_profile"] = dict(effective_load_profile)
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
            (TEXT_TASK_KIND, self._text_model_cache),
            (EMBED_TASK_KIND, self._embedding_model_cache),
            (ASR_TASK_KIND, self._asr_pipeline_cache),
            ("image", self._image_model_cache),
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
        runtime_resolution = self._runtime_resolution(base_dir=base_dir)
        helper_bridge_ready = self._helper_bridge_ready(runtime_resolution)
        has_pil = runtime_resolution.supports_modules("pil")
        tts_system_fallback_available = _tts_system_fallback_available()
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
            ASR_TASK_KIND: [
                _safe_str(model.get("id"))
                for model in registered_model_rows
                if ASR_TASK_KIND in _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds"))
            ],
            TTS_TASK_KIND: [
                _safe_str(model.get("id"))
                for model in registered_model_rows
                if TTS_TASK_KIND in _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds"))
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
        if helper_bridge_ready:
            for row in helper_loaded_instances:
                model_id = _safe_str(row.get("modelId"))
                if not model_id:
                    continue
                for task_kind in _string_list(row.get("taskKinds")):
                    if (
                        self._helper_bridge_supports_task_kind(task_kind)
                        and model_id not in task_model_ids.get(task_kind, [])
                    ):
                        task_model_ids.setdefault(task_kind, []).append(model_id)

        available_task_kinds: list[str] = []
        real_task_kinds: list[str] = []
        fallback_task_kinds: list[str] = []
        import_error = ""
        needs_transformers_runtime = any(
            bool(task_model_ids[task_kind])
            for task_kind in [TEXT_TASK_KIND, EMBED_TASK_KIND, ASR_TASK_KIND, VISION_TASK_KIND, OCR_TASK_KIND]
        ) or (bool(task_model_ids[TTS_TASK_KIND]) and not tts_system_fallback_available)
        if (
            needs_transformers_runtime
            and not helper_bridge_ready
            and not self._core_runtime_ready(runtime_resolution)
        ):
            import_error = self._task_runtime_import_error(
                runtime_resolution,
                task_kinds=[TEXT_TASK_KIND, EMBED_TASK_KIND, ASR_TASK_KIND, TTS_TASK_KIND],
            )
        if task_model_ids[TEXT_TASK_KIND]:
            if helper_bridge_ready or self._core_runtime_ready(runtime_resolution):
                real_task_kinds.append(TEXT_TASK_KIND)
                available_task_kinds.append(TEXT_TASK_KIND)
        if task_model_ids[EMBED_TASK_KIND]:
            if helper_bridge_ready:
                real_task_kinds.append(EMBED_TASK_KIND)
                available_task_kinds.append(EMBED_TASK_KIND)
            elif self._core_runtime_ready(runtime_resolution):
                real_task_kinds.append(EMBED_TASK_KIND)
                available_task_kinds.append(EMBED_TASK_KIND)
            elif _hash_fallback_enabled():
                fallback_task_kinds.append(EMBED_TASK_KIND)
                available_task_kinds.append(EMBED_TASK_KIND)
        if task_model_ids[ASR_TASK_KIND]:
            if self._core_runtime_ready(runtime_resolution):
                real_task_kinds.append(ASR_TASK_KIND)
                available_task_kinds.append(ASR_TASK_KIND)
            elif _asr_fallback_enabled():
                fallback_task_kinds.append(ASR_TASK_KIND)
                available_task_kinds.append(ASR_TASK_KIND)
        if task_model_ids[TTS_TASK_KIND]:
            tts_native_ready = any(
                self._tts_native_runtime_available(
                    model_info=self._resolve_model_info({"_resolved_model": model}),
                    runtime_resolution=runtime_resolution,
                )
                for model in registered_model_rows
                if TTS_TASK_KIND in _normalize_task_kinds(model.get("taskKinds") or model.get("task_kinds"))
            )
            if tts_native_ready:
                real_task_kinds.append(TTS_TASK_KIND)
                available_task_kinds.append(TTS_TASK_KIND)
            elif tts_system_fallback_available:
                fallback_task_kinds.append(TTS_TASK_KIND)
                available_task_kinds.append(TTS_TASK_KIND)
        if task_model_ids[VISION_TASK_KIND]:
            if helper_bridge_ready:
                real_task_kinds.append(VISION_TASK_KIND)
                available_task_kinds.append(VISION_TASK_KIND)
            elif self._image_runtime_ready(runtime_resolution):
                real_task_kinds.append(VISION_TASK_KIND)
                available_task_kinds.append(VISION_TASK_KIND)
            elif _vision_fallback_enabled():
                fallback_task_kinds.append(VISION_TASK_KIND)
                available_task_kinds.append(VISION_TASK_KIND)
            elif not has_pil and not import_error:
                import_error = self._task_runtime_import_error(
                    runtime_resolution,
                    task_kinds=[VISION_TASK_KIND],
                )
        if task_model_ids[OCR_TASK_KIND]:
            if helper_bridge_ready:
                real_task_kinds.append(OCR_TASK_KIND)
                available_task_kinds.append(OCR_TASK_KIND)
            elif self._image_runtime_ready(runtime_resolution):
                real_task_kinds.append(OCR_TASK_KIND)
                available_task_kinds.append(OCR_TASK_KIND)
            elif _vision_fallback_enabled():
                fallback_task_kinds.append(OCR_TASK_KIND)
                available_task_kinds.append(OCR_TASK_KIND)
            elif not has_pil and not import_error:
                import_error = self._task_runtime_import_error(
                    runtime_resolution,
                    task_kinds=[OCR_TASK_KIND],
                )

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
                reason_code = self._task_runtime_reason_code(
                    runtime_resolution,
                    task_kinds=unavailable_task_kinds or list(task_model_ids.keys()),
                )
            elif not any(task_model_ids.values()):
                reason_code = "no_supported_models"
            elif unavailable_task_kinds and all(task_kind in {VISION_TASK_KIND, OCR_TASK_KIND} for task_kind in unavailable_task_kinds):
                reason_code = "preview_disabled"
            elif task_model_ids[ASR_TASK_KIND] and not task_model_ids[EMBED_TASK_KIND]:
                reason_code = "asr_unavailable"
            elif task_model_ids[EMBED_TASK_KIND] and not task_model_ids[ASR_TASK_KIND]:
                reason_code = "embedding_unavailable"
            elif task_model_ids[TEXT_TASK_KIND] and not any(
                task_model_ids[token]
                for token in [EMBED_TASK_KIND, ASR_TASK_KIND, TTS_TASK_KIND, VISION_TASK_KIND, OCR_TASK_KIND]
            ):
                reason_code = "text_generation_unavailable"
            elif task_model_ids[TTS_TASK_KIND] and not any(
                task_model_ids[token]
                for token in [TEXT_TASK_KIND, EMBED_TASK_KIND, ASR_TASK_KIND, VISION_TASK_KIND, OCR_TASK_KIND]
            ):
                reason_code = "text_to_speech_unavailable"
            elif task_model_ids[VISION_TASK_KIND] and not task_model_ids[OCR_TASK_KIND]:
                reason_code = "vision_unavailable"
            elif task_model_ids[OCR_TASK_KIND] and not task_model_ids[VISION_TASK_KIND]:
                reason_code = "ocr_unavailable"
            else:
                reason_code = "provider_unavailable"
        else:
            ok = False
            reason_code = "no_registered_models"

        current_loaded_instances = helper_loaded_instances if helper_bridge_ready else self.loaded_instances()
        if current_loaded_instances and not helper_bridge_ready:
            self._sync_process_local_state(base_dir=base_dir)
            process_local_state = self._reconcile_process_local_state(base_dir=base_dir)
        loaded_instances = (
            helper_loaded_instances
            if helper_bridge_ready
            else self._normalize_loaded_instance_rows(
                current_loaded_instances or process_local_state.get("loadedInstances")
            )
        )
        loaded_models = sorted(
            {
                _safe_str(row.get("modelId"))
                for row in loaded_instances
                if _safe_str(row.get("modelId"))
            }
        )
        idle_eviction = (
            self._helper_bridge_idle_eviction_state()
            if helper_bridge_ready
            else self._normalize_idle_eviction_state(process_local_state.get("idleEviction"))
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
        if helper_bridge_ready and warmup_task_kinds:
            ok = True
            reason_code = "helper_bridge_loaded" if loaded_instances else "helper_bridge_ready"
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
        device_backend = self._helper_bridge_device_backend() if helper_bridge_ready else "mps_or_cpu"
        if (
            not helper_bridge_ready
            and TTS_TASK_KIND in fallback_task_kinds
            and not real_task_kinds
            and set(available_task_kinds).issubset({TTS_TASK_KIND})
        ):
            device_backend = "system_voice_compatibility"

        return ProviderHealth(
            provider=self.provider_id(),
            ok=ok,
            reason_code=reason_code,
            runtime_version=TRANSFORMERS_PROVIDER_RUNTIME_VERSION,
            available_task_kinds=available_task_kinds,
            loaded_models=loaded_models,
            device_backend=device_backend,
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
            real_task_kinds=real_task_kinds,
            fallback_task_kinds=fallback_task_kinds,
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
        if task_kind == TTS_TASK_KIND:
            return self._run_tts_task(request)
        if task_kind == TEXT_TASK_KIND:
            return self._run_text_task(request)
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

    def _embedding_bench_verdict(self, *, latency_ms: int, fallback_mode: str) -> str:
        if fallback_mode:
            return "CPU fallback"
        if latency_ms <= 120:
            return "Fast"
        if latency_ms <= 450:
            return "Balanced"
        return "Heavy"

    def _text_bench_verdict(self, *, generation_tps: float, fallback_mode: str) -> str:
        if fallback_mode:
            return "Fallback"
        if generation_tps >= 30.0:
            return "Fast"
        if generation_tps >= 12.0:
            return "Balanced"
        return "Heavy"

    def _asr_bench_verdict(self, *, realtime_factor: float, fallback_mode: str) -> str:
        if fallback_mode:
            return "CPU fallback"
        if realtime_factor >= 2.5:
            return "Fast"
        if realtime_factor >= 1.0:
            return "Balanced"
        return "Heavy"

    def _tts_bench_verdict(self, *, latency_ms: int, fallback_mode: str) -> str:
        if fallback_mode:
            return "Fallback"
        if latency_ms <= 400:
            return "Fast"
        if latency_ms <= 1500:
            return "Balanced"
        return "Heavy"

    def _image_bench_verdict(self, *, fallback_mode: str, latency_ms: int) -> str:
        if fallback_mode:
            return "Preview only"
        if latency_ms <= 500:
            return "Balanced"
        return "Heavy"

    def _bench_failure_output(
        self,
        *,
        task_kind: str,
        model_id: str,
        fixture_meta: dict[str, Any],
        reason_code: str,
        error_detail: str = "",
        source_result: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        out = {
            "ok": False,
            "provider": self.provider_id(),
            "taskKind": task_kind,
            "modelId": model_id,
            "fixtureProfile": _safe_str(fixture_meta.get("fixtureProfile")),
            "fixtureTitle": _safe_str(fixture_meta.get("fixtureTitle")),
            "resultKind": "task_aware_quick_bench",
            "reasonCode": _safe_str(reason_code) or "bench_failed",
            "error": _safe_str(reason_code) or "bench_failed",
            "verdict": "",
            "fallbackMode": "",
            "notes": [_safe_str(fixture_meta.get("fixtureDescription"))] if _safe_str(fixture_meta.get("fixtureDescription")) else [],
        }
        if error_detail:
            out["errorDetail"] = _safe_str(error_detail)[:240]
        return self._copy_bench_source_fields(out, source_result=source_result)

    def _copy_bench_source_fields(
        self,
        out: dict[str, Any],
        *,
        source_result: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        source = source_result if isinstance(source_result, dict) else {}
        for field in [
            "runtimeReasonCode",
            "runtimeSource",
            "runtimeSourcePath",
            "runtimeResolutionState",
            "fallbackUsed",
            "runtimeHint",
            "runtimeMissingRequirements",
            "runtimeMissingOptionalRequirements",
            "routeTrace",
            "route_trace",
        ]:
            value = source.get(field)
            if value is not None and value != "" and value != []:
                out[field] = value
        return out

    def run_bench(self, request: dict[str, Any]) -> dict[str, Any]:
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        task_kind = self._resolve_bench_task_kind(request, model_info=model_info)
        if not model_id:
            return self._bench_failure_output(
                task_kind=task_kind or "unknown",
                model_id="",
                fixture_meta={},
                reason_code="missing_model_id",
            )
        if not task_kind:
            return self._bench_failure_output(
                task_kind="unknown",
                model_id=model_id,
                fixture_meta={},
                reason_code="unsupported_task",
            )
        if task_kind not in self.supported_task_kinds():
            return self._bench_failure_output(
                task_kind=task_kind,
                model_id=model_id,
                fixture_meta={},
                reason_code="unsupported_task",
            )

        error_code, fixture_meta, fixture_request = self._resolve_bench_fixture(
            request,
            task_kind=task_kind,
            model_info=model_info,
        )
        if error_code:
            return self._bench_failure_output(
                task_kind=task_kind,
                model_id=model_id,
                fixture_meta=fixture_meta,
                reason_code=error_code,
            )

        peak_memory_bytes = 0
        if task_kind == EMBED_TASK_KIND:
            first = self._run_embedding_task(fixture_request)
            if not bool(first.get("ok")):
                return self._bench_failure_output(
                    task_kind=task_kind,
                    model_id=model_id,
                    fixture_meta=fixture_meta,
                    reason_code=_safe_str(first.get("reasonCode") or first.get("error")) or "bench_failed",
                    error_detail=_safe_str(first.get("errorDetail")),
                    source_result=first,
                )
            second = self._run_embedding_task(fixture_request)
            if not bool(second.get("ok")):
                second = first
            fallback_mode = _safe_str(second.get("fallbackMode") or second.get("fallback_mode"))
            latency_ms = max(0, _safe_int(second.get("latencyMs") or second.get("latency_ms"), 0))
            cold_start_ms = max(latency_ms, _safe_int(first.get("latencyMs") or first.get("latency_ms"), latency_ms))
            text_count = max(1, _safe_int(second.get("vectorCount") or second.get("vector_count"), 1))
            throughput_value = round(text_count / max(0.001, latency_ms / 1000.0), 3) if latency_ms > 0 else 0.0
            peak_memory_bytes = _process_peak_memory_bytes()
            return self._copy_bench_source_fields({
                "ok": True,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "modelId": model_id,
                "fixtureProfile": _safe_str(fixture_meta.get("fixtureProfile")),
                "fixtureTitle": _safe_str(fixture_meta.get("fixtureTitle")),
                "resultKind": "task_aware_quick_bench",
                "reasonCode": "fallback_only" if fallback_mode else "ready",
                "verdict": self._embedding_bench_verdict(latency_ms=latency_ms, fallback_mode=fallback_mode),
                "fallbackMode": fallback_mode,
                "coldStartMs": cold_start_ms,
                "latencyMs": latency_ms,
                "peakMemoryBytes": peak_memory_bytes,
                "throughputValue": throughput_value,
                "throughputUnit": "items_per_sec",
                "notes": [
                    f"dims={_safe_int(second.get('dims'), 0)}",
                    f"text_count={text_count}",
                    _safe_str(fixture_meta.get("fixtureDescription")),
                ],
            }, source_result=second)

        if task_kind == TEXT_TASK_KIND:
            first = self._run_text_task(fixture_request)
            if not bool(first.get("ok")):
                return self._bench_failure_output(
                    task_kind=task_kind,
                    model_id=model_id,
                    fixture_meta=fixture_meta,
                    reason_code=_safe_str(first.get("reasonCode") or first.get("error")) or "bench_failed",
                    error_detail=_safe_str(first.get("errorDetail")),
                    source_result=first,
                )
            second = self._run_text_task(fixture_request)
            if not bool(second.get("ok")):
                second = first
            fallback_mode = _safe_str(second.get("fallbackMode") or second.get("fallback_mode"))
            latency_ms = max(0, _safe_int(second.get("latencyMs") or second.get("latency_ms"), 0))
            cold_start_ms = max(latency_ms, _safe_int(first.get("latencyMs") or first.get("latency_ms"), latency_ms))
            usage = second.get("usage") if isinstance(second.get("usage"), dict) else {}
            prompt_tokens = max(0, _safe_int(usage.get("promptTokens") or usage.get("prompt_tokens"), 0))
            generation_tokens = max(
                1,
                _safe_int(
                    usage.get("completionTokens")
                    or usage.get("completion_tokens")
                    or usage.get("generatedTokens")
                    or usage.get("generated_tokens"),
                    1,
                ),
            )
            duration_sec = max(0.001, latency_ms / 1000.0) if latency_ms > 0 else 0.001
            prompt_tps = round(prompt_tokens / duration_sec, 3) if prompt_tokens > 0 else 0.0
            generation_tps = round(generation_tokens / duration_sec, 3)
            peak_memory_bytes = _process_peak_memory_bytes()
            return self._copy_bench_source_fields({
                "ok": True,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "modelId": model_id,
                "fixtureProfile": _safe_str(fixture_meta.get("fixtureProfile")),
                "fixtureTitle": _safe_str(fixture_meta.get("fixtureTitle")),
                "resultKind": "task_aware_quick_bench",
                "reasonCode": "fallback_only" if fallback_mode else "ready",
                "verdict": self._text_bench_verdict(generation_tps=generation_tps, fallback_mode=fallback_mode),
                "fallbackMode": fallback_mode,
                "coldStartMs": cold_start_ms,
                "latencyMs": latency_ms,
                "peakMemoryBytes": peak_memory_bytes,
                "throughputValue": generation_tps,
                "throughputUnit": "tokens_per_sec",
                "promptTokens": prompt_tokens,
                "generationTokens": generation_tokens,
                "promptTPS": prompt_tps,
                "generationTPS": generation_tps,
                "notes": [
                    _safe_str(second.get("text"))[:120],
                    _safe_str(fixture_meta.get("fixtureDescription")),
                ],
            }, source_result=second)

        if task_kind == ASR_TASK_KIND:
            first = self._run_asr_task(fixture_request)
            if not bool(first.get("ok")):
                return self._bench_failure_output(
                    task_kind=task_kind,
                    model_id=model_id,
                    fixture_meta=fixture_meta,
                    reason_code=_safe_str(first.get("reasonCode") or first.get("error")) or "bench_failed",
                    error_detail=_safe_str(first.get("errorDetail")),
                    source_result=first,
                )
            second = self._run_asr_task(fixture_request)
            if not bool(second.get("ok")):
                second = first
            fallback_mode = _safe_str(second.get("fallbackMode") or second.get("fallback_mode"))
            latency_ms = max(0, _safe_int(second.get("latencyMs") or second.get("latency_ms"), 0))
            cold_start_ms = max(latency_ms, _safe_int(first.get("latencyMs") or first.get("latency_ms"), latency_ms))
            usage = second.get("usage") if isinstance(second.get("usage"), dict) else {}
            duration_sec = max(0.001, _safe_float(usage.get("inputAudioSec") or usage.get("input_audio_sec"), 0.0))
            realtime_factor = round(duration_sec / max(0.001, latency_ms / 1000.0), 3) if latency_ms > 0 else 0.0
            peak_memory_bytes = _process_peak_memory_bytes()
            return self._copy_bench_source_fields({
                "ok": True,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "modelId": model_id,
                "fixtureProfile": _safe_str(fixture_meta.get("fixtureProfile")),
                "fixtureTitle": _safe_str(fixture_meta.get("fixtureTitle")),
                "resultKind": "task_aware_quick_bench",
                "reasonCode": "fallback_only" if fallback_mode else "ready",
                "verdict": self._asr_bench_verdict(realtime_factor=realtime_factor, fallback_mode=fallback_mode),
                "fallbackMode": fallback_mode,
                "coldStartMs": cold_start_ms,
                "latencyMs": latency_ms,
                "peakMemoryBytes": peak_memory_bytes,
                "throughputValue": realtime_factor,
                "throughputUnit": "x_realtime",
                "notes": [
                    f"audio_sec={round(duration_sec, 3)}",
                    f"device={_safe_str(second.get('deviceBackend') or second.get('device_backend')) or 'cpu'}",
                    _safe_str(fixture_meta.get("fixtureDescription")),
                ],
            }, source_result=second)

        if task_kind == TTS_TASK_KIND:
            first = self._run_tts_task(fixture_request)
            if not bool(first.get("ok")):
                return self._bench_failure_output(
                    task_kind=task_kind,
                    model_id=model_id,
                    fixture_meta=fixture_meta,
                    reason_code=_safe_str(first.get("reasonCode") or first.get("error")) or "bench_failed",
                    error_detail=_safe_str(first.get("errorDetail")),
                    source_result=first,
                )
            second = self._run_tts_task(fixture_request)
            if not bool(second.get("ok")):
                second = first
            fallback_mode = _safe_str(second.get("fallbackMode") or second.get("fallback_mode"))
            latency_ms = max(0, _safe_int(second.get("latencyMs") or second.get("latency_ms"), 0))
            cold_start_ms = max(latency_ms, _safe_int(first.get("latencyMs") or first.get("latency_ms"), latency_ms))
            usage = second.get("usage") if isinstance(second.get("usage"), dict) else {}
            input_text_chars = max(
                1,
                _safe_int(usage.get("inputTextChars") or usage.get("input_text_chars"), 0),
            )
            duration_sec = max(0.001, latency_ms / 1000.0) if latency_ms > 0 else 0.001
            synthesis_cps = round(input_text_chars / duration_sec, 3)
            peak_memory_bytes = _process_peak_memory_bytes()
            notes = [
                f"input_chars={input_text_chars}",
                _safe_str(fixture_meta.get("fixtureDescription")),
            ]
            output_audio_bytes = _safe_int(usage.get("outputAudioBytes") or usage.get("output_audio_bytes"), 0)
            if output_audio_bytes > 0:
                notes.insert(1, f"audio_bytes={output_audio_bytes}")
            return self._copy_bench_source_fields({
                "ok": True,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "modelId": model_id,
                "fixtureProfile": _safe_str(fixture_meta.get("fixtureProfile")),
                "fixtureTitle": _safe_str(fixture_meta.get("fixtureTitle")),
                "resultKind": "task_aware_quick_bench",
                "reasonCode": "fallback_only" if fallback_mode else "ready",
                "verdict": self._tts_bench_verdict(latency_ms=latency_ms, fallback_mode=fallback_mode),
                "fallbackMode": fallback_mode,
                "coldStartMs": cold_start_ms,
                "latencyMs": latency_ms,
                "peakMemoryBytes": peak_memory_bytes,
                "throughputValue": synthesis_cps,
                "throughputUnit": "chars_per_sec",
                "notes": [note for note in notes if note],
            }, source_result=second)

        if task_kind in {VISION_TASK_KIND, OCR_TASK_KIND}:
            first = self._run_image_task(fixture_request, task_kind=task_kind)
            if not bool(first.get("ok")):
                return self._bench_failure_output(
                    task_kind=task_kind,
                    model_id=model_id,
                    fixture_meta=fixture_meta,
                    reason_code=_safe_str(first.get("reasonCode") or first.get("error")) or "bench_failed",
                    error_detail=_safe_str(first.get("errorDetail")),
                    source_result=first,
                )
            second = self._run_image_task(fixture_request, task_kind=task_kind)
            if not bool(second.get("ok")):
                second = first
            fallback_mode = _safe_str(second.get("fallbackMode") or second.get("fallback_mode"))
            latency_ms = max(0, _safe_int(second.get("latencyMs") or second.get("latency_ms"), 0))
            cold_start_ms = max(latency_ms, _safe_int(first.get("latencyMs") or first.get("latency_ms"), latency_ms))
            throughput_value = round(1.0 / max(0.001, latency_ms / 1000.0), 3) if latency_ms > 0 else 0.0
            peak_memory_bytes = _process_peak_memory_bytes()
            return self._copy_bench_source_fields({
                "ok": True,
                "provider": self.provider_id(),
                "taskKind": task_kind,
                "modelId": model_id,
                "fixtureProfile": _safe_str(fixture_meta.get("fixtureProfile")),
                "fixtureTitle": _safe_str(fixture_meta.get("fixtureTitle")),
                "resultKind": "task_aware_quick_bench",
                "reasonCode": "fallback_only" if fallback_mode else "ready",
                "verdict": self._image_bench_verdict(fallback_mode=fallback_mode, latency_ms=latency_ms),
                "fallbackMode": fallback_mode,
                "coldStartMs": cold_start_ms,
                "latencyMs": latency_ms,
                "peakMemoryBytes": peak_memory_bytes,
                "throughputValue": throughput_value,
                "throughputUnit": "images_per_sec",
                "notes": [
                    _safe_str(second.get("text"))[:120],
                    f"device={_safe_str(second.get('deviceBackend') or second.get('device_backend')) or 'cpu'}",
                    _safe_str(fixture_meta.get("fixtureDescription")),
                ],
            }, source_result=second)

        return self._bench_failure_output(
            task_kind=task_kind,
            model_id=model_id,
            fixture_meta=fixture_meta,
            reason_code="unsupported_task",
        )

    def warmup_model(self, request: dict[str, Any]) -> dict[str, Any]:
        started_at = time.time()
        base_dir = _request_base_dir(request)
        runtime_resolution = self._runtime_resolution(base_dir=base_dir or "", request=request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        helper_model_ref = _safe_str(model_info.get("helper_model_ref"))
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
        helper_binary = self._helper_bridge_binary_path(runtime_resolution)
        helper_allows_task_inference = bool(
            self._uses_helper_bridge(runtime_resolution) and helper_binary and not requested_task_kind
        )
        if not selected_task_kinds and not helper_allows_task_inference:
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

        instance_key = _request_instance_key(request)
        load_profile_hash = _request_load_profile_hash(request)
        effective_context_length = _request_effective_context_length(request)
        max_context_length = max(
            0,
            _request_max_context_length(request),
            _safe_int(model_info.get("max_context_length"), 0),
        )
        effective_load_profile = _request_effective_load_profile(request)
        gpu_offload_ratio = _request_gpu_offload_ratio(request)
        parallel = _request_load_parallel(request)
        ttl_sec = _request_load_ttl(request)
        requested_identifier = _request_load_identifier(request)
        if self._uses_helper_bridge(runtime_resolution) and helper_binary:
            helper_load_timeout_sec = (
                MLX_VLM_HELPER_LOAD_TIMEOUT_SEC
                if self.provider_id() == "mlx_vlm" and any(
                    task_kind in {VISION_TASK_KIND, OCR_TASK_KIND}
                    for task_kind in selected_task_kinds
                )
                else 30.0
            )
            load_result = load_helper_bridge_model(
                helper_binary,
                request=HelperBinaryBridgeLoadRequest(
                    model_ref=helper_model_ref or model_path,
                    task_kind=selected_task_kinds[0] if len(selected_task_kinds) == 1 else "",
                    identifier=instance_key or requested_identifier,
                    context_length=effective_context_length,
                    gpu_offload_ratio=gpu_offload_ratio,
                    parallel=parallel,
                    ttl_sec=ttl_sec,
                ),
                timeout_sec=helper_load_timeout_sec,
            )
            if not bool(load_result.get("ok")):
                helper_reason = _safe_str(load_result.get("reasonCode") or load_result.get("error")) or "helper_load_failed"
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error=_safe_str(load_result.get("error")) or "helper_load_failed",
                    task_kind=requested_task_kind,
                    task_kinds=selected_task_kinds,
                    model_id=model_id,
                    model_path=model_path,
                    action="warmup_local_model",
                    error_detail=_safe_str(load_result.get("errorDetail")),
                    reason_code_override=helper_reason,
                    runtime_reason_code_override=helper_reason,
                )
            loaded_row = load_result.get("loadedModel") if isinstance(load_result.get("loadedModel"), dict) else {}
            helper_context_length = max(
                0,
                _safe_int(loaded_row.get("contextLength") or loaded_row.get("context_length"), effective_context_length),
            )
            helper_already_loaded = bool(load_result.get("alreadyLoaded"))
            helper_effective_task_kinds = (
                list(selected_task_kinds)
                if selected_task_kinds
                else self._helper_bridge_task_kinds_for_row(loaded_row)
            )
            if not helper_effective_task_kinds:
                if not helper_already_loaded and _safe_str(instance_key):
                    unload_helper_bridge_model(helper_binary, identifier=instance_key)
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error="helper_task_kind_unresolved",
                    model_id=model_id,
                    model_path=model_path,
                    action="warmup_local_model",
                    reason_code_override="helper_task_kind_unresolved",
                    runtime_reason_code_override="helper_task_kind_unresolved",
                )
            if base_dir:
                self._record_helper_bridge_loaded_instance(
                    base_dir=base_dir,
                    row={
                        "instanceKey": instance_key,
                        "modelId": model_id,
                        "taskKinds": helper_effective_task_kinds,
                        "loadProfileHash": load_profile_hash,
                        "effectiveContextLength": helper_context_length,
                        "maxContextLength": max_context_length,
                        "effectiveLoadProfile": dict(effective_load_profile or {}),
                        "loadedAt": time.time(),
                        "lastUsedAt": time.time(),
                        "residency": "resident",
                        "residencyScope": self._helper_bridge_residency_scope(),
                        "deviceBackend": self._helper_bridge_device_backend(),
                    },
                )
            return {
                "ok": True,
                "provider": self.provider_id(),
                "action": "warmup_local_model",
                "modelId": model_id,
                "modelPath": model_path,
                "taskKind": requested_task_kind or helper_effective_task_kinds[0],
                "taskKinds": helper_effective_task_kinds,
                "instanceKey": instance_key,
                "loadProfileHash": load_profile_hash,
                "effectiveContextLength": helper_context_length,
                "deviceBackend": self._helper_bridge_device_backend(),
                "coldStartMs": 0 if helper_already_loaded else max(0, int(round((time.time() - started_at) * 1000.0))),
                "alreadyLoaded": helper_already_loaded,
                "lifecycleMode": self.lifecycle_mode(),
                "supportedLifecycleActions": self.supported_lifecycle_actions(),
                "warmupTaskKinds": self.warmup_task_kinds(),
                "residencyScope": self._helper_bridge_residency_scope(),
                "processScoped": False,
            }

        required_image_runtime = any(
            task_kind in {VISION_TASK_KIND, OCR_TASK_KIND}
            for task_kind in selected_task_kinds
        )
        runtime_ready = self._image_runtime_ready(runtime_resolution) if required_image_runtime else self._core_runtime_ready(runtime_resolution)
        if not runtime_ready:
            return self._runtime_failure_output(
                request=request,
                runtime_resolution=runtime_resolution,
                error=self._task_runtime_import_error(
                    runtime_resolution,
                    task_kinds=selected_task_kinds,
                ) or "missing_runtime",
                task_kinds=selected_task_kinds,
                model_id=model_id,
                model_path=model_path,
                action="warmup_local_model",
            )

        device_backends: list[str] = []
        already_loaded = True

        try:
            cache_key = _safe_str(instance_key) or model_path or model_id
            image_task_kinds = [
                task_kind
                for task_kind in selected_task_kinds
                if task_kind in {VISION_TASK_KIND, OCR_TASK_KIND}
            ]
            if image_task_kinds:
                if cache_key not in self._image_model_cache:
                    already_loaded = False
                runtime = self._load_image_runtime(
                    model_id=model_id,
                    model_path=model_path,
                    task_kinds=image_task_kinds,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                    effective_context_length=effective_context_length,
                    max_context_length=max_context_length,
                    effective_load_profile=effective_load_profile,
                )
                device_backends.append(_safe_str(runtime.get("device")) or "cpu")
            for task_kind in selected_task_kinds:
                if task_kind in {VISION_TASK_KIND, OCR_TASK_KIND}:
                    continue
                if task_kind == TEXT_TASK_KIND:
                    if cache_key not in self._text_model_cache:
                        already_loaded = False
                    runtime = self._load_text_runtime(
                        model_id=model_id,
                        model_path=model_path,
                        instance_key=instance_key,
                        load_profile_hash=load_profile_hash,
                        effective_context_length=effective_context_length,
                        max_context_length=max_context_length,
                        effective_load_profile=effective_load_profile,
                    )
                elif task_kind == EMBED_TASK_KIND:
                    if cache_key not in self._embedding_model_cache:
                        already_loaded = False
                    runtime = self._load_embedding_runtime(
                        model_id=model_id,
                        model_path=model_path,
                        instance_key=instance_key,
                        load_profile_hash=load_profile_hash,
                        effective_context_length=effective_context_length,
                        max_context_length=max_context_length,
                        effective_load_profile=effective_load_profile,
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
                        max_context_length=max_context_length,
                        effective_load_profile=effective_load_profile,
                    )
                device_backends.append(_safe_str(runtime.get("device")) or "cpu")
        except Exception as exc:
            error_detail = _safe_str(exc)
            reason_code_override, runtime_reason_code_override = _classify_runtime_failure_reason(
                error_detail,
                "warmup_runtime_failed",
            )
            return self._runtime_failure_output(
                request=request,
                runtime_resolution=runtime_resolution,
                error="warmup_runtime_failed",
                task_kind=requested_task_kind,
                task_kinds=selected_task_kinds,
                model_id=model_id,
                model_path=model_path,
                action="warmup_local_model",
                error_detail=error_detail,
                reason_code_override=reason_code_override,
                runtime_reason_code_override=runtime_reason_code_override,
            )

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
        runtime_resolution = self._runtime_resolution(base_dir=base_dir or "", request=request)
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
        if self._uses_helper_bridge(runtime_resolution):
            helper_binary = self._helper_bridge_binary_path(runtime_resolution)
            if not helper_binary:
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error="helper_binary_missing",
                    model_id=model_id,
                    action="unload_local_model",
                    reason_code_override="helper_binary_missing",
                    runtime_reason_code_override="helper_binary_missing",
                )
            registered_rows = self.list_registered_models(catalog_models=[])
            matches = [
                row
                for row in self._helper_bridge_loaded_instance_rows(
                    runtime_resolution=runtime_resolution,
                    registered_model_rows=registered_rows,
                )
                if _safe_str(row.get("modelId")) == model_id
            ]
            if not matches:
                return {
                    "ok": False,
                    "provider": self.provider_id(),
                    "action": "unload_local_model",
                    "modelId": model_id,
                    "error": "model_not_loaded",
                    "request": dict(request or {}),
                }
            failed: dict[str, Any] | None = None
            for row in matches:
                result = unload_helper_bridge_model(
                    helper_binary,
                    identifier=_safe_str(row.get("instanceKey")),
                )
                if not bool(result.get("ok")):
                    failed = result
                    break
            if failed is not None:
                helper_reason = _safe_str(failed.get("reasonCode") or failed.get("error")) or "helper_unload_failed"
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error=_safe_str(failed.get("error")) or "helper_unload_failed",
                    model_id=model_id,
                    action="unload_local_model",
                    error_detail=_safe_str(failed.get("errorDetail")),
                    reason_code_override=helper_reason,
                    runtime_reason_code_override=helper_reason,
                )
            task_kinds = sorted(
                {
                    task_kind
                    for row in matches
                    for task_kind in _string_list(row.get("taskKinds") or row.get("task_kinds"))
                }
            )
            if base_dir:
                self._remove_helper_bridge_tracked_instances(
                    base_dir=base_dir,
                    model_id=model_id,
                    eviction_reason="manual_unload",
                )
            return {
                "ok": True,
                "provider": self.provider_id(),
                "action": "unload_local_model",
                "modelId": model_id,
                "taskKinds": task_kinds,
                "unloadedInstanceCount": len(matches),
                "lifecycleMode": self.lifecycle_mode(),
                "supportedLifecycleActions": self.supported_lifecycle_actions(),
                "warmupTaskKinds": self.warmup_task_kinds(),
                "residencyScope": self._helper_bridge_residency_scope(),
                "processScoped": False,
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
            if cache_name == TEXT_TASK_KIND:
                cache = self._text_model_cache
            elif cache_name == EMBED_TASK_KIND:
                cache = self._embedding_model_cache
            elif cache_name == ASR_TASK_KIND:
                cache = self._asr_pipeline_cache
            else:
                cache = self._image_model_cache
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
        runtime_resolution = self._runtime_resolution(base_dir=base_dir or "", request=request)
        instance_key = _request_instance_key(request)
        if not instance_key:
            return {
                "ok": False,
                "provider": self.provider_id(),
                "action": "evict_local_instance",
                "error": "missing_instance_key",
                "request": dict(request or {}),
            }
        if self._uses_helper_bridge(runtime_resolution):
            helper_binary = self._helper_bridge_binary_path(runtime_resolution)
            if not helper_binary:
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error="helper_binary_missing",
                    action="evict_local_instance",
                    reason_code_override="helper_binary_missing",
                    runtime_reason_code_override="helper_binary_missing",
                )
            registered_rows = self.list_registered_models(catalog_models=[])
            matches = [
                row
                for row in self._helper_bridge_loaded_instance_rows(
                    runtime_resolution=runtime_resolution,
                    registered_model_rows=registered_rows,
                )
                if _safe_str(row.get("instanceKey")) == instance_key
            ]
            if not matches:
                return {
                    "ok": False,
                    "provider": self.provider_id(),
                    "action": "evict_local_instance",
                    "instanceKey": instance_key,
                    "error": "instance_not_loaded",
                    "request": dict(request or {}),
                }
            result = unload_helper_bridge_model(helper_binary, identifier=instance_key)
            if not bool(result.get("ok")):
                helper_reason = _safe_str(result.get("reasonCode") or result.get("error")) or "helper_unload_failed"
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error=_safe_str(result.get("error")) or "helper_unload_failed",
                    model_id=_safe_str(matches[0].get("modelId")),
                    action="evict_local_instance",
                    error_detail=_safe_str(result.get("errorDetail")),
                    reason_code_override=helper_reason,
                    runtime_reason_code_override=helper_reason,
                )
            if base_dir:
                self._remove_helper_bridge_tracked_instances(
                    base_dir=base_dir,
                    instance_keys=[instance_key],
                    eviction_reason="manual_evict_instance",
                )
            return {
                "ok": True,
                "provider": self.provider_id(),
                "action": "evict_local_instance",
                "modelId": _safe_str(matches[0].get("modelId")),
                "instanceKey": instance_key,
                "taskKinds": _string_list(matches[0].get("taskKinds") or matches[0].get("task_kinds")),
                "evictedInstanceCount": 1,
                "lifecycleMode": self.lifecycle_mode(),
                "supportedLifecycleActions": self.supported_lifecycle_actions(),
                "warmupTaskKinds": self.warmup_task_kinds(),
                "residencyScope": self._helper_bridge_residency_scope(),
                "processScoped": False,
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
            if cache_name == TEXT_TASK_KIND:
                cache = self._text_model_cache
            elif cache_name == EMBED_TASK_KIND:
                cache = self._embedding_model_cache
            elif cache_name == ASR_TASK_KIND:
                cache = self._asr_pipeline_cache
            else:
                cache = self._image_model_cache
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
        voice_profile = (
            resolved_model.get("voiceProfile")
            if isinstance(resolved_model.get("voiceProfile"), dict)
            else resolved_model.get("voice_profile")
        )
        engine_hints = (
            voice_profile.get("engineHints")
            if isinstance(voice_profile, dict) and isinstance(voice_profile.get("engineHints"), list)
            else voice_profile.get("engine_hints")
            if isinstance(voice_profile, dict)
            else []
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
            "helper_model_ref": _safe_str(
                request.get("helper_model_ref")
                or request.get("helperModelRef")
                or resolved_model.get("helperModelRef")
                or resolved_model.get("helper_model_ref")
                or resolved_model.get("indexedModelIdentifier")
                or resolved_model.get("indexed_model_identifier")
                or resolved_model.get("modelKey")
                or resolved_model.get("model_key")
            ),
            "task_kinds": _normalize_task_kinds(
                request.get("task_kinds")
                or request.get("taskKinds")
                or resolved_model.get("taskKinds")
                or resolved_model.get("task_kinds")
            ),
            "processor_requirements": processor_requirements if isinstance(processor_requirements, dict) else {},
            "trust_profile": trust_profile if isinstance(trust_profile, dict) else {},
            "voice_profile": voice_profile if isinstance(voice_profile, dict) else {},
            "engine_hints": _string_list(engine_hints),
        }

    def _resolve_bench_task_kind(self, request: dict[str, Any], *, model_info: dict[str, Any]) -> str:
        requested = _safe_str(request.get("task_kind") or request.get("taskKind")).lower()
        if requested:
            return requested
        runtime_resolution = self._runtime_resolution(
            base_dir=_request_base_dir(request) or "",
            request=request,
        )
        for task_kind in self._inferred_model_task_kinds(
            request=request,
            model_info=model_info,
            runtime_resolution=runtime_resolution,
        ):
            if task_kind in self.supported_task_kinds():
                return task_kind
        return ""

    def _read_bench_fixture_pack(self, request: dict[str, Any]) -> tuple[str, list[dict[str, Any]]]:
        pack_path = _safe_str(request.get("fixture_pack_path") or request.get("fixturePackPath"))
        if not pack_path:
            return "fixture_pack_missing", []
        if not os.path.exists(pack_path) or not os.path.isfile(pack_path):
            return "fixture_pack_missing", []
        try:
            with open(pack_path, "r", encoding="utf-8") as handle:
                raw = json.load(handle)
        except Exception:
            return "fixture_pack_invalid", []
        if not isinstance(raw, dict):
            return "fixture_pack_invalid", []
        schema_version = _safe_str(raw.get("schemaVersion") or raw.get("schema_version"))
        if schema_version and schema_version != BENCH_FIXTURE_SCHEMA_VERSION:
            return "fixture_pack_version_mismatch", []
        fixtures = raw.get("fixtures")
        if not isinstance(fixtures, list):
            return "fixture_pack_invalid", []
        return "", [item for item in fixtures if isinstance(item, dict)]

    def _bench_fixture_directory(self, *, base_dir: str) -> str:
        return os.path.join(os.path.abspath(str(base_dir or "")), GENERATED_BENCH_FIXTURE_DIRNAME)

    def _materialize_audio_bench_fixture(
        self,
        fixture_id: str,
        audio_spec: dict[str, Any],
        *,
        base_dir: str,
    ) -> tuple[str, str]:
        generator = _safe_str(audio_spec.get("generator")).lower()
        if generator != "silence_wav":
            return "fixture_missing", ""
        duration_sec = max(0.05, _safe_float(audio_spec.get("durationSec") or audio_spec.get("duration_sec"), 0.25))
        sample_rate = max(8000, _safe_int(audio_spec.get("sampleRate") or audio_spec.get("sample_rate"), 16000))
        file_name = f"{_safe_slug(fixture_id)}_{int(duration_sec * 1000)}ms_{sample_rate}.wav"
        audio_path = os.path.join(self._bench_fixture_directory(base_dir=base_dir), file_name)
        _write_generated_silence_wav(audio_path, duration_sec=duration_sec, sample_rate=sample_rate)
        return "", audio_path

    def _materialize_image_bench_fixture(
        self,
        fixture_id: str,
        image_spec: dict[str, Any],
        *,
        base_dir: str,
    ) -> tuple[str, str]:
        generator = _safe_str(image_spec.get("generator")).lower()
        if generator != "png_header":
            return "fixture_missing", ""
        width = max(32, _safe_int(image_spec.get("width"), 640))
        height = max(32, _safe_int(image_spec.get("height"), 384))
        file_name = f"{_safe_slug(fixture_id)}_{width}x{height}.png"
        image_path = os.path.join(self._bench_fixture_directory(base_dir=base_dir), file_name)
        _write_generated_png_header(image_path, width=width, height=height)
        return "", image_path

    def _resolve_bench_fixture(
        self,
        request: dict[str, Any],
        *,
        task_kind: str,
        model_info: dict[str, Any],
    ) -> tuple[str, dict[str, Any], dict[str, Any]]:
        error_code, fixtures = self._read_bench_fixture_pack(request)
        if error_code:
            return error_code, {}, {}

        fixture_profile = _safe_str(request.get("fixture_profile") or request.get("fixtureProfile"))
        selected: dict[str, Any] | None = None
        for fixture in fixtures:
            if fixture_profile:
                if _safe_str(fixture.get("id")) != fixture_profile:
                    continue
                selected = fixture
                break
            if _safe_str(fixture.get("taskKind") or fixture.get("task_kind")).lower() == task_kind:
                selected = fixture
                break

        if selected is None:
            return "fixture_missing", {}, {}

        selected_task_kind = _safe_str(selected.get("taskKind") or selected.get("task_kind")).lower()
        if selected_task_kind != task_kind:
            return "fixture_task_mismatch", {}, {}

        provider_ids = _string_list(selected.get("providerIds") or selected.get("provider_ids"))
        if provider_ids and self.provider_id() not in provider_ids:
            return "fixture_provider_mismatch", {}, {}

        input_obj = selected.get("input") if isinstance(selected.get("input"), dict) else {}
        options = selected.get("options") if isinstance(selected.get("options"), dict) else {}
        base_dir = _request_base_dir(request)
        if not base_dir:
            return "fixture_missing", {}, {}

        fixture_meta = {
            "fixtureProfile": _safe_str(selected.get("id")),
            "fixtureTitle": _safe_str(selected.get("title")),
            "fixtureDescription": _safe_str(selected.get("description")),
        }
        fixture_request: dict[str, Any] = {
            **dict(request or {}),
            "task_kind": task_kind,
            "taskKind": task_kind,
        }

        if task_kind == EMBED_TASK_KIND:
            texts = input_obj.get("texts")
            if not isinstance(texts, list) or not texts:
                return "fixture_missing", {}, {}
            fixture_request["texts"] = [str(item or "") for item in texts]
            for key in ("max_length", "maxLength"):
                if options.get(key) is not None:
                    fixture_request["max_length"] = _safe_int(options.get(key), 256)
                    break
        elif task_kind == TEXT_TASK_KIND:
            prompt = _safe_str(input_obj.get("prompt"))
            if not prompt:
                return "fixture_missing", {}, {}
            fixture_request["prompt"] = prompt
            for key in ("max_new_tokens", "maxNewTokens", "max_tokens", "maxTokens"):
                if options.get(key) is not None:
                    fixture_request["max_new_tokens"] = _safe_int(options.get(key), 128)
                    break
            if options.get("temperature") is not None:
                fixture_request["temperature"] = _safe_float(options.get("temperature"), 0.0)
        elif task_kind == TTS_TASK_KIND:
            text = _safe_str(
                input_obj.get("text")
                or input_obj.get("prompt")
                or options.get("text")
                or options.get("prompt")
            )
            if not text:
                return "fixture_missing", {}, {}
            fixture_request["text"] = text
            locale = _safe_str(
                input_obj.get("locale")
                or input_obj.get("language")
                or options.get("locale")
                or options.get("language")
            )
            if locale:
                fixture_request["locale"] = locale
            voice_color = _safe_str(
                input_obj.get("voice_color")
                or input_obj.get("voiceColor")
                or options.get("voice_color")
                or options.get("voiceColor")
            ).lower()
            if voice_color:
                fixture_request["voice_color"] = voice_color
            speech_rate_value = (
                input_obj.get("speech_rate")
                if input_obj.get("speech_rate") is not None
                else input_obj.get("speechRate")
                if input_obj.get("speechRate") is not None
                else options.get("speech_rate")
                if options.get("speech_rate") is not None
                else options.get("speechRate")
            )
            if speech_rate_value is not None:
                fixture_request["speech_rate"] = max(0.6, min(1.8, _safe_float(speech_rate_value, 1.0)))
        elif task_kind == ASR_TASK_KIND:
            audio_spec = input_obj.get("audio") if isinstance(input_obj.get("audio"), dict) else {}
            error_code, audio_path = self._materialize_audio_bench_fixture(
                _safe_str(selected.get("id")),
                audio_spec,
                base_dir=base_dir,
            )
            if error_code or not audio_path:
                return error_code or "fixture_missing", {}, {}
            fixture_request["audio_path"] = audio_path
            fixture_request["language"] = _safe_str(input_obj.get("language"))
            fixture_request["timestamps"] = _safe_bool(input_obj.get("timestamps"), False)
        elif task_kind in {VISION_TASK_KIND, OCR_TASK_KIND}:
            image_spec = input_obj.get("image") if isinstance(input_obj.get("image"), dict) else {}
            error_code, image_path = self._materialize_image_bench_fixture(
                _safe_str(selected.get("id")),
                image_spec,
                base_dir=base_dir,
            )
            if error_code or not image_path:
                return error_code or "fixture_missing", {}, {}
            fixture_request["image_path"] = image_path
            fixture_request["prompt"] = _safe_str(input_obj.get("prompt"))
        else:
            return "unsupported_task", {}, {}

        if _safe_bool(request.get("allow_bench_fallback"), True):
            if task_kind == EMBED_TASK_KIND:
                fixture_request.setdefault("allow_hash_fallback", True)
            elif task_kind == ASR_TASK_KIND:
                fixture_request.setdefault("allow_asr_fallback", True)
            elif task_kind in {VISION_TASK_KIND, OCR_TASK_KIND}:
                fixture_request.setdefault("allow_vision_fallback", True)

        model_path = _safe_str(model_info.get("model_path"))
        if model_path:
            fixture_request.setdefault("model_path", model_path)

        return "", fixture_meta, fixture_request

    def _normalize_text_messages(self, request: dict[str, Any]) -> list[dict[str, Any]]:
        raw_messages = request.get("messages")
        if isinstance(raw_messages, list):
            normalized_messages: list[dict[str, Any]] = []
            for raw_message in raw_messages:
                if not isinstance(raw_message, dict):
                    continue
                role = _safe_str(raw_message.get("role")).lower() or "user"
                raw_content = raw_message.get("content")
                content_rows: list[dict[str, Any]] = []
                if isinstance(raw_content, str):
                    text = _safe_str(raw_content)
                    if text:
                        content_rows.append({"type": "text", "text": text})
                elif isinstance(raw_content, list):
                    for item in raw_content:
                        if not isinstance(item, dict):
                            continue
                        if _safe_str(item.get("type")).lower() != "text":
                            continue
                        text = _safe_str(item.get("text"))
                        if text:
                            content_rows.append({"type": "text", "text": text})
                if content_rows:
                    normalized_messages.append({"role": role, "content": content_rows})
            if normalized_messages:
                return normalized_messages

        input_obj = request.get("input") if isinstance(request.get("input"), dict) else {}
        options = request.get("options") if isinstance(request.get("options"), dict) else {}
        prompt = _safe_str(
            request.get("prompt")
            or request.get("text")
            or input_obj.get("prompt")
            or input_obj.get("text")
            or options.get("prompt")
            or options.get("text")
        )
        if not prompt:
            return []
        return [{"role": "user", "content": [{"type": "text", "text": prompt}]}]

    def _text_usage_payload(self, validated: dict[str, Any]) -> dict[str, Any]:
        return {
            "promptChars": int(validated.get("prompt_chars") or 0),
            "messageCount": int(validated.get("message_count") or 0),
        }

    def _tts_usage_payload(self, validated: dict[str, Any]) -> dict[str, Any]:
        return {
            "inputTextChars": int(validated.get("text_chars") or 0),
            "speechRate": round(_safe_float(validated.get("speech_rate"), 1.0), 3),
        }

    def _validate_text_request(self, request: dict[str, Any], *, model_info: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        model_id = _safe_str(model_info.get("model_id"))
        if not model_id:
            return "missing_model_id", {}

        task_kinds = model_info.get("task_kinds")
        if isinstance(task_kinds, list) and task_kinds and TEXT_TASK_KIND not in task_kinds:
            return f"model_task_unsupported:{TEXT_TASK_KIND}", {}

        messages = self._normalize_text_messages(request)
        if not messages:
            return "missing_prompt", {}

        prompt_chars = 0
        for message in messages:
            content_rows = message.get("content") if isinstance(message.get("content"), list) else []
            for item in content_rows:
                if not isinstance(item, dict):
                    continue
                if _safe_str(item.get("type")).lower() != "text":
                    continue
                prompt_chars += len(_safe_str(item.get("text")))

        if prompt_chars <= 0:
            return "missing_prompt", {}
        if prompt_chars > MAX_TOTAL_TEXT_CHARS:
            return "prompt_too_large", {}

        return "", {
            "messages": messages,
            "message_count": len(messages),
            "prompt_chars": prompt_chars,
        }

    def _extract_texts(self, request: dict[str, Any]) -> list[str]:
        raw_texts = request.get("texts")
        if isinstance(raw_texts, list):
            return [str(item or "") for item in raw_texts]
        if request.get("text") is not None:
            return [str(request.get("text") or "")]
        return []

    def _extract_tts_input(self, request: dict[str, Any]) -> dict[str, Any]:
        input_obj = request.get("input") if isinstance(request.get("input"), dict) else {}
        options = request.get("options") if isinstance(request.get("options"), dict) else {}
        return {
            "text": _safe_str(
                request.get("text")
                or request.get("prompt")
                or options.get("text")
                or options.get("prompt")
                or input_obj.get("text")
                or input_obj.get("prompt")
            ),
            "locale": _safe_str(
                request.get("locale")
                or request.get("language")
                or request.get("lang")
                or options.get("locale")
                or options.get("language")
                or options.get("lang")
                or input_obj.get("locale")
                or input_obj.get("language")
                or input_obj.get("lang")
            ),
            "voice_color": _safe_str(
                request.get("voice_color")
                or request.get("voiceColor")
                or options.get("voice_color")
                or options.get("voiceColor")
                or input_obj.get("voice_color")
                or input_obj.get("voiceColor")
            ).lower(),
            "speech_rate": max(
                0.6,
                min(
                    1.8,
                    _safe_float(
                        request.get("speech_rate")
                        if request.get("speech_rate") is not None
                        else request.get("speechRate")
                        if request.get("speechRate") is not None
                        else options.get("speech_rate")
                        if options.get("speech_rate") is not None
                        else options.get("speechRate")
                        if options.get("speechRate") is not None
                        else input_obj.get("speech_rate")
                        if input_obj.get("speech_rate") is not None
                        else input_obj.get("speechRate"),
                        1.0,
                    ),
                ),
            ),
        }

    def _validate_tts_request(self, request: dict[str, Any], *, model_info: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        model_id = _safe_str(model_info.get("model_id"))
        if not model_id:
            return "missing_model_id", {}

        task_kinds = model_info.get("task_kinds")
        if isinstance(task_kinds, list) and task_kinds and TTS_TASK_KIND not in task_kinds:
            return f"model_task_unsupported:{TTS_TASK_KIND}", {}

        tts_input = self._extract_tts_input(request)
        text = _safe_str(tts_input.get("text"))
        if not text:
            return "missing_text", {}
        if len(text) > MAX_TTS_TEXT_CHARS:
            return "tts_input_too_large", {
                "text_chars": len(text),
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
        if _contains_sensitive_text(text) and not allow_secret_input:
            return "policy_blocked_sensitive_text", {
                "text_chars": len(text),
            }

        return "", {
            "text": text,
            "text_chars": len(text),
            "locale": _safe_str(tts_input.get("locale")).replace("_", "-"),
            "voice_color": _safe_str(tts_input.get("voice_color")).lower(),
            "speech_rate": _safe_float(tts_input.get("speech_rate"), 1.0),
        }

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
        image_paths = _value_list(
            request.get("image_paths")
            or request.get("imagePaths")
            or input_obj.get("image_paths")
            or input_obj.get("imagePaths")
            or input_obj.get("paths")
        )
        has_explicit_image_paths = bool(image_paths)
        raw_multimodal_messages = (
            request.get("multimodal_messages")
            if isinstance(request.get("multimodal_messages"), list)
            else request.get("multimodalMessages")
        )
        multimodal_messages: list[dict[str, Any]] = []
        if isinstance(raw_multimodal_messages, list):
            for raw_message in raw_multimodal_messages:
                if not isinstance(raw_message, dict):
                    continue
                role = _safe_str(raw_message.get("role")).lower() or "user"
                raw_content = raw_message.get("content") if isinstance(raw_message.get("content"), list) else []
                content_rows: list[dict[str, Any]] = []
                for item in raw_content:
                    if not isinstance(item, dict):
                        continue
                    item_type = _safe_str(item.get("type")).lower()
                    if item_type == "text":
                        text = _safe_str(item.get("text"))
                        if text:
                            content_rows.append({"type": "text", "text": text})
                        continue
                    if item_type != "image":
                        continue
                    image_path = _safe_str(item.get("imagePath") or item.get("image_path") or item.get("path"))
                    if not image_path:
                        continue
                    if not has_explicit_image_paths:
                        image_paths.append(image_path)
                    image_row = {
                        "type": "image",
                        "imagePath": image_path,
                    }
                    source_kind = _safe_str(item.get("sourceKind") or item.get("source_kind"))
                    detail = _safe_str(item.get("detail"))
                    if source_kind:
                        image_row["sourceKind"] = source_kind
                    if detail:
                        image_row["detail"] = detail
                    content_rows.append(image_row)
                if content_rows:
                    multimodal_messages.append({"role": role, "content": content_rows})
        image_path = _safe_str(
            request.get("image_path")
            or request.get("imagePath")
            or input_obj.get("image_path")
            or input_obj.get("imagePath")
            or input_obj.get("path")
        )
        if image_path and image_path not in image_paths:
            image_paths.insert(0, image_path)
        return {
            "image_path": image_paths[0] if image_paths else image_path,
            "image_paths": image_paths,
            "image_count": len(image_paths),
            "multimodal_messages": multimodal_messages,
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
        image_paths = [path for path in list(image_input.get("image_paths") or []) if _safe_str(path)]
        if not image_paths:
            return "missing_image_path", {}
        max_image_bytes = max(1024, min(100 * 1024 * 1024, _safe_int(request.get("max_image_bytes"), MAX_IMAGE_BYTES)))
        max_image_dimension = _request_max_image_dimension(request)
        max_image_pixels = max(1024, min(100_000_000, _safe_int(request.get("max_image_pixels"), MAX_IMAGE_PIXELS)))
        validated = {
            **image_input,
            "image_path": image_paths[0],
            "image_paths": image_paths,
            "image_count": len(image_paths),
            "max_image_bytes": max_image_bytes,
            "max_image_pixels": max_image_pixels,
            "max_image_dimension": max_image_dimension,
        }
        page_index_value = request.get("page_index") if request.get("page_index") is not None else request.get("_ocr_page_index")
        page_count_value = request.get("page_count") if request.get("page_count") is not None else request.get("_ocr_page_count")
        if page_index_value is not None:
            validated["page_index"] = max(0, _safe_int(page_index_value, 0))
        if page_count_value is not None:
            validated["page_count"] = max(1, _safe_int(page_count_value, len(image_paths) or 1))
        image_items: list[dict[str, Any]] = []
        total_image_bytes = 0
        total_image_pixels = 0
        for index, image_path in enumerate(image_paths):
            if "\x00" in image_path:
                return "invalid_image_path", {
                    **validated,
                    "image_index": index,
                    "image_path": image_path,
                }
            if not os.path.exists(image_path) or not os.path.isfile(image_path):
                return "image_path_not_found", {
                    **validated,
                    "image_index": index,
                    "image_path": image_path,
                }

            ext = _normalize_image_extension(image_path)
            if ext not in SUPPORTED_IMAGE_EXTENSIONS:
                return "unsupported_image_format", {
                    **validated,
                    "image_index": index,
                    "image_path": image_path,
                    "image_format": ext,
                }

            file_size_bytes = max(0, os.path.getsize(image_path))
            if file_size_bytes > max_image_bytes:
                return "image_file_too_large", {
                    **validated,
                    "image_index": index,
                    "image_path": image_path,
                    "image_format": ext,
                    "file_size_bytes": file_size_bytes,
                }

            try:
                image_meta = _load_image_info(image_path)
            except RuntimeError as exc:
                return _safe_str(exc) or "image_decode_failed", {
                    **validated,
                    "image_index": index,
                    "image_path": image_path,
                    "image_format": ext,
                    "file_size_bytes": file_size_bytes,
                }

            image_width = int(image_meta.get("image_width") or 0)
            image_height = int(image_meta.get("image_height") or 0)
            image_pixels = int(image_meta.get("image_pixels") or 0)
            if image_width > max_image_dimension or image_height > max_image_dimension:
                return "image_dimensions_too_large", {
                    **validated,
                    "image_index": index,
                    "image_path": image_path,
                    "image_format": ext,
                    "file_size_bytes": file_size_bytes,
                    "image_width": image_width,
                    "image_height": image_height,
                    "image_pixels": image_pixels,
                }
            if image_pixels > max_image_pixels:
                return "image_pixels_too_large", {
                    **validated,
                    "image_index": index,
                    "image_path": image_path,
                    "image_format": ext,
                    "file_size_bytes": file_size_bytes,
                    "image_width": image_width,
                    "image_height": image_height,
                    "image_pixels": image_pixels,
                }

            image_item = {
                "index": index,
                "image_path": image_path,
                "image_format": _safe_str(image_meta.get("image_format")) or ext,
                "file_size_bytes": file_size_bytes,
                "image_width": image_width,
                "image_height": image_height,
                "image_pixels": image_pixels,
                "image_digest_prefix": _safe_str(image_meta.get("image_digest_prefix")),
            }
            image_items.append(image_item)
            total_image_bytes += file_size_bytes
            total_image_pixels += image_pixels

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
        first_item = image_items[0]
        if image_input.get("input_sensitivity") == "secret" and not allow_secret_input:
            return "policy_blocked_secret_image", {
                **validated,
                **first_item,
                "total_image_bytes": total_image_bytes,
                "total_image_pixels": total_image_pixels,
                "image_items": image_items,
            }

        return "", {
            **validated,
            **first_item,
            "image_items": image_items,
            "total_image_bytes": total_image_bytes,
            "total_image_pixels": total_image_pixels,
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
        max_context_length: int = 0,
        effective_load_profile: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        cache_key = _safe_str(instance_key) or model_path or model_id
        cached = self._asr_pipeline_cache.get(cache_key)
        if cached:
            return self._touch_cache_entry(
                cached,
                task_kinds=[ASR_TASK_KIND],
                effective_context_length=effective_context_length,
                max_context_length=max_context_length,
                effective_load_profile=effective_load_profile,
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
        if isinstance(getattr(pipe, "_forward_params", None), dict):
            pipe._forward_params.pop("local_files_only", None)

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
            "max_context_length": max(0, int(max_context_length or 0)),
            "effective_load_profile": dict(effective_load_profile or {}),
            "loaded_at": now,
            "last_used_at": now,
            "residency": "resident",
            "residency_scope": self.residency_scope(),
        }
        self._asr_pipeline_cache[cache_key] = out
        return out

    def _torch_device_backend(self) -> str:
        import torch  # type: ignore

        try:
            if bool(getattr(torch.backends, "mps", None)) and torch.backends.mps.is_available():
                return "mps"
        except Exception:
            pass
        cuda = getattr(torch, "cuda", None)
        try:
            if cuda is not None and cuda.is_available():
                return "cuda"
        except Exception:
            pass
        return "cpu"

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

        from transformers import (  # type: ignore
            AutoModelForCausalLM,
            AutoModelForImageTextToText,
            AutoModelForSeq2SeqLM,
            AutoModelForVision2Seq,
            AutoProcessor,
        )

        processor = AutoProcessor.from_pretrained(
            model_path,
            local_files_only=True,
            trust_remote_code=False,
        )
        device = self._torch_device_backend()

        load_errors: list[str] = []
        model = None
        model_loader_name = ""
        for loader_name, loader in (
            ("AutoModelForImageTextToText", AutoModelForImageTextToText),
            ("AutoModelForVision2Seq", AutoModelForVision2Seq),
            ("AutoModelForCausalLM", AutoModelForCausalLM),
            ("AutoModelForSeq2SeqLM", AutoModelForSeq2SeqLM),
        ):
            try:
                model = loader.from_pretrained(
                    model_path,
                    local_files_only=True,
                    trust_remote_code=False,
                )
                model_loader_name = loader_name
                break
            except Exception as exc:
                load_errors.append(f"{loader_name}:{_safe_str(exc)}")
                continue
        if model is None:
            raise RuntimeError(load_errors[-1] if load_errors else "image_model_init_failed")

        model.eval()
        model.to(device)

        now = time.time()
        out = {
            "processor": processor,
            "model": model,
            "device": device,
            "model_loader": model_loader_name,
            "model_id": model_id,
            "model_path": model_path,
            "instance_key": _safe_str(instance_key),
            "load_profile_hash": _safe_str(load_profile_hash),
            "task_kinds": _string_list(task_kinds),
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

    def _load_text_runtime(
        self,
        *,
        model_id: str,
        model_path: str,
        instance_key: str = "",
        load_profile_hash: str = "",
        effective_context_length: int = 0,
        max_context_length: int = 0,
        effective_load_profile: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        cache_key = _safe_str(instance_key) or model_path or model_id
        cached = self._text_model_cache.get(cache_key)
        if cached:
            return self._touch_cache_entry(
                cached,
                task_kinds=[TEXT_TASK_KIND],
                effective_context_length=effective_context_length,
                max_context_length=max_context_length,
                effective_load_profile=effective_load_profile,
            )

        from transformers import AutoModelForCausalLM, AutoModelForSeq2SeqLM, AutoTokenizer  # type: ignore

        tokenizer = None
        tokenizer_errors: list[str] = []
        for kwargs in (
            {"local_files_only": True, "trust_remote_code": False, "use_fast": True},
            {"local_files_only": True, "trust_remote_code": False},
            {"trust_remote_code": False},
            {},
        ):
            try:
                tokenizer = AutoTokenizer.from_pretrained(
                    model_path,
                    **kwargs,
                )
                break
            except TypeError as exc:
                tokenizer_errors.append(_safe_str(exc))
                continue
            except Exception as exc:
                tokenizer_errors.append(_safe_str(exc))
                continue
        if tokenizer is None:
            raise RuntimeError(tokenizer_errors[-1] if tokenizer_errors else "text_tokenizer_init_failed")

        device = self._torch_device_backend()
        load_errors: list[str] = []
        model = None
        model_loader_name = ""
        for loader_name, loader in (
            ("AutoModelForCausalLM", AutoModelForCausalLM),
            ("AutoModelForSeq2SeqLM", AutoModelForSeq2SeqLM),
        ):
            try:
                model = loader.from_pretrained(
                    model_path,
                    local_files_only=True,
                    trust_remote_code=False,
                )
                model_loader_name = loader_name
                break
            except Exception as exc:
                load_errors.append(f"{loader_name}:{_safe_str(exc)}")
                continue
        if model is None:
            raise RuntimeError(load_errors[-1] if load_errors else "text_model_init_failed")

        model.eval()
        model.to(device)

        config = getattr(model, "config", None)
        context_window = 0
        for attr in (
            "max_position_embeddings",
            "n_positions",
            "max_sequence_length",
            "seq_length",
            "max_source_positions",
        ):
            raw_value = getattr(config, attr, None) if config is not None else None
            if isinstance(raw_value, int) and raw_value > 0:
                context_window = int(raw_value)
                break

        pad_token_id = getattr(tokenizer, "pad_token_id", None)
        eos_token_id = getattr(tokenizer, "eos_token_id", None)
        if not isinstance(pad_token_id, int) or pad_token_id < 0:
            if isinstance(eos_token_id, int) and eos_token_id >= 0:
                pad_token_id = int(eos_token_id)
            else:
                pad_token_id = 0

        now = time.time()
        out = {
            "tokenizer": tokenizer,
            "model": model,
            "device": device,
            "model_loader": model_loader_name,
            "is_encoder_decoder": bool(getattr(config, "is_encoder_decoder", False))
            or model_loader_name == "AutoModelForSeq2SeqLM",
            "context_window": context_window,
            "pad_token_id": max(0, _safe_int(pad_token_id, 0)),
            "eos_token_id": max(-1, _safe_int(eos_token_id, -1)),
            "model_id": model_id,
            "model_path": model_path,
            "instance_key": _safe_str(instance_key),
            "load_profile_hash": _safe_str(load_profile_hash),
            "task_kinds": [TEXT_TASK_KIND],
            "effective_context_length": max(0, int(effective_context_length or 0)),
            "max_context_length": max(0, int(max_context_length or 0)),
            "effective_load_profile": dict(effective_load_profile or {}),
            "loaded_at": now,
            "last_used_at": now,
            "residency": "resident",
            "residency_scope": self.residency_scope(),
        }
        self._text_model_cache[cache_key] = out
        return out

    def _load_embedding_runtime(
        self,
        *,
        model_id: str,
        model_path: str,
        instance_key: str = "",
        load_profile_hash: str = "",
        effective_context_length: int = 0,
        max_context_length: int = 0,
        effective_load_profile: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        cache_key = _safe_str(instance_key) or model_path or model_id
        cached = self._embedding_model_cache.get(cache_key)
        if cached:
            return self._touch_cache_entry(
                cached,
                task_kinds=[EMBED_TASK_KIND],
                effective_context_length=effective_context_length,
                max_context_length=max_context_length,
                effective_load_profile=effective_load_profile,
            )

        import torch  # type: ignore
        from transformers import AutoModel, AutoTokenizer  # type: ignore

        device = self._torch_device_backend()
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
            "max_context_length": max(0, int(max_context_length or 0)),
            "effective_load_profile": dict(effective_load_profile or {}),
            "loaded_at": now,
            "last_used_at": now,
            "residency": "resident",
            "residency_scope": self.residency_scope(),
        }
        self._embedding_model_cache[cache_key] = out
        return out

    def _message_text_content(self, message: dict[str, Any]) -> str:
        content_rows = message.get("content") if isinstance(message.get("content"), list) else []
        lines = [
            _safe_str(item.get("text"))
            for item in content_rows
            if isinstance(item, dict) and _safe_str(item.get("type")).lower() == "text" and _safe_str(item.get("text"))
        ]
        return "\n".join(lines).strip()

    def _build_text_prompt(self, *, tokenizer: Any, messages: list[dict[str, Any]]) -> str:
        template_messages = []
        for message in messages:
            if not isinstance(message, dict):
                continue
            text = self._message_text_content(message)
            if not text:
                continue
            template_messages.append(
                {
                    "role": _safe_str(message.get("role")).lower() or "user",
                    "content": text,
                }
            )
        if hasattr(tokenizer, "apply_chat_template") and template_messages:
            try:
                templated = tokenizer.apply_chat_template(
                    template_messages,
                    tokenize=False,
                    add_generation_prompt=True,
                )
                if _safe_str(templated):
                    return _safe_str(templated)
            except TypeError:
                try:
                    templated = tokenizer.apply_chat_template(
                        template_messages,
                        tokenize=False,
                    )
                    if _safe_str(templated):
                        return _safe_str(templated)
                except Exception:
                    pass
            except Exception:
                pass

        lines: list[str] = []
        last_role = ""
        for message in template_messages:
            role = _safe_str(message.get("role")).lower() or "user"
            text = _safe_str(message.get("content"))
            if not text:
                continue
            last_role = role
            label = {
                "system": "System",
                "assistant": "Assistant",
                "user": "User",
            }.get(role, role.title() or "User")
            lines.append(f"{label}: {text}")
        if lines and last_role != "assistant":
            lines.append("Assistant:")
        return "\n\n".join(lines).strip()

    def _run_real_text_generate(
        self,
        *,
        model_id: str,
        model_path: str,
        instance_key: str,
        load_profile_hash: str,
        effective_context_length: int,
        max_context_length: int,
        effective_load_profile: dict[str, Any] | None,
        messages: list[dict[str, Any]],
        max_new_tokens: int,
        temperature: float,
        request: dict[str, Any],
    ) -> tuple[str, int, int, str, str]:
        import torch  # type: ignore

        runtime = self._load_text_runtime(
            model_id=model_id,
            model_path=model_path,
            instance_key=instance_key,
            load_profile_hash=load_profile_hash,
            effective_context_length=effective_context_length,
            max_context_length=max_context_length,
            effective_load_profile=effective_load_profile,
        )
        tokenizer = runtime["tokenizer"]
        model = runtime["model"]
        device = _safe_str(runtime.get("device")) or "cpu"
        prompt_text = self._build_text_prompt(tokenizer=tokenizer, messages=messages)
        if not prompt_text:
            raise RuntimeError("missing_prompt_text")

        context_window = max(
            0,
            _safe_int(runtime.get("context_window"), 0),
            max_context_length,
            effective_context_length,
        )
        prompt_token_budget = max(32, min(4096, context_window)) if context_window > 0 else 2048
        if context_window > max_new_tokens:
            prompt_token_budget = max(32, min(prompt_token_budget, context_window - max_new_tokens))

        encoded = tokenizer(
            prompt_text,
            return_tensors="pt",
            truncation=True,
            max_length=prompt_token_budget,
        )
        if not isinstance(encoded, dict) and hasattr(encoded, "items"):
            encoded = dict(encoded)
        if not isinstance(encoded, dict):
            raise RuntimeError("text_tokenizer_output_invalid")
        encoded = {
            key: value.to(device) if hasattr(value, "to") else value
            for key, value in encoded.items()
        }

        generation_kwargs: dict[str, Any] = {
            "max_new_tokens": max_new_tokens,
            "do_sample": temperature > 0.0,
        }
        if temperature > 0.0:
            generation_kwargs["temperature"] = temperature
            top_p = _safe_float(request.get("top_p") or request.get("topP"), 0.95)
            if 0.0 < top_p <= 1.0:
                generation_kwargs["top_p"] = top_p
            top_k = max(0, _safe_int(request.get("top_k") or request.get("topK"), 0))
            if top_k > 0:
                generation_kwargs["top_k"] = top_k
        pad_token_id = max(0, _safe_int(runtime.get("pad_token_id"), 0))
        eos_token_id = _safe_int(runtime.get("eos_token_id"), -1)
        if pad_token_id > 0:
            generation_kwargs["pad_token_id"] = pad_token_id
        if eos_token_id >= 0:
            generation_kwargs["eos_token_id"] = eos_token_id

        with torch.no_grad():
            generated = model.generate(
                **encoded,
                **generation_kwargs,
            )

        is_encoder_decoder = _safe_bool(runtime.get("is_encoder_decoder"), False)
        completion_only = generated if is_encoder_decoder else self._trim_generated_prompt_tokens(
            generated,
            prepared_inputs=encoded,
        )
        text = self._decode_generated_text(
            processor=tokenizer,
            generated=completion_only,
            prepared_inputs={},
        ).strip()
        if not text:
            raise RuntimeError("empty_text_generation")

        input_ids = encoded.get("input_ids")
        prompt_tokens = 0
        shape = getattr(input_ids, "shape", None)
        if shape and len(shape) >= 2:
            prompt_tokens = max(0, _safe_int(shape[-1], 0))
        elif isinstance(input_ids, list) and input_ids and isinstance(input_ids[0], list):
            prompt_tokens = len(input_ids[0])

        completion_tokens = 0
        completion_shape = getattr(completion_only, "shape", None)
        if completion_shape and len(completion_shape) >= 2:
            completion_tokens = max(0, _safe_int(completion_shape[-1], 0))
        elif isinstance(completion_only, list) and completion_only and isinstance(completion_only[0], list):
            completion_tokens = len(completion_only[0])
        elif isinstance(completion_only, list):
            completion_tokens = len(completion_only)
        if text and completion_tokens <= 0:
            completion_tokens = 1

        finish_reason = "length" if completion_tokens >= max_new_tokens else "stop"
        return text, prompt_tokens, completion_tokens, device, finish_reason

    def _run_real_embedding(
        self,
        *,
        model_id: str,
        model_path: str,
        instance_key: str,
        load_profile_hash: str,
        effective_context_length: int,
        max_context_length: int,
        effective_load_profile: dict[str, Any] | None,
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
            max_context_length=max_context_length,
            effective_load_profile=effective_load_profile,
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
        max_context_length: int,
        effective_load_profile: dict[str, Any] | None,
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
            max_context_length=max_context_length,
            effective_load_profile=effective_load_profile,
        )
        pipe = runtime["pipeline"]
        call_kwargs: dict[str, Any] = {}
        if timestamps:
            call_kwargs["return_timestamps"] = True
        if language:
            call_kwargs["generate_kwargs"] = {"language": language}
        raw_audio: Any = list(audio_meta.get("samples") or [])
        try:
            import numpy as np  # type: ignore

            raw_audio = np.asarray(raw_audio, dtype="float32")
        except Exception:
            pass
        result = pipe(
            {
                "raw": raw_audio,
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

    def _default_image_prompt(self, *, task_kind: str, prompt: str) -> str:
        cleaned = _safe_str(prompt)
        if cleaned:
            return cleaned
        if task_kind == OCR_TASK_KIND:
            return "Extract all visible text as plain text."
        return "Describe the image."

    def _build_image_task_route_trace(
        self,
        *,
        task_kind: str,
        image_input: dict[str, Any],
        runtime_ready: bool,
        helper_bridge_ready: bool,
        allow_vision_fallback: bool,
        execution_path: str = "",
        blocked_reason_code: str = "",
        fallback_mode: str = "",
    ) -> dict[str, Any]:
        row = image_input if isinstance(image_input, dict) else {}
        image_paths = [path for path in _value_list(row.get("image_paths")) if _safe_str(path)]
        if not image_paths and _safe_str(row.get("image_path")):
            image_paths.append(_safe_str(row.get("image_path")))
        multimodal_messages = row.get("multimodal_messages") if isinstance(row.get("multimodal_messages"), list) else []
        out = {
            "schemaVersion": IMAGE_TASK_ROUTE_TRACE_SCHEMA_VERSION,
            "selectedTaskKind": _safe_str(task_kind),
            "selectionReason": "direct_task_request",
            "imageCount": len(image_paths),
            "imageFiles": [os.path.basename(path) for path in image_paths if _safe_str(path)],
            "multimodalMessageCount": len(multimodal_messages),
            "messageRoles": [
                _safe_str(message.get("role")).lower() or "user"
                for message in multimodal_messages
                if isinstance(message, dict)
            ],
            "promptChars": len(_safe_str(row.get("prompt"))),
            "inputSensitivity": _safe_str(row.get("input_sensitivity")).lower(),
            "helperBridgeReady": bool(helper_bridge_ready),
            "runtimeReady": bool(runtime_ready),
            "fallbackAllowed": bool(allow_vision_fallback),
        }
        if image_paths:
            out["primaryImageFile"] = os.path.basename(image_paths[0])
        if execution_path:
            out["executionPath"] = _safe_str(execution_path)
        if blocked_reason_code:
            out["blockedReasonCode"] = _safe_str(blocked_reason_code)
        if fallback_mode:
            out["fallbackMode"] = _safe_str(fallback_mode)
        return out

    def _multimodal_message_image_count(self, multimodal_messages: list[dict[str, Any]] | None) -> int:
        count = 0
        for raw_message in multimodal_messages if isinstance(multimodal_messages, list) else []:
            if not isinstance(raw_message, dict):
                continue
            for item in raw_message.get("content") if isinstance(raw_message.get("content"), list) else []:
                if not isinstance(item, dict):
                    continue
                if _safe_str(item.get("type")).lower() == "image":
                    count += 1
        return count

    def _select_multimodal_messages_for_image_index(
        self,
        validated: dict[str, Any],
        *,
        image_index: int,
    ) -> list[dict[str, Any]]:
        raw_multimodal_messages = validated.get("multimodal_messages")
        if not isinstance(raw_multimodal_messages, list) or not raw_multimodal_messages:
            return []
        image_count = max(0, _safe_int(validated.get("image_count"), 0))
        if self._multimodal_message_image_count(raw_multimodal_messages) != image_count:
            return []
        selected_messages: list[dict[str, Any]] = []
        current_image_index = 0
        matched = False
        for raw_message in raw_multimodal_messages:
            if not isinstance(raw_message, dict):
                continue
            role = _safe_str(raw_message.get("role")).lower() or "user"
            content_rows: list[dict[str, Any]] = []
            for raw_item in raw_message.get("content") if isinstance(raw_message.get("content"), list) else []:
                if not isinstance(raw_item, dict):
                    continue
                item_type = _safe_str(raw_item.get("type")).lower()
                if item_type == "text":
                    text = _safe_str(raw_item.get("text"))
                    if text:
                        content_rows.append({"type": "text", "text": text})
                    continue
                if item_type != "image":
                    continue
                if current_image_index == image_index:
                    image_path = _safe_str(raw_item.get("imagePath") or raw_item.get("image_path") or raw_item.get("path"))
                    if image_path:
                        image_row = {
                            "type": "image",
                            "imagePath": image_path,
                        }
                        source_kind = _safe_str(raw_item.get("sourceKind") or raw_item.get("source_kind"))
                        detail = _safe_str(raw_item.get("detail"))
                        if source_kind:
                            image_row["sourceKind"] = source_kind
                        if detail:
                            image_row["detail"] = detail
                        content_rows.append(image_row)
                        matched = True
                current_image_index += 1
            if content_rows:
                selected_messages.append({"role": role, "content": content_rows})
        return selected_messages if matched else []

    def _single_image_request(self, request: dict[str, Any], validated: dict[str, Any], *, image_index: int) -> dict[str, Any]:
        image_items = [
            dict(item)
            for item in list(validated.get("image_items") or [])
            if isinstance(item, dict) and _safe_str(item.get("image_path"))
        ]
        if not image_items:
            image_path = _safe_str(validated.get("image_path"))
            if image_path:
                image_items = [{"image_path": image_path}]
        page_count = max(1, len(image_items))
        safe_index = max(0, min(image_index, page_count - 1))
        selected_item = image_items[safe_index]
        selected_image_path = _safe_str(selected_item.get("image_path"))
        page_request = dict(request or {})
        page_request["image_path"] = selected_image_path
        page_request["image_paths"] = [selected_image_path] if selected_image_path else []
        page_request["multimodal_messages"] = self._select_multimodal_messages_for_image_index(validated, image_index=safe_index)
        page_request["page_index"] = safe_index
        page_request["page_count"] = page_count
        return page_request

    def _merge_ocr_page_results(
        self,
        *,
        request: dict[str, Any],
        validated: dict[str, Any],
        page_results: list[dict[str, Any]],
        runtime_ready: bool,
        helper_bridge_ready: bool,
        allow_vision_fallback: bool,
        latency_ms: int,
    ) -> dict[str, Any]:
        image_items = [
            dict(item)
            for item in list(validated.get("image_items") or [])
            if isinstance(item, dict)
        ]
        page_count = max(1, len(page_results), len(image_items), _safe_int(validated.get("image_count"), 0))
        combined_text_parts: list[str] = []
        combined_spans: list[dict[str, Any]] = []
        page_execution_paths: list[str] = []
        fallback_modes: list[str] = []

        for page_index, page_result in enumerate(page_results):
            text = _safe_str(page_result.get("text"))
            if text:
                combined_text_parts.append(f"[page {page_index + 1}] {text}".strip())
            page_spans = page_result.get("spans") if isinstance(page_result.get("spans"), list) else []
            default_file_name = ""
            if page_index < len(image_items):
                default_file_name = os.path.basename(_safe_str(image_items[page_index].get("image_path")))
            for span in page_spans:
                if not isinstance(span, dict):
                    continue
                normalized_span = dict(span)
                normalized_span.setdefault("index", len(combined_spans))
                normalized_span.setdefault("pageIndex", page_index)
                normalized_span.setdefault("pageCount", page_count)
                if default_file_name and not _safe_str(normalized_span.get("fileName") or normalized_span.get("file_name")):
                    normalized_span["fileName"] = default_file_name
                combined_spans.append(normalized_span)
            page_route_trace = page_result.get("routeTrace") if isinstance(page_result.get("routeTrace"), dict) else {}
            execution_path = _safe_str(page_route_trace.get("executionPath") or page_route_trace.get("execution_path"))
            if execution_path:
                page_execution_paths.append(execution_path)
            fallback_mode = _safe_str(page_result.get("fallbackMode") or page_result.get("fallback_mode"))
            if fallback_mode:
                fallback_modes.append(fallback_mode)

        execution_path = ""
        if page_execution_paths:
            execution_path = page_execution_paths[0] if all(path == page_execution_paths[0] for path in page_execution_paths) else "page_aware_mixed"
        aggregate_fallback_mode = ""
        if fallback_modes:
            aggregate_fallback_mode = fallback_modes[0] if all(mode == fallback_modes[0] for mode in fallback_modes) else "page_aware_mixed"

        first_result = page_results[0] if page_results else {}
        out = {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": OCR_TASK_KIND,
            "modelId": _safe_str(first_result.get("modelId") or request.get("model_id") or request.get("modelId")),
            "modelPath": _safe_str(first_result.get("modelPath") or request.get("model_path") or request.get("modelPath")),
            "text": "\n\n".join(part for part in combined_text_parts if part).strip(),
            "spans": combined_spans,
            "language": _safe_str(first_result.get("language") or validated.get("language")),
            "latencyMs": latency_ms,
            "deviceBackend": _safe_str(first_result.get("deviceBackend") or first_result.get("device_backend")) or "cpu",
            "fallbackMode": aggregate_fallback_mode,
            "usage": self._image_usage_payload(validated),
        }
        for field in [
            "runtimeReasonCode",
            "runtimeSource",
            "runtimeSourcePath",
            "runtimeResolutionState",
            "fallbackUsed",
            "runtimeHint",
            "runtimeMissingRequirements",
            "runtimeMissingOptionalRequirements",
        ]:
            value = first_result.get(field)
            if value is not None and value != "" and value != []:
                out[field] = value
        out["routeTrace"] = self._build_image_task_route_trace(
            task_kind=OCR_TASK_KIND,
            image_input=validated,
            runtime_ready=runtime_ready,
            helper_bridge_ready=helper_bridge_ready,
            allow_vision_fallback=allow_vision_fallback,
            execution_path=execution_path or "page_aware_unknown",
            fallback_mode=aggregate_fallback_mode,
        )
        out["routeTrace"]["pageAwareSpans"] = True
        out["routeTrace"]["pageCount"] = page_count
        out["routeTrace"]["pageExecutionPaths"] = page_execution_paths
        return out

    def _run_multi_page_ocr_task(
        self,
        *,
        request: dict[str, Any],
        validated: dict[str, Any],
        runtime_ready: bool,
        helper_bridge_ready: bool,
        allow_vision_fallback: bool,
        started_at: float,
    ) -> dict[str, Any]:
        image_items = [
            dict(item)
            for item in list(validated.get("image_items") or [])
            if isinstance(item, dict) and _safe_str(item.get("image_path"))
        ]
        if len(image_items) <= 1:
            return {}

        page_results: list[dict[str, Any]] = []
        for image_index in range(len(image_items)):
            page_request = self._single_image_request(request, validated, image_index=image_index)
            page_result = self._run_image_task(page_request, task_kind=OCR_TASK_KIND)
            if not bool(page_result.get("ok")):
                blocked_reason = _safe_str(
                    page_result.get("reasonCode")
                    or page_result.get("runtimeReasonCode")
                    or page_result.get("error")
                )
                out = dict(page_result)
                out["routeTrace"] = self._build_image_task_route_trace(
                    task_kind=OCR_TASK_KIND,
                    image_input={**validated, "image_index": image_index},
                    runtime_ready=runtime_ready,
                    helper_bridge_ready=helper_bridge_ready,
                    allow_vision_fallback=allow_vision_fallback,
                    execution_path="page_aware_error",
                    blocked_reason_code=blocked_reason,
                    fallback_mode=_safe_str(page_result.get("fallbackMode") or page_result.get("fallback_mode")),
                )
                out["routeTrace"]["pageAwareSpans"] = True
                out["routeTrace"]["pageCount"] = len(image_items)
                out["routeTrace"]["blockedImageIndex"] = image_index
                return out
            page_results.append(page_result)

        latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
        return self._merge_ocr_page_results(
            request=request,
            validated=validated,
            page_results=page_results,
            runtime_ready=runtime_ready,
            helper_bridge_ready=helper_bridge_ready,
            allow_vision_fallback=allow_vision_fallback,
            latency_ms=latency_ms,
        )

    def _image_bbox_spans(self, validated: dict[str, Any], text: str) -> list[dict[str, Any]]:
        if not _safe_str(text):
            return []
        page_index = max(0, _safe_int(validated.get("page_index"), 0))
        page_count = max(1, _safe_int(validated.get("page_count"), 0), _safe_int(validated.get("image_count"), 0))
        image_path = _safe_str(validated.get("image_path"))
        return [
            {
                "index": page_index,
                "pageIndex": page_index,
                "pageCount": page_count,
                "fileName": os.path.basename(image_path) if image_path else "",
                "text": _safe_str(text),
                "bbox": {
                    "x": 0,
                    "y": 0,
                    "width": int(validated.get("image_width") or 0),
                    "height": int(validated.get("image_height") or 0),
                },
            }
        ]

    def _helper_bridge_multimodal_messages(
        self,
        *,
        validated: dict[str, Any],
        task_kind: str,
    ) -> tuple[str, list[dict[str, Any]]]:
        image_paths = [path for path in list(validated.get("image_paths") or []) if _safe_str(path)]
        if not image_paths and _safe_str(validated.get("image_path")):
            image_paths.append(_safe_str(validated.get("image_path")))
        raw_multimodal_messages = validated.get("multimodal_messages")
        if isinstance(raw_multimodal_messages, list) and raw_multimodal_messages:
            helper_messages: list[dict[str, Any]] = []
            helper_image_count = 0
            for raw_message in raw_multimodal_messages:
                if not isinstance(raw_message, dict):
                    continue
                role = _safe_str(raw_message.get("role")).lower() or "user"
                raw_content = raw_message.get("content") if isinstance(raw_message.get("content"), list) else []
                content_rows: list[dict[str, Any]] = []
                for item in raw_content:
                    if not isinstance(item, dict):
                        continue
                    item_type = _safe_str(item.get("type")).lower()
                    if item_type == "text":
                        text = _safe_str(item.get("text"))
                        if text:
                            content_rows.append({"type": "text", "text": text})
                        continue
                    if item_type != "image":
                        continue
                    image_data_url = encode_helper_image_data_url(_safe_str(item.get("imagePath") or item.get("image_path")))
                    if not image_data_url:
                        return "image_encode_failed", []
                    content_rows.append({"type": "image_url", "image_url": {"url": image_data_url}})
                    helper_image_count += 1
                if content_rows:
                    helper_messages.append({"role": role, "content": content_rows})
            if helper_messages and helper_image_count == len(image_paths):
                return "", helper_messages

        prompt = self._default_image_prompt(
            task_kind=task_kind,
            prompt=_safe_str(validated.get("prompt")),
        )
        content_rows: list[dict[str, Any]] = []
        if prompt:
            content_rows.append({"type": "text", "text": prompt})
        for image_path in image_paths:
            image_data_url = encode_helper_image_data_url(image_path)
            if not image_data_url:
                return "image_encode_failed", []
            content_rows.append({"type": "image_url", "image_url": {"url": image_data_url}})
        if not content_rows:
            return "image_encode_failed", []
        return "", [{"role": "user", "content": content_rows}]

    def _prepare_image_inputs(
        self,
        *,
        processor: Any,
        task_kind: str,
        images: list[Any],
        prompt: str,
        multimodal_messages: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        prompt_text = self._default_image_prompt(task_kind=task_kind, prompt=prompt)
        image_rows = [image for image in list(images or []) if image is not None]
        if not image_rows:
            raise RuntimeError("missing_image_input")
        errors: list[str] = []
        template_messages: list[dict[str, Any]] = []
        raw_multimodal_messages = multimodal_messages if isinstance(multimodal_messages, list) else []
        template_image_count = 0
        for raw_message in raw_multimodal_messages:
            if not isinstance(raw_message, dict):
                continue
            role = _safe_str(raw_message.get("role")).lower() or "user"
            raw_content = raw_message.get("content") if isinstance(raw_message.get("content"), list) else []
            content_rows: list[dict[str, Any]] = []
            for item in raw_content:
                if not isinstance(item, dict):
                    continue
                item_type = _safe_str(item.get("type")).lower()
                if item_type == "text":
                    text = _safe_str(item.get("text"))
                    if text:
                        content_rows.append({"type": "text", "text": text})
                    continue
                if item_type == "image":
                    content_rows.append({"type": "image"})
                    template_image_count += 1
            if content_rows:
                template_messages.append({"role": role, "content": content_rows})
        if template_image_count != len(image_rows):
            template_messages = []
        if not template_messages:
            content_rows = [{"type": "image"} for _ in image_rows]
            if prompt_text:
                content_rows.append({"type": "text", "text": prompt_text})
            template_messages = [{"role": "user", "content": content_rows}]

        primary_image = image_rows[0]
        if hasattr(processor, "apply_chat_template"):
            try:
                templated = processor.apply_chat_template(
                    template_messages,
                    tokenize=False,
                    add_generation_prompt=True,
                )
            except Exception as exc:
                errors.append(_safe_str(exc))
            else:
                attempts: list[dict[str, Any]] = [
                    {"images": image_rows, "text": templated, "return_tensors": "pt"},
                ]
                if len(image_rows) == 1:
                    attempts.append({"images": primary_image, "text": templated, "return_tensors": "pt"})
                for kwargs in attempts:
                    try:
                        prepared = processor(**kwargs)
                    except Exception as exc:
                        errors.append(_safe_str(exc))
                        continue
                    return dict(prepared) if not isinstance(prepared, dict) and hasattr(prepared, "items") else prepared

        attempts: list[dict[str, Any]] = [{"images": image_rows, "text": prompt_text, "return_tensors": "pt"}]
        if len(image_rows) == 1:
            attempts.insert(0, {"images": primary_image, "text": prompt_text, "return_tensors": "pt"})
        if task_kind == OCR_TASK_KIND:
            attempts.append({"images": image_rows, "return_tensors": "pt"})
            if len(image_rows) == 1:
                attempts.append({"images": primary_image, "return_tensors": "pt"})
        for kwargs in attempts:
            try:
                prepared = processor(**kwargs)
            except Exception as exc:
                errors.append(_safe_str(exc))
                continue
            return dict(prepared) if not isinstance(prepared, dict) and hasattr(prepared, "items") else prepared

        raise RuntimeError(errors[-1] if errors else "image_processor_failed")

    def _trim_generated_prompt_tokens(self, generated: Any, *, prepared_inputs: dict[str, Any]) -> Any:
        input_ids = prepared_inputs.get("input_ids")
        prompt_len = 0
        shape = getattr(input_ids, "shape", None)
        if shape and len(shape) >= 2:
            prompt_len = max(0, _safe_int(shape[-1], 0))
        elif isinstance(input_ids, list) and input_ids and isinstance(input_ids[0], list):
            prompt_len = len(input_ids[0])
        if prompt_len <= 0:
            return generated

        generated_shape = getattr(generated, "shape", None)
        if generated_shape and len(generated_shape) >= 2:
            try:
                if _safe_int(generated_shape[-1], 0) > prompt_len:
                    return generated[:, prompt_len:]
            except Exception:
                return generated
        if isinstance(generated, list) and generated and isinstance(generated[0], list):
            return [row[prompt_len:] if len(row) > prompt_len else row for row in generated]
        return generated

    def _decode_generated_text(
        self,
        *,
        processor: Any,
        generated: Any,
        prepared_inputs: dict[str, Any],
    ) -> str:
        decode_targets = [
            self._trim_generated_prompt_tokens(generated, prepared_inputs=prepared_inputs),
            generated,
        ]
        tokenizer = getattr(processor, "tokenizer", None)
        for candidate in decode_targets:
            for decoder_owner, decoder_name in (
                (processor, "batch_decode"),
                (tokenizer, "batch_decode"),
                (processor, "decode"),
                (tokenizer, "decode"),
            ):
                if decoder_owner is None or not hasattr(decoder_owner, decoder_name):
                    continue
                decoder = getattr(decoder_owner, decoder_name)
                try:
                    decoded = decoder(candidate, skip_special_tokens=True)
                except TypeError:
                    try:
                        decoded = decoder(candidate)
                    except Exception:
                        continue
                except Exception:
                    continue

                if isinstance(decoded, list):
                    text = _safe_str(decoded[0] if decoded else "")
                else:
                    text = _safe_str(decoded)
                if text:
                    return text
        return ""

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
        import torch  # type: ignore
        from PIL import Image  # type: ignore

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
        device = _safe_str(runtime.get("device")) or "cpu"
        image_items = [
            dict(item)
            for item in list(validated.get("image_items") or [])
            if isinstance(item, dict) and _safe_str(item.get("image_path"))
        ]
        if not image_items and _safe_str(validated.get("image_path")):
            image_items = [
                {
                    "image_path": _safe_str(validated.get("image_path")),
                }
            ]
        if not image_items:
            raise RuntimeError("missing_image_path")

        with ExitStack() as stack:
            images: list[Any] = []
            for image_item in image_items:
                handle = stack.enter_context(Image.open(_safe_str(image_item.get("image_path"))))
                image = handle.convert("RGB")
                if hasattr(image, "close"):
                    stack.callback(image.close)
                images.append(image)
            prepared_inputs = self._prepare_image_inputs(
                processor=processor,
                task_kind=task_kind,
                images=images,
                prompt=_safe_str(validated.get("prompt")),
                multimodal_messages=list(validated.get("multimodal_messages") or []),
            )

        if hasattr(prepared_inputs, "to"):
            try:
                prepared_inputs = prepared_inputs.to(device)
            except Exception:
                pass
        if not isinstance(prepared_inputs, dict) and hasattr(prepared_inputs, "items"):
            prepared_inputs = dict(prepared_inputs)
        if not isinstance(prepared_inputs, dict):
            raise RuntimeError("image_processor_output_invalid")

        model_inputs = {
            key: value.to(device) if hasattr(value, "to") else value
            for key, value in prepared_inputs.items()
        }
        if not hasattr(model, "generate"):
            raise RuntimeError("image_generate_not_supported")

        max_new_tokens = max(16, min(1024, _safe_int(request.get("max_new_tokens") or request.get("maxNewTokens"), 128)))
        with torch.no_grad():
            generated = model.generate(
                **model_inputs,
                max_new_tokens=max_new_tokens,
                do_sample=False,
            )

        text = self._decode_generated_text(
            processor=processor,
            generated=generated,
            prepared_inputs=model_inputs,
        ).strip()
        if not text:
            raise RuntimeError("empty_image_generation")

        spans: list[dict[str, Any]] = []
        if task_kind == OCR_TASK_KIND:
            spans = self._image_bbox_spans(validated, text)
        return text, spans, device

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

    def _build_tts_system_fallback_output(
        self,
        *,
        base_dir: str,
        model_id: str,
        model_path: str,
        validated: dict[str, Any],
        fallback_reason_code: str = "",
    ) -> dict[str, Any]:
        started_at = time.time()
        say_binary = _tts_say_binary_path()
        if not say_binary:
            raise RuntimeError("tts_system_fallback_unavailable")

        locale = _safe_str(validated.get("locale"))
        voice_color = _safe_str(validated.get("voice_color")).lower() or "neutral"
        speech_rate = _safe_float(validated.get("speech_rate"), 1.0)
        rate_wpm = _tts_system_rate_wpm(speech_rate)
        voice_name = _tts_system_select_voice(
            say_binary,
            locale=locale,
            voice_color=voice_color,
        )
        audio_path = _tts_output_path(base_dir, model_id=model_id, locale=locale)
        text = _safe_str(validated.get("text"))

        command = [say_binary]
        if voice_name:
            command.extend(["-v", voice_name])
        command.extend([
            "-r",
            str(rate_wpm),
            "-o",
            audio_path,
            text,
        ])
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=max(10.0, min(45.0, 6.0 + (len(text) / 48.0))),
        )
        if completed.returncode != 0:
            detail = _safe_str(completed.stderr) or _safe_str(completed.stdout) or f"say_exit_{completed.returncode}"
            raise RuntimeError(detail[:240])
        if not os.path.isfile(audio_path):
            raise RuntimeError("tts_system_fallback_missing_output")
        output_audio_bytes = os.path.getsize(audio_path)
        if output_audio_bytes <= 0:
            raise RuntimeError("tts_system_fallback_empty_output")

        out = {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": TTS_TASK_KIND,
            "modelId": model_id,
            "modelPath": model_path,
            "audioPath": audio_path,
            "audioFormat": "aiff",
            "locale": locale,
            "voiceColor": voice_color,
            "speechRate": round(speech_rate, 3),
            "latencyMs": max(0, int(round((time.time() - started_at) * 1000.0))),
            "engineName": "system_voice_compatibility",
            "deviceBackend": "system_voice_compatibility",
            "nativeTTSUsed": False,
            "fallbackMode": "system_voice_compatibility",
            "usage": {
                **self._tts_usage_payload(validated),
                "outputAudioBytes": output_audio_bytes,
                "outputAudioFormat": "aiff",
            },
        }
        if fallback_reason_code:
            out["fallbackReasonCode"] = fallback_reason_code
        if voice_name:
            out["voiceName"] = voice_name
        return out

    def _image_usage_payload(self, validated: dict[str, Any]) -> dict[str, Any]:
        image_items = [
            dict(item)
            for item in list(validated.get("image_items") or [])
            if isinstance(item, dict)
        ]
        first_item = image_items[0] if image_items else {}
        image_paths = [path for path in list(validated.get("image_paths") or []) if _safe_str(path)]
        image_count = max(
            0,
            _safe_int(validated.get("image_count"), 0),
            len(image_items),
            len(image_paths),
            1 if _safe_str(validated.get("image_path")) else 0,
        )
        return {
            "inputImageCount": image_count,
            "inputImageBytes": int(validated.get("total_image_bytes") or validated.get("file_size_bytes") or 0),
            "inputImageWidth": int(first_item.get("image_width") or validated.get("image_width") or 0),
            "inputImageHeight": int(first_item.get("image_height") or validated.get("image_height") or 0),
            "inputImagePixels": int(validated.get("total_image_pixels") or validated.get("image_pixels") or 0),
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
        image_count = max(1, _safe_int(validated.get("image_count"), 1))
        prompt = _safe_str(validated.get("prompt"))

        if task_kind == OCR_TASK_KIND:
            text = f"[{DEFAULT_OCR_FALLBACK_TEXT_PREFIX}:{digest}]"
            if image_count > 1:
                text = f"{text} image_count={image_count}"
            spans = self._image_bbox_spans(validated, text)
        else:
            text = f"[{DEFAULT_VISION_FALLBACK_TEXT_PREFIX}:{digest}] image_count={image_count} first={width}x{height}"
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
        model_path = _safe_str(model_info.get("model_path"))
        runtime_resolution = self._runtime_resolution(base_dir=base_dir or "", request=request)
        runtime_ready = self._core_runtime_ready(runtime_resolution)
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
        instance_key = _request_instance_key(request)
        load_profile_hash = _request_load_profile_hash(request)
        effective_context_length = _request_effective_context_length(request)
        max_context_length = max(
            0,
            _request_max_context_length(request),
            _safe_int(model_info.get("max_context_length"), 0),
        )
        effective_load_profile = _request_effective_load_profile(request)
        max_length = max(32, min(2048, _safe_int(request.get("max_length"), 512)))
        allow_hash_fallback = _hash_fallback_enabled(request)
        helper_binary = self._helper_bridge_binary_path(runtime_resolution)

        if self._helper_bridge_ready(runtime_resolution) and helper_binary:
            helper_usage = {}
            loaded_row = self._helper_bridge_resolve_instance_row(
                request=request,
                model_info=model_info,
                runtime_resolution=runtime_resolution,
                task_kind=EMBED_TASK_KIND,
            )
            helper_identifier = _safe_str(loaded_row.get("instanceKey")) or instance_key
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
                texts=texts,
                timeout_sec=20.0,
            )
            if bool(helper_result.get("ok")):
                helper_usage = helper_result.get("usage") if isinstance(helper_result.get("usage"), dict) else {}
                vectors = [
                    list(vector)
                    for vector in (helper_result.get("vectors") or [])
                    if isinstance(vector, list)
                ]
                dims = max(0, _safe_int(helper_result.get("dims"), 0))
                latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
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
                    "deviceBackend": self._helper_bridge_device_backend(),
                    "fallbackMode": "",
                    "usage": {
                        "textCount": int(validated.get("text_count") or len(texts)),
                        "totalChars": int(validated.get("total_chars") or 0),
                        "maxTextChars": int(validated.get("max_text_chars") or 0),
                        "inputSanitized": bool(validated.get("input_sanitized")),
                        "promptTokens": max(0, _safe_int(helper_usage.get("prompt_tokens"), 0)),
                        "totalTokens": max(0, _safe_int(helper_usage.get("total_tokens"), 0)),
                    },
                }
            error_detail = _safe_str(helper_result.get("errorDetail"))
            if not allow_hash_fallback:
                helper_reason = _safe_str(helper_result.get("reasonCode") or helper_result.get("error")) or "helper_embedding_failed"
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error="helper_embedding_failed",
                    task_kind=EMBED_TASK_KIND,
                    task_kinds=[EMBED_TASK_KIND],
                    model_id=model_id,
                    model_path=model_path,
                    error_detail=error_detail,
                    reason_code_override=helper_reason,
                    runtime_reason_code_override=helper_reason,
                )

        vectors: list[list[float]] = []
        dims = 0
        device_backend = "cpu"
        fallback_mode = ""
        error_detail = ""

        if runtime_ready and model_path:
            try:
                vectors, dims, device_backend = self._run_real_embedding(
                    model_id=model_id,
                    model_path=model_path,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                    effective_context_length=effective_context_length,
                    max_context_length=max_context_length,
                    effective_load_profile=effective_load_profile,
                    texts=texts,
                    max_length=max_length,
                )
            except Exception as exc:
                error_detail = _safe_str(exc)
                if not allow_hash_fallback:
                    reason_code_override, runtime_reason_code_override = _classify_runtime_failure_reason(
                        error_detail,
                        "embedding_runtime_failed",
                    )
                    return self._runtime_failure_output(
                        request=request,
                        runtime_resolution=runtime_resolution,
                        error="embedding_runtime_failed",
                        task_kind=EMBED_TASK_KIND,
                        task_kinds=[EMBED_TASK_KIND],
                        model_id=model_id,
                        model_path=model_path,
                        error_detail=error_detail,
                        reason_code_override=reason_code_override,
                        runtime_reason_code_override=runtime_reason_code_override,
                    )

        if not vectors:
            if not allow_hash_fallback:
                if not model_path:
                    error_code = "missing_model_path"
                elif not runtime_ready:
                    return self._runtime_failure_output(
                        request=request,
                        runtime_resolution=runtime_resolution,
                        error=self._task_runtime_import_error(
                            runtime_resolution,
                            task_kinds=[EMBED_TASK_KIND],
                        ) or "missing_runtime",
                        task_kind=EMBED_TASK_KIND,
                        task_kinds=[EMBED_TASK_KIND],
                        model_id=model_id,
                        model_path=model_path,
                    )
                else:
                    error_code = "embedding_runtime_failed"
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error=error_code,
                    task_kind=EMBED_TASK_KIND,
                    task_kinds=[EMBED_TASK_KIND],
                    model_id=model_id,
                    model_path=model_path,
                    error_detail=error_detail,
                    reason_code_override=error_code,
                )
            dims = self._hash_fallback_dims(request, model_info=model_info)
            vectors = [
                _deterministic_unit_vector(model_id=model_id, text=text, dims=dims)
                for text in texts
            ]
            device_backend = "cpu_hash"
            fallback_mode = "hash"

        latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
        if base_dir and not fallback_mode and runtime_ready and model_path:
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

    def _run_text_task(self, request: dict[str, Any]) -> dict[str, Any]:
        started_at = time.time()
        base_dir = _request_base_dir(request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        runtime_resolution = self._runtime_resolution(base_dir=base_dir or "", request=request)
        error_code, validated = self._validate_text_request(request, model_info=model_info)
        if error_code:
            out = {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": TEXT_TASK_KIND,
                "modelId": model_id,
                "modelPath": model_path,
                "error": error_code,
                "request": dict(request or {}),
            }
            out["usage"] = self._text_usage_payload(validated)
            return out

        helper_binary = self._helper_bridge_binary_path(runtime_resolution)
        instance_key = _request_instance_key(request)
        load_profile_hash = _request_load_profile_hash(request)
        effective_context_length = _request_effective_context_length(request)
        max_context_length = max(
            0,
            _request_max_context_length(request),
            _safe_int(model_info.get("max_context_length"), 0),
        )
        effective_load_profile = _request_effective_load_profile(request)
        runtime_ready = self._core_runtime_ready(runtime_resolution)
        if self._helper_bridge_ready(runtime_resolution) and helper_binary:
            loaded_row = self._helper_bridge_resolve_instance_row(
                request=request,
                model_info=model_info,
                runtime_resolution=runtime_resolution,
                task_kind=TEXT_TASK_KIND,
            )
            helper_identifier = _safe_str(loaded_row.get("instanceKey")) or instance_key
            if not helper_identifier:
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error="helper_model_not_loaded",
                    task_kind=TEXT_TASK_KIND,
                    task_kinds=[TEXT_TASK_KIND],
                    model_id=model_id,
                    model_path=model_path,
                    usage=self._text_usage_payload(validated),
                    reason_code_override="helper_model_not_loaded",
                    runtime_reason_code_override="helper_model_not_loaded",
                )
            helper_result = helper_bridge_chat_completion(
                helper_binary,
                identifier=helper_identifier,
                messages=list(validated.get("messages") or []),
                max_tokens=max(
                    16,
                    min(
                        2048,
                        _safe_int(
                            request.get("max_new_tokens")
                            or request.get("maxNewTokens")
                            or request.get("max_tokens")
                            or request.get("maxTokens"),
                            128,
                        ),
                    ),
                ),
                temperature=_safe_float(request.get("temperature"), 0.0),
                timeout_sec=20.0,
            )
            if bool(helper_result.get("ok")):
                helper_usage = helper_result.get("usage") if isinstance(helper_result.get("usage"), dict) else {}
                latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
                return {
                    "ok": True,
                    "provider": self.provider_id(),
                    "taskKind": TEXT_TASK_KIND,
                    "modelId": model_id,
                    "modelPath": model_path,
                    "text": _safe_str(helper_result.get("text")),
                    "latencyMs": latency_ms,
                    "deviceBackend": self._helper_bridge_device_backend(),
                    "fallbackMode": "",
                    "finishReason": _safe_str(helper_result.get("finishReason")),
                    "usage": {
                        **self._text_usage_payload(validated),
                        "promptTokens": max(0, _safe_int(helper_usage.get("prompt_tokens"), 0)),
                        "completionTokens": max(0, _safe_int(helper_usage.get("completion_tokens"), 0)),
                        "totalTokens": max(0, _safe_int(helper_usage.get("total_tokens"), 0)),
                    },
                }
            helper_reason = _safe_str(helper_result.get("reasonCode") or helper_result.get("error")) or "helper_chat_failed"
            return self._runtime_failure_output(
                request=request,
                runtime_resolution=runtime_resolution,
                error="helper_chat_failed",
                task_kind=TEXT_TASK_KIND,
                task_kinds=[TEXT_TASK_KIND],
                model_id=model_id,
                model_path=model_path,
                error_detail=_safe_str(helper_result.get("errorDetail")),
                usage=self._text_usage_payload(validated),
                reason_code_override=helper_reason,
                runtime_reason_code_override=helper_reason,
            )

        max_new_tokens = max(
            16,
            min(
                2048,
                _safe_int(
                    request.get("max_new_tokens")
                    or request.get("maxNewTokens")
                    or request.get("max_tokens")
                    or request.get("maxTokens"),
                    128,
                ),
            ),
        )
        temperature = max(
            0.0,
            min(
                2.0,
                _safe_float(request.get("temperature"), 0.0),
            ),
        )
        if runtime_ready and model_path:
            try:
                text, prompt_tokens, completion_tokens, device_backend, finish_reason = self._run_real_text_generate(
                    model_id=model_id,
                    model_path=model_path,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                    effective_context_length=effective_context_length,
                    max_context_length=max_context_length,
                    effective_load_profile=effective_load_profile,
                    messages=list(validated.get("messages") or []),
                    max_new_tokens=max_new_tokens,
                    temperature=temperature,
                    request=request,
                )
            except Exception as exc:
                error_detail = _safe_str(exc)
                reason_code_override, runtime_reason_code_override = _classify_runtime_failure_reason(
                    error_detail,
                    "text_generation_runtime_failed",
                )
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error="text_generation_runtime_failed",
                    task_kind=TEXT_TASK_KIND,
                    task_kinds=[TEXT_TASK_KIND],
                    model_id=model_id,
                    model_path=model_path,
                    error_detail=error_detail,
                    usage=self._text_usage_payload(validated),
                    reason_code_override=reason_code_override,
                    runtime_reason_code_override=runtime_reason_code_override,
                )
            latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
            if base_dir:
                self._sync_process_local_state(base_dir=base_dir)
            return {
                "ok": True,
                "provider": self.provider_id(),
                "taskKind": TEXT_TASK_KIND,
                "modelId": model_id,
                "modelPath": model_path,
                "text": text,
                "latencyMs": latency_ms,
                "deviceBackend": device_backend,
                "fallbackMode": "",
                "finishReason": finish_reason,
                "usage": {
                    **self._text_usage_payload(validated),
                    "promptTokens": prompt_tokens,
                    "completionTokens": completion_tokens,
                    "totalTokens": prompt_tokens + completion_tokens,
                },
            }

        error_code = "missing_model_path"
        reason_code_override = "missing_model_path"
        runtime_reason_code_override = ""
        if model_path:
            error_code = self._task_runtime_import_error(
                runtime_resolution,
                task_kinds=[TEXT_TASK_KIND],
            ) or "missing_runtime"
            reason_code_override = ""
        return self._runtime_failure_output(
            request=request,
            runtime_resolution=runtime_resolution,
            error=error_code,
            task_kind=TEXT_TASK_KIND,
            task_kinds=[TEXT_TASK_KIND],
            model_id=model_id,
            model_path=model_path,
            usage=self._text_usage_payload(validated),
            reason_code_override=reason_code_override,
            runtime_reason_code_override=runtime_reason_code_override,
        )

    def _run_tts_task(self, request: dict[str, Any]) -> dict[str, Any]:
        base_dir = _request_base_dir(request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        runtime_resolution = self._runtime_resolution(base_dir=base_dir or "", request=request)
        error_code, validated = self._validate_tts_request(request, model_info=model_info)
        if error_code:
            out = {
                "ok": False,
                "provider": self.provider_id(),
                "taskKind": TTS_TASK_KIND,
                "modelId": model_id,
                "modelPath": model_path,
                "error": error_code,
                "request": dict(request or {}),
            }
            out["usage"] = self._tts_usage_payload(validated)
            return out

        return self._run_tts_task_native_or_fallback(
            request=request,
            runtime_resolution=runtime_resolution,
            model_info=model_info,
            validated=validated,
        )

    def _decorate_tts_result(
        self,
        result: dict[str, Any],
        *,
        engine_name: str = "",
        speaker_id: str = "",
        native_tts_used: bool | None = None,
        fallback_mode: str | None = None,
        fallback_reason_code: str = "",
    ) -> dict[str, Any]:
        out = dict(result or {})
        if engine_name and not _safe_str(out.get("engineName") or out.get("engine_name")):
            out["engineName"] = engine_name
        if speaker_id and not _safe_str(out.get("speakerId") or out.get("speaker_id")):
            out["speakerId"] = speaker_id
        if native_tts_used is not None and out.get("nativeTTSUsed") is None and out.get("native_tts_used") is None:
            out["nativeTTSUsed"] = bool(native_tts_used)
        if fallback_mode is not None and out.get("fallbackMode") is None and out.get("fallback_mode") is None:
            out["fallbackMode"] = _safe_str(fallback_mode)
        if fallback_reason_code and not _safe_str(out.get("fallbackReasonCode") or out.get("fallback_reason_code")):
            out["fallbackReasonCode"] = fallback_reason_code
        return out

    def _run_tts_task_native(
        self,
        *,
        request: dict[str, Any],
        runtime_resolution: Any,
        model_info: dict[str, Any],
        validated: dict[str, Any],
    ) -> dict[str, Any]:
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        engine_name = _infer_tts_native_engine_name(model_info)
        if not engine_name:
            return self._decorate_tts_result(
                self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error=f"task_not_implemented:{self.provider_id()}:{TTS_TASK_KIND}",
                    task_kind=TTS_TASK_KIND,
                    task_kinds=[TTS_TASK_KIND],
                    model_id=model_id,
                    model_path=model_path,
                    usage=self._tts_usage_payload(validated),
                    reason_code_override="tts_native_engine_not_supported",
                    runtime_reason_code_override="tts_native_engine_not_supported",
                ),
                native_tts_used=False,
                fallback_mode="",
            )

        if engine_name == "kokoro":
            try:
                result = synthesize_kokoro_to_file(
                    base_dir=_request_base_dir(request),
                    model_id=model_id,
                    model_path=model_path,
                    text=_safe_str(validated.get("text")),
                    locale=_safe_str(validated.get("locale")),
                    voice_color=_safe_str(validated.get("voice_color")),
                    speech_rate=_safe_float(validated.get("speech_rate"), 1.0),
                )
                usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}
                result["usage"] = {
                    **self._tts_usage_payload(validated),
                    **usage,
                }
                return self._decorate_tts_result(
                    result,
                    engine_name="kokoro",
                    speaker_id=_safe_str(result.get("speakerId") or result.get("speaker_id")),
                    native_tts_used=True,
                    fallback_mode="",
                )
            except KokoroSynthesisError as exc:
                reason_code = _safe_str(exc.reason_code) or "text_to_speech_runtime_unavailable"
                error_code = "tts_native_runtime_failed"
                if reason_code in {"tts_native_engine_not_supported", "text_to_speech_runtime_unavailable"}:
                    error_code = f"task_not_implemented:{self.provider_id()}:{TTS_TASK_KIND}"
                return self._decorate_tts_result(
                    self._runtime_failure_output(
                        request=request,
                        runtime_resolution=runtime_resolution,
                        error=error_code,
                        task_kind=TTS_TASK_KIND,
                        task_kinds=[TTS_TASK_KIND],
                        model_id=model_id,
                        model_path=model_path,
                        usage=self._tts_usage_payload(validated),
                        error_detail=exc.detail,
                        reason_code_override=reason_code,
                        runtime_reason_code_override=reason_code,
                    ),
                    engine_name="kokoro",
                    native_tts_used=False,
                    fallback_mode="",
                )

        if not self._core_runtime_ready(runtime_resolution):
            return self._decorate_tts_result(
                self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error=self._task_runtime_import_error(
                        runtime_resolution,
                        task_kinds=[TTS_TASK_KIND],
                    ) or "missing_runtime",
                    task_kind=TTS_TASK_KIND,
                    task_kinds=[TTS_TASK_KIND],
                    model_id=model_id,
                    model_path=model_path,
                    usage=self._tts_usage_payload(validated),
                ),
                engine_name=engine_name,
                native_tts_used=False,
                fallback_mode="",
            )

        return self._decorate_tts_result(
            self._runtime_failure_output(
                request=request,
                runtime_resolution=runtime_resolution,
                error=f"task_not_implemented:{self.provider_id()}:{TTS_TASK_KIND}",
                task_kind=TTS_TASK_KIND,
                task_kinds=[TTS_TASK_KIND],
                model_id=model_id,
                model_path=model_path,
                usage=self._tts_usage_payload(validated),
                reason_code_override="text_to_speech_runtime_unavailable",
                runtime_reason_code_override="text_to_speech_runtime_unavailable",
            ),
            engine_name=engine_name,
            native_tts_used=False,
            fallback_mode="",
        )

    def _run_tts_task_native_or_fallback(
        self,
        *,
        request: dict[str, Any],
        runtime_resolution: Any,
        model_info: dict[str, Any],
        validated: dict[str, Any],
    ) -> dict[str, Any]:
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        native_result = self._run_tts_task_native(
            request=request,
            runtime_resolution=runtime_resolution,
            model_info=model_info,
            validated=validated,
        )
        if bool(native_result.get("ok")):
            return self._decorate_tts_result(
                native_result,
                native_tts_used=True,
                fallback_mode="",
            )

        fallback_reason_code = (
            _safe_str(native_result.get("reasonCode"))
            or _safe_str(native_result.get("runtimeReasonCode"))
            or _safe_str(native_result.get("error"))
            or "text_to_speech_runtime_unavailable"
        )
        if _tts_system_fallback_available(request):
            try:
                return self._build_tts_system_fallback_output(
                    base_dir=_request_base_dir(request),
                    model_id=model_id,
                    model_path=model_path,
                    validated=validated,
                    fallback_reason_code=fallback_reason_code,
                )
            except Exception as exc:
                error_detail = _safe_str(exc)
                return self._decorate_tts_result(
                    {
                        "ok": False,
                        "provider": self.provider_id(),
                        "taskKind": TTS_TASK_KIND,
                        "taskKinds": [TTS_TASK_KIND],
                        "modelId": model_id,
                        "modelPath": model_path,
                        "error": "tts_system_fallback_failed",
                        "reasonCode": "tts_system_fallback_failed",
                        "runtimeReasonCode": "tts_system_fallback_failed",
                        "errorDetail": error_detail[:240],
                        "usage": self._tts_usage_payload(validated),
                    },
                    native_tts_used=False,
                    fallback_mode="",
                    fallback_reason_code=fallback_reason_code,
                )

        return native_result

    def _run_asr_task(self, request: dict[str, Any]) -> dict[str, Any]:
        started_at = time.time()
        base_dir = _request_base_dir(request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        runtime_resolution = self._runtime_resolution(base_dir=base_dir or "", request=request)
        runtime_ready = self._core_runtime_ready(runtime_resolution)
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

        allow_asr_fallback = _asr_fallback_enabled(request)
        instance_key = _request_instance_key(request)
        load_profile_hash = _request_load_profile_hash(request)
        effective_context_length = _request_effective_context_length(request)
        max_context_length = max(
            0,
            _request_max_context_length(request),
            _safe_int(model_info.get("max_context_length"), 0),
        )
        effective_load_profile = _request_effective_load_profile(request)
        error_detail = ""
        text = ""
        segments: list[dict[str, Any]] = []
        device_backend = "cpu"
        fallback_mode = ""

        if runtime_ready and model_path:
            try:
                text, segments, device_backend = self._run_real_asr(
                    model_id=model_id,
                    model_path=model_path,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                    effective_context_length=effective_context_length,
                    max_context_length=max_context_length,
                    effective_load_profile=effective_load_profile,
                    audio_meta=validated,
                    language=_safe_str(validated.get("language")),
                    timestamps=bool(validated.get("timestamps")),
                )
            except Exception as exc:
                error_detail = _safe_str(exc)
                if not allow_asr_fallback:
                    reason_code_override, runtime_reason_code_override = _classify_runtime_failure_reason(
                        error_detail,
                        "speech_to_text_runtime_failed",
                    )
                    return self._runtime_failure_output(
                        request=request,
                        runtime_resolution=runtime_resolution,
                        error="speech_to_text_runtime_failed",
                        task_kind=ASR_TASK_KIND,
                        task_kinds=[ASR_TASK_KIND],
                        model_id=model_id,
                        model_path=model_path,
                        error_detail=error_detail,
                        usage={
                            "inputAudioBytes": int(validated.get("file_size_bytes") or 0),
                            "inputAudioSec": round(_safe_float(validated.get("duration_sec"), 0.0), 6),
                            "sampleRate": int(validated.get("sample_rate") or 0),
                            "channelCount": int(validated.get("channel_count") or 0),
                            "timestampsRequested": bool(validated.get("timestamps")),
                        },
                        reason_code_override=reason_code_override,
                        runtime_reason_code_override=runtime_reason_code_override,
                    )

        if not text and not segments:
            if not allow_asr_fallback:
                if not model_path:
                    error_code = "missing_model_path"
                elif not runtime_ready:
                    return self._runtime_failure_output(
                        request=request,
                        runtime_resolution=runtime_resolution,
                        error=self._task_runtime_import_error(
                            runtime_resolution,
                            task_kinds=[ASR_TASK_KIND],
                        ) or "missing_runtime",
                        task_kind=ASR_TASK_KIND,
                        task_kinds=[ASR_TASK_KIND],
                        model_id=model_id,
                        model_path=model_path,
                        usage={
                            "inputAudioBytes": int(validated.get("file_size_bytes") or 0),
                            "inputAudioSec": round(_safe_float(validated.get("duration_sec"), 0.0), 6),
                            "sampleRate": int(validated.get("sample_rate") or 0),
                            "channelCount": int(validated.get("channel_count") or 0),
                            "timestampsRequested": bool(validated.get("timestamps")),
                        },
                    )
                else:
                    error_code = "speech_to_text_runtime_failed"
                return self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error=error_code,
                    task_kind=ASR_TASK_KIND,
                    task_kinds=[ASR_TASK_KIND],
                    model_id=model_id,
                    model_path=model_path,
                    error_detail=error_detail,
                    usage={
                        "inputAudioBytes": int(validated.get("file_size_bytes") or 0),
                        "inputAudioSec": round(_safe_float(validated.get("duration_sec"), 0.0), 6),
                        "sampleRate": int(validated.get("sample_rate") or 0),
                        "channelCount": int(validated.get("channel_count") or 0),
                        "timestampsRequested": bool(validated.get("timestamps")),
                    },
                    reason_code_override=error_code,
                )

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
        if base_dir and not fallback_mode and runtime_ready and model_path:
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
        base_dir = _request_base_dir(request)
        if base_dir:
            self._ensure_process_local_tracking(base_dir=base_dir)
        model_info = self._resolve_model_info(request)
        model_id = _safe_str(model_info.get("model_id"))
        model_path = _safe_str(model_info.get("model_path"))
        runtime_resolution = self._runtime_resolution(base_dir=base_dir or "", request=request)
        runtime_ready = self._image_runtime_ready(runtime_resolution)
        raw_image_input = self._extract_image_input(request)
        allow_vision_fallback = _vision_fallback_enabled(request)
        helper_binary = self._helper_bridge_binary_path(runtime_resolution)
        helper_bridge_ready = self._helper_bridge_ready(runtime_resolution) and bool(helper_binary)
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
            out["routeTrace"] = self._build_image_task_route_trace(
                task_kind=task_kind,
                image_input={**raw_image_input, **validated},
                runtime_ready=runtime_ready,
                helper_bridge_ready=helper_bridge_ready,
                allow_vision_fallback=allow_vision_fallback,
                execution_path="validation_error",
                blocked_reason_code=error_code,
            )
            return out

        if task_kind == OCR_TASK_KIND and max(0, _safe_int(validated.get("image_count"), 0)) > 1:
            return self._run_multi_page_ocr_task(
                request=request,
                validated=validated,
                runtime_ready=runtime_ready,
                helper_bridge_ready=helper_bridge_ready,
                allow_vision_fallback=allow_vision_fallback,
                started_at=started_at,
            )

        instance_key = _request_instance_key(request)
        load_profile_hash = _request_load_profile_hash(request)
        effective_context_length = _request_effective_context_length(request)
        max_context_length = max(
            0,
            _request_max_context_length(request),
            _safe_int(model_info.get("max_context_length"), 0),
        )
        effective_load_profile = _request_effective_load_profile(request)
        text = ""
        spans: list[dict[str, Any]] = []
        device_backend = "cpu"
        fallback_mode = ""
        error_detail = ""
        execution_path = ""
        route_trace_input = validated

        if helper_bridge_ready:
            loaded_row = self._helper_bridge_resolve_instance_row(
                request=request,
                model_info=model_info,
                runtime_resolution=runtime_resolution,
                task_kind=task_kind,
            )
            helper_identifier = _safe_str(loaded_row.get("instanceKey")) or instance_key
            if not helper_identifier:
                out = self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error="helper_model_not_loaded",
                    task_kind=task_kind,
                    task_kinds=[task_kind],
                    model_id=model_id,
                    model_path=model_path,
                    usage=self._image_usage_payload(validated),
                    reason_code_override="helper_model_not_loaded",
                    runtime_reason_code_override="helper_model_not_loaded",
                )
                out["routeTrace"] = self._build_image_task_route_trace(
                    task_kind=task_kind,
                    image_input=route_trace_input,
                    runtime_ready=runtime_ready,
                    helper_bridge_ready=helper_bridge_ready,
                    allow_vision_fallback=allow_vision_fallback,
                    execution_path="helper_bridge_unavailable",
                    blocked_reason_code="helper_model_not_loaded",
                )
                return out
            helper_error, helper_messages = self._helper_bridge_multimodal_messages(
                validated=validated,
                task_kind=task_kind,
            )
            if helper_error or not helper_messages:
                out = self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error=helper_error or "image_encode_failed",
                    task_kind=task_kind,
                    task_kinds=[task_kind],
                    model_id=model_id,
                    model_path=model_path,
                    usage=self._image_usage_payload(validated),
                    reason_code_override=helper_error or "image_encode_failed",
                )
                out["routeTrace"] = self._build_image_task_route_trace(
                    task_kind=task_kind,
                    image_input=route_trace_input,
                    runtime_ready=runtime_ready,
                    helper_bridge_ready=helper_bridge_ready,
                    allow_vision_fallback=allow_vision_fallback,
                    execution_path="helper_bridge_error",
                    blocked_reason_code=helper_error or "image_encode_failed",
                )
                return out
            helper_result = helper_bridge_chat_completion(
                helper_binary,
                identifier=helper_identifier,
                messages=helper_messages,
                max_tokens=max(16, min(1024, _safe_int(request.get("max_new_tokens") or request.get("maxNewTokens"), 128))),
                timeout_sec=(
                    MLX_VLM_HELPER_CHAT_TIMEOUT_SEC
                    if self.provider_id() == "mlx_vlm"
                    else 20.0
                ),
            )
            if bool(helper_result.get("ok")):
                text = _safe_str(helper_result.get("text"))
                device_backend = self._helper_bridge_device_backend()
                execution_path = "helper_bridge"
                if task_kind == OCR_TASK_KIND and text:
                    spans = self._image_bbox_spans(validated, text)
            else:
                error_detail = _safe_str(helper_result.get("errorDetail"))
                if not allow_vision_fallback:
                    helper_reason = _safe_str(helper_result.get("reasonCode") or helper_result.get("error")) or "helper_chat_failed"
                    out = self._runtime_failure_output(
                        request=request,
                        runtime_resolution=runtime_resolution,
                        error="helper_chat_failed",
                        task_kind=task_kind,
                        task_kinds=[task_kind],
                        model_id=model_id,
                        model_path=model_path,
                        error_detail=error_detail,
                        usage=self._image_usage_payload(validated),
                        reason_code_override=helper_reason,
                        runtime_reason_code_override=helper_reason,
                    )
                    out["routeTrace"] = self._build_image_task_route_trace(
                        task_kind=task_kind,
                        image_input=route_trace_input,
                        runtime_ready=runtime_ready,
                        helper_bridge_ready=helper_bridge_ready,
                        allow_vision_fallback=allow_vision_fallback,
                        execution_path="helper_bridge_error",
                        blocked_reason_code=helper_reason,
                    )
                    return out

        if not text and not spans and runtime_ready and model_path:
            try:
                text, spans, device_backend = self._run_real_image(
                    task_kind=task_kind,
                    model_id=model_id,
                    model_path=model_path,
                    instance_key=instance_key,
                    load_profile_hash=load_profile_hash,
                    effective_context_length=effective_context_length,
                    max_context_length=max_context_length,
                    effective_load_profile=effective_load_profile,
                    validated=validated,
                    request=request,
                )
                execution_path = execution_path or "real_runtime"
            except Exception as exc:
                error_detail = _safe_str(exc)
                if not allow_vision_fallback:
                    task_error = "ocr_runtime_failed" if task_kind == OCR_TASK_KIND else "vision_runtime_failed"
                    reason_code_override, runtime_reason_code_override = _classify_runtime_failure_reason(
                        error_detail,
                        task_error,
                    )
                    out = self._runtime_failure_output(
                        request=request,
                        runtime_resolution=runtime_resolution,
                        error=task_error,
                        task_kind=task_kind,
                        task_kinds=[task_kind],
                        model_id=model_id,
                        model_path=model_path,
                        error_detail=error_detail,
                        usage=self._image_usage_payload(validated),
                        reason_code_override=reason_code_override,
                        runtime_reason_code_override=runtime_reason_code_override,
                    )
                    out["routeTrace"] = self._build_image_task_route_trace(
                        task_kind=task_kind,
                        image_input=route_trace_input,
                        runtime_ready=runtime_ready,
                        helper_bridge_ready=helper_bridge_ready,
                        allow_vision_fallback=allow_vision_fallback,
                        execution_path="runtime_error",
                        blocked_reason_code=reason_code_override or task_error,
                    )
                    return out

        if not text and not spans:
            if not allow_vision_fallback:
                if not model_path:
                    error_code = "missing_model_path"
                elif not runtime_ready:
                    out = self._runtime_failure_output(
                        request=request,
                        runtime_resolution=runtime_resolution,
                        error=self._task_runtime_import_error(
                            runtime_resolution,
                            task_kinds=[task_kind],
                        ) or "missing_runtime",
                        task_kind=task_kind,
                        task_kinds=[task_kind],
                        model_id=model_id,
                        model_path=model_path,
                        usage=self._image_usage_payload(validated),
                    )
                    out["routeTrace"] = self._build_image_task_route_trace(
                        task_kind=task_kind,
                        image_input=route_trace_input,
                        runtime_ready=runtime_ready,
                        helper_bridge_ready=helper_bridge_ready,
                        allow_vision_fallback=allow_vision_fallback,
                        execution_path="runtime_unavailable",
                        blocked_reason_code=_safe_str(out.get("runtimeReasonCode") or out.get("reasonCode") or out.get("error")),
                    )
                    return out
                else:
                    error_code = "ocr_runtime_failed" if task_kind == OCR_TASK_KIND else "vision_runtime_failed"
                out = self._runtime_failure_output(
                    request=request,
                    runtime_resolution=runtime_resolution,
                    error=error_code,
                    task_kind=task_kind,
                    task_kinds=[task_kind],
                    model_id=model_id,
                    model_path=model_path,
                    error_detail=error_detail,
                    usage=self._image_usage_payload(validated),
                    reason_code_override=error_code,
                )
                out["routeTrace"] = self._build_image_task_route_trace(
                    task_kind=task_kind,
                    image_input=route_trace_input,
                    runtime_ready=runtime_ready,
                    helper_bridge_ready=helper_bridge_ready,
                    allow_vision_fallback=allow_vision_fallback,
                    execution_path="runtime_error",
                    blocked_reason_code=error_code,
                )
                return out

            latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
            validated_with_model = {
                **validated,
                "model_path": model_path,
            }
            out = self._build_vision_fallback_output(
                task_kind=task_kind,
                model_id=model_id,
                validated=validated_with_model,
                latency_ms=latency_ms,
            )
            out["routeTrace"] = self._build_image_task_route_trace(
                task_kind=task_kind,
                image_input=route_trace_input,
                runtime_ready=runtime_ready,
                helper_bridge_ready=helper_bridge_ready,
                allow_vision_fallback=allow_vision_fallback,
                execution_path="fallback_preview",
                fallback_mode=_safe_str(out.get("fallbackMode") or out.get("fallback_mode")),
            )
            return out

        latency_ms = max(0, int(round((time.time() - started_at) * 1000.0)))
        if base_dir and not fallback_mode and runtime_ready and model_path:
            self._sync_process_local_state(base_dir=base_dir)
        out = {
            "ok": True,
            "provider": self.provider_id(),
            "taskKind": task_kind,
            "modelId": model_id,
            "modelPath": model_path,
            "text": text,
            "spans": spans,
            "language": _safe_str(validated.get("language")),
            "latencyMs": latency_ms,
            "deviceBackend": device_backend,
            "fallbackMode": fallback_mode,
            "usage": self._image_usage_payload(validated),
        }
        out["routeTrace"] = self._build_image_task_route_trace(
            task_kind=task_kind,
            image_input=route_trace_input,
            runtime_ready=runtime_ready,
            helper_bridge_ready=helper_bridge_ready,
            allow_vision_fallback=allow_vision_fallback,
            execution_path=execution_path or "unknown",
            fallback_mode=fallback_mode,
        )
        return out
