from __future__ import annotations

import base64
import json
import os
import sys
import tempfile
import threading
import types
import urllib.error
import urllib.request
from contextlib import contextmanager
from typing import Any


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if THIS_DIR not in sys.path:
    sys.path.insert(0, THIS_DIR)

from xhub_local_service_bridge import probe_xhub_local_service
from provider_runtime_resolver import resolve_provider_runtime
from xhub_local_service_runtime import (
    XHUB_LOCAL_SERVICE_HEALTH_SCHEMA_VERSION,
    build_xhub_local_service_server,
)


def run(name: str, fn) -> None:
    try:
        fn()
        sys.stdout.write(f"ok - {name}\n")
    except Exception:
        sys.stderr.write(f"not ok - {name}\n")
        raise


def write_json(path: str, obj: Any) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(obj, handle)


def write_png(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    payload = base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6d8AAAAASUVORK5CYII="
    )
    with open(path, "wb") as handle:
        handle.write(payload)


def request_json(url: str, *, method: str = "GET", payload: dict[str, Any] | None = None) -> tuple[int, dict[str, Any]]:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=2.5) as response:
            raw = response.read().decode("utf-8", errors="replace")
            return int(response.status), json.loads(raw or "{}")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        return int(getattr(exc, "code", 0) or 0), json.loads(raw or "{}")


@contextmanager
def running_local_service(
    base_dir: str,
    *,
    manage_local_model_fn: Any | None = None,
    run_local_task_fn: Any | None = None,
):
    server = build_xhub_local_service_server(
        base_dir=base_dir,
        host="127.0.0.1",
        port=0,
        manage_local_model_fn=manage_local_model_fn,
        run_local_task_fn=run_local_task_fn,
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f"http://127.0.0.1:{server.server_port}"
    try:
        yield base_url
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2.0)


def _test_health_endpoint_matches_bridge_probe_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_health_") as base_dir:
        with running_local_service(base_dir) as base_url:
            status, payload = request_json(f"{base_url}/health")
            probe = probe_xhub_local_service(base_url)

    assert status == 200
    assert payload["ok"] is True
    assert payload["status"] == "ready"
    assert payload["schemaVersion"] == XHUB_LOCAL_SERVICE_HEALTH_SCHEMA_VERSION
    assert "list_models" in (payload.get("capabilities") or [])
    assert probe.ready is True
    assert probe.reason_code == "xhub_local_service_ready"
    assert "warmup" in probe.supported_operations


def _test_models_endpoint_returns_catalog_inventory() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_models_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "bge-small",
                        "backend": "transformers",
                        "modelPath": "/models/bge-small",
                        "taskKinds": ["embedding"],
                        "maxContextLength": 8192,
                    },
                    {
                        "id": "mlx-qwen",
                        "backend": "mlx",
                        "modelPath": "/models/mlx-qwen",
                        "taskKinds": ["text_generate"],
                        "contextLength": 4096,
                    },
                ]
            },
        )
        with running_local_service(base_dir) as base_url:
            status, payload = request_json(f"{base_url}/v1/models")

    assert status == 200
    assert payload["object"] == "list"
    assert payload["count"] == 2
    assert payload["data"][0]["id"] == "bge-small"
    assert payload["data"][0]["provider"] == "transformers"
    assert payload["data"][1]["id"] == "mlx-qwen"
    assert payload["data"][1]["maxContextLength"] == 4096


def _test_admin_contract_delegates_to_local_runtime_manager() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_admin_") as base_dir:
        calls: list[dict[str, Any]] = []

        def fake_manage_local_model(request: dict[str, Any], *, base_dir: str) -> dict[str, Any]:
            calls.append(
                {
                    "request": dict(request or {}),
                    "base_dir": base_dir,
                }
            )
            return {
                "ok": True,
                "provider": "transformers",
                "action": str(request.get("action") or ""),
                "modelId": str(request.get("model") or request.get("modelId") or ""),
                "reasonCode": "delegated_ok",
            }

        with running_local_service(base_dir, manage_local_model_fn=fake_manage_local_model) as base_url:
            status, payload = request_json(
                f"{base_url}/admin/warmup",
                method="POST",
                payload={"provider": "transformers", "model": "bge-small"},
            )

    assert status == 200
    assert payload["ok"] is True
    assert payload["reasonCode"] == "delegated_ok"
    assert payload["action"] == "warmup_local_model"
    assert payload["delegatedVia"] == "xhub_local_service"
    assert calls[0]["request"]["action"] == "warmup_local_model"
    assert calls[0]["request"]["provider"] == "transformers"
    assert calls[0]["request"]["_xhub_local_service_internal"] is True
    assert calls[0]["base_dir"] == base_dir


