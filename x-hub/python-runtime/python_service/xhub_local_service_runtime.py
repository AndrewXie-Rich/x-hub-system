from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import unquote, urlparse

from provider_pack_registry import provider_pack_inventory
from relflowhub_local_runtime import (
    _base_dir,
    apply_offline_env,
    manage_local_model,
    read_catalog_models,
    run_local_task,
)
from xhub_local_service_bridge import (
    DEFAULT_XHUB_LOCAL_SERVICE_HOST,
    DEFAULT_XHUB_LOCAL_SERVICE_PORT,
)


XHUB_LOCAL_SERVICE_RUNTIME_VERSION = "2026-03-21-xhub-local-service-multimodal-chat-v2"
XHUB_LOCAL_SERVICE_HEALTH_SCHEMA_VERSION = "xhub.local_service.health.v1"
XHUB_LOCAL_SERVICE_MODEL_LIST_SCHEMA_VERSION = "xhub.local_service.models.v1"
XHUB_LOCAL_SERVICE_CHAT_ROUTE_TRACE_SCHEMA_VERSION = "xhub.local_service.chat_route_trace.v1"
XHUB_LOCAL_SERVICE_CONTROL_REASON = "xhub_local_service_control_plane_not_yet_wired"
XHUB_LOCAL_SERVICE_INFERENCE_REASON = "xhub_local_service_inference_not_yet_wired"
XHUB_LOCAL_SERVICE_INTERNAL_REQUEST_FLAG = "_xhub_local_service_internal"
XHUB_LOCAL_SERVICE_UPLOAD_DIRNAME = ".xhub_local_service_uploads"
_XHUB_LOCAL_SERVICE_CAPABILITIES = [
    "health",
    "list_models",
    "embeddings",
    "chat_completions",
    "warmup",
    "unload",
    "evict",
]


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_int(value: Any, fallback: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return int(fallback)


def _safe_float(value: Any, fallback: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return float(fallback)


def _safe_bool(value: Any, fallback: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    token = _safe_str(value).lower()
    if token in {"1", "true", "yes", "on"}:
        return True
    if token in {"0", "false", "no", "off"}:
        return False
    return bool(fallback)


def _dedupe_strings(values: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for raw in values:
        token = _safe_str(raw)
        if not token or token in seen:
            continue
        seen.add(token)
        out.append(token)
    return out


def _string_list(raw: Any) -> list[str]:
    items = raw if isinstance(raw, list) else [raw]
    out: list[str] = []
    seen: set[str] = set()
    for item in items:
        token = _safe_str(item)
        if not token or token in seen:
            continue
        seen.add(token)
        out.append(token)
    return out


def _provider_ids_from_catalog_models(catalog_models: list[dict[str, Any]]) -> list[str]:
    provider_ids: list[str] = []
    for model in catalog_models:
        if not isinstance(model, dict):
            continue
        provider_id = _safe_str(
            model.get("runtimeProviderID")
            or model.get("runtime_provider_id")
            or model.get("backend")
        ).lower()
        if provider_id:
            provider_ids.append(provider_id)
    if not provider_ids:
        provider_ids.extend(["mlx", "transformers"])
    return _dedupe_strings(provider_ids)


def _pack_summary_rows(base_dir: str, catalog_models: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for pack in provider_pack_inventory(_provider_ids_from_catalog_models(catalog_models), base_dir=base_dir):
        if not isinstance(pack, dict):
            continue
        runtime_requirements = (
            pack.get("runtimeRequirements")
            if isinstance(pack.get("runtimeRequirements"), dict)
            else {}
        )
        rows.append(
            {
                "providerId": _safe_str(pack.get("providerId") or pack.get("provider_id")).lower(),
                "engine": _safe_str(pack.get("engine")),
                "version": _safe_str(pack.get("version")),
                "installed": bool(pack.get("installed")),
                "enabled": bool(pack.get("enabled")),
                "packState": _safe_str(pack.get("packState") or pack.get("pack_state")).lower(),
                "reasonCode": _safe_str(pack.get("reasonCode") or pack.get("reason_code")),
                "executionMode": _safe_str(
                    runtime_requirements.get("executionMode")
                    or runtime_requirements.get("execution_mode")
                ).lower(),
            }
        )
    rows.sort(key=lambda item: _safe_str(item.get("providerId")))
    return rows


def build_xhub_local_service_health(
    *,
    base_dir: str,
    host: str,
    port: int,
    started_at: float,
) -> dict[str, Any]:
    catalog_models = read_catalog_models(base_dir)
    provider_packs = _pack_summary_rows(base_dir, catalog_models)
    return {
        "ok": True,
        "status": "ready",
        "schemaVersion": XHUB_LOCAL_SERVICE_HEALTH_SCHEMA_VERSION,
        "version": XHUB_LOCAL_SERVICE_RUNTIME_VERSION,
        "serviceMode": "task_proxy_v1",
        "baseDir": base_dir,
        "bindHost": host,
        "bindPort": max(0, int(port or 0)),
        "uptimeSec": max(0.0, time.time() - float(started_at or time.time())),
        "capabilities": list(_XHUB_LOCAL_SERVICE_CAPABILITIES),
        "catalogModelCount": len(catalog_models),
        "providerPacks": provider_packs,
        "providerIds": [row["providerId"] for row in provider_packs if _safe_str(row.get("providerId"))],
        "readyProviders": [],
        "runtimeHint": (
            "xhub_local_service is reachable. "
            "Health and model inventory are live; admin lifecycle actions and OpenAI-style embeddings/chat proxy "
            "through the Hub local runtime manager with fail-closed routing."
        ),
    }


def build_xhub_local_service_model_list(base_dir: str) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for model in read_catalog_models(base_dir):
        if not isinstance(model, dict):
            continue
        model_id = _safe_str(model.get("id")) or _safe_str(model.get("name"))
        if not model_id:
            continue
        rows.append(
            {
                "id": model_id,
                "object": "model",
                "provider": _safe_str(
                    model.get("runtimeProviderID")
                    or model.get("runtime_provider_id")
                    or model.get("backend")
                ).lower(),
                "backend": _safe_str(model.get("backend")).lower(),
                "modelPath": _safe_str(model.get("modelPath") or model.get("model_path")),
                "taskKinds": list(model.get("taskKinds") or model.get("task_kinds") or []),
                "maxContextLength": max(
                    0,
                    _safe_int(
                        model.get("maxContextLength")
                        or model.get("max_context_length")
                        or model.get("contextLength")
                        or model.get("context_length"),
                        0,
                    ),
                ),
                "owned_by": "xhub_local_service",
            }
        )
    rows.sort(key=lambda item: _safe_str(item.get("id")))
    return {
        "object": "list",
        "schemaVersion": XHUB_LOCAL_SERVICE_MODEL_LIST_SCHEMA_VERSION,
        "data": rows,
        "count": len(rows),
    }


def _catalog_model_by_id(base_dir: str, model_id: str) -> dict[str, Any] | None:
    needle = _safe_str(model_id)
    if not needle:
        return None
    for model in read_catalog_models(base_dir):
        if not isinstance(model, dict):
            continue
        candidate_id = _safe_str(model.get("id")) or _safe_str(model.get("name"))
        if candidate_id == needle:
            return dict(model)
    return None


def _catalog_model_provider_id(model: dict[str, Any] | None) -> str:
    row = model if isinstance(model, dict) else {}
    return _safe_str(
        row.get("runtimeProviderID")
        or row.get("runtime_provider_id")
        or row.get("backend")
    ).lower()


def _catalog_model_task_kinds(model: dict[str, Any] | None) -> list[str]:
    row = model if isinstance(model, dict) else {}
    raw = row.get("taskKinds") if isinstance(row.get("taskKinds"), list) else row.get("task_kinds")
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    seen: set[str] = set()
    for item in raw:
        token = _safe_str(item).lower()
        if not token or token in seen:
            continue
        seen.add(token)
        out.append(token)
    return out


def _error_type_for_status(status: int) -> str:
    return "invalid_request_error" if int(status) < 500 else "server_error"


def _service_error_response(
    status: int,
    reason_code: str,
    message: str,
    *,
    model: str = "",
    provider: str = "",
    task_kind: str = "",
    runtime_hint: str = "",
    extra_fields: dict[str, Any] | None = None,
) -> tuple[int, dict[str, Any]]:
    payload = {
        "ok": False,
        "status": "invalid_request" if int(status) < 500 else "error",
        "reasonCode": _safe_str(reason_code),
        "runtimeHint": _safe_str(runtime_hint) or _safe_str(message),
        "serviceVersion": XHUB_LOCAL_SERVICE_RUNTIME_VERSION,
        "error": {
            "message": _safe_str(message),
            "type": _error_type_for_status(status),
            "code": _safe_str(reason_code),
        },
    }
    if model:
        payload["model"] = _safe_str(model)
    if provider:
        payload["provider"] = _safe_str(provider)
    if task_kind:
        payload["taskKind"] = _safe_str(task_kind)
    if isinstance(extra_fields, dict):
        for key, value in extra_fields.items():
            if value is None:
                continue
            payload[key] = value
    return int(status), payload


def _runtime_usage_int(usage: dict[str, Any], *keys: str) -> int:
    for key in keys:
        value = usage.get(key)
        if value is None:
            continue
        return max(0, _safe_int(value, 0))
    return 0


def _normalize_embedding_inputs(request: dict[str, Any]) -> tuple[list[str], str]:
    raw_input = request.get("input")
    if raw_input is None and request.get("text") is not None:
        raw_input = request.get("text")
    if isinstance(raw_input, str):
        return [raw_input], ""
    if isinstance(raw_input, list):
        texts: list[str] = []
        for item in raw_input:
            if not isinstance(item, str):
                return [], "embedding_input_must_be_text"
            texts.append(item)
        return texts, ""
    return [], "missing_input"


def _image_source_from_content_item(item: dict[str, Any]) -> str:
    image_url = item.get("image_url")
    if isinstance(image_url, dict):
        return _safe_str(
            image_url.get("url")
            or image_url.get("path")
            or image_url.get("image_path")
        )
    if image_url is not None:
        return _safe_str(image_url)
    return _safe_str(
        item.get("url")
        or item.get("path")
        or item.get("image_path")
        or item.get("file_path")
    )


def _image_source_kind(raw_value: str) -> str:
    token = _safe_str(raw_value)
    if token.startswith("data:"):
        return "data_url"
    parsed = urlparse(token)
    scheme = _safe_str(parsed.scheme).lower()
    if scheme in {"http", "https"}:
        return "remote_url"
    if scheme == "file":
        return "file_url"
    if scheme:
        return f"{scheme}_url"
    return "local_path"


def _materialize_data_url_image(base_dir: str, raw_url: str) -> tuple[str, str]:
    token = _safe_str(raw_url)
    if not token.startswith("data:"):
        return "", "unsupported_image_url_scheme"
    header, sep, payload = token.partition(",")
    if not sep:
        return "", "invalid_data_url"
    lower_header = header.lower()
    if ";base64" not in lower_header:
        return "", "image_data_url_must_be_base64"
    mime = lower_header[5:].split(";", 1)[0]
    ext = ""
    if mime == "image/png":
        ext = ".png"
    elif mime == "image/jpeg":
        ext = ".jpg"
    if not ext:
        return "", "unsupported_image_mime_type"
    try:
        decoded = base64.b64decode(payload, validate=True)
    except (ValueError, binascii.Error):
        return "", "invalid_image_base64"
    if not decoded:
        return "", "empty_image_payload"
    digest = hashlib.sha256(decoded).hexdigest()[:40]
    upload_dir = os.path.join(base_dir, XHUB_LOCAL_SERVICE_UPLOAD_DIRNAME)
    os.makedirs(upload_dir, exist_ok=True)
    image_path = os.path.join(upload_dir, f"{digest}{ext}")
    if not os.path.exists(image_path):
        with open(image_path, "wb") as handle:
            handle.write(decoded)
    return image_path, ""


def _resolve_local_image_reference(base_dir: str, raw_value: str) -> tuple[str, str]:
    token = _safe_str(raw_value)
    if not token:
        return "", "missing_image_url"
    if token.startswith("data:"):
        return _materialize_data_url_image(base_dir, token)

    parsed = urlparse(token)
    scheme = _safe_str(parsed.scheme).lower()
    if scheme in {"http", "https"}:
        return "", "remote_image_url_not_supported"
    if scheme and scheme != "file":
        return "", f"unsupported_image_url_scheme:{scheme}"
    if scheme == "file":
        file_path = unquote(parsed.path or "")
        if parsed.netloc:
            file_path = f"/{_safe_str(parsed.netloc)}{file_path}" if not file_path.startswith("/") else file_path
        return os.path.abspath(os.path.expanduser(file_path)), ""
    return os.path.abspath(os.path.expanduser(token)), ""


def _looks_like_ocr_prompt(prompt: str) -> bool:
    token = _safe_str(prompt).lower()
    if not token:
        return False
    markers = [
        "ocr",
        "extract text",
        "extract all visible text",
        "read the text",
        "read all text",
        "visible text",
        "what text",
        "what does it say",
        "transcribe the text",
        "提取文字",
        "识别文字",
        "识别图片中的文字",
        "读出文字",
        "图里写了什么",
        "图片里的文字",
        "所有文字",
    ]
    return any(marker in token for marker in markers)


def _flatten_prompt_from_messages(messages: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    multi_turn = len(messages) > 1
    for message in messages:
        role = _safe_str(message.get("role")).lower() or "user"
        content_rows = message.get("content") if isinstance(message.get("content"), list) else []
        text = " ".join(
            _safe_str(item.get("text"))
            for item in content_rows
            if isinstance(item, dict) and _safe_str(item.get("type")).lower() == "text" and _safe_str(item.get("text"))
        )
        if not text:
            continue
        lines.append(f"{role}: {text}" if multi_turn else text)
    return "\n".join(lines).strip()


def _message_roles(messages: list[dict[str, Any]]) -> list[str]:
    return [
        _safe_str(message.get("role")).lower() or "user"
        for message in messages
        if isinstance(message, dict)
    ]


def _build_chat_route_trace(
    *,
    request_mode: str,
    selected_task_kind: str,
    selection_reason: str,
    explicit_task_kind: str,
    model_task_kinds: list[str],
    messages: list[dict[str, Any]],
    image_parts: list[dict[str, Any]],
    prompt: str,
    ocr_prompt_heuristic_matched: bool,
) -> dict[str, Any]:
    image_inputs: list[dict[str, Any]] = []
    for index, item in enumerate(image_parts):
        image_inputs.append(
            {
                "index": index,
                "role": _safe_str(item.get("role")).lower() or "user",
                "sourceKind": _image_source_kind(_safe_str(item.get("source"))),
                "detail": _safe_str(item.get("detail")),
            }
        )
    return {
        "schemaVersion": XHUB_LOCAL_SERVICE_CHAT_ROUTE_TRACE_SCHEMA_VERSION,
        "requestMode": _safe_str(request_mode),
        "messageCount": len(messages),
        "messageRoles": _message_roles(messages),
        "imageCount": len(image_parts),
        "imageInputs": image_inputs,
        "selectedTaskKind": _safe_str(selected_task_kind),
        "selectionReason": _safe_str(selection_reason),
        "explicitTaskKind": _safe_str(explicit_task_kind),
        "modelTaskKinds": _string_list(model_task_kinds),
        "ocrPromptHeuristicMatched": bool(ocr_prompt_heuristic_matched),
        "promptChars": len(_safe_str(prompt)),
    }


def _attach_resolved_images_to_route_trace(
    route_trace: dict[str, Any],
    resolved_images: list[dict[str, Any]],
) -> dict[str, Any]:
    out = dict(route_trace or {})
    out["resolvedImageCount"] = len(resolved_images)
    out["resolvedImages"] = [
        {
            "index": index,
            "role": _safe_str(item.get("role")).lower() or "user",
            "sourceKind": _safe_str(item.get("sourceKind")),
            "fileName": os.path.basename(_safe_str(item.get("imagePath"))),
            "detail": _safe_str(item.get("detail")),
        }
        for index, item in enumerate(resolved_images)
    ]
    return out


def _route_trace_payload(*objects: Any) -> dict[str, Any] | None:
    for obj in objects:
        if not isinstance(obj, dict):
            continue
        trace = obj.get("routeTrace")
        if isinstance(trace, dict):
            return dict(trace)
        trace = obj.get("route_trace")
        if isinstance(trace, dict):
            return dict(trace)
    return None


def _resolve_chat_image_parts(
    base_dir: str,
    image_parts: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], str, int]:
    resolved: list[dict[str, Any]] = []
    for index, part in enumerate(image_parts):
        raw_source = _safe_str(part.get("source"))
        image_path, image_error = _resolve_local_image_reference(base_dir, raw_source)
        if image_error:
            return [], image_error, index
        resolved.append(
            {
                "role": _safe_str(part.get("role")).lower() or "user",
                "sourceKind": _image_source_kind(raw_source),
                "detail": _safe_str(part.get("detail")),
                "imagePath": image_path,
            }
        )
    return resolved, "", -1


def _parse_chat_messages(
    request: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], str]:
    raw_messages = request.get("messages")
    if not isinstance(raw_messages, list) or not raw_messages:
        return [], [], "missing_messages"

    normalized_messages: list[dict[str, Any]] = []
    image_parts: list[dict[str, Any]] = []
    for raw_message in raw_messages:
        if not isinstance(raw_message, dict):
            return [], [], "invalid_message"
        role = _safe_str(raw_message.get("role")).lower() or "user"
        raw_content = raw_message.get("content")
        content_rows: list[dict[str, Any]] = []
        image_count_before = len(image_parts)
        if isinstance(raw_content, str):
            text = _safe_str(raw_content)
            if text:
                content_rows.append({"type": "text", "text": text})
        elif isinstance(raw_content, list):
            for item in raw_content:
                if not isinstance(item, dict):
                    return [], [], "invalid_message_content"
                item_type = _safe_str(item.get("type")).lower()
                if item_type in {"text", "input_text"}:
                    text = _safe_str(item.get("text"))
                    if text:
                        content_rows.append({"type": "text", "text": text})
                    continue
                if item_type in {"image", "image_url", "input_image"}:
                    source = _image_source_from_content_item(item)
                    if not source:
                        return [], [], "missing_image_url"
                    image_parts.append(
                        {
                            "role": role,
                            "source": source,
                            "detail": _safe_str(item.get("detail")),
                        }
                    )
                    continue
                return [], [], f"unsupported_message_content_type:{item_type or 'unknown'}"
        elif raw_content is not None:
            return [], [], "invalid_message_content"
        if content_rows or len(image_parts) > image_count_before:
            normalized_messages.append({"role": role, "content": content_rows})
    return normalized_messages, image_parts, ""


def _build_embeddings_runtime_request(
    request: dict[str, Any],
    *,
    base_dir: str,
) -> tuple[dict[str, Any] | None, tuple[int, dict[str, Any]] | None]:
    model_id = _safe_str(request.get("model") or request.get("modelId") or request.get("model_id"))
    if not model_id:
        return None, _service_error_response(400, "missing_model", "embeddings request must include model.", task_kind="embedding")

    catalog_model = _catalog_model_by_id(base_dir, model_id)
    if catalog_model is None:
        return None, _service_error_response(404, "model_not_found", f"Model {model_id} is not registered in xhub_local_service.", model=model_id, task_kind="embedding")

    task_kinds = _catalog_model_task_kinds(catalog_model)
    if task_kinds and "embedding" not in task_kinds:
        return None, _service_error_response(400, "model_task_unsupported:embedding", f"Model {model_id} is not registered for embedding tasks.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="embedding")

    encoding_format = _safe_str(request.get("encoding_format") or request.get("encodingFormat")).lower()
    if encoding_format and encoding_format != "float":
        return None, _service_error_response(400, "unsupported_encoding_format", "xhub_local_service only supports float embedding output.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="embedding")

    if _safe_int(request.get("dimensions"), 0) > 0:
        return None, _service_error_response(400, "embedding_dimensions_not_supported", "xhub_local_service does not support dimensions override yet.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="embedding")

    texts, error_code = _normalize_embedding_inputs(request)
    if error_code:
        return None, _service_error_response(400, error_code, "embeddings input must be a string or a list of strings.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="embedding")

    runtime_request = {
        "task_kind": "embedding",
        "taskKind": "embedding",
        "model_id": model_id,
        "modelId": model_id,
        "provider": _catalog_model_provider_id(catalog_model),
        "texts": [str(text or "") for text in texts],
        XHUB_LOCAL_SERVICE_INTERNAL_REQUEST_FLAG: True,
    }
    if "input_sanitized" in request or "inputSanitized" in request:
        runtime_request["input_sanitized"] = _safe_bool(
            request.get("input_sanitized")
            if request.get("input_sanitized") is not None
            else request.get("inputSanitized"),
            False,
        )
    if "allow_hash_fallback" in request or "allowHashFallback" in request:
        runtime_request["allow_hash_fallback"] = _safe_bool(
            request.get("allow_hash_fallback")
            if request.get("allow_hash_fallback") is not None
            else request.get("allowHashFallback"),
            False,
        )
    return runtime_request, None


def _build_chat_runtime_request(
    request: dict[str, Any],
    *,
    base_dir: str,
) -> tuple[dict[str, Any] | None, tuple[int, dict[str, Any]] | None]:
    model_id = _safe_str(request.get("model") or request.get("modelId") or request.get("model_id"))
    if not model_id:
        return None, _service_error_response(400, "missing_model", "chat request must include model.", task_kind="text_generate")

    catalog_model = _catalog_model_by_id(base_dir, model_id)
    if catalog_model is None:
        return None, _service_error_response(404, "model_not_found", f"Model {model_id} is not registered in xhub_local_service.", model=model_id, task_kind="text_generate")

    if _safe_bool(request.get("stream"), False):
        return None, _service_error_response(400, "stream_not_supported", "xhub_local_service does not support streaming chat completions yet.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="text_generate")

    choice_count = _safe_int(request.get("n"), 1)
    if choice_count > 1:
        return None, _service_error_response(400, "chat_choice_count_not_supported", "xhub_local_service only supports n=1 for chat completions.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="text_generate")

    if request.get("tools") or request.get("tool_choice") or request.get("functions") or request.get("function_call"):
        return None, _service_error_response(400, "tool_calls_not_yet_supported", "xhub_local_service does not support tools or function calling yet.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="text_generate")

    response_format = request.get("response_format")
    if isinstance(response_format, dict):
        response_type = _safe_str(response_format.get("type")).lower()
        if response_type and response_type != "text":
            return None, _service_error_response(400, "response_format_not_supported", "xhub_local_service currently supports text chat responses only.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="text_generate")

    messages, image_parts, error_code = _parse_chat_messages(request)
    if error_code:
        prompt_fallback = _safe_str(request.get("prompt") or request.get("text"))
        if error_code == "missing_messages" and prompt_fallback:
            messages = [{"role": "user", "content": [{"type": "text", "text": prompt_fallback}]}]
            image_parts = []
        else:
            return None, _service_error_response(400, error_code, "chat request must include valid messages.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="text_generate")

    task_kinds = set(_catalog_model_task_kinds(catalog_model))
    explicit_task_kind = _safe_str(request.get("task_kind") or request.get("taskKind")).lower()
    if explicit_task_kind and explicit_task_kind not in {"text_generate", "vision_understand", "ocr"}:
        return None, _service_error_response(400, "unsupported_chat_task_kind", f"xhub_local_service does not support chat task kind override {explicit_task_kind}.", model=model_id, provider=_catalog_model_provider_id(catalog_model), task_kind="text_generate")

    prompt = _flatten_prompt_from_messages(messages)
    ocr_prompt_heuristic_matched = _looks_like_ocr_prompt(prompt)

    if not image_parts:
        route_trace = _build_chat_route_trace(
            request_mode="text_only",
            selected_task_kind="text_generate",
            selection_reason="text_only_no_images",
            explicit_task_kind=explicit_task_kind,
            model_task_kinds=sorted(task_kinds),
            messages=messages,
            image_parts=image_parts,
            prompt=prompt,
            ocr_prompt_heuristic_matched=ocr_prompt_heuristic_matched,
        )
        if task_kinds and "text_generate" not in task_kinds:
            return None, _service_error_response(
                400,
                "model_task_unsupported:text_generate",
                f"Model {model_id} is not registered for chat/text generation tasks.",
                model=model_id,
                provider=_catalog_model_provider_id(catalog_model),
                task_kind="text_generate",
                extra_fields={"routeTrace": route_trace},
            )
        runtime_request = {
            "task_kind": "text_generate",
            "taskKind": "text_generate",
            "model_id": model_id,
            "modelId": model_id,
            "provider": _catalog_model_provider_id(catalog_model),
            "messages": messages,
            "routeTrace": route_trace,
            "route_trace": route_trace,
            XHUB_LOCAL_SERVICE_INTERNAL_REQUEST_FLAG: True,
        }
    else:
        if explicit_task_kind == "text_generate":
            route_trace = _build_chat_route_trace(
                request_mode="multimodal",
                selected_task_kind="text_generate",
                selection_reason="invalid_text_generate_override_for_image_input",
                explicit_task_kind=explicit_task_kind,
                model_task_kinds=sorted(task_kinds),
                messages=messages,
                image_parts=image_parts,
                prompt=prompt,
                ocr_prompt_heuristic_matched=ocr_prompt_heuristic_matched,
            )
            return None, _service_error_response(
                400,
                "image_content_requires_vision_task",
                "Requests with image content must route to vision_understand or ocr.",
                model=model_id,
                provider=_catalog_model_provider_id(catalog_model),
                task_kind="vision_understand",
                extra_fields={"routeTrace": route_trace},
            )

        has_vision = "vision_understand" in task_kinds
        has_ocr = "ocr" in task_kinds
        task_kind = explicit_task_kind
        selection_reason = ""
        if not task_kind:
            if has_ocr and not has_vision:
                task_kind = "ocr"
                selection_reason = "model_only_ocr"
            elif has_vision and not has_ocr:
                task_kind = "vision_understand"
                selection_reason = "model_only_vision_understand"
            elif has_ocr and has_vision:
                task_kind = "ocr" if ocr_prompt_heuristic_matched else "vision_understand"
                selection_reason = "ocr_prompt_heuristic" if ocr_prompt_heuristic_matched else "default_vision_understand"
            else:
                task_kind = "ocr" if ocr_prompt_heuristic_matched else "vision_understand"
                selection_reason = (
                    "ocr_prompt_heuristic_without_model_allowlist"
                    if ocr_prompt_heuristic_matched
                    else "default_vision_understand_without_model_allowlist"
                )
        else:
            selection_reason = "explicit_task_kind"
        route_trace = _build_chat_route_trace(
            request_mode="multimodal",
            selected_task_kind=task_kind,
            selection_reason=selection_reason,
            explicit_task_kind=explicit_task_kind,
            model_task_kinds=sorted(task_kinds),
            messages=messages,
            image_parts=image_parts,
            prompt=prompt,
            ocr_prompt_heuristic_matched=ocr_prompt_heuristic_matched,
        )
        if task_kinds and task_kind not in task_kinds:
            return None, _service_error_response(
                400,
                f"model_task_unsupported:{task_kind}",
                f"Model {model_id} is not registered for {task_kind} tasks.",
                model=model_id,
                provider=_catalog_model_provider_id(catalog_model),
                task_kind=task_kind,
                extra_fields={"routeTrace": route_trace},
            )

        resolved_images, image_error, blocked_image_index = _resolve_chat_image_parts(base_dir, image_parts)
        if image_error:
            message = "image content must be a local path, file:// URL, or data URL."
            if image_error == "remote_image_url_not_supported":
                message = "xhub_local_service does not fetch remote image URLs; pass a local file, file:// URL, or data URL instead."
            route_trace["blockedImageIndex"] = blocked_image_index
            route_trace["blockedReasonCode"] = image_error
            return None, _service_error_response(
                400,
                image_error,
                message,
                model=model_id,
                provider=_catalog_model_provider_id(catalog_model),
                task_kind=task_kind,
                extra_fields={"routeTrace": route_trace},
            )

        route_trace = _attach_resolved_images_to_route_trace(route_trace, resolved_images)
        image_paths = [_safe_str(item.get("imagePath")) for item in resolved_images if _safe_str(item.get("imagePath"))]
        multimodal_messages: list[dict[str, Any]] = []
        resolved_index = 0
        for message in messages:
            role = _safe_str(message.get("role")).lower() or "user"
            content_rows = message.get("content") if isinstance(message.get("content"), list) else []
            resolved_content: list[dict[str, Any]] = []
            for item in content_rows:
                if not isinstance(item, dict):
                    continue
                item_type = _safe_str(item.get("type")).lower()
                if item_type == "text":
                    text = _safe_str(item.get("text"))
                    if text:
                        resolved_content.append({"type": "text", "text": text})
                    continue
                if item_type == "image" and resolved_index < len(resolved_images):
                    resolved_image = resolved_images[resolved_index]
                    resolved_index += 1
                    resolved_content.append(
                        {
                            "type": "image",
                            "imagePath": _safe_str(resolved_image.get("imagePath")),
                            "sourceKind": _safe_str(resolved_image.get("sourceKind")),
                            "detail": _safe_str(resolved_image.get("detail")),
                        }
                    )
            if resolved_content:
                multimodal_messages.append({"role": role, "content": resolved_content})

        runtime_request = {
            "task_kind": task_kind,
            "taskKind": task_kind,
            "model_id": model_id,
            "modelId": model_id,
            "provider": _catalog_model_provider_id(catalog_model),
            "image_path": image_paths[0] if image_paths else "",
            "imagePath": image_paths[0] if image_paths else "",
            "image_paths": image_paths,
            "imagePaths": image_paths,
            "image_count": len(image_paths),
            "imageCount": len(image_paths),
            "multimodal_messages": multimodal_messages,
            "multimodalMessages": multimodal_messages,
            "prompt": prompt,
            "messages": messages,
            "routeTrace": route_trace,
            "route_trace": route_trace,
            XHUB_LOCAL_SERVICE_INTERNAL_REQUEST_FLAG: True,
        }
        if _safe_str(request.get("language") or request.get("lang")):
            runtime_request["language"] = _safe_str(request.get("language") or request.get("lang"))

    max_tokens = request.get("max_completion_tokens")
    if max_tokens is None:
        max_tokens = request.get("max_tokens")
    if max_tokens is None:
        max_tokens = request.get("maxNewTokens")
    if max_tokens is not None:
        runtime_request["max_new_tokens"] = max(1, _safe_int(max_tokens, 128))
    if request.get("temperature") is not None:
        runtime_request["temperature"] = _safe_float(request.get("temperature"), 0.0)
    return runtime_request, None


def _runtime_meta_fields(runtime_result: dict[str, Any]) -> dict[str, Any]:
    out = {
        "provider": _safe_str(runtime_result.get("provider")),
        "taskKind": _safe_str(runtime_result.get("taskKind") or runtime_result.get("task_kind")),
        "latencyMs": max(0, _safe_int(runtime_result.get("latencyMs") or runtime_result.get("latency_ms"), 0)),
        "fallbackMode": _safe_str(runtime_result.get("fallbackMode") or runtime_result.get("fallback_mode")),
        "delegatedVia": "xhub_local_service",
        "serviceVersion": XHUB_LOCAL_SERVICE_RUNTIME_VERSION,
    }
    return out


def _runtime_error_response(
    request: dict[str, Any],
    runtime_result: dict[str, Any],
    *,
    task_kind: str,
    runtime_request: dict[str, Any] | None = None,
) -> tuple[int, dict[str, Any]]:
    status = _http_status_for_runtime_result(runtime_result)
    reason_code = _safe_str(runtime_result.get("reasonCode") or runtime_result.get("error")) or "local_runtime_failed"
    message = (
        _safe_str(runtime_result.get("runtimeHint"))
        or _safe_str(runtime_result.get("errorDetail"))
        or _safe_str(runtime_result.get("error"))
        or reason_code
    )
    response_status, payload = _service_error_response(
        status,
        reason_code,
        message,
        model=_safe_str(request.get("model") or runtime_result.get("modelId")),
        provider=_safe_str(runtime_result.get("provider")),
        task_kind=task_kind,
        runtime_hint=_safe_str(runtime_result.get("runtimeHint")),
        extra_fields={"routeTrace": _route_trace_payload(runtime_result, runtime_request, request)},
    )
    payload.update(_runtime_meta_fields(runtime_result))
    return response_status, payload


def _build_embeddings_success_response(request: dict[str, Any], runtime_result: dict[str, Any]) -> dict[str, Any]:
    vectors = [
        list(vector)
        for vector in (runtime_result.get("vectors") or [])
        if isinstance(vector, list)
    ]
    usage = runtime_result.get("usage") if isinstance(runtime_result.get("usage"), dict) else {}
    prompt_tokens = _runtime_usage_int(usage, "promptTokens", "prompt_tokens", "totalTokens", "total_tokens")
    total_tokens = _runtime_usage_int(usage, "totalTokens", "total_tokens")
    if total_tokens <= 0:
        total_tokens = prompt_tokens
    return {
        "object": "list",
        "data": [
            {
                "object": "embedding",
                "index": index,
                "embedding": vector,
            }
            for index, vector in enumerate(vectors)
        ],
        "model": _safe_str(request.get("model") or runtime_result.get("modelId")),
        "usage": {
            "prompt_tokens": prompt_tokens,
            "total_tokens": total_tokens,
        },
        **_runtime_meta_fields(runtime_result),
    }


def _normalize_finish_reason(value: Any) -> str:
    token = _safe_str(value).lower()
    if not token:
        return "stop"
    if token in {"completed", "eos", "done"}:
        return "stop"
    return token


def _build_chat_success_response(request: dict[str, Any], runtime_result: dict[str, Any]) -> dict[str, Any]:
    usage = runtime_result.get("usage") if isinstance(runtime_result.get("usage"), dict) else {}
    prompt_tokens = _runtime_usage_int(usage, "promptTokens", "prompt_tokens")
    completion_tokens = _runtime_usage_int(usage, "completionTokens", "completion_tokens")
    total_tokens = _runtime_usage_int(usage, "totalTokens", "total_tokens")
    if total_tokens <= 0:
        total_tokens = prompt_tokens + completion_tokens
    payload = {
        "id": f"chatcmpl-xhub-{int(time.time() * 1000)}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": _safe_str(request.get("model") or runtime_result.get("modelId")),
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": _safe_str(runtime_result.get("text")),
                },
                "finish_reason": _normalize_finish_reason(
                    runtime_result.get("finishReason") or runtime_result.get("finish_reason")
                ),
            }
        ],
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
        },
        **_runtime_meta_fields(runtime_result),
    }
    if isinstance(runtime_result.get("spans"), list):
        payload["spans"] = list(runtime_result.get("spans") or [])
    if _safe_str(runtime_result.get("language")):
        payload["language"] = _safe_str(runtime_result.get("language"))
    route_trace = _route_trace_payload(runtime_result, request)
    if route_trace is not None:
        payload["routeTrace"] = route_trace
    return payload


def _delegate_inference_action(
    *,
    run_local_task_fn: Any,
    request: dict[str, Any],
    base_dir: str,
    request_builder: Any,
    success_builder: Any,
    task_kind: str,
) -> tuple[int, dict[str, Any]]:
    if not callable(run_local_task_fn):
        return _inference_stub_response(task_kind, request)

    runtime_request, early_response = request_builder(request, base_dir=base_dir)
    if early_response is not None:
        return early_response
    if not isinstance(runtime_request, dict):
        return _service_error_response(
            500,
            "xhub_local_service_runtime_request_missing",
            "xhub_local_service failed to build a runtime request.",
            model=_safe_str(request.get("model")),
            task_kind=task_kind,
        )

    try:
        runtime_result = run_local_task_fn(runtime_request, base_dir=base_dir)
    except Exception as exc:
        return _service_error_response(
            500,
            "xhub_local_service_inference_delegate_failed",
            f"xhub_local_service failed while delegating {task_kind}: {type(exc).__name__}:{exc}",
            model=_safe_str(request.get("model")),
            task_kind=task_kind,
        )

    route_trace = _route_trace_payload(runtime_request)
    if route_trace is not None and not _route_trace_payload(runtime_result):
        runtime_result = dict(runtime_result or {})
        runtime_result["routeTrace"] = route_trace

    if not bool(runtime_result.get("ok")):
        return _runtime_error_response(
            request,
            dict(runtime_result or {}),
            task_kind=task_kind,
            runtime_request=runtime_request,
        )
    return 200, success_builder(request, dict(runtime_result or {}))


def _request_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    content_length = max(0, _safe_int(handler.headers.get("Content-Length"), 0))
    if content_length <= 0:
        return {}
    try:
        raw = handler.rfile.read(content_length)
    except Exception:
        return {}
    try:
        obj = json.loads(raw.decode("utf-8", errors="replace"))
    except Exception:
        return {}
    return obj if isinstance(obj, dict) else {}


def _write_json(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(int(status))
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _control_plane_stub_response(action: str, request: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    return 501, {
        "ok": False,
        "action": _safe_str(action),
        "reasonCode": XHUB_LOCAL_SERVICE_CONTROL_REASON,
        "status": "not_implemented",
        "runtimeHint": (
            "xhub_local_service skeleton exposes the admin contract, but warmup/unload/evict "
            "delegation is not wired yet. Keep using direct local runtime commands until the service bridge lands."
        ),
        "request": dict(request or {}),
        "version": XHUB_LOCAL_SERVICE_RUNTIME_VERSION,
    }


def _inference_stub_response(kind: str, request: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    return 501, {
        "ok": False,
        "kind": _safe_str(kind),
        "reasonCode": XHUB_LOCAL_SERVICE_INFERENCE_REASON,
        "status": "not_implemented",
        "runtimeHint": (
            "xhub_local_service skeleton is online, but inference proxying is not wired yet. "
            "Use the existing local runtime entrypoint until service-backed task routing lands."
        ),
        "request": dict(request or {}),
        "version": XHUB_LOCAL_SERVICE_RUNTIME_VERSION,
    }


def _http_status_for_runtime_result(result: dict[str, Any]) -> int:
    if bool(result.get("ok")):
        return 200
    error = _safe_str(result.get("error") or result.get("reasonCode")).lower()
    if error.startswith("missing_") or error.startswith("unsupported_") or error.startswith("unknown_"):
        return 400
    if "busy" in error or "rate_limit" in error:
        return 429
    if "not_found" in error:
        return 404
    return 503


def _delegate_admin_action(
    *,
    manage_local_model_fn: Any,
    action: str,
    request: dict[str, Any],
    base_dir: str,
) -> tuple[int, dict[str, Any]]:
    if not callable(manage_local_model_fn):
        return _control_plane_stub_response(action, request)

    forwarded_request = dict(request or {})
    forwarded_request.setdefault("action", _safe_str(action))
    forwarded_request[XHUB_LOCAL_SERVICE_INTERNAL_REQUEST_FLAG] = True
    try:
        result = manage_local_model_fn(forwarded_request, base_dir=base_dir)
    except Exception as exc:
        return 500, {
            "ok": False,
            "action": _safe_str(action),
            "reasonCode": "xhub_local_service_control_plane_delegate_failed",
            "error": f"{type(exc).__name__}:{exc}",
            "runtimeHint": "xhub_local_service failed while delegating the lifecycle action into the local runtime manager.",
            "version": XHUB_LOCAL_SERVICE_RUNTIME_VERSION,
        }

    payload = dict(result or {})
    payload.setdefault("action", _safe_str(action))
    payload.setdefault("serviceVersion", XHUB_LOCAL_SERVICE_RUNTIME_VERSION)
    payload.setdefault("delegatedVia", "xhub_local_service")
    return _http_status_for_runtime_result(payload), payload


def build_xhub_local_service_server(
    *,
    base_dir: str | None = None,
    host: str = DEFAULT_XHUB_LOCAL_SERVICE_HOST,
    port: int = DEFAULT_XHUB_LOCAL_SERVICE_PORT,
    manage_local_model_fn: Any | None = None,
    run_local_task_fn: Any | None = None,
) -> ThreadingHTTPServer:
    resolved_base_dir = os.path.abspath(str(base_dir or _base_dir()))
    resolved_host = _safe_str(host) or DEFAULT_XHUB_LOCAL_SERVICE_HOST
    resolved_port = max(0, _safe_int(port, DEFAULT_XHUB_LOCAL_SERVICE_PORT))
    os.makedirs(resolved_base_dir, exist_ok=True)
    started_at = time.time()
    lifecycle_delegate = manage_local_model if manage_local_model_fn is None else manage_local_model_fn
    inference_delegate = run_local_task if run_local_task_fn is None else run_local_task_fn

    class XHubLocalServiceHandler(BaseHTTPRequestHandler):
        server_version = "XHubLocalService/0.1"
        sys_version = ""

        def log_message(self, format: str, *args: Any) -> None:
            return

        def _health_payload(self) -> dict[str, Any]:
            actual_port = max(0, _safe_int(getattr(self.server, "server_port", resolved_port), resolved_port))
            return build_xhub_local_service_health(
                base_dir=resolved_base_dir,
                host=resolved_host,
                port=actual_port,
                started_at=started_at,
            )

        def do_GET(self) -> None:
            path = urlparse(self.path).path
            if path == "/health":
                _write_json(self, 200, self._health_payload())
                return
            if path == "/v1/models":
                _write_json(self, 200, build_xhub_local_service_model_list(resolved_base_dir))
                return
            _write_json(
                self,
                404,
                {
                    "ok": False,
                    "error": "not_found",
                    "path": path,
                },
            )

        def do_POST(self) -> None:
            path = urlparse(self.path).path
            request = _request_json(self)
            if path == "/admin/warmup":
                status, payload = _delegate_admin_action(
                    manage_local_model_fn=lifecycle_delegate,
                    action="warmup_local_model",
                    request=request,
                    base_dir=resolved_base_dir,
                )
                _write_json(self, status, payload)
                return
            if path == "/admin/unload":
                status, payload = _delegate_admin_action(
                    manage_local_model_fn=lifecycle_delegate,
                    action="unload_local_model",
                    request=request,
                    base_dir=resolved_base_dir,
                )
                _write_json(self, status, payload)
                return
            if path == "/admin/evict":
                status, payload = _delegate_admin_action(
                    manage_local_model_fn=lifecycle_delegate,
                    action="evict_local_instance",
                    request=request,
                    base_dir=resolved_base_dir,
                )
                _write_json(self, status, payload)
                return
            if path == "/v1/embeddings":
                status, payload = _delegate_inference_action(
                    run_local_task_fn=inference_delegate,
                    request=request,
                    base_dir=resolved_base_dir,
                    request_builder=_build_embeddings_runtime_request,
                    success_builder=_build_embeddings_success_response,
                    task_kind="embedding",
                )
                _write_json(self, status, payload)
                return
            if path == "/v1/chat/completions":
                status, payload = _delegate_inference_action(
                    run_local_task_fn=inference_delegate,
                    request=request,
                    base_dir=resolved_base_dir,
                    request_builder=_build_chat_runtime_request,
                    success_builder=_build_chat_success_response,
                    task_kind="text_generate",
                )
                _write_json(self, status, payload)
                return
            _write_json(
                self,
                404,
                {
                    "ok": False,
                    "error": "not_found",
                    "path": path,
                },
            )

    server = ThreadingHTTPServer((resolved_host, resolved_port), XHubLocalServiceHandler)
    server.daemon_threads = True
    return server


def _parse_common_args(args: list[str]) -> tuple[str, int, str]:
    host = DEFAULT_XHUB_LOCAL_SERVICE_HOST
    port = DEFAULT_XHUB_LOCAL_SERVICE_PORT
    base_dir = _base_dir()
    index = 0
    while index < len(args):
        token = _safe_str(args[index])
        if token == "--host" and index + 1 < len(args):
            host = _safe_str(args[index + 1]) or host
            index += 2
            continue
        if token == "--port" and index + 1 < len(args):
            port = max(0, _safe_int(args[index + 1], port))
            index += 2
            continue
        if token == "--base-dir" and index + 1 < len(args):
            base_dir = os.path.abspath(os.path.expanduser(_safe_str(args[index + 1]) or base_dir))
            index += 2
            continue
        index += 1
    return host, port, base_dir


def main(argv: list[str] | None = None) -> int:
    apply_offline_env()
    args = list(sys.argv[1:] if argv is None else argv)
    cmd = _safe_str(args[0]).lower() if args else "serve"
    tail = args[1:] if args else []
    host, port, base_dir = _parse_common_args(tail if cmd in {"serve", "health", "models"} else args)

    if cmd == "health":
        payload = build_xhub_local_service_health(
            base_dir=base_dir,
            host=host,
            port=port,
            started_at=time.time(),
        )
        print(json.dumps(payload, ensure_ascii=False, indent=2), flush=True)
        return 0

    if cmd == "models":
        payload = build_xhub_local_service_model_list(base_dir)
        print(json.dumps(payload, ensure_ascii=False, indent=2), flush=True)
        return 0

    server = build_xhub_local_service_server(
        base_dir=base_dir,
        host=host,
        port=port,
    )
    try:
        print(
            json.dumps(
                {
                    "ok": True,
                    "status": "serving",
                    "version": XHUB_LOCAL_SERVICE_RUNTIME_VERSION,
                    "baseDir": base_dir,
                    "bindHost": host,
                    "bindPort": int(server.server_port),
                },
                ensure_ascii=False,
            ),
            flush=True,
        )
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
