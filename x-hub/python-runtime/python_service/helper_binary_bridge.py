from __future__ import annotations

import base64
from dataclasses import dataclass, field
import json
import os
import shutil
import subprocess
import time
from typing import Any
import urllib.error
import urllib.request


DEFAULT_HELPER_BRIDGE_TIMEOUT_SEC = 2.5
DEFAULT_HELPER_SERVER_TIMEOUT_SEC = 20.0
DEFAULT_HELPER_SERVER_START_TIMEOUT_SEC = 12.0
DEFAULT_LMS_SERVER_PORT = 1234
DEFAULT_LMS_SERVER_HOST = "127.0.0.1"
_LMS_HELPER_ALIASES = {"lms", "llmster", "lmstudio"}
_LMS_LOAD_PARAMETER_FIELDS = [
    "context_length",
    "identifier",
    "gpu_offload_ratio",
    "parallel",
    "ttl",
]
_LMS_SUPPORTED_OPERATIONS = [
    "service_status",
    "ensure_server",
    "list_downloaded_models",
    "list_loaded_models",
    "load_model",
    "unload_model",
    "embedding_task",
    "chat_completion_task",
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


def _normalize_path(value: str) -> str:
    raw = _safe_str(value)
    if not raw:
        return ""
    return os.path.abspath(os.path.expanduser(raw)) if raw.startswith(("~", "/")) else raw


def _normalize_base_url(value: str) -> str:
    token = _safe_str(value).rstrip("/")
    if not token:
        return ""
    if token.startswith(("http://", "https://")):
        return token
    return ""


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


def _helper_name(helper_binary: str) -> str:
    normalized = _normalize_path(helper_binary)
    if not normalized:
        return ""
    if normalized.startswith("/"):
        return _safe_str(os.path.basename(normalized)).lower()
    return _safe_str(normalized).lower()


def _json_dict(raw: Any) -> dict[str, Any]:
    return raw if isinstance(raw, dict) else {}


def _looks_like_lms(helper_binary: str, helper_path: str) -> bool:
    helper_name = _helper_name(helper_binary) or _helper_name(helper_path)
    path_lower = _normalize_path(helper_path).lower()
    return (
        helper_name in _LMS_HELPER_ALIASES
        or path_lower.endswith("/lms")
        or "/.lmstudio/" in path_lower
        or "llmster" in path_lower
    )


def _resolve_binary_candidate(candidate: str) -> str:
    token = _safe_str(candidate)
    if not token:
        return ""
    normalized = _normalize_path(token)
    if normalized.startswith("/"):
        return normalized if os.path.isfile(normalized) and os.access(normalized, os.X_OK) else ""
    resolved = shutil.which(token)
    return _normalize_path(resolved)


def _default_lms_candidates() -> list[str]:
    return [
        os.path.join(os.path.expanduser("~"), ".lmstudio", "bin", "lms"),
        "~/.lmstudio/bin/lms",
        "lms",
    ]


def _default_lms_server_base_url() -> str:
    return f"http://{DEFAULT_LMS_SERVER_HOST}:{DEFAULT_LMS_SERVER_PORT}"


def _lmstudio_home_candidates(helper_binary_path: str) -> list[str]:
    normalized_helper_path = _normalize_path(helper_binary_path)
    helper_dir = os.path.dirname(normalized_helper_path) if normalized_helper_path else ""
    default_home = os.path.join(os.path.expanduser("~"), ".lmstudio")
    candidates = [
        _safe_str(os.environ.get("XHUB_LMSTUDIO_HOME")),
        _safe_str(os.environ.get("LMSTUDIO_HOME")),
    ]
    if helper_dir:
        candidates.append(helper_dir)
        parent_dir = os.path.dirname(helper_dir)
        if parent_dir:
            candidates.append(parent_dir)
    if normalized_helper_path.startswith(default_home) or "/.lmstudio/" in normalized_helper_path:
        candidates.append(default_home)
    return _dedupe_strings([_normalize_path(candidate) for candidate in candidates if _normalize_path(candidate)])


def _discover_lmstudio_home(helper_binary_path: str) -> str:
    for candidate in _lmstudio_home_candidates(helper_binary_path):
        if os.path.isfile(os.path.join(candidate, "settings.json")):
            return candidate
        if os.path.isdir(os.path.join(candidate, ".internal")):
            return candidate
    return ""


def _load_json_file(path: str) -> dict[str, Any]:
    normalized_path = _normalize_path(path)
    if not normalized_path or not os.path.isfile(normalized_path):
        return {}
    try:
        with open(normalized_path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def _lmstudio_environment_metadata(helper_binary_path: str) -> dict[str, Any]:
    lmstudio_home = _discover_lmstudio_home(helper_binary_path)
    if not lmstudio_home:
        return {}
    metadata: dict[str, Any] = {
        "lmStudioHome": lmstudio_home,
    }
    settings_path = os.path.join(lmstudio_home, "settings.json")
    metadata["settingsPath"] = settings_path
    metadata["settingsFound"] = bool(os.path.isfile(settings_path))
    settings_payload = _load_json_file(settings_path)
    settings_flags: dict[str, Any] = {}
    if settings_payload:
        if "enableLocalService" in settings_payload:
            settings_flags["enableLocalService"] = bool(settings_payload.get("enableLocalService"))
        if "cliInstalled" in settings_payload:
            settings_flags["cliInstalled"] = bool(settings_payload.get("cliInstalled"))
        if "appFirstLoad" in settings_payload:
            settings_flags["appFirstLoad"] = bool(settings_payload.get("appFirstLoad"))
        developer_payload = _json_dict(settings_payload.get("developer"))
        if "attemptedInstallLmsCliOnStartup" in developer_payload:
            settings_flags["attemptedInstallLmsCliOnStartup"] = bool(
                developer_payload.get("attemptedInstallLmsCliOnStartup")
            )
    if settings_flags:
        metadata["settingsFlags"] = settings_flags
    return metadata


@dataclass
class HelperBinaryBridgeLoadRequest:
    model_ref: str
    task_kind: str = ""
    identifier: str = ""
    context_length: int = 0
    gpu_offload_ratio: float | None = None
    parallel: int | None = None
    ttl_sec: int | None = None
    extra_config: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        out = {
            "modelRef": _safe_str(self.model_ref),
            "taskKind": _safe_str(self.task_kind).lower(),
            "identifier": _safe_str(self.identifier),
            "contextLength": max(0, _safe_int(self.context_length, 0)),
            "extraConfig": dict(self.extra_config),
        }
        if self.gpu_offload_ratio is not None:
            out["gpuOffloadRatio"] = float(self.gpu_offload_ratio)
        if self.parallel is not None:
            out["parallel"] = max(0, _safe_int(self.parallel, 0))
        if self.ttl_sec is not None:
            out["ttlSec"] = max(0, _safe_int(self.ttl_sec, 0))
        return out


@dataclass
class HelperBinaryBridgeUnloadRequest:
    model_ref: str = ""
    identifier: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "modelRef": _safe_str(self.model_ref),
            "identifier": _safe_str(self.identifier),
        }


@dataclass
class HelperBinaryBridgeProbe:
    helper_binary: str
    helper_binary_path: str
    helper_kind: str
    binary_found: bool
    service_state: str
    reason_code: str
    runtime_hint: str = ""
    import_error: str = ""
    missing_requirements: list[str] = field(default_factory=list)
    missing_optional_requirements: list[str] = field(default_factory=list)
    supported_operations: list[str] = field(default_factory=list)
    load_parameter_fields: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def helper_name(self) -> str:
        return _helper_name(self.helper_binary_path or self.helper_binary)

    @property
    def ready(self) -> bool:
        return _safe_str(self.reason_code) == "helper_bridge_ready"

    def to_dict(self) -> dict[str, Any]:
        return {
            "helperBinary": _safe_str(self.helper_binary),
            "helperBinaryPath": _safe_str(self.helper_binary_path),
            "helperKind": _safe_str(self.helper_kind),
            "binaryFound": bool(self.binary_found),
            "serviceState": _safe_str(self.service_state),
            "reasonCode": _safe_str(self.reason_code),
            "runtimeHint": _safe_str(self.runtime_hint),
            "importError": _safe_str(self.import_error),
            "missingRequirements": _string_list(self.missing_requirements),
            "missingOptionalRequirements": _string_list(self.missing_optional_requirements),
            "supportedOperations": _string_list(self.supported_operations),
            "loadParameterFields": _string_list(self.load_parameter_fields),
            "metadata": dict(self.metadata),
        }


def discover_helper_binary(helper_binary: str) -> tuple[str, list[str]]:
    requested = _safe_str(helper_binary)
    helper_name = _helper_name(requested)
    candidates: list[str] = []
    if requested:
        candidates.append(requested)
    if not requested or helper_name in _LMS_HELPER_ALIASES:
        candidates.extend(_default_lms_candidates())
    resolved_candidates = _dedupe_strings([_normalize_path(candidate) for candidate in candidates])
    for candidate in candidates:
        resolved = _resolve_binary_candidate(candidate)
        if resolved:
            return resolved, resolved_candidates
    return "", resolved_candidates


def _run_helper_command(binary_path: str, args: list[str], *, timeout_sec: float) -> dict[str, Any]:
    command = [_normalize_path(binary_path)] + [str(arg) for arg in args]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=max(0.5, float(timeout_sec or DEFAULT_HELPER_BRIDGE_TIMEOUT_SEC)),
        )
        output = "\n".join(
            token for token in [_safe_str(completed.stdout), _safe_str(completed.stderr)] if token
        ).strip()
        return {
            "ok": completed.returncode == 0,
            "returncode": int(completed.returncode),
            "output": output,
            "timedOut": False,
            "command": command,
        }
    except subprocess.TimeoutExpired as exc:
        output = "\n".join(
            token
            for token in [
                _safe_str(getattr(exc, "stdout", "")),
                _safe_str(getattr(exc, "stderr", "")),
            ]
            if token
        ).strip()
        return {
            "ok": False,
            "returncode": -1,
            "output": output,
            "timedOut": True,
            "command": command,
        }
    except Exception as exc:
        return {
            "ok": False,
            "returncode": -1,
            "output": f"{type(exc).__name__}:{exc}",
            "timedOut": False,
            "command": command,
        }


