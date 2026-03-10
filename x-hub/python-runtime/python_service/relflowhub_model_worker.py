"""REL Flow Hub model command worker (offline-only, lightweight).

This bridges the Swift UI (which writes `model_commands/cmd_*.json`) and the
models snapshot (`models_state.json`).

Today it implements a safe MVP:
  - consume commands (load/sleep/unload)
  - update models_state.json accordingly
  - write an audit log

Later you can replace the "apply" logic with real MLX / llama.cpp loading.

No network access is required; we set common offline env vars defensively.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass


def _group_base_dir() -> str:
    # Keep consistent with `python_client/relflowhub_ipc.py`.
    return os.path.expanduser("~/Library/Group Containers/group.rel.flowhub")


def _base_dir() -> str:
    env = (os.environ.get("REL_FLOW_HUB_BASE_DIR") or "").strip()
    return os.path.expanduser(env) if env else _group_base_dir()


def _audit_path(base: str) -> str:
    return os.path.join(base, "model_worker_audit.log")


def _cmd_dir(base: str) -> str:
    return os.path.join(base, "model_commands")


def _cmd_result_dir(base: str) -> str:
    return os.path.join(base, "model_results")


def _state_path(base: str) -> str:
    return os.path.join(base, "models_state.json")


def _write_cmd_result(base: str, *, req_id: str, action: str, model_id: str, ok: bool, msg: str) -> None:
    try:
        os.makedirs(_cmd_result_dir(base), exist_ok=True)
        obj = {
            "type": "model_result",
            "req_id": str(req_id or ""),
            "action": str(action or ""),
            "model_id": str(model_id or ""),
            "ok": bool(ok),
            "msg": str(msg or ""),
            "finished_at": float(_now()),
        }
        out = os.path.join(_cmd_result_dir(base), f"res_{req_id}.json")
        tmp = out + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False)
        os.replace(tmp, out)
    except Exception:
        pass


def _now() -> float:
    return time.time()


def _audit(base: str, event: str, **kv: object) -> None:
    # TSV-ish for easy grep.
    parts = [f"{_now():.6f}", event]
    for k, v in kv.items():
        parts.append(f"{k}={v}")
    line = "\t".join(parts) + "\n"
    try:
        with open(_audit_path(base), "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass


def _read_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _write_json_atomic(path: str, obj: dict) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def _quant_bytes_per_param(quant: str) -> float:
    q = (quant or "").lower()
    if "int4" in q or "4" == q:
        return 0.5
    if "int8" in q or "8" == q:
        return 1.0
    # bf16/fp16
    return 2.0


def _estimate_memory_bytes(model: dict) -> int:
    # Rough, explainable estimate for UI; replace with real measured values later.
    params_b = float(model.get("paramsB") or 0.0)
    ctx = int(model.get("contextLength") or 0)
    bpp = _quant_bytes_per_param(str(model.get("quant") or ""))

    weights = params_b * 1e9 * bpp
    overhead = 0.35 * 1e9
    kv = 0.0
    if ctx > 0:
        kv = min(0.8e9, (ctx / 8192.0) * 0.25e9)
    return int(max(50_000_000, weights + overhead + kv))


def _estimate_tokens_per_sec(model: dict) -> float:
    # Purely a UI placeholder until real benchmarking is wired.
    params_b = max(0.1, float(model.get("paramsB") or 0.0))
    q = str(model.get("quant") or "").lower()
    quant_boost = 1.0
    if "int4" in q or q == "4":
        quant_boost = 1.25
    elif "int8" in q or q == "8":
        quant_boost = 1.1
    else:
        quant_boost = 0.85

    # Heuristic: bigger models are slower; keep within a sensible range.
    tps = (42.0 / (params_b ** 0.6)) * quant_boost
    return float(max(1.0, min(80.0, tps)))


@dataclass
class Cmd:
    path: str
    action: str
    model_id: str
    req_id: str
    requested_at: float


def _load_state(base: str) -> dict:
    p = _state_path(base)
    if not os.path.exists(p):
        return {"models": [], "updatedAt": _now()}
    try:
        return _read_json(p)
    except Exception:
        return {"models": [], "updatedAt": _now()}


def _save_state(base: str, state: dict) -> None:
    state["updatedAt"] = _now()
    _write_json_atomic(_state_path(base), state)


def _apply_command(state: dict, cmd: Cmd) -> tuple[bool, str]:
    models = state.get("models")
    if not isinstance(models, list):
        return False, "invalid_state_models"

    idx = None
    for i, m in enumerate(models):
        if isinstance(m, dict) and str(m.get("id") or "") == cmd.model_id:
            idx = i
            break
    if idx is None:
        return False, "unknown_model_id"

    m = models[idx]
    if cmd.action == "load":
        m["state"] = "loaded"
        if m.get("memoryBytes") in (None, 0):
            m["memoryBytes"] = _estimate_memory_bytes(m)
        if m.get("tokensPerSec") in (None, 0):
            m["tokensPerSec"] = _estimate_tokens_per_sec(m)
        return True, "ok"

    if cmd.action == "sleep":
        m["state"] = "sleeping"
        # Keep memoryBytes for now; later you can shrink here if sleep frees weights.
        if m.get("memoryBytes") in (None, 0):
            m["memoryBytes"] = _estimate_memory_bytes(m)
        m["tokensPerSec"] = None
        return True, "ok"

    if cmd.action == "unload":
        m["state"] = "available"
        m["memoryBytes"] = None
        m["tokensPerSec"] = None
        return True, "ok"

    return False, "unknown_action"


def _scan_commands(base: str) -> list[Cmd]:
    d = _cmd_dir(base)
    try:
        os.makedirs(d, exist_ok=True)
        files = [f for f in os.listdir(d) if f.endswith(".json") and f.startswith("cmd_")]
    except Exception:
        return []

    out: list[Cmd] = []
    for name in sorted(files):
        path = os.path.join(d, name)
        try:
            obj = _read_json(path)
            if str(obj.get("type") or "") != "model_command":
                continue
            out.append(
                Cmd(
                    path=path,
                    action=str(obj.get("action") or ""),
                    model_id=str(obj.get("model_id") or ""),
                    req_id=str(obj.get("req_id") or ""),
                    requested_at=float(obj.get("requested_at") or 0.0),
                )
            )
        except Exception:
            _audit(base, "cmd_parse_failed", path=path)
            # Don't spin forever on a bad file.
            try:
                os.remove(path)
            except Exception:
                pass
    return out


def _consume(base: str, cmd: Cmd) -> None:
    state = _load_state(base)
    ok, msg = _apply_command(state, cmd)
    if ok:
        _save_state(base, state)
    _write_cmd_result(base, req_id=cmd.req_id, action=cmd.action, model_id=cmd.model_id, ok=ok, msg=msg)
    _audit(base, "cmd", ok=int(ok), action=cmd.action, model_id=cmd.model_id, req_id=cmd.req_id, msg=msg)
    try:
        os.remove(cmd.path)
    except Exception:
        pass


def main() -> int:
    # Hard-disable common online codepaths.
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
    os.environ.setdefault("HF_DATASETS_OFFLINE", "1")
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

    base = _base_dir()
    os.makedirs(base, exist_ok=True)
    _audit(base, "model_worker_start", base=base)

    # Polling loop (ultra-light). File-system events are an easy future upgrade.
    while True:
        cmds = _scan_commands(base)
        for c in cmds:
            _consume(base, c)
        time.sleep(0.5)


if __name__ == "__main__":
    raise SystemExit(main())
