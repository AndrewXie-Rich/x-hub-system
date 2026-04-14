from __future__ import annotations

import hashlib
import importlib
import importlib.util
import json
import math
import os
import sys
import tempfile
import time
import wave
from typing import Any


GENERATED_TTS_AUDIO_DIRNAME = "generated_tts_audio"
DEFAULT_SAMPLE_RATE = 24000
_NATIVE_ERROR_TOKENS = (
    "dlopen",
    "library not loaded",
    "image not found",
    "symbol not found",
    "mach-o",
    "native",
)
_CONFIG_SPEAKER_KEYS = ("voices", "voice_ids", "speaker_ids", "speakers")
_ROUTE_STYLE_ALIASES = {
    "bright": "clear",
    "soft": "calm",
    "gentle": "calm",
    "soothing": "calm",
    "studio": "clear",
    "crisp": "clear",
}
_KOKORO_ROUTE_CANDIDATES = {
    ("zh", "warm"): [
        "zh_warm_f1",
        "zh_warm_f2",
        "zh_warm_m1",
        "zh_f_warm",
        "zh_m_warm",
        "zf_warm_1",
        "zm_warm_1",
    ],
    ("zh", "clear"): [
        "zh_clear_f1",
        "zh_clear_f2",
        "zh_clear_m1",
        "zh_f_clear",
        "zh_m_clear",
        "zf_clear_1",
        "zm_clear_1",
    ],
    ("zh", "calm"): [
        "zh_calm_f1",
        "zh_calm_m1",
        "zh_f_calm",
        "zh_m_calm",
    ],
    ("en", "warm"): [
        "en_warm_f1",
        "en_warm_m1",
        "af_heart",
        "af_bella",
        "af_nicole",
        "am_adam",
    ],
    ("en", "clear"): [
        "en_clear_f1",
        "en_clear_m1",
        "af_sarah",
        "af_sky",
        "am_michael",
    ],
    ("en", "calm"): [
        "en_calm_f1",
        "en_calm_m1",
        "bf_emma",
        "bf_lily",
        "bf_isabella",
        "bm_george",
    ],
    ("en", "neutral"): [
        "en_neutral_f1",
        "en_neutral_m1",
        "af_bella",
        "bf_emma",
        "am_adam",
    ],
}


class KokoroSynthesisError(RuntimeError):
    def __init__(self, reason_code: str, detail: str = "") -> None:
        self.reason_code = str(reason_code or "").strip() or "text_to_speech_runtime_unavailable"
        self.detail = str(detail or "").strip()
        super().__init__(self.detail or self.reason_code)


def kokoro_runtime_available() -> bool:
    for module_name in ("kokoro", "kokoro_onnx"):
        if module_name in sys.modules:
            return True
        try:
            if importlib.util.find_spec(module_name) is not None:
                return True
        except Exception:
            continue
    return False


def synthesize_kokoro_to_file(
    *,
    base_dir: str,
    model_id: str,
    model_path: str,
    text: str,
    locale: str,
    voice_color: str,
    speech_rate: float,
) -> dict[str, Any]:
    module = _import_kokoro_module()
    normalized_locale = _normalize_locale(locale)
    speaker_candidates = discover_available_speaker_ids(model_path)
    speaker_id = _pick_speaker_id(
        available_speakers=speaker_candidates,
        locale=normalized_locale,
        voice_color=voice_color,
    )
    output_path = _output_path(
        base_dir=base_dir,
        model_id=model_id,
        locale=normalized_locale,
        extension="wav",
    )
    last_detail = ""

    for owner in _candidate_runtime_owners(module, model_path=model_path, locale=normalized_locale):
        try:
            synthesized = _try_owner_file_synthesis(
                owner,
                text=text,
                output_path=output_path,
                speaker_id=speaker_id,
                locale=normalized_locale,
                speech_rate=speech_rate,
            )
            if synthesized:
                resolved_path = _resolve_audio_path(synthesized)
                resolved_speaker = speaker_id or _extract_speaker_id(synthesized) or "default"
                return _success_payload(
                    audio_path=resolved_path,
                    locale=normalized_locale,
                    voice_color=voice_color,
                    speech_rate=speech_rate,
                    speaker_id=resolved_speaker,
                    device_backend=_owner_device_backend(owner),
                )

            payload = _try_owner_in_memory_synthesis(
                owner,
                text=text,
                speaker_id=speaker_id,
                locale=normalized_locale,
                speech_rate=speech_rate,
            )
            audio_data, sample_rate, payload_speaker = _extract_audio_payload(payload)
            if audio_data is None:
                continue
            _write_wav(output_path, audio_data=audio_data, sample_rate=sample_rate or DEFAULT_SAMPLE_RATE)
            return _success_payload(
                audio_path=output_path,
                locale=normalized_locale,
                voice_color=voice_color,
                speech_rate=speech_rate,
                speaker_id=speaker_id or payload_speaker or "default",
                device_backend=_owner_device_backend(owner),
            )
        except KokoroSynthesisError:
            raise
        except Exception as exc:
            last_detail = _safe_str(exc)
            if _looks_like_native_dependency_error(last_detail):
                raise KokoroSynthesisError("native_dependency_error", last_detail)

    raise KokoroSynthesisError(
        "text_to_speech_runtime_unavailable",
        last_detail or "kokoro runtime returned no playable audio payload",
    )