def _test_embeddings_contract_delegates_to_local_runtime_and_returns_openai_shape() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_embed_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "bge-small",
                        "backend": "transformers",
                        "modelPath": "/models/bge-small",
                        "taskKinds": ["embedding"],
                    }
                ]
            },
        )
        calls: list[dict[str, Any]] = []

        def fake_run_local_task(request: dict[str, Any], *, base_dir: str) -> dict[str, Any]:
            calls.append({"request": dict(request or {}), "base_dir": base_dir})
            return {
                "ok": True,
                "provider": "transformers",
                "taskKind": "embedding",
                "modelId": "bge-small",
                "vectors": [[0.11, 0.22], [0.33, 0.44]],
                "dims": 2,
                "latencyMs": 12,
                "usage": {
                    "promptTokens": 8,
                    "totalTokens": 8,
                },
            }

        with running_local_service(base_dir, run_local_task_fn=fake_run_local_task) as base_url:
            status, payload = request_json(
                f"{base_url}/v1/embeddings",
                method="POST",
                payload={"model": "bge-small", "input": ["hello world", "hi again"]},
            )

    assert status == 200
    assert payload["object"] == "list"
    assert payload["model"] == "bge-small"
    assert payload["usage"]["prompt_tokens"] == 8
    assert payload["data"][0]["object"] == "embedding"
    assert payload["data"][1]["embedding"] == [0.33, 0.44]
    assert payload["delegatedVia"] == "xhub_local_service"
    assert calls[0]["request"]["task_kind"] == "embedding"
    assert calls[0]["request"]["texts"] == ["hello world", "hi again"]
    assert calls[0]["request"]["provider"] == "transformers"
    assert calls[0]["request"]["_xhub_local_service_internal"] is True
    assert calls[0]["base_dir"] == base_dir


def _test_chat_contract_delegates_to_local_runtime_and_returns_openai_shape() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_chat_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "qwen-local",
                        "backend": "transformers",
                        "modelPath": "/models/qwen-local",
                        "taskKinds": ["text_generate"],
                    }
                ]
            },
        )
        calls: list[dict[str, Any]] = []

        def fake_run_local_task(request: dict[str, Any], *, base_dir: str) -> dict[str, Any]:
            calls.append({"request": dict(request or {}), "base_dir": base_dir})
            return {
                "ok": True,
                "provider": "transformers",
                "taskKind": "text_generate",
                "modelId": "qwen-local",
                "text": "已收到，继续执行下一步。",
                "finishReason": "stop",
                "latencyMs": 21,
                "usage": {
                    "promptTokens": 17,
                    "completionTokens": 9,
                    "totalTokens": 26,
                },
            }

        with running_local_service(base_dir, run_local_task_fn=fake_run_local_task) as base_url:
            status, payload = request_json(
                f"{base_url}/v1/chat/completions",
                method="POST",
                payload={
                    "model": "qwen-local",
                    "messages": [
                        {"role": "system", "content": "你是 supervisor。"},
                        {"role": "user", "content": "继续推进这个项目"},
                    ],
                    "max_tokens": 128,
                    "temperature": 0.2,
                },
            )

    assert status == 200
    assert payload["object"] == "chat.completion"
    assert payload["model"] == "qwen-local"
    assert payload["choices"][0]["message"]["content"] == "已收到，继续执行下一步。"
    assert payload["choices"][0]["finish_reason"] == "stop"
    assert payload["usage"]["total_tokens"] == 26
    assert payload["delegatedVia"] == "xhub_local_service"
    assert calls[0]["request"]["task_kind"] == "text_generate"
    assert calls[0]["request"]["max_new_tokens"] == 128
    assert calls[0]["request"]["temperature"] == 0.2
    assert calls[0]["request"]["_xhub_local_service_internal"] is True


