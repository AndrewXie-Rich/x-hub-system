"""Canonical local provider runtime entrypoint for X-Hub.

This entrypoint is intentionally low-risk in v1:
- it owns provider registry / status aggregation
- it keeps the runtime offline-only
- the default execution path still delegates to the proven MLX runtime loop
"""

from __future__ import annotations

import json
import os
import sys
import time
from typing import Any

from providers import LocalProviderRegistry, MLXProvider, TransformersProvider
from providers.mlx_provider import run_legacy_runtime


# Keep this aligned with the legacy runtime version so Hub's runtime-version
# watchdog does not trigger restart loops during the delegate phase.
RUNTIME_VERSION = "2026-02-21-constitution-trigger-v2"
LOCAL_RUNTIME_ENTRY_VERSION = "2026-03-12-lpr-skeleton-v1"
LOCAL_RUNTIME_STATUS_SCHEMA_VERSION = "xhub.local_provider_runtime.entry.v1"


def _group_base_dir() -> str:
    return os.path.expanduser("~/Library/Group Containers/group.rel.flowhub")


def _base_dir() -> str:
    env = (os.environ.get("REL_FLOW_HUB_BASE_DIR") or "").strip()
    return os.path.expanduser(env) if env else _group_base_dir()


def _catalog_path(base_dir: str) -> str:
    return os.path.join(base_dir, "models_catalog.json")


def _now() -> float:
    return time.time()


def apply_offline_env() -> None:
    defaults = {
        "PYTHONUNBUFFERED": "1",
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "HF_DATASETS_OFFLINE": "1",
        "TOKENIZERS_PARALLELISM": "false",
    }
    for key, value in defaults.items():
        os.environ.setdefault(key, value)


def read_catalog_models(base_dir: str) -> list[dict[str, Any]]:
    path = _catalog_path(base_dir)
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as handle:
            obj = json.load(handle)
    except Exception:
        return []

    if isinstance(obj, dict) and isinstance(obj.get("models"), list):
        return [item for item in obj.get("models") if isinstance(item, dict)]
    if isinstance(obj, list):
        return [item for item in obj if isinstance(item, dict)]
    return []


def build_registry(*, runtime: Any | None = None) -> LocalProviderRegistry:
    registry = LocalProviderRegistry()
    registry.register(MLXProvider(runtime=runtime, runtime_version=RUNTIME_VERSION))
    registry.register(TransformersProvider())
    return registry


def provider_status_snapshot(base_dir: str, *, runtime: Any | None = None) -> dict[str, dict[str, Any]]:
    catalog_models = read_catalog_models(base_dir)
    snapshot = build_registry(runtime=runtime).health_snapshot(
        base_dir=base_dir,
        catalog_models=catalog_models,
    )
    return {provider_id: health.to_dict() for provider_id, health in snapshot.items()}


def _resolve_provider_id(request: dict[str, Any], *, catalog_models: list[dict[str, Any]]) -> str:
    explicit_provider = str(request.get("provider") or request.get("backend") or "").strip().lower()
    if explicit_provider:
        return explicit_provider

    model_id = str(request.get("model_id") or request.get("modelId") or "").strip()
    if model_id:
        for model in catalog_models:
            if str(model.get("id") or "").strip() != model_id:
                continue
            backend = str(model.get("backend") or "").strip().lower()
            if backend:
                return backend

    task_kind = str(request.get("task_kind") or request.get("taskKind") or "").strip().lower()
    if task_kind == "text_generate":
        return "mlx"
    return ""


def run_local_task(request: dict[str, Any], *, base_dir: str | None = None) -> dict[str, Any]:
    base = str(base_dir or _base_dir())
    catalog_models = read_catalog_models(base)
    provider_id = _resolve_provider_id(request, catalog_models=catalog_models)
    task_kind = str(request.get("task_kind") or request.get("taskKind") or "").strip().lower()

    if not provider_id:
        return {
            "ok": False,
            "error": "provider_not_resolved",
            "taskKind": task_kind,
            "request": dict(request or {}),
        }

    registry = build_registry()
    provider = registry.get(provider_id)
    if provider is None:
        return {
            "ok": False,
            "provider": provider_id,
            "taskKind": task_kind,
            "error": f"unknown_provider:{provider_id}",
            "request": dict(request or {}),
        }

    if task_kind and task_kind not in provider.supported_task_kinds():
        return {
            "ok": False,
            "provider": provider_id,
            "taskKind": task_kind,
            "error": f"unsupported_task_kind:{task_kind}",
            "request": dict(request or {}),
        }

    out = provider.run_task(dict(request or {}))
    out.setdefault("provider", provider_id)
    if task_kind:
        out.setdefault("taskKind", task_kind)
    out.setdefault("runtimeVersion", RUNTIME_VERSION)
    out.setdefault("localRuntimeEntryVersion", LOCAL_RUNTIME_ENTRY_VERSION)
    out.setdefault("updatedAt", _now())
    return out


def _load_request_arg(raw: str) -> dict[str, Any]:
    token = str(raw or "").strip()
    if not token:
        return {}
    if token == "-":
        data = sys.stdin.read()
        return json.loads(data) if data.strip() else {}
    if os.path.exists(token):
        with open(token, "r", encoding="utf-8") as handle:
            obj = json.load(handle)
        return obj if isinstance(obj, dict) else {}
    obj = json.loads(token)
    return obj if isinstance(obj, dict) else {}


def _status_payload(base_dir: str) -> dict[str, Any]:
    providers = provider_status_snapshot(base_dir)
    ready_provider_ids = sorted(
        provider_id
        for provider_id, status in providers.items()
        if isinstance(status, dict) and bool(status.get("ok"))
    )
    return {
        "schemaVersion": LOCAL_RUNTIME_STATUS_SCHEMA_VERSION,
        "runtimeVersion": RUNTIME_VERSION,
        "localRuntimeEntryVersion": LOCAL_RUNTIME_ENTRY_VERSION,
        "baseDir": base_dir,
        "providerIds": sorted(providers.keys()),
        "readyProviderIds": ready_provider_ids,
        "catalogModelCount": len(read_catalog_models(base_dir)),
        "providers": providers,
        "updatedAt": _now(),
    }


def _print_status(base_dir: str) -> None:
    print(json.dumps(_status_payload(base_dir), ensure_ascii=False, indent=2), flush=True)


def main(argv: list[str] | None = None) -> int:
    apply_offline_env()
    args = list(sys.argv[1:] if argv is None else argv)
    base_dir = _base_dir()
    os.makedirs(base_dir, exist_ok=True)

    if args:
        cmd = str(args[0] or "").strip().lower()
        if cmd in {"status", "--status", "--status-json", "providers"}:
            _print_status(base_dir)
            return 0
        if cmd == "run-local-task":
            request = _load_request_arg(args[1] if len(args) > 1 else "-")
            print(json.dumps(run_local_task(request, base_dir=base_dir), ensure_ascii=False, indent=2), flush=True)
            return 0

    snapshot = _status_payload(base_dir)
    ready = snapshot.get("readyProviderIds") or []
    ready_text = ",".join(str(provider_id) for provider_id in ready) if ready else "none"
    print(
        f"[local_runtime] start pid={os.getpid()} version={RUNTIME_VERSION} "
        f"entry={LOCAL_RUNTIME_ENTRY_VERSION} ready={ready_text}",
        flush=True,
    )
    return run_legacy_runtime()


if __name__ == "__main__":
    raise SystemExit(main())
