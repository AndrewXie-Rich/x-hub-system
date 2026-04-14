from __future__ import annotations

from dataclasses import dataclass, field
import json
import os
import subprocess
import sys
import time
from typing import Any
import urllib.error
import urllib.request
from urllib.parse import urlparse


DEFAULT_XHUB_LOCAL_SERVICE_TIMEOUT_SEC = 2.5
DEFAULT_XHUB_LOCAL_SERVICE_START_TIMEOUT_SEC = 8.0
DEFAULT_XHUB_LOCAL_SERVICE_START_POLL_INTERVAL_SEC = 0.25
DEFAULT_XHUB_LOCAL_SERVICE_HOST = "127.0.0.1"
DEFAULT_XHUB_LOCAL_SERVICE_PORT = 50171
XHUB_LOCAL_SERVICE_STATE_SCHEMA_VERSION = "xhub.local_service.state.v1"
XHUB_LOCAL_SERVICE_STATE_FILENAME = "xhub_local_service_state.json"
XHUB_LOCAL_SERVICE_STDOUT_LOG_FILENAME = "xhub_local_service.stdout.log"
XHUB_LOCAL_SERVICE_STDERR_LOG_FILENAME = "xhub_local_service.stderr.log"
_XHUB_LOCAL_SERVICE_SUPPORTED_OPERATIONS = [
    "health",
    "list_models",
    "embeddings",
    "chat_completions",
    "warmup",
    "unload",
    "evict",
]
_XHUB_LOCAL_SERVICE_ALLOWED_HOSTS = {"127.0.0.1", "localhost", "::1"}
_XHUB_LOCAL_SERVICE_WAITABLE_REASON_CODES = {
    "xhub_local_service_unreachable",
    "xhub_local_service_starting",
    "xhub_local_service_not_ready",
}


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


def _string_list(values: Any) -> list[str]:
    if values is None:
        return []
    items = values if isinstance(values, list) else str(values or "").split(",")
    out: list[str] = []
    seen: set[str] = set()
    for raw in items:
        cleaned = _safe_str(raw).lower()
        if not cleaned or cleaned in seen:
            continue
        seen.add(cleaned)
        out.append(cleaned)
    return out


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


def _normalize_base_url(value: str) -> str:
    token = _safe_str(value).rstrip("/")
    if not token:
        return ""
    if token.startswith(("http://", "https://")):
        return token
    return ""


def _json_dict(raw: Any) -> dict[str, Any]:
    return raw if isinstance(raw, dict) else {}


def _now_ms() -> int:
    return max(0, int(round(time.time() * 1000.0)))


def default_xhub_local_service_base_url() -> str:
    explicit = _normalize_base_url(
        _safe_str(os.environ.get("XHUB_LOCAL_SERVICE_BASE_URL"))
        or _safe_str(os.environ.get("AX_XHUB_LOCAL_SERVICE_BASE_URL"))
    )
    if explicit:
        return explicit
    host_token = _safe_str(
        os.environ.get("XHUB_LOCAL_SERVICE_HOST")
        or os.environ.get("AX_XHUB_LOCAL_SERVICE_HOST")
    )
    port_token = _safe_str(
        os.environ.get("XHUB_LOCAL_SERVICE_PORT")
        or os.environ.get("AX_XHUB_LOCAL_SERVICE_PORT")
    )
    if not host_token and not port_token:
        return ""
    port = max(
        1,
        _safe_int(
            port_token,
            DEFAULT_XHUB_LOCAL_SERVICE_PORT,
        ),
    )
    host = host_token or DEFAULT_XHUB_LOCAL_SERVICE_HOST
    return f"http://{host}:{port}"


def xhub_local_service_state_path(base_dir: str) -> str:
    return os.path.join(os.path.abspath(str(base_dir or "")), XHUB_LOCAL_SERVICE_STATE_FILENAME)