def _test_chat_contract_routes_local_image_parts_into_vision_task() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_chat_vision_") as base_dir:
        image_path = os.path.join(base_dir, "frame.png")
        write_png(image_path)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "vision-local",
                        "backend": "transformers",
                        "modelPath": "/models/vision-local",
                        "taskKinds": ["vision_understand"],
                    }
                ]
            },
        )
        calls: list[dict[str, Any]] = []

        def fake_run_local_task(request: dict[str, Any], *, base_dir: str) -> dict[str, Any]:
            calls.append({"request": dict(request or {}), "base_dir": base_dir})
            return {
                "ok": True,
                "provider": "transformers",
                "taskKind": "vision_understand",
                "modelId": "vision-local",
                "text": "我看到了一个很小的测试图片。",
                "latencyMs": 18,
                "usage": {
                    "promptTokens": 11,
                    "completionTokens": 8,
                    "totalTokens": 19,
                },
            }

        with running_local_service(base_dir, run_local_task_fn=fake_run_local_task) as base_url:
            status, payload = request_json(
                f"{base_url}/v1/chat/completions",
                method="POST",
                payload={
                    "model": "vision-local",
                    "messages": [
                        {"role": "system", "content": "你是视觉助手。"},
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "请描述这张图"},
                                {"type": "image_url", "image_url": {"url": f"file://{image_path}"}},
                            ],
                        },
                    ],
                },
            )

    assert status == 200
    assert payload["object"] == "chat.completion"
    assert payload["taskKind"] == "vision_understand"
    assert payload["choices"][0]["message"]["content"] == "我看到了一个很小的测试图片。"
    assert calls[0]["request"]["task_kind"] == "vision_understand"
    assert calls[0]["request"]["image_path"] == image_path
    assert calls[0]["request"]["image_paths"] == [image_path]
    assert calls[0]["request"]["imageCount"] == 1
    assert "请描述这张图" in str(calls[0]["request"]["prompt"])
    assert payload["routeTrace"]["selectedTaskKind"] == "vision_understand"
    assert payload["routeTrace"]["selectionReason"] == "model_only_vision_understand"
    assert payload["routeTrace"]["imageCount"] == 1
    assert payload["routeTrace"]["resolvedImageCount"] == 1
    assert calls[0]["request"]["_xhub_local_service_internal"] is True


def _test_chat_contract_routes_multiple_local_image_parts_into_vision_task_and_emits_route_trace() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_chat_multi_vision_") as base_dir:
        image_a = os.path.join(base_dir, "FrameA.PNG")
        image_b = os.path.join(base_dir, "FrameB.PNG")
        write_png(image_a)
        write_png(image_b)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "vision-local",
                        "backend": "transformers",
                        "modelPath": "/models/vision-local",
                        "taskKinds": ["vision_understand"],
                    }
                ]
            },
        )
        calls: list[dict[str, Any]] = []

        def fake_run_local_task(request: dict[str, Any], *, base_dir: str) -> dict[str, Any]:
            calls.append({"request": dict(request or {}), "base_dir": base_dir})
            return {
                "ok": True,
                "provider": "transformers",
                "taskKind": "vision_understand",
                "modelId": "vision-local",
                "text": "我看到了两张测试图片。",
                "latencyMs": 20,
                "usage": {
                    "promptTokens": 14,
                    "completionTokens": 7,
                    "totalTokens": 21,
                },
            }

        with running_local_service(base_dir, run_local_task_fn=fake_run_local_task) as base_url:
            status, payload = request_json(
                f"{base_url}/v1/chat/completions",
                method="POST",
                payload={
                    "model": "vision-local",
                    "messages": [
                        {"role": "system", "content": "你是视觉助手。"},
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "比较这两张图"},
                                {"type": "image_url", "image_url": {"url": f"file://{image_a}"}},
                                {"type": "image_url", "image_url": {"url": f"file://{image_b}"}},
                            ],
                        },
                    ],
                },
            )

    assert status == 200
    assert payload["taskKind"] == "vision_understand"
    assert payload["choices"][0]["message"]["content"] == "我看到了两张测试图片。"
    assert calls[0]["request"]["task_kind"] == "vision_understand"
    assert calls[0]["request"]["image_paths"] == [image_a, image_b]
    assert calls[0]["request"]["imageCount"] == 2
    assert len(calls[0]["request"]["multimodal_messages"]) == 2
    assert payload["routeTrace"]["selectedTaskKind"] == "vision_understand"
    assert payload["routeTrace"]["selectionReason"] == "model_only_vision_understand"
    assert payload["routeTrace"]["imageCount"] == 2
    assert payload["routeTrace"]["resolvedImageCount"] == 2
    assert [row["fileName"] for row in payload["routeTrace"]["resolvedImages"]] == ["FrameA.PNG", "FrameB.PNG"]