def discover_available_speaker_ids(model_path: str) -> list[str]:
    base_dir = _model_base_dir(model_path)
    speakers: list[str] = []
    seen: set[str] = set()

    for token in _read_speakers_from_config(base_dir):
        if token not in seen:
            seen.add(token)
            speakers.append(token)

    for token in _read_speakers_from_filesystem(base_dir):
        if token not in seen:
            seen.add(token)
            speakers.append(token)

    return speakers


def preferred_speaker_candidates(locale: str, voice_color: str) -> list[str]:
    normalized_locale = _normalize_locale(locale)
    language_token = normalized_locale.split("-", 1)[0]
    normalized_color = _normalized_route_color(voice_color)
    out: list[str] = []
    seen: set[str] = set()

    for key in [
        (language_token, normalized_color),
        (language_token, "neutral"),
    ]:
        for candidate in _KOKORO_ROUTE_CANDIDATES.get(key, []):
            if candidate not in seen:
                seen.add(candidate)
                out.append(candidate)

    generic_patterns = [
        f"{language_token}_{normalized_color}_f1",
        f"{language_token}_{normalized_color}_m1",
        f"{language_token}_f_{normalized_color}",
        f"{language_token}_m_{normalized_color}",
        f"{language_token}_{normalized_color}",
        f"{language_token}_neutral_f1",
        f"{language_token}_neutral_m1",
    ]
    for candidate in generic_patterns:
        cleaned = _safe_str(candidate)
        if cleaned and cleaned not in seen:
            seen.add(cleaned)
            out.append(cleaned)
    return out


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_float(value: Any, fallback: float = 0.0) -> float:
    try:
        number = float(value)
    except Exception:
        return float(fallback)
    return number if math.isfinite(number) else float(fallback)


def _normalize_locale(locale: str) -> str:
    return _safe_str(locale).replace("_", "-").lower()


def _model_base_dir(model_path: str) -> str:
    raw = _safe_str(model_path)
    if raw and os.path.isdir(raw):
        return raw
    if raw:
        return os.path.dirname(raw) or os.getcwd()
    return os.getcwd()


def _output_path(*, base_dir: str, model_id: str, locale: str, extension: str) -> str:
    safe_base_dir = os.path.abspath(str(base_dir or "")) if _safe_str(base_dir) else tempfile.gettempdir()
    output_dir = os.path.join(safe_base_dir, GENERATED_TTS_AUDIO_DIRNAME)
    os.makedirs(output_dir, exist_ok=True)
    digest = hashlib.sha256(
        f"{_safe_str(model_id)}\0{_safe_str(locale)}\0{time.time_ns()}".encode("utf-8")
    ).hexdigest()[:16]
    normalized_extension = extension if extension.startswith(".") else f".{extension}"
    return os.path.join(output_dir, f"tts_{digest}{normalized_extension}")