def _parse_json_output(output: str) -> dict[str, Any]:
    try:
        payload = json.loads(_safe_str(output))
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def _http_json_request(
    url: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    timeout_sec: float = DEFAULT_HELPER_SERVER_TIMEOUT_SEC,
) -> dict[str, Any]:
    normalized_url = _normalize_base_url(url)
    if not normalized_url:
        return {
            "ok": False,
            "status": 0,
            "body": {},
            "text": "",
            "error": "invalid_helper_server_url",
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
        with urllib.request.urlopen(request, timeout=max(0.5, float(timeout_sec or DEFAULT_HELPER_SERVER_TIMEOUT_SEC))) as response:
            text = response.read().decode("utf-8", errors="replace")
            return {
                "ok": 200 <= int(response.status) < 300,
                "status": int(response.status),
                "body": _parse_json_output(text),
                "text": _safe_str(text),
                "error": "",
            }
    except urllib.error.HTTPError as exc:
        try:
            text = exc.read().decode("utf-8", errors="replace")
        except Exception:
            text = ""
        return {
            "ok": False,
            "status": int(getattr(exc, "code", 0) or 0),
            "body": _parse_json_output(text),
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


def _ready_probe(
    helper_binary: str,
    helper_binary_path: str,
    *,
    helper_kind: str,
    service_state: str,
    reason_code: str,
    runtime_hint: str,
    import_error: str = "",
    missing_requirements: list[str] | None = None,
    metadata: dict[str, Any] | None = None,
) -> HelperBinaryBridgeProbe:
    supported_operations = _LMS_SUPPORTED_OPERATIONS if helper_kind == "lmstudio" else ["service_status"]
    load_parameter_fields = _LMS_LOAD_PARAMETER_FIELDS if helper_kind == "lmstudio" else ["context_length"]
    return HelperBinaryBridgeProbe(
        helper_binary=helper_binary,
        helper_binary_path=helper_binary_path,
        helper_kind=helper_kind,
        binary_found=bool(helper_binary_path),
        service_state=service_state,
        reason_code=reason_code,
        runtime_hint=runtime_hint,
        import_error=import_error,
        missing_requirements=_string_list(missing_requirements),
        missing_optional_requirements=[],
        supported_operations=supported_operations,
        load_parameter_fields=load_parameter_fields,
        metadata=dict(metadata or {}),
    )


def _probe_lms_bridge(helper_binary: str, helper_binary_path: str, *, timeout_sec: float) -> HelperBinaryBridgeProbe:
    json_probe_result = _run_helper_command(
        helper_binary_path,
        ["daemon", "status", "--json"],
        timeout_sec=timeout_sec,
    )
    json_output = _safe_str(json_probe_result.get("output"))
    json_payload = _parse_json_output(json_output)
    json_status = _safe_str(json_payload.get("status")).lower()
    json_running = json_status == "running" or (
        json_probe_result.get("ok")
        and bool(json_payload.get("isDaemon"))
        and max(0, _safe_int(json_payload.get("pid"), 0)) > 0
    )

    probe_result = json_probe_result
    output = json_output
    lower = output.lower()
    if not json_status and not json_running and not json_probe_result.get("timedOut"):
        probe_result = _run_helper_command(helper_binary_path, ["daemon", "status"], timeout_sec=timeout_sec)
        output = _safe_str(probe_result.get("output"))
        lower = output.lower()

    metadata = {
        "helperKind": "lmstudio",
        "probeCommand": list(probe_result.get("command") or []),
        "probeReturnCode": int(probe_result.get("returncode") or 0),
        "probeOutput": output[:240],
    }
    if json_output:
        metadata["probeJSONCommand"] = list(json_probe_result.get("command") or [])
        metadata["probeJSONReturnCode"] = int(json_probe_result.get("returncode") or 0)
        metadata["probeJSONOutput"] = json_output[:240]
    if json_status:
        metadata["probeJSONStatus"] = json_status
    if json_running:
        metadata["probeJSONRunning"] = True
    environment_metadata = _lmstudio_environment_metadata(helper_binary_path)
    if environment_metadata:
        metadata["lmStudioEnvironment"] = environment_metadata
    settings_flags = _json_dict(environment_metadata.get("settingsFlags"))
    local_service_disabled = settings_flags.get("enableLocalService") is False
    settings_path = _safe_str(environment_metadata.get("settingsPath"))

    if json_running:
        return _ready_probe(
            helper_binary,
            helper_binary_path,
            helper_kind="lmstudio",
            service_state="running",
            reason_code="helper_bridge_ready",
            runtime_hint=(
                f"External local engine bridge is reachable at {helper_binary_path}. "
                "Downloaded-model listing and load routing can use this bridge when enabled."
            ),
            metadata=metadata,
        )

    if probe_result.get("timedOut"):
        return _ready_probe(
            helper_binary,
            helper_binary_path,
            helper_kind="lmstudio",
            service_state="unknown",
            reason_code="helper_probe_timeout",
            import_error="helper_probe_timeout:lms",
            missing_requirements=["helper_service:lms_daemon"],
            runtime_hint=(
                f"External local engine bridge is installed at {helper_binary_path}, "
                "but the service status probe timed out."
            ),
            metadata=metadata,
        )

    if json_status in {"not-running", "not_running", "stopped", "down"} or any(
        token in lower for token in ["not running", "not started", "stopped", "daemon down"]
    ):
        if local_service_disabled:
            detail_parts = []
            if settings_path:
                detail_parts.append(f"LM Studio local service appears disabled in {settings_path}.")
            else:
                detail_parts.append("LM Studio local service appears disabled in settings.")
            if settings_flags.get("appFirstLoad") is True:
                detail_parts.append("LM Studio still appears to be in first-launch/onboarding state.")
            if settings_flags.get("cliInstalled") is False:
                detail_parts.append("The LM Studio CLI state also reports cliInstalled=false.")
            detail_parts.append("Enable Local Service in LM Studio and rerun the helper probe.")
            return _ready_probe(
                helper_binary,
                helper_binary_path,
                helper_kind="lmstudio",
                service_state="disabled",
                reason_code="helper_local_service_disabled",
                import_error="helper_local_service_disabled:lms",
                missing_requirements=["helper_service:lms_local_service_enabled"],
                runtime_hint=(
                    f"External local engine bridge is installed at {helper_binary_path}, "
                    + " ".join(detail_parts)
                ),
                metadata=metadata,
            )
        return _ready_probe(
            helper_binary,
            helper_binary_path,
            helper_kind="lmstudio",
            service_state="down",
            reason_code="helper_service_down",
            import_error="helper_service_down:lms",
            missing_requirements=["helper_service:lms_daemon"],
            runtime_hint=(
                f"External local engine bridge is installed at {helper_binary_path}, "
                "but its background service is not running. Hub readiness checks do not auto-start it."
            ),
            metadata=metadata,
        )

    if json_status in {"starting", "booting"} or any(token in lower for token in ["waking up", "starting", "booting"]):
        return _ready_probe(
            helper_binary,
            helper_binary_path,
            helper_kind="lmstudio",
            service_state="starting",
            reason_code="helper_service_down",
            import_error="helper_service_starting:lms",
            missing_requirements=["helper_service:lms_daemon"],
            runtime_hint=(
                f"External local engine bridge is installed at {helper_binary_path}, "
                "but its background service is still starting."
            ),
            metadata=metadata,
        )

    if probe_result.get("ok") and not any(token in lower for token in ["not running", "stopped", "down"]):
        return _ready_probe(
            helper_binary,
            helper_binary_path,
            helper_kind="lmstudio",
            service_state="running",
            reason_code="helper_bridge_ready",
            runtime_hint=(
                f"External local engine bridge is reachable at {helper_binary_path}. "
                "Downloaded-model listing and load routing can use this bridge when enabled."
            ),
            metadata=metadata,
        )

    return _ready_probe(
        helper_binary,
        helper_binary_path,
        helper_kind="lmstudio",
        service_state="unknown",
        reason_code="helper_probe_failed",
        import_error="helper_probe_failed:lms",
        missing_requirements=["helper_service:lms_daemon"],
        runtime_hint=(
            f"External local engine bridge was found at {helper_binary_path}, "
            "but Hub could not verify its daemon state."
        ),
        metadata=metadata,
    )


def probe_helper_binary_bridge(
    helper_binary: str,
    *,
    timeout_sec: float = DEFAULT_HELPER_BRIDGE_TIMEOUT_SEC,
) -> HelperBinaryBridgeProbe:
    helper_binary_path, candidates = discover_helper_binary(helper_binary)
    requested = _safe_str(helper_binary)
    metadata = {
        "candidatePaths": candidates,
    }
    if not helper_binary_path:
        requested_label = requested or "helper_binary"
        return HelperBinaryBridgeProbe(
            helper_binary=requested,
            helper_binary_path="",
            helper_kind="unknown",
            binary_found=False,
            service_state="missing",
            reason_code="helper_binary_missing",
            runtime_hint=(
                f"External local engine bridge binary is missing for {requested_label}. "
                "Install or register the helper binary before enabling this execution mode."
            ),
            import_error=f"missing_helper_binary:{requested_label}",
            missing_requirements=[f"helper_binary:{requested_label}"],
            missing_optional_requirements=[],
            supported_operations=["service_status"],
            load_parameter_fields=["context_length"],
            metadata=metadata,
        )

    if _looks_like_lms(requested or helper_binary_path, helper_binary_path):
        return _probe_lms_bridge(
            requested or helper_binary_path,
            helper_binary_path,
            timeout_sec=timeout_sec,
        )

    return _ready_probe(
        requested or helper_binary_path,
        helper_binary_path,
        helper_kind="generic_helper_binary",
        service_state="running",
        reason_code="helper_bridge_ready",
        runtime_hint=(
            f"External local engine bridge binary is available at {helper_binary_path}. "
            "Provider-specific load and task routing still needs to opt into this helper."
        ),
        metadata=metadata,
    )


def _extract_rows_from_json(output: str) -> list[dict[str, Any]]:
    if not output:
        return []
    try:
        payload = json.loads(output)
    except Exception:
        return []
    if isinstance(payload, list):
        return [dict(item) for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        for field in ["models", "items", "data", "loadedModels"]:
            rows = payload.get(field)
            if isinstance(rows, list):
                return [dict(item) for item in rows if isinstance(item, dict)]
    return []


def _resolve_probe_input(helper_binary: str | HelperBinaryBridgeProbe) -> HelperBinaryBridgeProbe:
    if isinstance(helper_binary, HelperBinaryBridgeProbe):
        return helper_binary
    return probe_helper_binary_bridge(str(helper_binary or ""))


def ensure_helper_binary_bridge_ready(
    helper_binary: str | HelperBinaryBridgeProbe,
    *,
    auto_start_daemon: bool = True,
    timeout_sec: float = 8.0,
    probe_timeout_sec: float = DEFAULT_HELPER_BRIDGE_TIMEOUT_SEC,
) -> HelperBinaryBridgeProbe:
    probe = _resolve_probe_input(helper_binary)
    if probe.ready:
        return probe
    if not auto_start_daemon or probe.helper_kind != "lmstudio" or not probe.helper_binary_path:
        return probe
    if _safe_str(probe.reason_code) not in {
        "helper_service_down",
        "helper_probe_failed",
        "helper_probe_timeout",
    }:
        return probe

    start_result = _run_helper_command(
        probe.helper_binary_path,
        ["daemon", "up", "--json"],
        timeout_sec=min(max(1.0, float(timeout_sec or 8.0)), 8.0),
    )
    deadline = time.time() + max(1.0, float(timeout_sec or 8.0))
    latest_probe = probe
    while time.time() < deadline:
        latest_probe = probe_helper_binary_bridge(
            probe.helper_binary_path,
            timeout_sec=probe_timeout_sec,
        )
        if latest_probe.ready:
            latest_probe.metadata["daemonAutoStarted"] = True
            latest_probe.metadata["daemonUpOutput"] = _safe_str(start_result.get("output"))[:240]
            return latest_probe
        time.sleep(0.25)
    if _safe_str(start_result.get("output")):
        latest_probe.metadata["daemonUpOutput"] = _safe_str(start_result.get("output"))[:240]
    return latest_probe


def _normalize_gpu_offload_ratio(value: Any) -> str:
    token = _safe_str(value).lower()
    if token in {"off", "max"}:
        return token
    if not token:
        return ""
    try:
        number = float(token)
    except Exception:
        return ""
    if number < 0.0 or number > 1.0:
        return ""
    return str(number)


def _candidate_helper_server_base_urls(status_payload: dict[str, Any] | None = None) -> list[str]:
    payload = _json_dict(status_payload)
    candidates = [
        _safe_str(os.environ.get("XHUB_HELPER_BRIDGE_SERVER_BASE_URL")),
        _safe_str(payload.get("baseUrl") or payload.get("baseURL")),
    ]
    host = _safe_str(
        payload.get("bind")
        or payload.get("bindAddress")
        or payload.get("host")
        or payload.get("hostname")
    ) or DEFAULT_LMS_SERVER_HOST
    port = max(
        0,
        _safe_int(
            payload.get("port")
            or payload.get("serverPort")
            or payload.get("httpPort"),
            DEFAULT_LMS_SERVER_PORT,
        ),
    )
    if port > 0:
        candidates.append(f"http://{host}:{port}")
    env_port = max(0, _safe_int(os.environ.get("XHUB_HELPER_BRIDGE_SERVER_PORT"), 0))
    if env_port > 0:
        candidates.append(f"http://{DEFAULT_LMS_SERVER_HOST}:{env_port}")
    candidates.append(_default_lms_server_base_url())
    return _dedupe_strings([_normalize_base_url(candidate) for candidate in candidates if _normalize_base_url(candidate)])


def _is_helper_load_wakeup_output(output: str) -> bool:
    normalized = _safe_str(output).lower()
    if not normalized:
        return False
    return any(
        token in normalized
        for token in [
            "waking up lm studio service",
            "waking up lm studio",
            "waking up service",
            "service is waking up",
        ]
    )


def _helper_server_status_payload(binary_path: str, *, timeout_sec: float) -> tuple[dict[str, Any], str]:
    result = _run_helper_command(binary_path, ["server", "status", "--json"], timeout_sec=timeout_sec)
    output = _safe_str(result.get("output"))
    payload = _parse_json_output(output)
    return payload, output


def _probe_helper_server_base_url(base_url: str, *, timeout_sec: float) -> dict[str, Any]:
    result = _http_json_request(
        f"{_normalize_base_url(base_url)}/v1/models",
        method="GET",
        timeout_sec=timeout_sec,
    )
    body = _json_dict(result.get("body"))
    models = body.get("data")
    if result.get("ok") and isinstance(models, list):
        return {
            "ok": True,
            "baseUrl": _normalize_base_url(base_url),
            "models": [dict(item) for item in models if isinstance(item, dict)],
            "status": int(result.get("status") or 0),
        }
    return {
        "ok": False,
        "baseUrl": _normalize_base_url(base_url),
        "models": [],
        "status": int(result.get("status") or 0),
        "error": _safe_str(result.get("error")) or _safe_str(result.get("text"))[:240],
    }


def ensure_helper_bridge_server(
    helper_binary: str | HelperBinaryBridgeProbe,
    *,
    auto_start_daemon: bool = True,
    auto_start_server: bool = True,
    preferred_port: int = DEFAULT_LMS_SERVER_PORT,
    timeout_sec: float = DEFAULT_HELPER_SERVER_START_TIMEOUT_SEC,
) -> dict[str, Any]:
    probe = ensure_helper_binary_bridge_ready(
        helper_binary,
        auto_start_daemon=auto_start_daemon,
        timeout_sec=min(max(1.0, float(timeout_sec or DEFAULT_HELPER_SERVER_START_TIMEOUT_SEC)), 10.0),
    )
    if not probe.ready:
        reason_code = _safe_str(probe.reason_code) or "helper_service_down"
        return {
            "ok": False,
            "reasonCode": reason_code,
            "error": reason_code,
            "errorDetail": _safe_str(probe.import_error) or _safe_str(probe.runtime_hint),
            "helperBinaryPath": _safe_str(probe.helper_binary_path),
            "serverBaseUrl": "",
            "serverRunning": False,
            "autoStartedServer": False,
        }

    binary_path = _safe_str(probe.helper_binary_path)
    status_payload, status_output = _helper_server_status_payload(binary_path, timeout_sec=3.0)
    candidates = _candidate_helper_server_base_urls(status_payload)
    for candidate in candidates:
        probe_result = _probe_helper_server_base_url(candidate, timeout_sec=2.0)
        if probe_result.get("ok"):
            return {
                "ok": True,
                "reasonCode": "helper_server_ready",
                "error": "",
                "errorDetail": "",
                "helperBinaryPath": binary_path,
                "serverBaseUrl": candidate,
                "serverRunning": True,
                "autoStartedServer": False,
                "models": probe_result.get("models") or [],
            }

    status_running = bool(status_payload.get("running"))
    if not auto_start_server:
        return {
            "ok": False,
            "reasonCode": "helper_server_down" if not status_running else "helper_server_unreachable",
            "error": "helper_server_down" if not status_running else "helper_server_unreachable",
            "errorDetail": status_output[:240],
            "helperBinaryPath": binary_path,
            "serverBaseUrl": candidates[0] if candidates else "",
            "serverRunning": status_running,
            "autoStartedServer": False,
        }

    start_args = ["server", "start", "--bind", DEFAULT_LMS_SERVER_HOST]
    start_port = max(0, int(preferred_port or DEFAULT_LMS_SERVER_PORT))
    if start_port > 0:
        start_args.extend(["--port", str(start_port)])
    start_result = _run_helper_command(binary_path, start_args, timeout_sec=min(max(2.0, timeout_sec), 6.0))
    deadline = time.time() + max(2.0, float(timeout_sec or DEFAULT_HELPER_SERVER_START_TIMEOUT_SEC))
    latest_output = _safe_str(start_result.get("output"))

    while time.time() < deadline:
        status_payload, status_output = _helper_server_status_payload(binary_path, timeout_sec=3.0)
        latest_output = _safe_str(status_output) or latest_output
        poll_candidates = _candidate_helper_server_base_urls(status_payload)
        if start_port > 0:
            poll_candidates = _dedupe_strings(
                [f"http://{DEFAULT_LMS_SERVER_HOST}:{start_port}"] + poll_candidates
            )
        for candidate in poll_candidates:
            probe_result = _probe_helper_server_base_url(candidate, timeout_sec=2.0)
            if probe_result.get("ok"):
                return {
                    "ok": True,
                    "reasonCode": "helper_server_ready",
                    "error": "",
                    "errorDetail": _safe_str(start_result.get("output"))[:240],
                    "helperBinaryPath": binary_path,
                    "serverBaseUrl": candidate,
                    "serverRunning": True,
                    "autoStartedServer": True,
                    "models": probe_result.get("models") or [],
                }
        time.sleep(0.25)

    return {
        "ok": False,
        "reasonCode": "helper_server_start_failed",
        "error": "helper_server_start_failed",
        "errorDetail": latest_output[:240],
        "helperBinaryPath": binary_path,
        "serverBaseUrl": f"http://{DEFAULT_LMS_SERVER_HOST}:{start_port}" if start_port > 0 else "",
        "serverRunning": bool(status_payload.get("running")),
        "autoStartedServer": False,
    }


def helper_bridge_embeddings(
    helper_binary: str | HelperBinaryBridgeProbe,
    *,
    identifier: str,
    texts: list[str],
    dimensions: int = 0,
    timeout_sec: float = DEFAULT_HELPER_SERVER_TIMEOUT_SEC,
) -> dict[str, Any]:
    identifier_token = _safe_str(identifier)
    text_rows = [str(item or "") for item in (texts or [])]
    if not identifier_token:
        return {
            "ok": False,
            "reasonCode": "missing_helper_identifier",
            "error": "missing_helper_identifier",
            "errorDetail": "",
            "vectors": [],
            "dims": 0,
            "usage": {},
        }
    if not text_rows:
        return {
            "ok": False,
            "reasonCode": "missing_texts",
            "error": "missing_texts",
            "errorDetail": "",
            "vectors": [],
            "dims": 0,
            "usage": {},
        }

    server = ensure_helper_bridge_server(helper_binary, timeout_sec=min(max(4.0, timeout_sec), 15.0))
    if not bool(server.get("ok")):
        return {
            "ok": False,
            "reasonCode": _safe_str(server.get("reasonCode")) or "helper_server_down",
            "error": _safe_str(server.get("error")) or "helper_server_down",
            "errorDetail": _safe_str(server.get("errorDetail")),
            "vectors": [],
            "dims": 0,
            "usage": {},
            "serverBaseUrl": _safe_str(server.get("serverBaseUrl")),
        }

    payload = {
        "model": identifier_token,
        "input": text_rows,
    }
    if dimensions > 0:
        payload["dimensions"] = max(1, int(dimensions))
    result = _http_json_request(
        f"{_safe_str(server.get('serverBaseUrl'))}/v1/embeddings",
        method="POST",
        payload=payload,
        timeout_sec=timeout_sec,
    )
    if not bool(result.get("ok")):
        body = _json_dict(result.get("body"))
        error_obj = _json_dict(body.get("error"))
        return {
            "ok": False,
            "reasonCode": "helper_embedding_failed",
            "error": "helper_embedding_failed",
            "errorDetail": (
                _safe_str(error_obj.get("message"))
                or _safe_str(result.get("text"))
                or _safe_str(result.get("error"))
            )[:240],
            "vectors": [],
            "dims": 0,
            "usage": {},
            "serverBaseUrl": _safe_str(server.get("serverBaseUrl")),
        }

    body = _json_dict(result.get("body"))
    raw_rows = body.get("data") if isinstance(body.get("data"), list) else []
    vectors: list[list[float]] = []
    for row in sorted(
        [dict(item) for item in raw_rows if isinstance(item, dict)],
        key=lambda item: _safe_int(item.get("index"), 0),
    ):
        embedding = row.get("embedding")
        if not isinstance(embedding, list):
            continue
        vector: list[float] = []
        for value in embedding:
            try:
                vector.append(float(value))
            except Exception:
                vector.append(0.0)
        if vector:
            vectors.append(vector)
    dims = len(vectors[0]) if vectors else 0
    usage = _json_dict(body.get("usage"))
    return {
        "ok": bool(vectors),
        "reasonCode": "helper_embedding_ready" if vectors else "helper_embedding_empty",
        "error": "" if vectors else "helper_embedding_empty",
        "errorDetail": "",
        "vectors": vectors,
        "dims": dims,
        "usage": usage,
        "serverBaseUrl": _safe_str(server.get("serverBaseUrl")),
        "model": _safe_str(body.get("model")) or identifier_token,
        "autoStartedServer": bool(server.get("autoStartedServer")),
    }


def helper_bridge_chat_completion(
    helper_binary: str | HelperBinaryBridgeProbe,
    *,
    identifier: str,
    messages: list[dict[str, Any]],
    max_tokens: int = 0,
    temperature: float = 0.0,
    timeout_sec: float = DEFAULT_HELPER_SERVER_TIMEOUT_SEC,
) -> dict[str, Any]:
    identifier_token = _safe_str(identifier)
    if not identifier_token:
        return {
            "ok": False,
            "reasonCode": "missing_helper_identifier",
            "error": "missing_helper_identifier",
            "errorDetail": "",
            "text": "",
            "usage": {},
        }
    if not messages:
        return {
            "ok": False,
            "reasonCode": "missing_messages",
            "error": "missing_messages",
            "errorDetail": "",
            "text": "",
            "usage": {},
        }

    server = ensure_helper_bridge_server(helper_binary, timeout_sec=min(max(4.0, timeout_sec), 15.0))
    if not bool(server.get("ok")):
        return {
            "ok": False,
            "reasonCode": _safe_str(server.get("reasonCode")) or "helper_server_down",
            "error": _safe_str(server.get("error")) or "helper_server_down",
            "errorDetail": _safe_str(server.get("errorDetail")),
            "text": "",
            "usage": {},
            "serverBaseUrl": _safe_str(server.get("serverBaseUrl")),
        }

    payload: dict[str, Any] = {
        "model": identifier_token,
        "messages": [dict(item) for item in messages if isinstance(item, dict)],
        "temperature": float(temperature),
        "stream": False,
    }
    if max_tokens > 0:
        payload["max_tokens"] = max(1, int(max_tokens))
    result = _http_json_request(
        f"{_safe_str(server.get('serverBaseUrl'))}/v1/chat/completions",
        method="POST",
        payload=payload,
        timeout_sec=timeout_sec,
    )
    if not bool(result.get("ok")):
        body = _json_dict(result.get("body"))
        error_obj = _json_dict(body.get("error"))
        return {
            "ok": False,
            "reasonCode": "helper_chat_failed",
            "error": "helper_chat_failed",
            "errorDetail": (
                _safe_str(error_obj.get("message"))
                or _safe_str(result.get("text"))
                or _safe_str(result.get("error"))
            )[:240],
            "text": "",
            "usage": {},
            "serverBaseUrl": _safe_str(server.get("serverBaseUrl")),
        }

    body = _json_dict(result.get("body"))
    choices = body.get("choices") if isinstance(body.get("choices"), list) else []
    message = _json_dict(choices[0].get("message")) if choices and isinstance(choices[0], dict) else {}
    content = message.get("content")
    text = ""
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        text = "\n".join(
            _safe_str(item.get("text"))
            for item in content
            if isinstance(item, dict) and _safe_str(item.get("text"))
        ).strip()
    return {
        "ok": bool(text),
        "reasonCode": "helper_chat_ready" if text else "helper_chat_empty",
        "error": "" if text else "helper_chat_empty",
        "errorDetail": "",
        "text": text,
        "usage": _json_dict(body.get("usage")),
        "finishReason": _safe_str(choices[0].get("finish_reason")) if choices and isinstance(choices[0], dict) else "",
        "serverBaseUrl": _safe_str(server.get("serverBaseUrl")),
        "model": _safe_str(body.get("model")) or identifier_token,
        "autoStartedServer": bool(server.get("autoStartedServer")),
    }


def encode_helper_image_data_url(image_path: str) -> str:
    normalized = _normalize_path(image_path)
    if not normalized or not os.path.exists(normalized):
        return ""
    ext = os.path.splitext(normalized)[1].lower()
    mime_type = "image/png" if ext == ".png" else "image/jpeg"
    with open(normalized, "rb") as handle:
        payload = base64.b64encode(handle.read()).decode("ascii")
    return f"data:{mime_type};base64,{payload}"


def list_helper_bridge_downloaded_models(
    helper_binary: str | HelperBinaryBridgeProbe,
    *,
    timeout_sec: float = 4.0,
) -> list[dict[str, Any]]:
    probe = _resolve_probe_input(helper_binary)
    if not probe.ready or probe.helper_kind != "lmstudio" or not probe.helper_binary_path:
        return []
    result = _run_helper_command(probe.helper_binary_path, ["ls", "--json"], timeout_sec=timeout_sec)
    return _extract_rows_from_json(_safe_str(result.get("output")))


def list_helper_bridge_loaded_models(
    helper_binary: str | HelperBinaryBridgeProbe,
    *,
    timeout_sec: float = 4.0,
) -> list[dict[str, Any]]:
    probe = _resolve_probe_input(helper_binary)
    if not probe.ready or probe.helper_kind != "lmstudio" or not probe.helper_binary_path:
        return []
    result = _run_helper_command(probe.helper_binary_path, ["ps", "--json"], timeout_sec=timeout_sec)
    return _extract_rows_from_json(_safe_str(result.get("output")))


def _resolve_helper_load_model_ref(
    probe: HelperBinaryBridgeProbe,
    model_ref: str,
    *,
    timeout_sec: float,
) -> str:
    requested = _safe_str(model_ref)
    if not requested:
        return ""
    downloaded = list_helper_bridge_downloaded_models(probe, timeout_sec=min(4.0, timeout_sec))
    if not downloaded:
        return requested

    requested_lower = requested.lower()
    requested_base = os.path.basename(requested.rstrip("/")).lower()

    for row in downloaded:
        if not isinstance(row, dict):
            continue
        model_key = _safe_str(row.get("modelKey"))
        indexed_identifier = _safe_str(
            row.get("indexedModelIdentifier")
            or row.get("indexed_model_identifier")
        )
        path_ref = _safe_str(row.get("path"))
        candidates = [
            model_key,
            indexed_identifier,
            path_ref,
        ]
        candidate_bases = {
            os.path.basename(candidate.rstrip("/")).lower()
            for candidate in candidates
            if candidate
        }
        if any(requested_lower == candidate.lower() for candidate in candidates if candidate):
            return model_key or indexed_identifier or path_ref or requested
        if requested_base and requested_base in candidate_bases:
            return model_key or indexed_identifier or path_ref or requested
        if requested_lower.startswith("/") and any(
            requested_lower.endswith(f"/{candidate.lower()}") for candidate in (indexed_identifier, path_ref) if candidate
        ):
            return model_key or indexed_identifier or path_ref or requested
    return requested


def _select_helper_loaded_row(
    rows: list[dict[str, Any]],
    *,
    identifier: str,
    model_ref: str,
) -> dict[str, Any]:
    return next(
        (
            dict(row)
            for row in (rows or [])
            if isinstance(row, dict)
            and (
                (_safe_str(row.get("identifier")) and _safe_str(row.get("identifier")) == identifier)
                or (_safe_str(row.get("modelKey")) and _safe_str(row.get("modelKey")) == model_ref)
                or (_safe_str(row.get("path")) and _safe_str(row.get("path")) == model_ref)
            )
        ),
        {},
    )


def load_helper_bridge_model(
    helper_binary: str | HelperBinaryBridgeProbe,
    *,
    request: HelperBinaryBridgeLoadRequest | dict[str, Any],
    timeout_sec: float = 30.0,
) -> dict[str, Any]:
    probe = ensure_helper_binary_bridge_ready(helper_binary, auto_start_daemon=True)
    binary_path = _safe_str(probe.helper_binary_path)
    request_obj = request.to_dict() if isinstance(request, HelperBinaryBridgeLoadRequest) else dict(request or {})
    model_ref = _safe_str(request_obj.get("modelRef") or request_obj.get("model_ref"))
    identifier = _safe_str(request_obj.get("identifier"))
    context_length = max(0, _safe_int(request_obj.get("contextLength") or request_obj.get("context_length"), 0))
    gpu_offload_ratio = _normalize_gpu_offload_ratio(
        request_obj.get("gpuOffloadRatio") if request_obj.get("gpuOffloadRatio") is not None else request_obj.get("gpu_offload_ratio")
    )
    parallel = max(0, _safe_int(request_obj.get("parallel"), 0))
    ttl_sec = max(
        0,
        _safe_int(
            request_obj.get("ttlSec")
            if request_obj.get("ttlSec") is not None
            else request_obj.get("ttl_sec")
            if request_obj.get("ttl_sec") is not None
            else request_obj.get("ttl"),
            0,
        ),
    )
    if not binary_path:
        return {
            "ok": False,
            "reasonCode": "helper_binary_missing",
            "error": "helper_binary_missing",
            "errorDetail": _safe_str(probe.import_error),
            "helperBinaryPath": "",
            "loadedModel": {},
            "alreadyLoaded": False,
        }
    if not model_ref:
        return {
            "ok": False,
            "reasonCode": "missing_model_ref",
            "error": "missing_model_ref",
            "errorDetail": "",
            "helperBinaryPath": binary_path,
            "loadedModel": {},
            "alreadyLoaded": False,
        }
    model_ref = _resolve_helper_load_model_ref(probe, model_ref, timeout_sec=timeout_sec)

    before_loaded = list_helper_bridge_loaded_models(probe, timeout_sec=min(4.0, timeout_sec))
    before_identifiers = {
        _safe_str(row.get("identifier"))
        for row in before_loaded
        if isinstance(row, dict) and _safe_str(row.get("identifier"))
    }
    already_loaded_row = _select_helper_loaded_row(before_loaded, identifier=identifier, model_ref=model_ref)
    if identifier and identifier in before_identifiers and already_loaded_row:
        return {
            "ok": True,
            "reasonCode": "helper_load_already_ready",
            "error": "",
            "errorDetail": "",
            "helperBinaryPath": binary_path,
            "loadedModel": already_loaded_row,
            "alreadyLoaded": True,
        }

    args = ["load", model_ref, "--yes"]
    if identifier:
        args.extend(["--identifier", identifier])
    if context_length > 0:
        args.extend(["--context-length", str(context_length)])
    if gpu_offload_ratio:
        args.extend(["--gpu", gpu_offload_ratio])
    if parallel > 0:
        args.extend(["--parallel", str(parallel)])
    if ttl_sec > 0:
        args.extend(["--ttl", str(ttl_sec)])

    load_deadline = time.time() + max(2.0, float(timeout_sec or 30.0))
    wakeup_retry_count = 0
    result: dict[str, Any] = {}
    output = ""
    after_loaded: list[dict[str, Any]] = []
    loaded_row: dict[str, Any] = {}
    while True:
        remaining_timeout = max(2.0, load_deadline - time.time())
        result = _run_helper_command(binary_path, args, timeout_sec=remaining_timeout)
        output = _safe_str(result.get("output"))
        wakeup_output = _is_helper_load_wakeup_output(output)
        after_loaded = (
            list_helper_bridge_loaded_models(binary_path, timeout_sec=max(4.0, min(remaining_timeout, 12.0)))
            if result.get("timedOut") or result.get("ok") or "already exists" in output.lower() or wakeup_output
            else []
        )
        loaded_row = _select_helper_loaded_row(after_loaded, identifier=identifier, model_ref=model_ref)
        if result.get("timedOut") and loaded_row:
            return {
                "ok": True,
                "reasonCode": "helper_load_ready_after_timeout",
                "error": "",
                "errorDetail": output[:240],
                "helperBinaryPath": binary_path,
                "loadedModel": loaded_row,
                "alreadyLoaded": bool(identifier and identifier in before_identifiers),
            }
        if not result.get("ok") and loaded_row and "already exists" in output.lower():
            return {
                "ok": True,
                "reasonCode": "helper_load_already_ready",
                "error": "",
                "errorDetail": output[:240],
                "helperBinaryPath": binary_path,
                "loadedModel": loaded_row,
                "alreadyLoaded": True,
            }
        if wakeup_output:
            if loaded_row:
                return {
                    "ok": True,
                    "reasonCode": "helper_load_ready_after_wakeup",
                    "error": "",
                    "errorDetail": output[:240],
                    "helperBinaryPath": binary_path,
                    "loadedModel": loaded_row,
                    "alreadyLoaded": bool(identifier and identifier in before_identifiers),
                }
            if time.time() + 0.5 < load_deadline:
                ensure_helper_bridge_server(
                    probe,
                    auto_start_daemon=True,
                    auto_start_server=True,
                    timeout_sec=max(4.0, min(remaining_timeout, 15.0)),
                )
                wakeup_retry_count += 1
                time.sleep(0.5)
                continue
        break

    if result.get("timedOut"):
        return {
            "ok": False,
            "reasonCode": "helper_load_timeout",
            "error": "helper_load_timeout",
            "errorDetail": output[:240],
            "helperBinaryPath": binary_path,
            "loadedModel": {},
            "alreadyLoaded": False,
        }
    if not result.get("ok"):
        return {
            "ok": False,
            "reasonCode": "helper_load_failed",
            "error": "helper_load_failed",
            "errorDetail": output[:240],
            "helperBinaryPath": binary_path,
            "loadedModel": {},
            "alreadyLoaded": False,
        }

    if not loaded_row:
        loaded_row = {
            "identifier": identifier,
            "modelKey": model_ref,
            "path": model_ref,
            "contextLength": context_length,
            "type": "",
            "lastUsedTime": int(round(_safe_float(0.0) * 1000.0)),
        }

    return {
        "ok": True,
        "reasonCode": "helper_load_ready_after_wakeup" if wakeup_retry_count > 0 else "helper_load_ready",
        "error": "",
        "errorDetail": output[:240],
        "helperBinaryPath": binary_path,
        "loadedModel": loaded_row,
        "alreadyLoaded": bool(identifier and identifier in before_identifiers),
    }


def unload_helper_bridge_model(
    helper_binary: str | HelperBinaryBridgeProbe,
    *,
    identifier: str = "",
    unload_all: bool = False,
    timeout_sec: float = 15.0,
) -> dict[str, Any]:
    probe = _resolve_probe_input(helper_binary)
    binary_path = _safe_str(probe.helper_binary_path)
    unload_identifier = _safe_str(identifier)
    if not binary_path:
        return {
            "ok": False,
            "reasonCode": "helper_binary_missing",
            "error": "helper_binary_missing",
            "errorDetail": _safe_str(probe.import_error),
            "helperBinaryPath": "",
        }
    if not unload_all and not unload_identifier:
        return {
            "ok": False,
            "reasonCode": "missing_helper_identifier",
            "error": "missing_helper_identifier",
            "errorDetail": "",
            "helperBinaryPath": binary_path,
        }

    args = ["unload", "--all"] if unload_all else ["unload", unload_identifier]
    result = _run_helper_command(binary_path, args, timeout_sec=timeout_sec)
    output = _safe_str(result.get("output"))
    if result.get("timedOut"):
        return {
            "ok": False,
            "reasonCode": "helper_unload_timeout",
            "error": "helper_unload_timeout",
            "errorDetail": output[:240],
            "helperBinaryPath": binary_path,
        }
    if not result.get("ok"):
        return {
            "ok": False,
            "reasonCode": "helper_unload_failed",
            "error": "helper_unload_failed",
            "errorDetail": output[:240],
            "helperBinaryPath": binary_path,
        }

    return {
        "ok": True,
        "reasonCode": "helper_unload_ready",
        "error": "",
        "errorDetail": output[:240],
        "helperBinaryPath": binary_path,
    }