def _test_chat_contract_routes_multiple_local_image_parts_into_ocr_and_preserves_page_aware_spans() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_chat_multi_ocr_") as base_dir:
        image_a = os.path.join(base_dir, "ReceiptA.PNG")
        image_b = os.path.join(base_dir, "ReceiptB.PNG")
        write_png(image_a)
        write_png(image_b)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "vision-local",
                        "backend": "transformers",
                        "modelPath": "/models/vision-local",
                        "taskKinds": ["vision_understand", "ocr"],
                    }
                ]
            },
        )
        calls: list[dict[str, Any]] = []

        def fake_run_local_task(request: dict[str, Any], *, base_dir: str) -> dict[str, Any]:
            calls.append({"request": dict(request or {}), "base_dir": base_dir})
            return {
                "ok": True,
                "provider": "transformers",
                "taskKind": "ocr",
                "modelId": "vision-local",
                "text": "[page 1] 牛奶 3.50\n\n[page 2] 面包 5.20",
                "spans": [
                    {
                        "index": 0,
                        "pageIndex": 0,
                        "pageCount": 2,
                        "fileName": "ReceiptA.PNG",
                        "text": "牛奶 3.50",
                        "bbox": {"x": 0, "y": 0, "width": 1, "height": 1},
                    },
                    {
                        "index": 1,
                        "pageIndex": 1,
                        "pageCount": 2,
                        "fileName": "ReceiptB.PNG",
                        "text": "面包 5.20",
                        "bbox": {"x": 0, "y": 0, "width": 1, "height": 1},
                    },
                ],
                "latencyMs": 24,
                "usage": {
                    "promptTokens": 15,
                    "completionTokens": 8,
                    "totalTokens": 23,
                },
            }

        with running_local_service(base_dir, run_local_task_fn=fake_run_local_task) as base_url:
            status, payload = request_json(
                f"{base_url}/v1/chat/completions",
                method="POST",
                payload={
                    "model": "vision-local",
                    "messages": [
                        {"role": "system", "content": "你是 OCR 助手。"},
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "请提取这两页收据里的所有文字"},
                                {"type": "image_url", "image_url": {"url": f"file://{image_a}"}},
                                {"type": "image_url", "image_url": {"url": f"file://{image_b}"}},
                            ],
                        },
                    ],
                },
            )

    assert status == 200
    assert payload["taskKind"] == "ocr"
    assert calls[0]["request"]["task_kind"] == "ocr"
    assert calls[0]["request"]["image_paths"] == [image_a, image_b]
    assert calls[0]["request"]["imageCount"] == 2
    assert payload["routeTrace"]["selectedTaskKind"] == "ocr"
    assert payload["routeTrace"]["selectionReason"] == "ocr_prompt_heuristic"
    assert payload["routeTrace"]["imageCount"] == 2
    assert isinstance(payload["spans"], list)
    assert len(payload["spans"]) == 2
    assert payload["spans"][0]["pageIndex"] == 0
    assert payload["spans"][0]["pageCount"] == 2
    assert payload["spans"][0]["fileName"] == "ReceiptA.PNG"
    assert payload["spans"][1]["pageIndex"] == 1
    assert payload["spans"][1]["pageCount"] == 2
    assert payload["spans"][1]["fileName"] == "ReceiptB.PNG"