def _import_kokoro_module() -> Any:
    details: list[str] = []
    for module_name in ("kokoro", "kokoro_onnx"):
        try:
            return importlib.import_module(module_name)
        except Exception as exc:
            details.append(f"{module_name}:{_safe_str(exc)}")
    raise KokoroSynthesisError("native_dependency_error", " | ".join(token for token in details if token))


def _candidate_runtime_owners(module: Any, *, model_path: str, locale: str) -> list[Any]:
    owners: list[Any] = [module]
    errors: list[str] = []

    pipeline_cls = getattr(module, "KPipeline", None)
    if callable(pipeline_cls):
        pipeline = _instantiate_runtime_object(
            pipeline_cls,
            variants=[
                {"lang_code": _kokoro_lang_code(locale), "model_path": model_path},
                {"lang_code": _kokoro_lang_code(locale), "model": model_path},
                {"lang_code": _kokoro_lang_code(locale), "checkpoint": model_path},
                {"lang_code": _kokoro_lang_code(locale), "repo_id": model_path},
                {"lang_code": _kokoro_lang_code(locale)},
                {"model_path": model_path},
                {},
            ],
            positional_variants=[[model_path], []],
            errors=errors,
        )
        if pipeline is not None:
            owners.append(pipeline)

    kokoro_cls = getattr(module, "Kokoro", None)
    if callable(kokoro_cls):
        voices_path = _discover_voices_path(model_path)
        kokoro_runtime = _instantiate_runtime_object(
            kokoro_cls,
            variants=[
                {"model_path": model_path, "voices_path": voices_path},
                {"model": model_path, "voices_path": voices_path},
                {"checkpoint": model_path, "voices_path": voices_path},
                {"model_path": model_path},
                {"model": model_path},
                {},
            ],
            positional_variants=[[model_path], []],
            errors=errors,
        )
        if kokoro_runtime is not None:
            owners.append(kokoro_runtime)

    if len(owners) == 1 and errors:
        detail = " | ".join(token for token in errors if token)
        if detail:
            raise KokoroSynthesisError("native_dependency_error", detail)
    return owners


def _instantiate_runtime_object(
    factory: Any,
    *,
    variants: list[dict[str, Any]],
    positional_variants: list[list[Any]],
    errors: list[str],
) -> Any:
    for kwargs in variants:
        try:
            return factory(**{key: value for key, value in kwargs.items() if value not in {None, ""}})
        except TypeError:
            continue
        except Exception as exc:
            errors.append(_safe_str(exc))
    for args in positional_variants:
        try:
            return factory(*args)
        except TypeError:
            continue
        except Exception as exc:
            errors.append(_safe_str(exc))
    return None


def _kokoro_lang_code(locale: str) -> str:
    normalized = _normalize_locale(locale)
    if normalized.startswith("zh"):
        return "zh"
    if normalized.startswith("en"):
        return "en"
    if normalized.startswith("ja"):
        return "ja"
    return normalized.split("-", 1)[0] or "en"


def _discover_voices_path(model_path: str) -> str:
    base_dir = _model_base_dir(model_path)
    candidates = [
        os.path.join(base_dir, "voices"),
        os.path.join(base_dir, "voice"),
        os.path.join(base_dir, "voices.bin"),
        os.path.join(base_dir, "voices.json"),
    ]
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    return ""