def xhub_local_service_log_paths(base_dir: str) -> tuple[str, str]:
    root = os.path.abspath(str(base_dir or ""))
    return (
        os.path.join(root, XHUB_LOCAL_SERVICE_STDOUT_LOG_FILENAME),
        os.path.join(root, XHUB_LOCAL_SERVICE_STDERR_LOG_FILENAME),
    )


def read_xhub_local_service_state(base_dir: str) -> dict[str, Any]:
    path = xhub_local_service_state_path(base_dir)
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except Exception:
        return {}
    return raw if isinstance(raw, dict) else {}


def _write_json_atomic(path: str, payload: dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
    os.replace(tmp, path)


def _update_xhub_local_service_state(base_dir: str, patch: dict[str, Any]) -> dict[str, Any]:
    normalized_base_dir = os.path.abspath(str(base_dir or ""))
    if not normalized_base_dir:
        return dict(patch or {})
    state = read_xhub_local_service_state(normalized_base_dir)
    state["schemaVersion"] = XHUB_LOCAL_SERVICE_STATE_SCHEMA_VERSION
    state["baseDir"] = normalized_base_dir
    for key, value in (patch or {}).items():
        if key == "schemaVersion":
            continue
        if value is None:
            state.pop(key, None)
            continue
        state[key] = value
    state["updatedAtMs"] = _now_ms()
    _write_json_atomic(xhub_local_service_state_path(normalized_base_dir), state)
    return state


def _service_process_running(pid: int) -> bool:
    process_id = max(0, _safe_int(pid, 0))
    if process_id <= 1:
        return False
    try:
        os.kill(process_id, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except Exception:
        return False


def _canonical_base_url(host: str, port: int) -> str:
    normalized_host = _safe_str(host).lower()
    normalized_port = max(1, _safe_int(port, DEFAULT_XHUB_LOCAL_SERVICE_PORT))
    if normalized_host == "::1":
        return f"http://[::1]:{normalized_port}"
    return f"http://{normalized_host}:{normalized_port}"


def _resolve_local_service_target(service_base_url: str) -> dict[str, Any]:
    base_url = _normalize_base_url(service_base_url) or default_xhub_local_service_base_url()
    if not base_url:
        return {
            "ok": False,
            "baseUrl": "",
            "reasonCode": "xhub_local_service_config_missing",
            "runtimeHint": (
                "Provider is configured to use xhub_local_service, but no service base URL was supplied. "
                "Set runtimeRequirements.serviceBaseUrl or XHUB_LOCAL_SERVICE_BASE_URL."
            ),
            "missingRequirements": ["xhub_local_service:base_url"],
        }

    parsed = urlparse(base_url)
    scheme = _safe_str(parsed.scheme).lower()
    hostname = _safe_str(parsed.hostname).lower()
    try:
        parsed_port = parsed.port
    except Exception:
        parsed_port = None
    port = max(1, _safe_int(parsed_port, DEFAULT_XHUB_LOCAL_SERVICE_PORT))
    has_extra_components = bool(
        _safe_str(parsed.username)
        or _safe_str(parsed.password)
        or (parsed.path not in {"", "/"})
        or _safe_str(parsed.params)
        or _safe_str(parsed.query)
        or _safe_str(parsed.fragment)
    )
    if scheme != "http" or hostname not in _XHUB_LOCAL_SERVICE_ALLOWED_HOSTS or has_extra_components:
        return {
            "ok": False,
            "baseUrl": base_url,
            "reasonCode": "xhub_local_service_nonlocal_endpoint",
            "runtimeHint": (
                "xhub_local_service must use a local loopback HTTP endpoint such as "
                "http://127.0.0.1:50171 or http://localhost:50171. "
                f"Hub refused to manage {base_url} because it is not a safe loopback target."
            ),
            "missingRequirements": [f"xhub_local_service:loopback_http_endpoint:{base_url}"],
        }

    bind_host = "::1" if hostname == "::1" else DEFAULT_XHUB_LOCAL_SERVICE_HOST
    canonical_base_url = _canonical_base_url(bind_host, port)
    return {
        "ok": True,
        "baseUrl": canonical_base_url,
        "bindHost": bind_host,
        "bindPort": port,
        "missingRequirements": [],
        "reasonCode": "",
        "runtimeHint": "",
    }


def _spawn_xhub_local_service_process(
    base_dir: str,
    *,
    bind_host: str,
    bind_port: int,
) -> subprocess.Popen[Any]:
    script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xhub_local_service_runtime.py")
    stdout_path, stderr_path = xhub_local_service_log_paths(base_dir)
    os.makedirs(os.path.abspath(str(base_dir or "")), exist_ok=True)
    env = dict(os.environ)
    env.setdefault("PYTHONUNBUFFERED", "1")
    stdout_handle = open(stdout_path, "ab")
    stderr_handle = open(stderr_path, "ab")
    popen_kwargs: dict[str, Any] = {
        "args": [
            sys.executable,
            script_path,
            "serve",
            "--host",
            _safe_str(bind_host) or DEFAULT_XHUB_LOCAL_SERVICE_HOST,
            "--port",
            str(max(1, _safe_int(bind_port, DEFAULT_XHUB_LOCAL_SERVICE_PORT))),
            "--base-dir",
            os.path.abspath(str(base_dir or "")),
        ],
        "stdin": subprocess.DEVNULL,
        "stdout": stdout_handle,
        "stderr": stderr_handle,
        "cwd": os.path.dirname(script_path),
        "env": env,
        "close_fds": True,
    }
    if os.name == "nt":
        popen_kwargs["creationflags"] = int(
            getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
            | getattr(subprocess, "DETACHED_PROCESS", 0)
        )
    else:
        popen_kwargs["start_new_session"] = True
    try:
        return subprocess.Popen(**popen_kwargs)
    finally:
        stdout_handle.close()
        stderr_handle.close()


def _http_json_request(
    url: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    timeout_sec: float = DEFAULT_XHUB_LOCAL_SERVICE_TIMEOUT_SEC,
) -> dict[str, Any]:
    normalized_url = _normalize_base_url(url)
    if not normalized_url:
        return {
            "ok": False,
            "status": 0,
            "body": {},
            "text": "",
            "error": "invalid_local_service_url",
        }
    body_bytes = b""
    headers = {"Accept": "application/json"}
    if payload is not None:
        body_bytes = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        normalized_url,
        data=body_bytes if payload is not None else None,
        method=str(method or "GET").upper(),
        headers=headers,
    )
    try:
        with urllib.request.urlopen(request, timeout=max(0.5, float(timeout_sec or DEFAULT_XHUB_LOCAL_SERVICE_TIMEOUT_SEC))) as response:
            text = response.read().decode("utf-8", errors="replace")
            try:
                body = json.loads(_safe_str(text))
            except Exception:
                body = {}
            return {
                "ok": 200 <= int(response.status) < 300,
                "status": int(response.status),
                "body": body if isinstance(body, dict) else {},
                "text": _safe_str(text),
                "error": "",
            }
    except urllib.error.HTTPError as exc:
        try:
            text = exc.read().decode("utf-8", errors="replace")
        except Exception:
            text = ""
        try:
            body = json.loads(_safe_str(text))
        except Exception:
            body = {}
        return {
            "ok": False,
            "status": int(getattr(exc, "code", 0) or 0),
            "body": body if isinstance(body, dict) else {},
            "text": _safe_str(text),
            "error": f"http_error:{getattr(exc, 'code', 0)}",
        }
    except Exception as exc:
        return {
            "ok": False,
            "status": 0,
            "body": {},
            "text": "",
            "error": f"{type(exc).__name__}:{exc}",
        }


@dataclass
class XHubLocalServiceProbe:
    base_url: str
    service_state: str
    reason_code: str
    runtime_hint: str = ""
    missing_requirements: list[str] = field(default_factory=list)
    supported_operations: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def ready(self) -> bool:
        return _safe_str(self.reason_code) == "xhub_local_service_ready"

    def to_dict(self) -> dict[str, Any]:
        return {
            "baseUrl": _safe_str(self.base_url),
            "serviceState": _safe_str(self.service_state),
            "reasonCode": _safe_str(self.reason_code),
            "runtimeHint": _safe_str(self.runtime_hint),
            "missingRequirements": _string_list(self.missing_requirements),
            "supportedOperations": _string_list(self.supported_operations),
            "metadata": dict(self.metadata),
        }


def probe_xhub_local_service(
    service_base_url: str = "",
    *,
    base_dir: str = "",
    timeout_sec: float = DEFAULT_XHUB_LOCAL_SERVICE_TIMEOUT_SEC,
) -> XHubLocalServiceProbe:
    target = _resolve_local_service_target(service_base_url)
    if not bool(target.get("ok")):
        managed_state = read_xhub_local_service_state(base_dir) if _safe_str(base_dir) else {}
        if _safe_str(base_dir):
            managed_state = _update_xhub_local_service_state(
                base_dir,
                {
                    "baseUrl": _safe_str(target.get("baseUrl")),
                    "bindHost": "",
                    "bindPort": 0,
                    "processState": "missing_config"
                    if _safe_str(target.get("reasonCode")) == "xhub_local_service_config_missing"
                    else "unsafe_endpoint",
                    "pid": max(0, _safe_int(managed_state.get("pid"), 0)),
                    "lastProbeAtMs": _now_ms(),
                    "lastProbeHttpStatus": 0,
                    "lastProbeError": _safe_str(target.get("reasonCode")),
                    "lastStartError": _safe_str(target.get("runtimeHint")),
                },
            )
        return XHubLocalServiceProbe(
            base_url=_safe_str(target.get("baseUrl")),
            service_state="missing_config"
            if _safe_str(target.get("reasonCode")) == "xhub_local_service_config_missing"
            else "unsafe_endpoint",
            reason_code=_safe_str(target.get("reasonCode")) or "xhub_local_service_probe_failed",
            runtime_hint=_safe_str(target.get("runtimeHint")),
            missing_requirements=_string_list(target.get("missingRequirements")),
            supported_operations=_XHUB_LOCAL_SERVICE_SUPPORTED_OPERATIONS,
            metadata={
                "managedStatePath": xhub_local_service_state_path(base_dir) if _safe_str(base_dir) else "",
                "managedState": managed_state,
            },
        )

    base_url = _safe_str(target.get("baseUrl"))
    response = _http_json_request(
        f"{base_url}/health",
        method="GET",
        timeout_sec=timeout_sec,
    )
    body = _json_dict(response.get("body"))
    status_token = _safe_str(body.get("status") or body.get("state")).lower()
    reported_capabilities = _dedupe_strings(
        _string_list(body.get("capabilities")) or _XHUB_LOCAL_SERVICE_SUPPORTED_OPERATIONS
    )
    metadata = {
        "probeUrl": f"{base_url}/health",
        "probeHttpStatus": int(response.get("status") or 0),
        "probeError": _safe_str(response.get("error")),
        "reportedState": status_token,
        "reportedOk": bool(body.get("ok")),
        "reportedVersion": _safe_str(body.get("version")),
        "reportedCapabilities": reported_capabilities,
    }
    if _safe_str(base_dir):
        state_patch = {
            "baseUrl": base_url,
            "bindHost": _safe_str(target.get("bindHost")) or DEFAULT_XHUB_LOCAL_SERVICE_HOST,
            "bindPort": max(1, _safe_int(target.get("bindPort"), DEFAULT_XHUB_LOCAL_SERVICE_PORT)),
            "processState": "down",
            "lastProbeAtMs": _now_ms(),
            "lastProbeHttpStatus": int(response.get("status") or 0),
            "lastProbeError": _safe_str(response.get("error")),
        }
        if bool(response.get("ok")) and (bool(body.get("ok")) or status_token in {"ready", "running", "ok"}):
            state_patch["processState"] = "ready"
            state_patch["lastReadyAtMs"] = state_patch["lastProbeAtMs"]
            state_patch["lastStartError"] = ""
        elif status_token in {"starting", "booting", "warming"}:
            state_patch["processState"] = "starting"
        elif bool(response.get("ok")):
            state_patch["processState"] = "not_ready"
        managed_state = _update_xhub_local_service_state(base_dir, state_patch)
        metadata["managedStatePath"] = xhub_local_service_state_path(base_dir)
        metadata["managedState"] = managed_state

    if not bool(response.get("ok")):
        return XHubLocalServiceProbe(
            base_url=base_url,
            service_state="down",
            reason_code="xhub_local_service_unreachable",
            runtime_hint=(
                f"Hub-managed local runtime service at {base_url} is not reachable. "
                "Start xhub_local_service or point runtimeRequirements.serviceBaseUrl to a healthy local service."
            ),
            missing_requirements=[f"xhub_local_service:{base_url}"],
            supported_operations=_XHUB_LOCAL_SERVICE_SUPPORTED_OPERATIONS,
            metadata=metadata,
        )

    if bool(body.get("ok")) or status_token in {"ready", "running", "ok"}:
        return XHubLocalServiceProbe(
            base_url=base_url,
            service_state="ready",
            reason_code="xhub_local_service_ready",
            runtime_hint=(
                f"Hub-managed local runtime service is reachable at {base_url}. "
                "Providers can route local inference through this service when executionMode=xhub_local_service."
            ),
            missing_requirements=[],
            supported_operations=reported_capabilities,
            metadata=metadata,
        )

    if status_token in {"starting", "booting", "warming"}:
        return XHubLocalServiceProbe(
            base_url=base_url,
            service_state="starting",
            reason_code="xhub_local_service_starting",
            runtime_hint=(
                f"Hub-managed local runtime service at {base_url} is still starting. "
                "Wait for /health to report ready before routing live tasks."
            ),
            missing_requirements=[f"xhub_local_service:ready:{base_url}"],
            supported_operations=reported_capabilities,
            metadata=metadata,
        )

    return XHubLocalServiceProbe(
        base_url=base_url,
        service_state="degraded",
        reason_code="xhub_local_service_not_ready",
        runtime_hint=(
            f"Hub-managed local runtime service at {base_url} responded to /health but is not ready. "
            "Check the service health payload, runtime manager, and provider registries."
        ),
        missing_requirements=[f"xhub_local_service:ready:{base_url}"],
        supported_operations=reported_capabilities,
        metadata=metadata,
    )


def ensure_xhub_local_service(
    service_base_url: str = "",
    *,
    base_dir: str,
    start_timeout_sec: float = DEFAULT_XHUB_LOCAL_SERVICE_START_TIMEOUT_SEC,
) -> XHubLocalServiceProbe:
    normalized_base_dir = os.path.abspath(str(base_dir or ""))
    target = _resolve_local_service_target(service_base_url)
    if not bool(target.get("ok")):
        return probe_xhub_local_service(
            service_base_url,
            base_dir=normalized_base_dir,
            timeout_sec=min(DEFAULT_XHUB_LOCAL_SERVICE_TIMEOUT_SEC, 1.0),
        )

    base_url = _safe_str(target.get("baseUrl"))
    bind_host = _safe_str(target.get("bindHost")) or DEFAULT_XHUB_LOCAL_SERVICE_HOST
    bind_port = max(1, _safe_int(target.get("bindPort"), DEFAULT_XHUB_LOCAL_SERVICE_PORT))
    state = read_xhub_local_service_state(normalized_base_dir)
    state_pid = max(0, _safe_int(state.get("pid"), 0))
    state_base_url = _safe_str(state.get("baseUrl"))
    process_running = _service_process_running(state_pid)
    launched = False
    reused_existing_process = bool(process_running and state_base_url == base_url)
    now_ms = _now_ms()

    if not reused_existing_process:
        stdout_path, stderr_path = xhub_local_service_log_paths(normalized_base_dir)
        try:
            process = _spawn_xhub_local_service_process(
                normalized_base_dir,
                bind_host=bind_host,
                bind_port=bind_port,
            )
            launched = True
            state = _update_xhub_local_service_state(
                normalized_base_dir,
                {
                    "baseUrl": base_url,
                    "bindHost": bind_host,
                    "bindPort": bind_port,
                    "pid": max(0, _safe_int(getattr(process, "pid", 0), 0)),
                    "processState": "starting",
                    "startedAtMs": now_ms,
                    "lastLaunchAttemptAtMs": now_ms,
                    "startAttemptCount": max(0, _safe_int(state.get("startAttemptCount"), 0)) + 1,
                    "lastStartError": "",
                    "pythonExecutable": _safe_str(sys.executable),
                    "runtimeScriptPath": os.path.join(
                        os.path.dirname(os.path.abspath(__file__)),
                        "xhub_local_service_runtime.py",
                    ),
                    "stdoutLogPath": stdout_path,
                    "stderrLogPath": stderr_path,
                },
            )
        except Exception as exc:
            detail = f"{type(exc).__name__}:{exc}"
            managed_state = _update_xhub_local_service_state(
                normalized_base_dir,
                {
                    "baseUrl": base_url,
                    "bindHost": bind_host,
                    "bindPort": bind_port,
                    "pid": 0,
                    "processState": "launch_failed",
                    "lastLaunchAttemptAtMs": now_ms,
                    "startAttemptCount": max(0, _safe_int(state.get("startAttemptCount"), 0)) + 1,
                    "lastStartError": detail,
                    "pythonExecutable": _safe_str(sys.executable),
                },
            )
            return XHubLocalServiceProbe(
                base_url=base_url,
                service_state="down",
                reason_code="xhub_local_service_unreachable",
                runtime_hint=(
                    f"Hub tried to start xhub_local_service at {base_url}, but launch failed: {detail}. "
                    "Inspect the managed service state and stderr log before routing live traffic."
                ),
                missing_requirements=[f"xhub_local_service:{base_url}"],
                supported_operations=_XHUB_LOCAL_SERVICE_SUPPORTED_OPERATIONS,
                metadata={
                    "launchAttempted": True,
                    "reusedExistingProcess": False,
                    "managedStatePath": xhub_local_service_state_path(normalized_base_dir),
                    "managedState": managed_state,
                    "launchError": detail,
                },
            )

    deadline = time.time() + max(1.0, float(start_timeout_sec or DEFAULT_XHUB_LOCAL_SERVICE_START_TIMEOUT_SEC))
    probe = probe_xhub_local_service(
        base_url,
        base_dir=normalized_base_dir,
        timeout_sec=min(DEFAULT_XHUB_LOCAL_SERVICE_TIMEOUT_SEC, 1.0),
    )
    while not probe.ready and probe.reason_code in _XHUB_LOCAL_SERVICE_WAITABLE_REASON_CODES and time.time() < deadline:
        time.sleep(max(0.05, DEFAULT_XHUB_LOCAL_SERVICE_START_POLL_INTERVAL_SEC))
        probe = probe_xhub_local_service(
            base_url,
            base_dir=normalized_base_dir,
            timeout_sec=min(DEFAULT_XHUB_LOCAL_SERVICE_TIMEOUT_SEC, 1.0),
        )

    if launched and not probe.ready and probe.reason_code == "xhub_local_service_unreachable":
        detail = f"health_timeout:{base_url}"
        managed_state = _update_xhub_local_service_state(
            normalized_base_dir,
            {
                "baseUrl": base_url,
                "bindHost": bind_host,
                "bindPort": bind_port,
                "processState": "down",
                "lastStartError": detail,
            },
        )
        probe.metadata["managedStatePath"] = xhub_local_service_state_path(normalized_base_dir)
        probe.metadata["managedState"] = managed_state
        probe.runtime_hint = (
            f"Hub started xhub_local_service for {base_url}, but /health did not become ready before timeout. "
            "Inspect the managed service state and logs before retrying live traffic."
        )

    probe.metadata["launchAttempted"] = bool(launched)
    probe.metadata["reusedExistingProcess"] = bool(reused_existing_process)
    return probe