def _test_chat_contract_routes_local_image_parts_into_ocr_task_when_prompt_looks_like_ocr() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_chat_ocr_") as base_dir:
        image_path = os.path.join(base_dir, "receipt.png")
        write_png(image_path)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "vision-local",
                        "backend": "transformers",
                        "modelPath": "/models/vision-local",
                        "taskKinds": ["vision_understand", "ocr"],
                    }
                ]
            },
        )
        calls: list[dict[str, Any]] = []

        def fake_run_local_task(request: dict[str, Any], *, base_dir: str) -> dict[str, Any]:
            calls.append({"request": dict(request or {}), "base_dir": base_dir})
            return {
                "ok": True,
                "provider": "transformers",
                "taskKind": "ocr",
                "modelId": "vision-local",
                "text": "牛奶 3.50",
                "spans": [{"index": 0, "text": "牛奶 3.50"}],
                "latencyMs": 22,
                "usage": {
                    "promptTokens": 9,
                    "completionTokens": 4,
                    "totalTokens": 13,
                },
            }

        with running_local_service(base_dir, run_local_task_fn=fake_run_local_task) as base_url:
            status, payload = request_json(
                f"{base_url}/v1/chat/completions",
                method="POST",
                payload={
                    "model": "vision-local",
                    "messages": [
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "请提取这张图里的所有文字"},
                                {"type": "image_url", "image_url": {"url": f"file://{image_path}"}},
                            ],
                        }
                    ],
                },
            )

    assert status == 200
    assert payload["taskKind"] == "ocr"
    assert payload["choices"][0]["message"]["content"] == "牛奶 3.50"
    assert isinstance(payload["spans"], list)
    assert calls[0]["request"]["task_kind"] == "ocr"
    assert payload["routeTrace"]["selectedTaskKind"] == "ocr"
    assert payload["routeTrace"]["selectionReason"] == "ocr_prompt_heuristic"
    assert payload["routeTrace"]["imageCount"] == 1


def _test_chat_contract_honors_explicit_task_kind_override_and_emits_route_trace() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_chat_explicit_task_") as base_dir:
        image_path = os.path.join(base_dir, "ReceiptA.PNG")
        write_png(image_path)
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "vision-local",
                        "backend": "transformers",
                        "modelPath": "/models/vision-local",
                        "taskKinds": ["vision_understand", "ocr"],
                    }
                ]
            },
        )
        calls: list[dict[str, Any]] = []

        def fake_run_local_task(request: dict[str, Any], *, base_dir: str) -> dict[str, Any]:
            calls.append({"request": dict(request or {}), "base_dir": base_dir})
            return {
                "ok": True,
                "provider": "transformers",
                "taskKind": "ocr",
                "modelId": "vision-local",
                "text": "收据文字已识别。",
                "spans": [{"index": 0, "text": "收据文字已识别。"}],
                "latencyMs": 19,
                "usage": {
                    "promptTokens": 8,
                    "completionTokens": 5,
                    "totalTokens": 13,
                },
            }

        with running_local_service(base_dir, run_local_task_fn=fake_run_local_task) as base_url:
            status, payload = request_json(
                f"{base_url}/v1/chat/completions",
                method="POST",
                payload={
                    "model": "vision-local",
                    "task_kind": "ocr",
                    "messages": [
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "请概括这张图的大意"},
                                {"type": "image_url", "image_url": {"url": f"file://{image_path}"}},
                            ],
                        }
                    ],
                },
            )

    assert status == 200
    assert payload["taskKind"] == "ocr"
    assert calls[0]["request"]["task_kind"] == "ocr"
    assert payload["routeTrace"]["selectedTaskKind"] == "ocr"
    assert payload["routeTrace"]["selectionReason"] == "explicit_task_kind"
    assert payload["routeTrace"]["explicitTaskKind"] == "ocr"
    assert payload["routeTrace"]["imageCount"] == 1


def _test_chat_contract_rejects_remote_image_urls_fail_closed() -> None:
    with tempfile.TemporaryDirectory(prefix="xhub_local_service_chat_guard_") as base_dir:
        write_json(
            os.path.join(base_dir, "models_catalog.json"),
            {
                "models": [
                    {
                        "id": "vision-local",
                        "backend": "transformers",
                        "modelPath": "/models/vision-local",
                        "taskKinds": ["vision_understand"],
                    }
                ]
            },
        )
        called = {"value": False}

        def fake_run_local_task(request: dict[str, Any], *, base_dir: str) -> dict[str, Any]:
            called["value"] = True
            return {"ok": True}

        with running_local_service(base_dir, run_local_task_fn=fake_run_local_task) as base_url:
            status, payload = request_json(
                f"{base_url}/v1/chat/completions",
                method="POST",
                payload={
                    "model": "vision-local",
                    "messages": [
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": "请描述这张图"},
                                {"type": "image_url", "image_url": {"url": "https://example.com/image.png"}},
                            ],
                        }
                    ],
                },
            )

    assert status == 400
    assert payload["ok"] is False
    assert payload["reasonCode"] == "remote_image_url_not_supported"
    assert payload["routeTrace"]["imageCount"] == 1
    assert payload["routeTrace"]["blockedReasonCode"] == "remote_image_url_not_supported"
    assert payload["routeTrace"]["blockedImageIndex"] == 0
    assert called["value"] is False


