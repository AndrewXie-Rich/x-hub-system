from __future__ import annotations

from dataclasses import dataclass, field
import importlib
import importlib.util
import os
import sys
from typing import Any

from helper_binary_bridge import ensure_helper_binary_bridge_ready, probe_helper_binary_bridge
from provider_pack_registry import provider_pack_inventory
from xhub_local_service_bridge import ensure_xhub_local_service, probe_xhub_local_service


PACK_RUNTIME_READY = "pack_runtime_ready"
USER_RUNTIME_FALLBACK = "user_runtime_fallback"
RUNTIME_MISSING = "runtime_missing"

_NATIVE_ERROR_TOKENS = (
    "dlopen",
    "library not loaded",
    "image not found",
    "symbol not found",
    "mach-o",
    "native",
)
_READY_RUNTIME_REASON_CODES = {"ready", "helper_bridge_ready", "xhub_local_service_ready"}


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


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


def _json_dict(raw: Any) -> dict[str, Any]:
    return raw if isinstance(raw, dict) else {}


def _normalize_path(value: str) -> str:
    raw = _safe_str(value)
    if not raw or not raw.startswith("/"):
        return raw
    return os.path.abspath(os.path.expanduser(raw))


def _dedupe_paths(values: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for raw in values:
        normalized = _normalize_path(raw)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        out.append(normalized)
    return out


def _import_name(module_name: str) -> str:
    normalized = _safe_str(module_name).lower()
    if normalized in {"pil", "pillow"}:
        return "PIL"
    return normalized


def _module_origin_from_spec(spec: Any) -> str:
    if spec is None:
        return ""
    search_locations = getattr(spec, "submodule_search_locations", None)
    if search_locations:
        for location in list(search_locations):
            normalized = _normalize_path(str(location))
            if normalized:
                return normalized
    origin = _safe_str(getattr(spec, "origin", ""))
    if origin.lower() in {"built-in", "builtins", "frozen"}:
        return ""
    return _normalize_path(origin)


def _module_origin_from_loaded_module(module: Any) -> str:
    if module is None:
        return ""
    direct = _normalize_path(_safe_str(getattr(module, "__file__", "")))
    if direct:
        return direct
    return _module_origin_from_spec(getattr(module, "__spec__", None))


def _path_within_roots(path: str, roots: list[str]) -> bool:
    normalized = _normalize_path(path)
    if not normalized:
        return False
    for root in roots:
        candidate = _normalize_path(root)
        if not candidate:
            continue
        if normalized == candidate or normalized.startswith(candidate + os.sep):
            return True
    return False


def _candidate_hub_runtime_roots(base_dir: str) -> list[str]:
    normalized_base = _normalize_path(base_dir)
    candidates: list[str] = []
    for root in [
        os.path.expanduser("~/RELFlowHub"),
        normalized_base,
    ]:
        normalized_root = _normalize_path(root)
        if not normalized_root:
            continue
        py_deps_root = os.path.join(normalized_root, "py_deps")
        site_packages = os.path.join(py_deps_root, "site-packages")
        if os.path.isdir(site_packages) or os.path.exists(os.path.join(py_deps_root, "USE_PYTHONPATH")):
            candidates.append(site_packages)
        ai_runtime_root = os.path.join(normalized_root, "ai_runtime")
        if os.path.isdir(ai_runtime_root):
            candidates.append(ai_runtime_root)
    return _dedupe_paths(candidates)


def _guess_user_runtime_source(python_path: str) -> str:
    normalized = _normalize_path(python_path)
    lower = normalized.lower()
    if "/.venv/" in lower or "/venv/" in lower or "/conda/" in lower:
        return "user_python_venv"
    if normalized in {"/usr/bin/python3", "/usr/bin/python", "/usr/bin/env", "python3", "python"}:
        return "user_python_system"
    return "user_python_custom"


def _looks_like_native_dependency_error(exc: BaseException) -> bool:
    if isinstance(exc, OSError):
        return True
    detail = f"{type(exc).__name__}:{exc}".lower()
    return any(token in detail for token in _NATIVE_ERROR_TOKENS)


def _runtime_hint(
    provider_id: str,
    *,
    resolution_state: str,
    reason_code: str,
    current_python: str,
    hub_runtime_root: str,
    missing_requirements: list[str],
) -> str:
    provider = _safe_str(provider_id) or "provider"
    python_path = _normalize_path(current_python)
    hub_root = _normalize_path(hub_runtime_root)
    if resolution_state == USER_RUNTIME_FALLBACK:
        if python_path:
            if hub_root:
                return (
                    f"{provider} is running from user Python {python_path}. "
                    f"Install the provider runtime into {hub_root} to avoid per-machine Python drift."
                )
            return f"{provider} is running from user Python {python_path} instead of a Hub-managed runtime."
        return f"{provider} is running from a user-managed Python runtime."
    if resolution_state != RUNTIME_MISSING:
        return ""

    missing = ", ".join(sorted(_string_list(missing_requirements)))
    if reason_code == "native_dependency_error":
        if hub_root:
            return (
                f"{provider} runtime is present but native dependencies could not load. "
                f"Check the Python packages under {hub_root} or switch Hub to a real local .venv."
            )
        return f"{provider} runtime is present but native dependencies could not load in the current Python."
    if hub_root:
        return (
            f"{provider} runtime is missing required dependencies ({missing or 'unknown'}). "
            f"Install them into {hub_root} or start Hub with a local .venv that already has them."
        )
    return (
        f"{provider} runtime is missing required dependencies ({missing or 'unknown'}). "
        "Install them into a local .venv and restart AI Runtime."
    )


@dataclass
class ProviderRuntimeResolution:
    provider_id: str
    runtime_source: str
    runtime_source_path: str
    runtime_resolution_state: str
    runtime_reason_code: str
    fallback_used: bool
    import_error: str = ""
    runtime_hint: str = ""
    missing_requirements: list[str] = field(default_factory=list)
    missing_optional_requirements: list[str] = field(default_factory=list)
    ready_python_modules: list[str] = field(default_factory=list)
    python_executable: str = ""
    module_origins: dict[str, str] = field(default_factory=dict)
    managed_service_state: dict[str, Any] = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return _safe_str(self.runtime_reason_code) in _READY_RUNTIME_REASON_CODES

    def supports_modules(self, *module_names: str) -> bool:
        ready = set(_string_list(self.ready_python_modules))
        wanted = set(_string_list(list(module_names)))
        return wanted.issubset(ready)

    def to_status_fields(self) -> dict[str, Any]:
        return {
            "runtimeSource": _safe_str(self.runtime_source),
            "runtimeSourcePath": _safe_str(self.runtime_source_path),
            "runtimeResolutionState": _safe_str(self.runtime_resolution_state),
            "runtimeReasonCode": _safe_str(self.runtime_reason_code),
            "fallbackUsed": bool(self.fallback_used),
            "runtimeHint": _safe_str(self.runtime_hint),
            "runtimeMissingRequirements": _string_list(self.missing_requirements),
            "runtimeMissingOptionalRequirements": _string_list(self.missing_optional_requirements),
            "managedServiceState": _json_dict(self.managed_service_state),
        }


def resolve_provider_runtime(
    provider_id: str,
    *,
    base_dir: str,
    optional_python_modules: list[str] | None = None,
    eager_import: bool = True,
    service_hosted_runtime: bool = False,
    auto_start_runtime_services: bool = False,
) -> ProviderRuntimeResolution:
    provider = _safe_str(provider_id).lower() or "unknown"
    pack = next(
        (
            entry
            for entry in provider_pack_inventory([provider], base_dir=base_dir)
            if _safe_str(entry.get("providerId") or entry.get("provider_id")).lower() == provider
        ),
        {},
    )
    runtime_requirements = pack.get("runtimeRequirements") if isinstance(pack.get("runtimeRequirements"), dict) else {}
    execution_mode = _safe_str(runtime_requirements.get("executionMode") or runtime_requirements.get("execution_mode")).lower()
    declared_modules = _string_list(
        runtime_requirements.get("pythonModules") or runtime_requirements.get("python_modules")
    )
    optional_modules = set(_string_list(optional_python_modules))
    core_modules = [module for module in declared_modules if module not in optional_modules]
    helper_binary = _safe_str(runtime_requirements.get("helperBinary") or runtime_requirements.get("helper_binary"))
    native_dylib = _safe_str(runtime_requirements.get("nativeDylib") or runtime_requirements.get("native_dylib"))
    service_base_url = _safe_str(runtime_requirements.get("serviceBaseUrl") or runtime_requirements.get("service_base_url"))
    hub_runtime_roots = _candidate_hub_runtime_roots(base_dir)
    hub_runtime_root = hub_runtime_roots[0] if hub_runtime_roots else ""
    current_python = _normalize_path(sys.executable)

    if execution_mode == "helper_binary_bridge":
        probe = (
            ensure_helper_binary_bridge_ready(helper_binary, auto_start_daemon=True)
            if auto_start_runtime_services
            else probe_helper_binary_bridge(helper_binary)
        )
        normalized_missing = _string_list(probe.missing_requirements)
        normalized_optional_missing = _string_list(probe.missing_optional_requirements)
        return ProviderRuntimeResolution(
            provider_id=provider,
            runtime_source="helper_binary_bridge",
            runtime_source_path=_normalize_path(probe.helper_binary_path or helper_binary),
            runtime_resolution_state=PACK_RUNTIME_READY if probe.ready else RUNTIME_MISSING,
            runtime_reason_code=_safe_str(probe.reason_code) or "helper_probe_failed",
            fallback_used=False,
            import_error=_safe_str(probe.import_error),
            runtime_hint=_safe_str(probe.runtime_hint),
            missing_requirements=normalized_missing,
            missing_optional_requirements=normalized_optional_missing,
            ready_python_modules=[],
            python_executable=current_python,
            module_origins={},
        )

    service_runtime_internal = execution_mode == "xhub_local_service" and bool(service_hosted_runtime)

    if execution_mode == "xhub_local_service" and not service_runtime_internal:
        probe = probe_xhub_local_service(service_base_url, base_dir=base_dir)
        if not probe.ready and _safe_str(probe.reason_code) in {
            "xhub_local_service_unreachable",
            "xhub_local_service_starting",
            "xhub_local_service_not_ready",
        }:
            probe = ensure_xhub_local_service(
                service_base_url,
                base_dir=base_dir,
            )
        normalized_missing = _string_list(probe.missing_requirements)
        return ProviderRuntimeResolution(
            provider_id=provider,
            runtime_source="xhub_local_service",
            runtime_source_path=_safe_str(probe.base_url or service_base_url),
            runtime_resolution_state=PACK_RUNTIME_READY if probe.ready else RUNTIME_MISSING,
            runtime_reason_code=_safe_str(probe.reason_code) or "xhub_local_service_probe_failed",
            fallback_used=False,
            import_error="",
            runtime_hint=_safe_str(probe.runtime_hint),
            missing_requirements=normalized_missing,
            missing_optional_requirements=[],
            ready_python_modules=[],
            python_executable=current_python,
            module_origins={},
            managed_service_state=_json_dict(_json_dict(probe.metadata).get("managedState")),
        )

    ready_modules: list[str] = []
    missing_requirements: list[str] = []
    missing_optional_requirements: list[str] = []
    module_origins: dict[str, str] = {}
    import_error = ""
    runtime_reason_code = "ready"

    for module_name in declared_modules:
        import_name = _import_name(module_name)
        loaded_module = sys.modules.get(import_name)
        origin = _module_origin_from_loaded_module(loaded_module)
        spec = None
        if origin:
            spec = getattr(loaded_module, "__spec__", None)
        else:
            try:
                spec = importlib.util.find_spec(import_name)
            except Exception:
                spec = None
            origin = _module_origin_from_spec(spec)

        if origin:
            module_origins[module_name] = origin

        if not eager_import:
            if spec is None and loaded_module is None:
                if module_name in optional_modules:
                    missing_optional_requirements.append(f"python_module:{module_name}")
                    continue
                missing_requirements.append(f"python_module:{module_name}")
                if not import_error:
                    import_error = f"missing_module:{module_name}"
                runtime_reason_code = "missing_runtime"
                continue
            ready_modules.append(module_name)
            if not origin:
                module_origins[module_name] = _module_origin_from_loaded_module(loaded_module)
            continue

        try:
            importlib.import_module(import_name)
            ready_modules.append(module_name)
            if not origin:
                module_origins[module_name] = _module_origin_from_loaded_module(sys.modules.get(import_name))
            continue
        except Exception as exc:
            detail = f"{type(exc).__name__}:{exc}"
            if spec is None and loaded_module is None:
                if module_name in optional_modules:
                    missing_optional_requirements.append(f"python_module:{module_name}")
                    continue
                missing_requirements.append(f"python_module:{module_name}")
                if not import_error:
                    import_error = f"missing_module:{module_name}"
                runtime_reason_code = "missing_runtime"
                continue
            if _looks_like_native_dependency_error(exc):
                if module_name in optional_modules:
                    missing_optional_requirements.append(f"python_module:{module_name}")
                    continue
                runtime_reason_code = "native_dependency_error"
                if not import_error:
                    import_error = f"native_dependency_error:{module_name}:{detail}"
            else:
                if module_name in optional_modules:
                    missing_optional_requirements.append(f"python_module:{module_name}")
                    continue
                runtime_reason_code = "import_error"
                if not import_error:
                    import_error = f"module_import_failed:{module_name}:{detail}"
            missing_requirements.append(f"python_module:{module_name}")

    if helper_binary:
        helper_path = _normalize_path(helper_binary)
        if not helper_path or not os.path.exists(helper_path):
            missing_requirements.append(f"helper_binary:{helper_binary}")
            if runtime_reason_code == "ready":
                runtime_reason_code = "missing_runtime"
                import_error = import_error or f"missing_helper_binary:{helper_binary}"

    if native_dylib:
        dylib_path = _normalize_path(native_dylib)
        if not dylib_path or not os.path.exists(dylib_path):
            missing_requirements.append(f"native_dylib:{native_dylib}")
            if runtime_reason_code == "ready":
                runtime_reason_code = "missing_runtime"
                import_error = import_error or f"missing_native_dylib:{native_dylib}"

    normalized_missing = _string_list(missing_requirements)
    normalized_optional_missing = _string_list(missing_optional_requirements)
    all_core_ready = not normalized_missing and runtime_reason_code == "ready"
    all_declared_from_hub = bool(declared_modules) and all(
        _path_within_roots(module_origins.get(module_name, ""), hub_runtime_roots)
        for module_name in declared_modules
        if module_name in ready_modules
    )
    python_is_hub_managed = _path_within_roots(current_python, hub_runtime_roots)

    if service_runtime_internal:
        runtime_source = "xhub_local_service"
        runtime_source_path = _safe_str(service_base_url) or current_python
        if all_core_ready:
            runtime_resolution_state = PACK_RUNTIME_READY
            fallback_used = False
            runtime_reason_code = "xhub_local_service_ready"
        else:
            runtime_resolution_state = RUNTIME_MISSING
            fallback_used = False
            if runtime_reason_code == "ready":
                runtime_reason_code = "missing_runtime"
    elif all_core_ready:
        if all_declared_from_hub or python_is_hub_managed:
            runtime_source = "hub_py_deps" if all_declared_from_hub else "hub_runtime_python"
            runtime_source_path = hub_runtime_root or current_python
            runtime_resolution_state = PACK_RUNTIME_READY
            fallback_used = False
        else:
            runtime_source = _guess_user_runtime_source(current_python)
            runtime_source_path = current_python
            runtime_resolution_state = USER_RUNTIME_FALLBACK
            fallback_used = True
    else:
        runtime_source = "hub_py_deps" if hub_runtime_root else _guess_user_runtime_source(current_python)
        runtime_source_path = hub_runtime_root or current_python
        runtime_resolution_state = RUNTIME_MISSING
        fallback_used = False

    runtime_hint = _runtime_hint(
        provider,
        resolution_state=runtime_resolution_state,
        reason_code=runtime_reason_code,
        current_python=current_python,
        hub_runtime_root=hub_runtime_root,
        missing_requirements=normalized_missing + normalized_optional_missing,
    )
    if service_runtime_internal:
        missing_text = ", ".join(sorted(normalized_missing + normalized_optional_missing))
        if runtime_resolution_state == PACK_RUNTIME_READY:
            runtime_hint = (
                f"{provider} is executing inside xhub_local_service using service-hosted Python modules "
                f"from {current_python}."
            )
        else:
            runtime_hint = (
                f"{provider} is configured for xhub_local_service, but the service-hosted runtime in {current_python} "
                f"is missing required dependencies ({missing_text or 'unknown'})."
            )

    return ProviderRuntimeResolution(
        provider_id=provider,
        runtime_source=runtime_source,
        runtime_source_path=runtime_source_path,
        runtime_resolution_state=runtime_resolution_state,
        runtime_reason_code=runtime_reason_code,
        fallback_used=fallback_used,
        import_error=import_error,
        runtime_hint=runtime_hint,
        missing_requirements=normalized_missing,
        missing_optional_requirements=normalized_optional_missing,
        ready_python_modules=_string_list(ready_modules),
        python_executable=current_python,
        module_origins=module_origins,
    )