def _read_speakers_from_config(base_dir: str) -> list[str]:
    config_path = os.path.join(base_dir, "config.json")
    if not os.path.isfile(config_path):
        return []
    try:
        with open(config_path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except Exception:
        return []
    return _collect_speakers_from_value(payload)


def _collect_speakers_from_value(value: Any) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    if isinstance(value, dict):
        for key, nested in value.items():
            normalized_key = _safe_str(key).lower()
            if normalized_key in _CONFIG_SPEAKER_KEYS:
                for token in _flatten_speaker_tokens(nested):
                    if token not in seen:
                        seen.add(token)
                        out.append(token)
            else:
                for token in _collect_speakers_from_value(nested):
                    if token not in seen:
                        seen.add(token)
                        out.append(token)
    elif isinstance(value, list):
        for item in value:
            for token in _collect_speakers_from_value(item):
                if token not in seen:
                    seen.add(token)
                    out.append(token)
    return out


def _flatten_speaker_tokens(value: Any) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    if isinstance(value, dict):
        candidates = list(value.keys()) + [
            nested for nested in value.values() if isinstance(nested, str)
        ]
    elif isinstance(value, list):
        candidates = list(value)
    else:
        candidates = [value]
    for raw in candidates:
        token = _safe_str(raw)
        if not token or token.lower() in {"default", "none"} or token in seen:
            continue
        seen.add(token)
        out.append(token)
    return out


def _read_speakers_from_filesystem(base_dir: str) -> list[str]:
    candidates: list[str] = []
    seen: set[str] = set()
    for directory in [base_dir, os.path.join(base_dir, "voices"), os.path.join(base_dir, "speaker")]:
        if not os.path.isdir(directory):
            continue
        for entry in sorted(os.listdir(directory)):
            stem = os.path.splitext(entry)[0]
            token = _safe_str(stem)
            if not token or token.lower() in {"config", "model", "tokenizer", "voice", "voices", "speaker", "speakers"} or token in seen:
                continue
            if any(marker in token.lower() for marker in ["voice", "speaker", "af_", "am_", "bf_", "bm_", "zf_", "zm_", "zh_", "en_"]):
                seen.add(token)
                candidates.append(token)
    return candidates


def _pick_speaker_id(*, available_speakers: list[str], locale: str, voice_color: str) -> str:
    if not available_speakers:
        return ""
    normalized_locale = _normalize_locale(locale)
    language_token = normalized_locale.split("-", 1)[0]
    normalized_color = _normalized_route_color(voice_color)
    preferred_candidates = preferred_speaker_candidates(normalized_locale, normalized_color)
    normalized_by_lower = {
        speaker_id.lower(): speaker_id
        for speaker_id in available_speakers
    }
    for candidate in preferred_candidates:
        exact = normalized_by_lower.get(candidate.lower())
        if exact:
            return exact
    for candidate in preferred_candidates:
        for speaker_id in available_speakers:
            if _speaker_matches_candidate(speaker_id, candidate):
                return speaker_id
    preferred_markers = [marker for marker in [language_token, normalized_color] if marker]
    for speaker_id in available_speakers:
        lowered = speaker_id.lower()
        if preferred_markers and all(marker in lowered for marker in preferred_markers):
            return speaker_id
    for speaker_id in available_speakers:
        lowered = speaker_id.lower()
        if language_token and language_token in lowered:
            return speaker_id
    for speaker_id in available_speakers:
        lowered = speaker_id.lower()
        if normalized_color and normalized_color in lowered:
            return speaker_id
    return available_speakers[0]


def _normalized_route_color(voice_color: str) -> str:
    normalized = _safe_str(voice_color).lower() or "neutral"
    return _ROUTE_STYLE_ALIASES.get(normalized, normalized)


def _speaker_matches_candidate(speaker_id: str, candidate: str) -> bool:
    normalized_speaker = _safe_str(speaker_id).lower()
    normalized_candidate = _safe_str(candidate).lower()
    if not normalized_speaker or not normalized_candidate:
        return False
    if normalized_speaker == normalized_candidate:
        return True
    candidate_tokens = [
        token for token in normalized_candidate.replace("-", "_").split("_")
        if token
    ]
    if not candidate_tokens:
        return False
    return all(token in normalized_speaker for token in candidate_tokens)


def _try_owner_file_synthesis(
    owner: Any,
    *,
    text: str,
    output_path: str,
    speaker_id: str,
    locale: str,
    speech_rate: float,
) -> Any:
    for method_name in ("synthesize_to_file", "generate_to_file", "save", "create_to_file"):
        method = getattr(owner, method_name, None)
        if not callable(method):
            continue
        result = _invoke_callable_variants(
            method,
            text=text,
            output_path=output_path,
            speaker_id=speaker_id,
            locale=locale,
            speech_rate=speech_rate,
        )
        if os.path.isfile(output_path) and os.path.getsize(output_path) > 0:
            return result or output_path
        resolved = _resolve_audio_path(result)
        if resolved:
            return resolved
    return None


def _try_owner_in_memory_synthesis(
    owner: Any,
    *,
    text: str,
    speaker_id: str,
    locale: str,
    speech_rate: float,
) -> Any:
    for candidate in _callable_candidates(owner):
        result = _invoke_callable_variants(
            candidate,
            text=text,
            output_path="",
            speaker_id=speaker_id,
            locale=locale,
            speech_rate=speech_rate,
        )
        if result is not None:
            return result
    return None


def _callable_candidates(owner: Any) -> list[Any]:
    out: list[Any] = []
    for candidate in [
        owner if callable(owner) else None,
        getattr(owner, "synthesize", None),
        getattr(owner, "generate", None),
        getattr(owner, "create", None),
        getattr(owner, "__call__", None) if not callable(owner) else None,
    ]:
        if callable(candidate) and candidate not in out:
            out.append(candidate)
    return out


def _invoke_callable_variants(
    fn: Any,
    *,
    text: str,
    output_path: str,
    speaker_id: str,
    locale: str,
    speech_rate: float,
) -> Any:
    kwargs_variants = [
        {
            "text": text,
            "output_path": output_path,
            "voice": speaker_id,
            "speed": speech_rate,
            "lang": _kokoro_lang_code(locale),
            "language": _kokoro_lang_code(locale),
        },
        {
            "text": text,
            "path": output_path,
            "speaker": speaker_id,
            "speed": speech_rate,
            "lang": _kokoro_lang_code(locale),
        },
        {
            "text": text,
            "file_path": output_path,
            "voice": speaker_id,
            "speed": speech_rate,
        },
        {
            "text": text,
            "voice": speaker_id,
            "speed": speech_rate,
        },
        {
            "text": text,
            "speaker": speaker_id,
            "speed": speech_rate,
        },
        {
            "text": text,
        },
    ]
    for kwargs in kwargs_variants:
        normalized_kwargs = {
            key: value for key, value in kwargs.items()
            if value not in {None, ""} and not (key in {"output_path", "path", "file_path"} and not output_path)
        }
        try:
            return fn(**normalized_kwargs)
        except TypeError:
            continue
    positional_variants = [
        [text, output_path] if output_path else [],
        [text],
    ]
    for args in positional_variants:
        if not args:
            continue
        try:
            return fn(*args)
        except TypeError:
            continue
    return None


def _resolve_audio_path(value: Any) -> str:
    if isinstance(value, str):
        return value if os.path.isfile(value) and os.path.getsize(value) > 0 else ""
    if isinstance(value, dict):
        for key in ("audio_path", "audioPath", "path", "output_path", "outputPath", "file_path", "filePath"):
            candidate = _safe_str(value.get(key))
            if candidate and os.path.isfile(candidate) and os.path.getsize(candidate) > 0:
                return candidate
    return ""


def _extract_speaker_id(value: Any) -> str:
    if isinstance(value, dict):
        for key in ("speakerId", "speaker_id", "voice", "voice_name", "speaker"):
            token = _safe_str(value.get(key))
            if token:
                return token
    return ""


def _extract_audio_payload(value: Any) -> tuple[Any, int, str]:
    if value is None:
        return None, 0, ""
    if isinstance(value, dict):
        sample_rate = int(_safe_float(value.get("sample_rate") or value.get("sampleRate"), 0))
        speaker_id = _extract_speaker_id(value)
        for key in ("audio", "samples", "audio_samples", "pcm", "wav"):
            if key in value:
                return value.get(key), sample_rate, speaker_id
        resolved = _resolve_audio_path(value)
        if resolved:
            return {"audio_path": resolved}, sample_rate, speaker_id
        for nested in value.values():
            audio, nested_rate, nested_speaker = _extract_audio_payload(nested)
            if audio is not None:
                return audio, nested_rate or sample_rate, nested_speaker or speaker_id
        return None, sample_rate, speaker_id
    if isinstance(value, (bytes, bytearray)):
        return bytes(value), 0, ""
    if hasattr(value, "tolist") and not isinstance(value, (str, bytes, bytearray)):
        try:
            return value.tolist(), 0, ""
        except Exception:
            pass
    if isinstance(value, (list, tuple)):
        if len(value) == 2 and not isinstance(value[0], (str, bytes, bytearray)) and isinstance(value[1], (int, float)):
            return value[0], int(_safe_float(value[1], 0)), ""
        if value and all(isinstance(item, (int, float)) for item in value[: min(8, len(value))]):
            return list(value), 0, ""
        speaker_id = ""
        sample_rate = 0
        for item in value:
            if isinstance(item, str) and not speaker_id:
                speaker_id = _safe_str(item)
            elif isinstance(item, (int, float)) and item > 1000 and sample_rate <= 0:
                sample_rate = int(item)
        for nested in reversed(value):
            audio, nested_rate, nested_speaker = _extract_audio_payload(nested)
            if audio is not None:
                return audio, nested_rate or sample_rate, nested_speaker or speaker_id
    return None, 0, ""


def _write_wav(path: str, *, audio_data: Any, sample_rate: int) -> None:
    if isinstance(audio_data, dict):
        resolved = _resolve_audio_path(audio_data)
        if resolved:
            with open(resolved, "rb") as source, open(path, "wb") as target:
                target.write(source.read())
            return
    if isinstance(audio_data, (bytes, bytearray)):
        data = bytes(audio_data)
        if data.startswith(b"RIFF"):
            with open(path, "wb") as handle:
                handle.write(data)
            return
        frames = data
    else:
        samples = _flatten_audio_samples(audio_data)
        if not samples:
            raise KokoroSynthesisError("tts_native_audio_missing", "kokoro audio sample payload was empty")
        pcm = bytearray()
        for raw in samples:
            number = _safe_float(raw, 0.0)
            if abs(number) <= 1.0:
                number *= 32767.0
            clamped = max(-32768, min(32767, int(round(number))))
            pcm.extend(int(clamped).to_bytes(2, "little", signed=True))
        frames = bytes(pcm)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(max(8000, int(sample_rate or DEFAULT_SAMPLE_RATE)))
        handle.writeframes(frames)


def _flatten_audio_samples(value: Any) -> list[float]:
    out: list[float] = []
    if hasattr(value, "tolist") and not isinstance(value, (str, bytes, bytearray)):
        try:
            value = value.tolist()
        except Exception:
            value = []
    if isinstance(value, (list, tuple)):
        for item in value:
            if isinstance(item, (list, tuple)) or hasattr(item, "tolist"):
                out.extend(_flatten_audio_samples(item))
            else:
                out.append(_safe_float(item, 0.0))
    return out


def _success_payload(
    *,
    audio_path: str,
    locale: str,
    voice_color: str,
    speech_rate: float,
    speaker_id: str,
    device_backend: str,
) -> dict[str, Any]:
    if not os.path.isfile(audio_path):
        raise KokoroSynthesisError("tts_native_audio_missing", f"missing_audio_output:{audio_path}")
    output_audio_bytes = os.path.getsize(audio_path)
    if output_audio_bytes <= 0:
        raise KokoroSynthesisError("tts_native_audio_missing", "kokoro output audio file was empty")
    return {
        "ok": True,
        "audioPath": audio_path,
        "audioFormat": "wav",
        "locale": locale,
        "voiceColor": _safe_str(voice_color).lower() or "neutral",
        "speechRate": round(_safe_float(speech_rate, 1.0), 3),
        "engineName": "kokoro",
        "speakerId": speaker_id or "default",
        "deviceBackend": device_backend or "kokoro_native",
        "nativeTTSUsed": True,
        "fallbackMode": "",
        "usage": {
            "outputAudioBytes": output_audio_bytes,
            "outputAudioFormat": "wav",
        },
    }


def _owner_device_backend(owner: Any) -> str:
    device = _safe_str(getattr(owner, "device", ""))
    return device or "kokoro_native"


def _looks_like_native_dependency_error(detail: str) -> bool:
    lowered = _safe_str(detail).lower()
    return any(token in lowered for token in _NATIVE_ERROR_TOKENS)