def _test_service_hosted_runtime_resolution_marks_modules_ready_for_internal_execution() -> None:
    import provider_runtime_resolver as resolver_module

    with tempfile.TemporaryDirectory(prefix="xhub_local_service_internal_runtime_") as base_dir:
        os.makedirs(os.path.join(base_dir, "py_deps", "site-packages"), exist_ok=True)
        write_json(
            os.path.join(base_dir, "provider_pack_registry.json"),
            {
                "schemaVersion": "xhub.provider_pack_registry.v1",
                "packs": [
                    {
                        "providerId": "transformers",
                        "runtimeRequirements": {
                            "executionMode": "xhub_local_service",
                            "serviceBaseUrl": "http://127.0.0.1:50171",
                            "pythonModules": ["transformers", "torch", "tokenizers", "PIL"],
                        },
                    }
                ],
            },
        )

        original_find_spec = resolver_module.importlib.util.find_spec
        original_import_module = resolver_module.importlib.import_module

        def fake_find_spec(name: str):
            if name == "PIL":
                origin_name = "PIL"
            else:
                origin_name = name
            if name in {"transformers", "torch", "tokenizers", "PIL"}:
                return types.SimpleNamespace(
                    origin=os.path.join(base_dir, "py_deps", "site-packages", origin_name, "__init__.py"),
                    submodule_search_locations=None,
                )
            return None

        def fake_import_module(name: str):
            if name in {"transformers", "torch", "tokenizers", "PIL"}:
                return types.SimpleNamespace(__file__=os.path.join(base_dir, "py_deps", "site-packages", name, "__init__.py"))
            raise ModuleNotFoundError(name)

        resolver_module.importlib.util.find_spec = fake_find_spec
        resolver_module.importlib.import_module = fake_import_module
        try:
            resolution = resolve_provider_runtime(
                "transformers",
                base_dir=base_dir,
                service_hosted_runtime=True,
            )
        finally:
            resolver_module.importlib.util.find_spec = original_find_spec
            resolver_module.importlib.import_module = original_import_module

    assert resolution.runtime_source == "xhub_local_service"
    assert resolution.runtime_reason_code == "xhub_local_service_ready"
    assert resolution.runtime_resolution_state == "pack_runtime_ready"
    assert resolution.supports_modules("transformers", "torch")
    assert "service-hosted Python modules" in resolution.runtime_hint


run("xhub_local_service /health is bridge-compatible and reports the skeleton contract", lambda: _test_health_endpoint_matches_bridge_probe_contract())
run("xhub_local_service /v1/models returns catalog inventory machine-readably", lambda: _test_models_endpoint_returns_catalog_inventory())
run("xhub_local_service admin endpoints delegate lifecycle actions into the local runtime manager", lambda: _test_admin_contract_delegates_to_local_runtime_manager())
run("xhub_local_service /v1/embeddings proxies into the local runtime with OpenAI-style output", lambda: _test_embeddings_contract_delegates_to_local_runtime_and_returns_openai_shape())
run("xhub_local_service /v1/chat/completions proxies into the local runtime with OpenAI-style output", lambda: _test_chat_contract_delegates_to_local_runtime_and_returns_openai_shape())
run("xhub_local_service routes local image chat parts into vision_understand", lambda: _test_chat_contract_routes_local_image_parts_into_vision_task())
run("xhub_local_service routes multiple local image chat parts into vision_understand and emits route trace", lambda: _test_chat_contract_routes_multiple_local_image_parts_into_vision_task_and_emits_route_trace())
run("xhub_local_service routes multiple local image chat parts into ocr and preserves page-aware spans", lambda: _test_chat_contract_routes_multiple_local_image_parts_into_ocr_and_preserves_page_aware_spans())
run("xhub_local_service routes OCR-like image chat prompts into ocr", lambda: _test_chat_contract_routes_local_image_parts_into_ocr_task_when_prompt_looks_like_ocr())
run("xhub_local_service honors explicit task_kind override for image chat routes", lambda: _test_chat_contract_honors_explicit_task_kind_override_and_emits_route_trace())
run("xhub_local_service rejects remote image URLs fail-closed", lambda: _test_chat_contract_rejects_remote_image_urls_fail_closed())
run("service-hosted runtime resolution marks modules ready when xhub_local_service executes internally", lambda: _test_service_hosted_runtime_resolution_marks_modules_ready_for_internal_execution())
