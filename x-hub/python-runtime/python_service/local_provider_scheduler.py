from __future__ import annotations

import json
import os
import time
import uuid
from typing import Any


SCHEDULER_SCHEMA_VERSION = "xhub.local_provider_scheduler.v1"
SCHEDULER_LOCK_STALE_SEC = 10.0
DEFAULT_QUEUE_POLL_MS = 50
DEFAULT_LEASE_TTL_MS = 15 * 60 * 1000


def _now() -> float:
    return time.time()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_int(value: Any, fallback: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return int(fallback)


def _safe_bool(value: Any, fallback: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    token = _safe_str(value).lower()
    if token in {"1", "true", "yes", "on"}:
        return True
    if token in {"0", "false", "no", "off"}:
        return False
    return bool(fallback)


def _normalize_provider_id(value: Any) -> str:
    return _safe_str(value).lower()


def _normalize_task_kind(value: Any) -> str:
    return _safe_str(value).lower()


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


def _normalize_model_task_kinds(model: dict[str, Any] | None) -> list[str]:
    row = model if isinstance(model, dict) else {}
    task_kinds = _string_list(row.get("taskKinds") or row.get("task_kinds"))
    if task_kinds:
        return task_kinds
    return ["text_generate"] if _normalize_provider_id(row.get("backend")) == "mlx" else []


def _scheduler_root(base_dir: str) -> str:
    return os.path.join(str(base_dir), "local_provider_scheduler")


def _provider_root(base_dir: str, provider_id: str) -> str:
    return os.path.join(_scheduler_root(base_dir), _normalize_provider_id(provider_id) or "unknown")


def _provider_lock_path(base_dir: str, provider_id: str) -> str:
    return os.path.join(_provider_root(base_dir, provider_id), ".scheduler.lock")


def _provider_leases_dir(base_dir: str, provider_id: str) -> str:
    return os.path.join(_provider_root(base_dir, provider_id), "leases")


def _provider_waiters_dir(base_dir: str, provider_id: str) -> str:
    return os.path.join(_provider_root(base_dir, provider_id), "waiters")


def _provider_events_path(base_dir: str, provider_id: str) -> str:
    return os.path.join(_provider_root(base_dir, provider_id), "events.json")


def _ensure_provider_dirs(base_dir: str, provider_id: str) -> None:
    os.makedirs(_provider_leases_dir(base_dir, provider_id), exist_ok=True)
    os.makedirs(_provider_waiters_dir(base_dir, provider_id), exist_ok=True)


def _read_json(path: str) -> dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            obj = json.load(handle)
        return obj if isinstance(obj, dict) else {}
    except Exception:
        return {}


def _write_json_atomic(path: str, obj: dict[str, Any]) -> None:
    tmp = f"{path}.tmp.{os.getpid()}.{uuid.uuid4().hex}"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(obj, handle, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def _remove_file(path: str) -> None:
    try:
        os.unlink(path)
    except Exception:
        pass


def _try_acquire_guard_lock(lock_path: str) -> bool:
    try:
        fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(f"{os.getpid()}\t{_now():.6f}\n")
        return True
    except FileExistsError:
        try:
            stat = os.stat(lock_path)
        except Exception:
            return False
        if (_now() - float(stat.st_mtime or 0.0)) > SCHEDULER_LOCK_STALE_SEC:
            try:
                os.unlink(lock_path)
            except Exception:
                return False
        return False


def _acquire_guard_lock(lock_path: str, *, timeout_ms: int = 2_000, poll_ms: int = 25) -> bool:
    deadline = _now() + (max(1, timeout_ms) / 1000.0)
    while _now() <= deadline:
        if _try_acquire_guard_lock(lock_path):
            return True
        time.sleep(max(0.005, poll_ms / 1000.0))
    return False


def _release_guard_lock(lock_path: str) -> None:
    try:
        os.unlink(lock_path)
    except Exception:
        pass


def _collect_entry_files(directory: str) -> list[str]:
    try:
        entries = [
            os.path.join(directory, name)
            for name in os.listdir(directory)
            if name.endswith(".json")
        ]
    except Exception:
        return []
    entries.sort()
    return entries


def _prune_stale_entries(base_dir: str, provider_id: str, *, now: float | None = None) -> None:
    ts = float(now if now is not None else _now())
    for directory in (_provider_leases_dir(base_dir, provider_id), _provider_waiters_dir(base_dir, provider_id)):
        for path in _collect_entry_files(directory):
            obj = _read_json(path)
            expires_at = float(obj.get("expiresAt") or 0.0)
            if expires_at > 0 and expires_at < ts:
                try:
                    os.unlink(path)
                except Exception:
                    pass


def _load_live_entries(base_dir: str, provider_id: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    leases: list[dict[str, Any]] = []
    waiters: list[dict[str, Any]] = []
    for path in _collect_entry_files(_provider_leases_dir(base_dir, provider_id)):
        obj = _read_json(path)
        if obj:
            leases.append(obj)
    for path in _collect_entry_files(_provider_waiters_dir(base_dir, provider_id)):
        obj = _read_json(path)
        if obj:
            waiters.append(obj)
    return leases, waiters


def _read_event_counters(base_dir: str, provider_id: str) -> dict[str, Any]:
    obj = _read_json(_provider_events_path(base_dir, provider_id))
    return {
        "contentionCount": max(0, _safe_int(obj.get("contentionCount"), 0)),
        "lastContentionAt": float(obj.get("lastContentionAt") or 0.0),
    }


def _record_contention_event(base_dir: str, provider_id: str, *, now: float | None = None) -> None:
    ts = float(now if now is not None else _now())
    path = _provider_events_path(base_dir, provider_id)
    obj = _read_json(path)
    _write_json_atomic(
        path,
        {
            "schemaVersion": SCHEDULER_SCHEMA_VERSION,
            "provider": _normalize_provider_id(provider_id),
            "contentionCount": max(0, _safe_int(obj.get("contentionCount"), 0)) + 1,
            "lastContentionAt": ts,
            "updatedAt": ts,
        },
    )


def _extract_model_resource_profile(model: dict[str, Any] | None) -> dict[str, Any]:
    row = model if isinstance(model, dict) else {}
    profile = row.get("resourceProfile") if isinstance(row.get("resourceProfile"), dict) else row.get("resource_profile")
    obj = profile if isinstance(profile, dict) else {}
    return {
        "preferred_device": _safe_str(obj.get("preferred_device") or obj.get("preferredDevice")).lower() or "unknown",
        "memory_floor_mb": max(0, _safe_int(obj.get("memory_floor_mb") or obj.get("memoryFloorMB"), 0)),
        "dtype": _safe_str(obj.get("dtype")).lower() or "unknown",
    }


def _provider_models(provider_id: str, catalog_models: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized_provider = _normalize_provider_id(provider_id)
    return [
        model
        for model in catalog_models
        if isinstance(model, dict) and _normalize_provider_id(model.get("backend")) == normalized_provider
    ]


def _task_concurrency_limit(task_kind: str, *, preferred_device: str, memory_floor_mb: int) -> int:
    task = _normalize_task_kind(task_kind)
    device = _safe_str(preferred_device).lower()
    memory_floor = max(0, _safe_int(memory_floor_mb, 0))

    if task in {"text_generate", "speech_to_text", "vision_understand", "ocr"}:
        return 1
    if task == "embedding":
        if device in {"mps", "metal"}:
            return 1
        if memory_floor >= 4096:
            return 1
        return 2
    return 1


def build_provider_resource_policy(
    provider_id: str,
    *,
    catalog_models: list[dict[str, Any]],
    request: dict[str, Any] | None = None,
) -> dict[str, Any]:
    provider = _normalize_provider_id(provider_id)
    provider_models = _provider_models(provider, catalog_models)
    request_obj = request if isinstance(request, dict) else {}
    requested_task_kind = _normalize_task_kind(request_obj.get("task_kind") or request_obj.get("taskKind"))

    preferred_device = "unknown"
    dtype = "unknown"
    memory_floor_mb = 0
    task_kinds: set[str] = set()

    for model in provider_models:
        profile = _extract_model_resource_profile(model)
        if preferred_device == "unknown" and profile["preferred_device"] != "unknown":
            preferred_device = profile["preferred_device"]
        if dtype == "unknown" and profile["dtype"] != "unknown":
            dtype = profile["dtype"]
        memory_floor_mb = max(memory_floor_mb, int(profile["memory_floor_mb"]))
        task_kinds.update(_normalize_model_task_kinds(model))

    if requested_task_kind:
        task_kinds.add(requested_task_kind)

    if provider == "mlx" and not task_kinds:
        task_kinds.add("text_generate")

    task_limits = {
        task_kind: _task_concurrency_limit(
            task_kind,
            preferred_device=preferred_device,
            memory_floor_mb=memory_floor_mb,
        )
        for task_kind in sorted(task_kinds)
    }
    concurrency_limit = min(task_limits.values()) if task_limits else 1
    selected_task_limit = task_limits.get(requested_task_kind, concurrency_limit)
    return {
        "provider": provider,
        "preferredDevice": preferred_device,
        "memoryFloorMB": memory_floor_mb,
        "dtype": dtype,
        "taskLimits": task_limits,
        "concurrencyLimit": max(1, int(concurrency_limit)),
        "selectedTaskKind": requested_task_kind,
        "selectedTaskLimit": max(1, int(selected_task_limit)),
        "queueingSupported": True,
        "queueMode": "opt_in_wait",
        "defaultQueuePollMs": DEFAULT_QUEUE_POLL_MS,
    }


def read_provider_scheduler_telemetry(
    base_dir: str,
    provider_id: str,
    *,
    policy: dict[str, Any] | None = None,
) -> dict[str, Any]:
    provider = _normalize_provider_id(provider_id)
    _ensure_provider_dirs(base_dir, provider)
    lock_path = _provider_lock_path(base_dir, provider)
    if _acquire_guard_lock(lock_path, timeout_ms=250, poll_ms=25):
        try:
            _prune_stale_entries(base_dir, provider)
            leases, waiters = _load_live_entries(base_dir, provider)
        finally:
            _release_guard_lock(lock_path)
    else:
        leases, waiters = _load_live_entries(base_dir, provider)

    event_counters = _read_event_counters(base_dir, provider)
    resource_policy = policy if isinstance(policy, dict) else {}
    return {
        "provider": provider,
        "concurrencyLimit": max(1, _safe_int(resource_policy.get("concurrencyLimit"), 1)),
        "activeTaskCount": len(leases),
        "queuedTaskCount": len(waiters),
        "activeTasks": [
            {
                "leaseId": _safe_str(entry.get("leaseId")),
                "taskKind": _normalize_task_kind(entry.get("taskKind")),
                "modelId": _safe_str(entry.get("modelId")),
                "requestId": _safe_str(entry.get("requestId")),
                "startedAt": float(entry.get("startedAt") or 0.0),
            }
            for entry in leases
        ],
        "queueMode": _safe_str(resource_policy.get("queueMode")) or "opt_in_wait",
        "queueingSupported": bool(resource_policy.get("queueingSupported", True)),
        "contentionCount": int(event_counters.get("contentionCount") or 0),
        "lastContentionAt": float(event_counters.get("lastContentionAt") or 0.0),
        "updatedAt": _now(),
    }


def acquire_provider_slot(
    base_dir: str,
    provider_id: str,
    *,
    request: dict[str, Any] | None = None,
    catalog_models: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    provider = _normalize_provider_id(provider_id)
    request_obj = request if isinstance(request, dict) else {}
    catalog = catalog_models if isinstance(catalog_models, list) else []
    policy = build_provider_resource_policy(provider, catalog_models=catalog, request=request_obj)
    limit = max(1, _safe_int(policy.get("selectedTaskLimit"), policy.get("concurrencyLimit")))
    queue_if_busy = _safe_bool(request_obj.get("queue_if_busy") if request_obj.get("queue_if_busy") is not None else request_obj.get("queueIfBusy"), False)
    queue_timeout_ms = max(0, _safe_int(request_obj.get("queue_timeout_ms") if request_obj.get("queue_timeout_ms") is not None else request_obj.get("queueTimeoutMs"), 0))
    queue_poll_ms = max(10, min(500, _safe_int(request_obj.get("queue_poll_ms") if request_obj.get("queue_poll_ms") is not None else request_obj.get("queuePollMs"), DEFAULT_QUEUE_POLL_MS)))
    lease_ttl_ms = max(1_000, min(12 * 60 * 60 * 1000, _safe_int(request_obj.get("lease_ttl_ms") if request_obj.get("lease_ttl_ms") is not None else request_obj.get("leaseTtlMs"), DEFAULT_LEASE_TTL_MS)))

    lease_id = uuid.uuid4().hex
    waiter_id = uuid.uuid4().hex
    request_id = _safe_str(request_obj.get("request_id") or request_obj.get("requestId"))
    task_kind = _normalize_task_kind(request_obj.get("task_kind") or request_obj.get("taskKind"))
    model_id = _safe_str(request_obj.get("model_id") or request_obj.get("modelId"))

    _ensure_provider_dirs(base_dir, provider)
    lock_path = _provider_lock_path(base_dir, provider)
    waiter_path = os.path.join(_provider_waiters_dir(base_dir, provider), f"{waiter_id}.json")
    lease_path = os.path.join(_provider_leases_dir(base_dir, provider), f"{lease_id}.json")
    start_ts = _now()
    deadline = start_ts + (queue_timeout_ms / 1000.0 if queue_if_busy and queue_timeout_ms > 0 else 0.0)
    wait_registered = False

    while True:
        if not _acquire_guard_lock(lock_path, timeout_ms=2_000, poll_ms=25):
            if wait_registered:
                _remove_file(waiter_path)
            return {
                "ok": False,
                "error": "scheduler_lock_timeout",
                "scheduler": {
                    "provider": provider,
                    "concurrencyLimit": limit,
                    "queueState": "lock_timeout",
                    "queueWaitMs": max(0, int(round((_now() - start_ts) * 1000.0))),
                },
            }

        try:
            now = _now()
            _prune_stale_entries(base_dir, provider, now=now)
            leases, waiters = _load_live_entries(base_dir, provider)
            active_count = len(leases)
            queued_count = len(waiters)

            if active_count < limit:
                lease_obj = {
                    "schemaVersion": SCHEDULER_SCHEMA_VERSION,
                    "provider": provider,
                    "leaseId": lease_id,
                    "requestId": request_id,
                    "taskKind": task_kind,
                    "modelId": model_id,
                    "startedAt": now,
                    "expiresAt": now + (lease_ttl_ms / 1000.0),
                    "pid": os.getpid(),
                }
                _write_json_atomic(lease_path, lease_obj)
                if wait_registered:
                    _remove_file(waiter_path)
                final_wait_ms = max(0, int(round((now - start_ts) * 1000.0)))
                return {
                    "ok": True,
                    "lease_id": lease_id,
                    "scheduler": {
                        "provider": provider,
                        "preferredDevice": _safe_str(policy.get("preferredDevice")),
                        "memoryFloorMB": max(0, _safe_int(policy.get("memoryFloorMB"), 0)),
                        "concurrencyLimit": limit,
                        "queueState": "waited" if final_wait_ms > 0 else "acquired",
                        "queueWaitMs": final_wait_ms,
                        "activeTaskCount": active_count + 1,
                        "queuedTaskCount": max(0, queued_count - (1 if wait_registered else 0)),
                    },
                }

            _record_contention_event(base_dir, provider, now=now)

            if not queue_if_busy:
                return {
                    "ok": False,
                    "error": "provider_busy",
                    "scheduler": {
                        "provider": provider,
                        "preferredDevice": _safe_str(policy.get("preferredDevice")),
                        "memoryFloorMB": max(0, _safe_int(policy.get("memoryFloorMB"), 0)),
                        "concurrencyLimit": limit,
                        "queueState": "rejected",
                        "queueWaitMs": 0,
                        "activeTaskCount": active_count,
                        "queuedTaskCount": queued_count,
                    },
                }

            if not wait_registered:
                waiter_obj = {
                    "schemaVersion": SCHEDULER_SCHEMA_VERSION,
                    "provider": provider,
                    "waiterId": waiter_id,
                    "requestId": request_id,
                    "taskKind": task_kind,
                    "modelId": model_id,
                    "startedAt": start_ts,
                    "expiresAt": now + max(1.0, (max(queue_timeout_ms, lease_ttl_ms) / 1000.0)),
                    "pid": os.getpid(),
                }
                _write_json_atomic(waiter_path, waiter_obj)
                wait_registered = True

            if queue_timeout_ms <= 0 or now >= deadline:
                _remove_file(waiter_path)
                return {
                    "ok": False,
                    "error": "provider_queue_timeout",
                    "scheduler": {
                        "provider": provider,
                        "preferredDevice": _safe_str(policy.get("preferredDevice")),
                        "memoryFloorMB": max(0, _safe_int(policy.get("memoryFloorMB"), 0)),
                        "concurrencyLimit": limit,
                        "queueState": "timed_out",
                        "queueWaitMs": max(0, int(round((now - start_ts) * 1000.0))),
                        "activeTaskCount": active_count,
                        "queuedTaskCount": queued_count + (0 if wait_registered else 1),
                    },
                }
        finally:
            _release_guard_lock(lock_path)

        time.sleep(queue_poll_ms / 1000.0)


def release_provider_slot(base_dir: str, provider_id: str, lease_id: str) -> None:
    provider = _normalize_provider_id(provider_id)
    lease = _safe_str(lease_id)
    if not provider or not lease:
        return
    path = os.path.join(_provider_leases_dir(base_dir, provider), f"{lease}.json")
    try:
        os.unlink(path)
    except Exception:
        pass
