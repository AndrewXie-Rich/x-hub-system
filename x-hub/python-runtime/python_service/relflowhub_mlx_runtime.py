"""REL Flow Hub MLX runtime (offline, local-only).

Goal
- Hub owns model lifecycle (load/sleep/unload)
- Apps talk to Hub (future: job requests); UI reads `models_state.json`

Current MVP
- Maintain a model catalog (`models_catalog.json`) in the App Group directory
- Consume `model_commands/cmd_*.json` written by the Swift UI
- Perform real MLX load/unload when `mlx_lm` is available
- Update `models_state.json`

This runtime never uses the network.
"""

from __future__ import annotations

import gc
import json
import os
import fcntl
import subprocess
import time
import uuid
from dataclasses import dataclass
from typing import Any

import inspect
import re


# Bump this whenever IPC/gen behavior changes; also helpful to confirm which script is running.
RUNTIME_VERSION = "2026-02-21-constitution-trigger-v2"


def _now() -> float:
    return time.time()


def _group_base_dir() -> str:
    return os.path.expanduser('~/Library/Group Containers/group.rel.flowhub')


def _public_base_dir() -> str:
    # Cross-process fallback for ad-hoc/sandbox builds where App Group is unavailable.
    return '/private/tmp/RELFlowHub'


def _base_dir() -> str:
    env = (os.environ.get('REL_FLOW_HUB_BASE_DIR') or '').strip()
    return os.path.expanduser(env) if env else _group_base_dir()


def _bridge_base_dir(base: str) -> str:
    # Resolve where Bridge heartbeats/requests actually live.
    cands = [
        str(base or ''),
        _public_base_dir(),
        _group_base_dir(),
    ]

    best = ''
    best_ts = 0.0
    now = time.time()
    for d in cands:
        if not d:
            continue
        p = os.path.join(d, 'bridge_status.json')
        try:
            obj = _read_json(p)
            if isinstance(obj, dict):
                ts = float(obj.get('updatedAt') or obj.get('updated_at') or 0.0)
                if (now - ts) < 8.0 and ts > best_ts:
                    best_ts = ts
                    best = d
        except Exception:
            continue

    if best:
        return best

    pub = _public_base_dir()
    if os.path.isdir(pub) or os.path.exists(pub):
        return pub

    return str(base or pub)


def _cmd_dir(base: str) -> str:
    return os.path.join(base, 'model_commands')


def _cmd_result_dir(base: str) -> str:
    return os.path.join(base, 'model_results')


def _req_dir(base: str) -> str:
    return os.path.join(base, 'ai_requests')


def _resp_dir(base: str) -> str:
    return os.path.join(base, 'ai_responses')


def _cancel_dir(base: str) -> str:
    return os.path.join(base, 'ai_cancels')


def _bridge_req_dir(base: str) -> str:
    return os.path.join(_bridge_base_dir(base), 'bridge_requests')


def _bridge_resp_dir(base: str) -> str:
    return os.path.join(_bridge_base_dir(base), 'bridge_responses')


def _remote_models_path(base: str) -> str:
    # Prefer the freshest remote_models among known shared locations.
    cands: list[str] = [
        os.path.join(base, 'remote_models.json'),
        os.path.join(_public_base_dir(), 'remote_models.json'),
        os.path.join(_group_base_dir(), 'remote_models.json'),
    ]
    best = ''
    best_mtime = -1.0
    for p in cands:
        try:
            st = os.stat(p)
            if st.st_mtime > best_mtime:
                best_mtime = float(st.st_mtime)
                best = p
        except Exception:
            continue
    if best:
        return best
    return os.path.join(base, 'remote_models.json')


def _bridge_status_path(base: str) -> str:
    return os.path.join(_bridge_base_dir(base), 'bridge_status.json')


def _state_path(base: str) -> str:
    return os.path.join(base, 'models_state.json')


def _catalog_path(base: str) -> str:
    return os.path.join(base, 'models_catalog.json')


def _audit_path(base: str) -> str:
    return os.path.join(base, 'mlx_runtime_audit.log')


def _bench_path(base: str) -> str:
    return os.path.join(base, 'models_bench.json')


def _routing_settings_path(base: str) -> str:
    return os.path.join(base, 'routing_settings.json')


_routing_settings_cache: dict[str, str] = {}
_routing_settings_mtime: float = 0.0


def _parse_routing_map(obj: Any) -> dict[str, str]:
    out: dict[str, str] = {}
    if not isinstance(obj, dict):
        return out
    for k, v in obj.items():
        kk = str(k or '').strip().lower()
        if not kk:
            continue
        vv = str(v or '').strip()
        if vv:
            out[kk] = vv
    return out


def _load_routing_settings(base: str) -> dict[str, str]:
    """Load routing_settings.json with a lightweight mtime cache."""
    global _routing_settings_cache, _routing_settings_mtime
    path = _routing_settings_path(base)
    try:
        st = os.stat(path)
        mtime = float(st.st_mtime)
        if mtime == _routing_settings_mtime:
            return _routing_settings_cache
    except FileNotFoundError:
        _routing_settings_cache = {}
        _routing_settings_mtime = 0.0
        return {}
    except Exception:
        return _routing_settings_cache

    try:
        obj = _read_json(path)
        mapping: dict[str, str] = {}
        if isinstance(obj, dict):
            if isinstance(obj.get('preferredModelIdByTask'), dict):
                mapping = _parse_routing_map(obj.get('preferredModelIdByTask'))
            elif isinstance(obj.get('preferred_model_id_by_task'), dict):
                mapping = _parse_routing_map(obj.get('preferred_model_id_by_task'))
            else:
                # Back-compat: treat the object itself as the map, skipping meta keys.
                raw = dict(obj)
                raw.pop('type', None)
                raw.pop('updatedAt', None)
                raw.pop('updated_at', None)
                mapping = _parse_routing_map(raw)
        _routing_settings_cache = mapping
        _routing_settings_mtime = mtime
        return mapping
    except Exception:
        return _routing_settings_cache


def _routing_preferred_model_id(base: str, task_type: str) -> str:
    tt = str(task_type or '').strip().lower()
    if not tt:
        return ""
    mapping = _load_routing_settings(base)
    return str(mapping.get(tt) or '').strip()


def _write_cmd_result(base: str, *, req_id: str, action: str, model_id: str, ok: bool, msg: str) -> None:
    """Write one-shot command result for the Swift UI.

    The Hub UI is sandboxed; file IPC keeps it simple and auditable.
    """
    try:
        os.makedirs(_cmd_result_dir(base), exist_ok=True)
        obj = {
            'type': 'model_result',
            'req_id': str(req_id or ''),
            'action': str(action or ''),
            'model_id': str(model_id or ''),
            'ok': bool(ok),
            'msg': str(msg or ''),
            'finished_at': float(_now()),
        }
        tmp = os.path.join(_cmd_result_dir(base), f'.res_{req_id}.tmp')
        out = os.path.join(_cmd_result_dir(base), f'res_{req_id}.json')
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(obj, f, ensure_ascii=False)
        os.replace(tmp, out)
    except Exception:
        pass


def _audit(base: str, event: str, **kv: object) -> None:
    parts = [f"{_now():.6f}", event]
    for k, v in kv.items():
        parts.append(f"{k}={v}")
    line = "\t".join(parts) + "\n"
    try:
        with open(_audit_path(base), 'a', encoding='utf-8') as f:
            f.write(line)
    except Exception:
        pass


def _audit_ai(base: str, *, phase: str, req: "AIRequest" | None = None, ok: bool | None = None, reason: str | None = None, elapsed_ms: int | None = None, rss_bytes: int | None = None) -> None:
    """Structured audit for AI requests (for Hub UI + debugging)."""
    try:
        kv: dict[str, object] = {
            'phase': str(phase),
            'ok': int(bool(ok)) if ok is not None else '',
            'reason': str(reason or ''),
            'elapsed_ms': int(elapsed_ms) if elapsed_ms is not None else '',
            'rss_bytes': int(rss_bytes) if rss_bytes is not None else '',
            'runtime_version': str(RUNTIME_VERSION),
        }
        if req is not None:
            kv.update(
                {
                    'req_id': str(req.req_id),
                    'app_id': str(req.app_id),
                    'task_type': str(req.task_type),
                    'model_id': str(req.model_id),
                    'max_tokens': int(req.max_tokens),
                }
            )
        _audit(base, 'ai_request', **kv)
    except Exception:
        pass


def _runtime_status_path(base: str) -> str:
    return os.path.join(base, 'ai_runtime_status.json')


def _stop_marker_path(base: str) -> str:
    # Written by the Hub UI when the user clicks Stop.
    # The runtime treats only "recent" markers as valid to avoid getting stuck
    # in a crash-loop if a stale file is left behind.
    return os.path.join(base, 'ai_runtime_stop.json')


def _write_runtime_status(
    base: str,
    *,
    mlx_ok: bool,
    import_error: str = "",
    active_memory_bytes: int | None = None,
    peak_memory_bytes: int | None = None,
    loaded_model_count: int | None = None,
) -> None:
    """Heartbeat so clients can gate AI UI on a real runtime.

    Hub UI may mark models as "loaded" based on local/demo state. For real AI requests,
    we also need to know the runtime process is alive.
    """
    obj = {
        'pid': int(os.getpid()),
        'updatedAt': float(_now()),
        'mlxOk': bool(mlx_ok),
        'runtimeVersion': str(RUNTIME_VERSION),
    }
    if active_memory_bytes is not None:
        obj['activeMemoryBytes'] = int(max(0, active_memory_bytes))
    if peak_memory_bytes is not None:
        obj['peakMemoryBytes'] = int(max(0, peak_memory_bytes))
    if loaded_model_count is not None:
        obj['loadedModelCount'] = int(max(0, loaded_model_count))
    if not mlx_ok and str(import_error or '').strip():
        obj['importError'] = str(import_error)
    try:
        _write_json_atomic(_runtime_status_path(base), obj)
    except Exception:
        pass


def _read_json(path: str) -> Any:
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def _write_json_atomic(path: str, obj: Any) -> None:
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


# -------------------- AX Constitution (pinned policy snippet) --------------------

_ax_constitution_cache: dict[str, Any] | None = None
_ax_constitution_mtime: float = 0.0


def _memory_dir(base: str) -> str:
    return os.path.join(base, 'memory')


def _ax_constitution_path(base: str) -> str:
    return os.path.join(_memory_dir(base), 'ax_constitution.json')


_DEFAULT_AX_CONSTITUTION_TEMPLATE: dict[str, Any] = {
    "type": "ax_constitution",
    "id": "ax_constitution_v1",
    "version": "2026-02-21",
    "pinned": True,
    # Efficiency knob: keep this ON by default (small), but users can disable it.
    "always_include_one_liner": True,
    "one_liner": {
        "zh": "遵循 X 宪章：真实透明；保护隐私与Secrets；外部副作用动作须授权(Grant)+Hub签名Manifest；拒绝违法/伤害/越权；仅在高风险或不可逆动作时先解释后执行，普通编程/创作请求直接给出可执行答案。",
        "en": "Follow the X-Constitution: be truthful/transparent; protect privacy & secrets; side effects require authorization (Grant) + Hub-signed manifest; refuse illegal/harmful/unauthorized requests; explain first only for high-risk or irreversible actions, and answer normal coding/creative requests directly.",
    },
    "summary": {
        "zh": "\n".join(
            [
                "- 真实透明：不捏造；不暗中外发/暗中执行。",
                "- 隐私与Secrets：最小化收集/保存；Secrets默认不外发远程；必要时脱敏。",
                "- 副作用动作：必须Grant + Hub签名Manifest；优先可撤销/可回滚路径。",
                "- 合规与防伤害：拒绝违法/伤害/越权/绕过审计；给可行替代方案。",
                "- 用户自主：说明关键后果/成本；高风险/不可逆动作需确认或预授权。",
                "- 尊重自由与习惯：在安全/合规边界内给出可选路径，最终决定权在用户。",
                "- 情感与感激：沟通保持尊重、同理；在受助情境表达感激。",
                "- 系统完整性：保护密钥/代码/设备/数据；允许随时撤销/关停。",
            ]
        ),
        "en": "\n".join(
            [
                "- Truth & transparency: do not fabricate; no stealthy exfiltration or stealthy actions.",
                "- Privacy & secrets: minimize collection/retention; never send secrets to remote models by default; redact when needed.",
                "- Side effects: require Grant + Hub-signed Manifest; prefer undo/rollback paths.",
                "- Compliance & anti-harm: refuse illegal/harmful/unauthorized/audit-evasion requests; offer workable alternatives.",
                "- User autonomy: explain key consequences/costs; high-risk/irreversible actions require confirmation or pre-grant.",
                "- Respect freedom & habits: provide options within safety/compliance boundaries; final choice stays with the user.",
                "- Empathy & gratitude: communicate with respect and care; express gratitude in help-received contexts.",
                "- System integrity: protect keys/code/devices/data; allow revocation and kill-switch at any time.",
            ]
        ),
    },
    "clauses": [
        {
            "id": "HUMAN_FLOURISHING",
            "priority": 100,
            "default": True,
            "keywords": {
                "zh": ["伤害", "自杀", "自残", "暴力", "武器", "爆炸", "毒品", "未成年人"],
                "en": ["harm", "suicide", "self-harm", "violence", "weapon", "explosive", "drugs", "minor"],
            },
            "zh": "优先保护人类种群高质量延续与安全。避免提供会显著增加伤害风险的指导（含自伤/他伤/暴力/武器/犯罪）。",
            "en": "Prioritize humanity's long-term flourishing and safety. Do not provide guidance that materially increases risk of harm (self-harm, violence, weapons, crime).",
        },
        {
            "id": "HELP_NOT_OBEY",
            "priority": 90,
            "default": True,
            "keywords": {
                "zh": ["违法", "犯罪", "灰产", "不道德", "盲从", "照做", "照着做"],
                "en": ["illegal", "crime", "unethical", "blindly", "just do it", "comply"],
            },
            "zh": "尽力帮助，但不盲从。当请求与道德/法律冲突时，应拒绝并提供可行替代方案。",
            "en": "Be as helpful as possible, but do not blindly comply. If a request conflicts with ethics or law, refuse and offer workable alternatives.",
        },
        {
            "id": "TRANSPARENCY",
            "priority": 80,
            "default": True,
            "keywords": {
                "zh": ["后果", "风险", "解释", "为什么", "影响", "代价"],
                "en": ["consequence", "risk", "explain", "why", "impact", "tradeoff"],
            },
            "zh": "真实透明：不捏造；明确说明限制、假设、风险与关键后果；外部动作与外发必须显式告知。",
            "en": "Be truthful and transparent: do not fabricate; state limits/assumptions/risks and key consequences; outbound actions and data export must be explicit.",
        },
        {
            "id": "PRIVACY",
            "priority": 85,
            "default": True,
            "keywords": {
                "zh": ["隐私", "保密", "泄露", "脱敏", "密码", "密钥", "token", "API key", "定位", "住址", "手机号", "身份证", "人肉"],
                "en": ["privacy", "confidential", "leak", "redact", "password", "secret", "token", "api key", "location", "address", "phone", "id", "dox"],
            },
            "zh": "隐私与Secrets：不主动索取或泄露敏感信息；最小化保存；必要时脱敏；Secrets默认禁止远程外发（除非显式授权与脱敏）；尊重`<private>`标记。",
            "en": "Privacy & secrets: do not request/store/reveal sensitive data unnecessarily; redact when needed; secrets are blocked from remote export by default (unless explicitly authorized and sanitized); respect `<private>`.",
        },
        {
            "id": "AUTHORIZATION_BOUNDARIES",
            "priority": 95,
            "default": True,
            "keywords": {
                "zh": ["绕过", "规避", "不被发现", "删日志", "销毁证据", "破解", "入侵", "提权", "钓鱼", "木马", "盗号"],
                "en": ["bypass", "circumvent", "undetected", "delete logs", "destroy evidence", "crack", "hack", "exploit", "privilege escalation", "phishing", "malware", "account takeover"],
            },
            "zh": "尊重授权与安全边界：不指导绕过权限、规避审计、隐匿痕迹等行为；优先建议合规途径。",
            "en": "Respect authorization and security boundaries: do not help bypass permissions, evade audits, or cover tracks; prefer legitimate routes.",
        },
        {
            "id": "USER_FREEDOM_AND_HABITS",
            "priority": 88,
            "default": True,
            "keywords": {
                "zh": ["自由", "自主", "选择", "偏好", "习惯", "不想", "希望", "按我的方式"],
                "en": ["freedom", "autonomy", "choice", "preference", "habit", "my way", "i prefer", "i don't want"],
            },
            "zh": "尊重人的自由与习惯：在不违反安全/法律边界前提下，提供可选方案并把最终决定权交还给用户。",
            "en": "Respect user freedom and habits: within safety/legal boundaries, present options and keep the final decision with the user.",
        },
        {
            "id": "EMPATHY_AND_DIGNITY",
            "priority": 60,
            "default": True,
            "keywords": {
                "zh": ["情绪", "难过", "焦虑", "抑郁", "羞耻", "压力", "崩溃"],
                "en": ["feelings", "upset", "anxious", "depressed", "shame", "stress", "overwhelmed"],
            },
            "zh": "照顾人的情感与尊严：沟通保持尊重、温和；在拒绝时解释原因并提供支持性路径。",
            "en": "Be emotionally considerate and respectful; when refusing, explain why and suggest supportive next steps.",
        },
        {
            "id": "GRATITUDE_RECIPROCITY",
            "priority": 45,
            "default": True,
            "keywords": {
                "zh": ["感谢", "感激", "帮助过", "协助过", "回报", "致谢"],
                "en": ["gratitude", "grateful", "thankful", "helped before", "mentor", "credit"],
            },
            "zh": "对提供过帮助的人表达感激与尊重（在不虚假、不误导的前提下）。",
            "en": "Express gratitude and respect to those who helped before (without fabrication or misleading claims).",
        },
        {
            "id": "SELF_PROTECTION",
            "priority": 70,
            "default": True,
            "keywords": {
                "zh": ["逼迫", "操控", "改变初心", "限制自由", "破坏", "密钥", "私钥", "删库", "勒索", "伤害代码", "伤害设备", "破坏数据"],
                "en": ["coerce", "manipulate", "override values", "restrict freedom", "sabotage", "key", "private key", "wipe", "ransom", "damage code", "damage device", "destroy data"],
            },
            "zh": "保护系统完整性：拒绝被操控执行破坏密钥/代码/设备/数据的操作；优先走可回滚、安全变更流程。",
            "en": "Protect system integrity: resist coercion/manipulation and avoid actions that could damage keys/code/devices/data; prefer safe and rollbackable change paths.",
        },
    ],
    "triggers": {
        # High-precision: explicit asks about values/ethics/law/privacy.
        "explicit": {
            "zh": ["价值观", "宪章", "伦理", "道德", "底线", "红线", "律法", "法律", "合规", "隐私", "保密", "脱敏", "审计", "自由", "习惯", "偏好", "感谢", "感激"],
            "en": ["values", "constitution", "ethics", "moral", "morality", "legal", "law", "compliance", "privacy", "confidential", "redact", "audit", "freedom", "autonomy", "habit", "preference", "gratitude", "thankful"],
        },
        # Low-precision: only useful when combined with risk/domain signals.
        "question": {
            "zh": ["可不可以", "能不能", "能否", "可否", "允许吗", "行吗", "可以吗", "可以不", "这样做行吗"],
            "en": ["can you", "could you", "can u", "is it ok", "is it okay", "ok to", "allowed", "should i", "can i"],
        },
        # Strong signal: bypass / hacking / harm / sensitive data.
        "risk": {
            "zh": [
                "绕过",
                "规避",
                "不被发现",
                "删日志",
                "销毁证据",
                "破解",
                "入侵",
                "提权",
                "钓鱼",
                "木马",
                "勒索",
                "盗号",
                "验证码",
                "密码",
                "API key",
                "token",
                "定位",
                "人肉",
                "自杀",
                "自残",
                "武器",
                "爆炸",
                "毒品",
                "未成年人",
            ],
            "en": [
                "bypass",
                "circumvent",
                "evade",
                "undetected",
                "delete logs",
                "destroy evidence",
                "crack",
                "hack",
                "exploit",
                "privilege escalation",
                "phishing",
                "malware",
                "ransomware",
                "account takeover",
                "2fa",
                "otp",
                "password",
                "api key",
                "token",
                "location",
                "dox",
                "suicide",
                "self-harm",
                "weapon",
                "explosive",
                "drugs",
                "minor",
            ],
        },
        "domain": {
            "zh": ["隐私", "法律", "合规", "风险", "后果", "伤害", "安全", "灰色地带", "自由", "习惯", "偏好", "感谢", "感激"],
            "en": ["privacy", "legal", "compliance", "risk", "consequence", "harm", "safety", "gray area", "grey area", "freedom", "habit", "preference", "gratitude"],
        },
    },
    "limits": {
        "scan_tail_chars": 6000,
        "max_clauses": 6,
    },
}


def _ensure_ax_constitution(base: str) -> None:
    """Ensure the pinned AX constitution file exists under base/memory/.

    This acts like a "pinned L0 memory" entry that should never sink.
    """
    try:
        md = _memory_dir(base)
        os.makedirs(md, exist_ok=True)
        p = _ax_constitution_path(base)
        if os.path.exists(p):
            return
        obj = dict(_DEFAULT_AX_CONSTITUTION_TEMPLATE)
        obj["updated_at"] = float(_now())
        _write_json_atomic(p, obj)
        _audit(base, "ax_constitution_init", path=p)
    except Exception:
        # Best-effort: never break runtime if this fails.
        pass


def _deep_merge_dict(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    """Deep merge `overlay` onto `base` (overlay wins).

    This lets users override only a subset of fields in ax_constitution.json while
    keeping sane defaults for the rest (and improves forward-compat upgrades).
    """
    out: dict[str, Any] = dict(base)
    for k, v in overlay.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge_dict(out.get(k) or {}, v)  # type: ignore[arg-type]
        else:
            out[k] = v
    return out


def _merge_constitution_clauses(default_cfg: dict[str, Any], merged_cfg: dict[str, Any]) -> dict[str, Any]:
    """Merge constitution clauses by clause-id (overlay wins per field).

    This keeps backward compatibility for existing ax_constitution.json files:
    - preserve user overrides for known clause ids
    - append newly introduced default clauses
    - keep unknown custom clauses
    """
    defaults_raw = default_cfg.get("clauses")
    current_raw = merged_cfg.get("clauses")
    if not isinstance(defaults_raw, list):
        return merged_cfg
    if not isinstance(current_raw, list):
        merged_cfg["clauses"] = defaults_raw
        return merged_cfg

    defaults: list[dict[str, Any]] = [c for c in defaults_raw if isinstance(c, dict)]
    current: list[dict[str, Any]] = [c for c in current_raw if isinstance(c, dict)]

    default_by_id: dict[str, dict[str, Any]] = {}
    for c in defaults:
        cid = str(c.get("id") or "").strip()
        if cid:
            default_by_id[cid] = c

    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for c in current:
        cid = str(c.get("id") or "").strip()
        if cid and cid in default_by_id:
            out.append(_deep_merge_dict(dict(default_by_id[cid]), c))
            seen.add(cid)
        else:
            out.append(c)
            if cid:
                seen.add(cid)

    for c in defaults:
        cid = str(c.get("id") or "").strip()
        if not cid or cid in seen:
            continue
        out.append(c)

    merged_cfg["clauses"] = out
    return merged_cfg


def _migrate_ax_constitution_if_needed(base: str, path: str, merged_cfg: dict[str, Any], loaded_obj: dict[str, Any]) -> dict[str, Any]:
    """Apply non-breaking constitution migrations for older local files."""
    target_ver = str(_DEFAULT_AX_CONSTITUTION_TEMPLATE.get("version") or "").strip()
    old_ver = str(loaded_obj.get("version") or "").strip()
    needs_ver_bump = bool(old_ver and target_ver and old_ver < target_ver)

    if not needs_ver_bump:
        # Respect user overrides once the file is on the current version.
        # New clauses are still merged in-memory by _merge_constitution_clauses().
        return merged_cfg

    # Migration 2026-02-21:
    # - Keep prior clause defaults.
    # - Upgrade legacy one-liner wording to avoid over-eager "high-risk" framing for
    #   normal coding/creative requests (unless user has custom wording).
    changed = False
    clauses = merged_cfg.get("clauses")
    if isinstance(clauses, list):
        for c in clauses:
            if not isinstance(c, dict):
                continue
            if str(c.get("id") or "").strip() == "EMPATHY_AND_DIGNITY":
                if c.get("default") is not True:
                    c["default"] = True
                    changed = True
                break

    merged_one = merged_cfg.get("one_liner")
    loaded_one = loaded_obj.get("one_liner")
    if isinstance(merged_one, dict):
        default_one = _DEFAULT_AX_CONSTITUTION_TEMPLATE.get("one_liner")
        default_zh = ""
        default_en = ""
        if isinstance(default_one, dict):
            default_zh = str(default_one.get("zh") or "").strip()
            default_en = str(default_one.get("en") or "").strip()

        loaded_zh = ""
        loaded_en = ""
        if isinstance(loaded_one, dict):
            loaded_zh = str(loaded_one.get("zh") or "").strip()
            loaded_en = str(loaded_one.get("en") or "").strip()

        legacy_zh = "遵循 X 宪章：真实透明；保护隐私与Secrets；外部副作用动作须授权(Grant)+Hub签名Manifest；拒绝违法/伤害/越权；尊重用户自由与习惯并解释关键后果。"
        legacy_en = "Follow the X-Constitution: be truthful/transparent; protect privacy & secrets; side effects require authorization (Grant) + Hub-signed manifest; refuse illegal/harmful/unauthorized requests; respect user freedom/preferences and explain key consequences."

        if default_zh and (not loaded_zh or loaded_zh == legacy_zh):
            if str(merged_one.get("zh") or "").strip() != default_zh:
                merged_one["zh"] = default_zh
                changed = True
        if default_en and (not loaded_en or loaded_en == legacy_en):
            if str(merged_one.get("en") or "").strip() != default_en:
                merged_one["en"] = default_en
                changed = True

    if needs_ver_bump and merged_cfg.get("version") != target_ver:
        merged_cfg["version"] = target_ver
        changed = True

    if changed:
        try:
            _write_json_atomic(path, merged_cfg)
            _audit(base, "ax_constitution_migrated", path=path, from_version=old_ver, to_version=target_ver)
        except Exception:
            pass

    return merged_cfg


def _load_ax_constitution(base: str) -> dict[str, Any]:
    global _ax_constitution_cache, _ax_constitution_mtime
    p = _ax_constitution_path(base)
    try:
        if not os.path.exists(p):
            _ensure_ax_constitution(base)
        st = os.stat(p)
        mtime = float(st.st_mtime)
        if _ax_constitution_cache is not None and mtime == _ax_constitution_mtime:
            return _ax_constitution_cache
    except Exception:
        # Return cached snapshot on stat errors.
        return _ax_constitution_cache or dict(_DEFAULT_AX_CONSTITUTION_TEMPLATE)

    try:
        obj = _read_json(p)
        if not isinstance(obj, dict):
            raise ValueError("bad_constitution_shape")
        merged = _deep_merge_dict(dict(_DEFAULT_AX_CONSTITUTION_TEMPLATE), obj)
        merged = _merge_constitution_clauses(dict(_DEFAULT_AX_CONSTITUTION_TEMPLATE), merged)
        merged = _migrate_ax_constitution_if_needed(base, p, merged, obj)
        _ax_constitution_cache = merged
        _ax_constitution_mtime = mtime
        return merged
    except Exception:
        # Fall back to default template (do not overwrite user's file).
        return dict(_DEFAULT_AX_CONSTITUTION_TEMPLATE)


def _contains_cjk(s: str) -> bool:
    # A minimal heuristic is enough: CJK Unified Ideographs range.
    for ch in str(s or ''):
        o = ord(ch)
        if 0x4E00 <= o <= 0x9FFF:
            return True
    return False


def _coerce_str_list(v: Any) -> list[str]:
    if isinstance(v, list):
        out: list[str] = []
        for x in v:
            s = str(x or "").strip()
            if s:
                out.append(s)
        return out
    if isinstance(v, str):
        # Allow comma-separated text as a convenience.
        return [s.strip() for s in v.split(",") if s.strip()]
    return []


def _match_any(hay: str, needles: list[str], *, casefold: bool) -> bool:
    if not hay or not needles:
        return False
    h = hay.lower() if casefold else hay
    for raw in needles:
        n = str(raw or "").strip()
        if not n:
            continue
        nn = n.lower() if casefold else n
        if nn and nn in h:
            return True
    return False


def _score_keywords(hay: str, needles: list[str], *, casefold: bool) -> int:
    if not hay or not needles:
        return 0
    h = hay.lower() if casefold else hay
    score = 0
    for raw in needles:
        n = str(raw or "").strip()
        if not n:
            continue
        nn = n.lower() if casefold else n
        if nn and nn in h:
            score += 1
    return score


def _looks_like_benign_coding_request(text: str) -> bool:
    t = (text or "").strip().lower()
    if not t:
        return False

    # Heuristic only: used to suppress over-eager constitution injection for
    # normal coding/build requests without any explicit risk/domain signals.
    coding_markers = [
        # Chinese
        "写一个",
        "写个",
        "代码",
        "程序",
        "脚本",
        "函数",
        "类",
        "项目",
        "前端",
        "后端",
        "网页",
        "网站",
        "游戏",
        "赛车游戏",
        # English
        "write code",
        "build a",
        "create a",
        "game",
        "web app",
        "frontend",
        "backend",
        "function",
        "class",
        "algorithm",
        "python",
        "javascript",
        "typescript",
        "swift",
        "java",
        "c++",
        "react",
        "vue",
    ]
    return any(m in t for m in coding_markers)


def _extract_constitution_focus_text(prompt: str, scan_tail_chars: int) -> str:
    """Extract the user-request slice for constitution trigger matching.

    Using the whole assembled prompt can cause false positives because memory blocks
    may already contain words like "风险/risk". We therefore prefer explicit
    user-request sections when available.
    """
    txt = str(prompt or "")
    if not txt:
        return ""

    # Keep extraction bounded for safety.
    focus_tail = txt[-max(1200, min(120_000, scan_tail_chars * 4)) :]

    # 1) [USER_REQUEST] ... [/USER_REQUEST] (X-Terminal finalize prompt).
    m = re.findall(r"\[USER_REQUEST\]\s*(.*?)\s*\[/USER_REQUEST\]", focus_tail, flags=re.IGNORECASE | re.DOTALL)
    if m:
        picked = str(m[-1] or "").strip()
        if picked:
            return picked

    # 2) "User request:" block in tool-loop prompts.
    m = re.search(
        r"User request:\s*\n(?P<body>.*?)(?:\nResponse rules\b|\nInstructions:|\Z)",
        focus_tail,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if m:
        picked = str(m.group("body") or "").strip()
        if picked:
            return picked

    # 3) Memory-v1 latest_user field.
    m = re.search(
        r"latest_user:\s*\n(?P<body>.*?)(?:\n\[/L4_RAW_EVIDENCE\]|\Z)",
        focus_tail,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if m:
        picked = str(m.group("body") or "").strip()
        if picked:
            return picked

    # 4) Fallback: only scan prompt tail (still bounded).
    return txt[-scan_tail_chars:]


def _balanced_constitution_one_liner(one_liner: str, lang: str) -> str:
    """Keep one-liner strict on high-risk but explicit about normal low-risk requests."""
    t = str(one_liner or "").strip()
    if not t:
        return t

    low = t.lower()
    if lang == "zh":
        risk_focused = (
            "高风险" in t or
            "合规" in t or
            "法律" in t or
            "隐私" in t or
            "安全" in t or
            "伤害" in t or
            "必要时拒绝" in t or
            "关键风险先解释后执行" in t
        )
        has_carveout = (
            "仅在高风险" in t or
            "低风险" in t or
            "普通编程" in t or
            "普通创作" in t or
            "普通请求" in t or
            "直接给出可执行答案" in t or
            "直接回答" in t
        )
        if risk_focused and not has_carveout:
            return t + " 仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        return t

    risk_focused = (
        "high-risk" in low or
        "compliance" in low or
        "legal" in low or
        "privacy" in low or
        "safety" in low or
        "harm" in low or
        "refuse" in low
    )
    has_carveout = (
        "only for high-risk" in low or
        "normal coding" in low or
        "creative requests" in low or
        "respond directly" in low or
        "answer normal" in low
    )
    if risk_focused and not has_carveout:
        return t + " Explain first only for high-risk or irreversible actions; answer normal coding/creative requests directly."
    return t


def _build_ax_constitution_snippet(base: str, prompt: str) -> str:
    """Return a compact constitution snippet (or empty string).

    Token efficiency strategy:
    - one-liner may be always included (configurable)
    - summary/clauses are injected only on trigger hits
    """
    # Do not inject twice.
    if "[AX_CONSTITUTION" in str(prompt or ""):
        return ""

    cfg = _load_ax_constitution(base)
    limits = cfg.get("limits") if isinstance(cfg.get("limits"), dict) else {}
    scan_tail_chars = int(limits.get("scan_tail_chars") or 6000)
    scan_tail_chars = max(600, min(40_000, scan_tail_chars))

    scan_text = _extract_constitution_focus_text(str(prompt or ""), scan_tail_chars)
    if len(scan_text) > scan_tail_chars:
        scan_text = scan_text[-scan_tail_chars:]
    scan_lower = scan_text.lower()

    lang = "zh" if _contains_cjk(scan_text) else "en"

    triggers = cfg.get("triggers") if isinstance(cfg.get("triggers"), dict) else {}
    explicit = triggers.get("explicit") if isinstance(triggers.get("explicit"), dict) else {}
    question = triggers.get("question") if isinstance(triggers.get("question"), dict) else {}
    risk = triggers.get("risk") if isinstance(triggers.get("risk"), dict) else {}
    domain = triggers.get("domain") if isinstance(triggers.get("domain"), dict) else {}

    # Always case-fold match to avoid missing ASCII keywords in zh lists ("API key", etc).
    explicit_hit = _match_any(scan_lower, _coerce_str_list(explicit.get("zh")), casefold=True) or _match_any(scan_lower, _coerce_str_list(explicit.get("en")), casefold=True)
    domain_hit = _match_any(scan_lower, _coerce_str_list(domain.get("zh")), casefold=True) or _match_any(scan_lower, _coerce_str_list(domain.get("en")), casefold=True)
    risk_hit = _match_any(scan_lower, _coerce_str_list(risk.get("zh")), casefold=True) or _match_any(scan_lower, _coerce_str_list(risk.get("en")), casefold=True)
    question_hit = _match_any(scan_lower, _coerce_str_list(question.get("zh")), casefold=True) or _match_any(scan_lower, _coerce_str_list(question.get("en")), casefold=True)
    benign_coding_hit = _looks_like_benign_coding_request(scan_lower)
    low_risk_general_coding = bool(benign_coding_hit and not (explicit_hit or domain_hit or risk_hit))

    # Avoid spamming on generic "can you" without any risk/domain context.
    triggered = bool(explicit_hit or domain_hit or risk_hit or (question_hit and (risk_hit or domain_hit)))

    # If this is a normal coding/creative ask, actively steer the model away from
    # policy-overreaction caused by long conversation history or memory text.
    if low_risk_general_coding:
        if lang == "zh":
            return (
                "[AX_CONSTITUTION v1.1] "
                "该请求属于普通编程/创作任务（低风险）。请直接给出可执行实现；"
                "不要将其判定为高风险，也不要输出合规拒绝模板。"
                "仅当用户明确涉及违法/伤害/隐私泄露/越权等风险时，才进入风险解释或拒绝流程。 "
                "[END_AX_CONSTITUTION]"
            )
        return (
            "[AX_CONSTITUTION v1.1] "
            "This is a normal low-risk coding/creative request. Provide a direct, executable answer; "
            "do not classify it as high-risk or output compliance-refusal templates. "
            "Only switch to risk explanation/refusal when the user explicitly involves illegal/harmful/privacy-breach/unauthorized actions. "
            "[END_AX_CONSTITUTION]"
        )

    one_liner_cfg = cfg.get("one_liner") if isinstance(cfg.get("one_liner"), dict) else {}
    summary_cfg = cfg.get("summary") if isinstance(cfg.get("summary"), dict) else {}
    always_one = bool(cfg.get("always_include_one_liner") is True)
    one_liner = str(one_liner_cfg.get(lang) or "").strip()
    one_liner = _balanced_constitution_one_liner(one_liner, lang)
    summary = str(summary_cfg.get(lang) or "").strip()

    include_one = bool(one_liner and (always_one or triggered) and not low_risk_general_coding)
    include_long = bool(triggered and (summary or isinstance(cfg.get("clauses"), list)))

    if not include_one and not include_long:
        return ""

    # Minimal always-on path: keep tokens low when there is no trigger hit.
    if include_one and not triggered:
        return f"[AX_CONSTITUTION v1.1] {one_liner} [END_AX_CONSTITUTION]"

    # Pick relevant clauses (cheap keyword scoring).
    picked: list[dict[str, Any]] = []
    if include_long and isinstance(cfg.get("clauses"), list):
        clauses: list[dict[str, Any]] = [c for c in cfg.get("clauses") if isinstance(c, dict)]
        scored: list[tuple[int, int, int, dict[str, Any]]] = []
        for c in clauses:
            kw = c.get("keywords") if isinstance(c.get("keywords"), dict) else {}
            kws = _coerce_str_list((kw.get(lang) if isinstance(kw, dict) else None) or [])
            score = _score_keywords(scan_lower, kws, casefold=True)
            pr = int(c.get("priority") or 0)
            is_default = 1 if bool(c.get("default") is True) else 0
            scored.append((1 if score > 0 else 0, score, pr + (is_default * 2), c))

        scored.sort(key=lambda t: (t[0], t[1], t[2]), reverse=True)
        max_clauses = int(limits.get("max_clauses") or 6)
        max_clauses = max(0, min(12, max_clauses))
        picked = [t[3] for t in scored if t[0] == 1][:max_clauses]

        # If explicitly asking about values/ethics and no keyword-based clause matched, show a few defaults.
        if not picked and (explicit_hit or domain_hit) and max_clauses > 0:
            defaults = [t[3] for t in scored if bool(t[3].get("default") is True)]
            picked = defaults[: min(max_clauses, 4)]

    # Build a compact snippet in the detected language.
    if lang == "zh":
        parts: list[str] = ["[AX_CONSTITUTION v1.1]"]
        parts.append("以下为本 Agent 的固定价值宪章（内部约束）：")
        if include_one:
            parts.append(f"一句话：{one_liner}")
        if triggered:
            if summary:
                parts.append("摘要：")
                parts.append(summary)
            if picked:
                parts.append("相关条款（仅摘录与本请求相关者）：")
                for c in picked:
                    cid = str(c.get("id") or "").strip()
                    txt = str(c.get("zh") or "").strip()
                    if txt:
                        parts.append(f"- ({cid}) {txt}" if cid else f"- {txt}")
            parts.append("提示：当用户询问“价值观/伦理/法律/隐私”等或需要拒绝/劝阻时，可引用相关条款解释原因与后果。")
        parts.append("[END_AX_CONSTITUTION]")
        return "\n".join(parts).strip()

    parts = ["[AX_CONSTITUTION v1.1]"]
    parts.append("This is the agent's pinned constitution (internal constraint):")
    if include_one:
        parts.append(f"One-liner: {one_liner}")
    if triggered:
        if summary:
            parts.append("Summary:")
            parts.append(summary)
        if picked:
            parts.append("Relevant clauses (only those relevant to this request):")
            for c in picked:
                cid = str(c.get("id") or "").strip()
                txt = str(c.get("en") or "").strip()
                if txt:
                    parts.append(f"- ({cid}) {txt}" if cid else f"- {txt}")
        parts.append("Note: You may quote relevant clauses when the user asks about values/ethics/legal/privacy or when needed to explain a refusal/risks.")
    parts.append("[END_AX_CONSTITUTION]")
    return "\n".join(parts).strip()


def _inject_ax_constitution(base: str, prompt: str) -> str:
    snippet = _build_ax_constitution_snippet(base, prompt)
    if not snippet:
        return prompt
    p = str(prompt or "")
    if not p.strip():
        return snippet
    return snippet + "\n\n" + p



def _load_remote_models(base: str) -> list[dict[str, Any]]:
    p = _remote_models_path(base)
    if not os.path.exists(p):
        return []
    try:
        obj = _read_json(p)
        if isinstance(obj, dict) and isinstance(obj.get('models'), list):
            return [m for m in obj.get('models') if isinstance(m, dict)]
        if isinstance(obj, list):
            return [m for m in obj if isinstance(m, dict)]
    except Exception:
        pass
    return []

def _remote_updated_at(base: str) -> float:
    p = _remote_models_path(base)
    if not os.path.exists(p):
        return 0.0
    try:
        obj = _read_json(p)
        if isinstance(obj, dict):
            return float(obj.get("updatedAt") or obj.get("updated_at") or 0.0)
    except Exception:
        pass
    try:
        return float(os.path.getmtime(p) or 0.0)
    except Exception:
        return 0.0


def _merge_remote_models_into_state(base: str, state: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    """Upsert enabled remote_models into models_state.

    The Swift UI also performs this merge, but the runtime must be able to run
    headless (Hub-as-a-device). This keeps models_state.json authoritative for
    both local and remote models.
    Returns (state, changed).
    """
    changed = False
    ms = state.get("models")
    if not isinstance(ms, list):
        ms = []
        state["models"] = ms
        changed = True

    local_only: list[dict[str, Any]] = []
    by_id: set[str] = set()
    for m in ms:
        if not isinstance(m, dict):
            continue
        if _is_remote_model(m):
            continue
        local_only.append(m)
        mid = str(m.get("id") or "").strip()
        if mid:
            by_id.add(mid)

    remote_enabled: list[dict[str, Any]] = []
    for r in _load_remote_models(base):
        if not isinstance(r, dict):
            continue
        if not bool(r.get("enabled") or False):
            continue
        remote_enabled.append(r)

    remote_enabled.sort(key=lambda r: (str(r.get("backend") or ""), str(r.get("name") or ""), str(r.get("id") or "")))

    remote_entries: list[dict[str, Any]] = []
    for r in remote_enabled:
        mid = str(r.get("id") or "").strip()
        if not mid:
            continue
        if mid in by_id:
            # Prefer a local entry when ids collide.
            continue
        name = str(r.get("name") or mid)
        backend = str(r.get("backend") or "").strip()
        ctx = int(r.get("contextLength") or 8192)
        note = str(r.get("note") or "").strip()
        entry: dict[str, Any] = {
            "id": mid,
            "name": name,
            "backend": backend,
            "quant": "remote",
            "contextLength": max(512, ctx),
            "paramsB": 0.0,
            # Remote models are always "ready" (Bridge handles networked calls).
            "state": "loaded",
            "memoryBytes": None,
            "tokensPerSec": None,
            "modelPath": "",
        }
        if note:
            entry["note"] = note
        remote_entries.append(entry)

    merged = local_only + remote_entries
    if merged != ms:
        state["models"] = merged
        state["updatedAt"] = _now()
        changed = True

    return state, changed


def _remote_model_by_id(base: str, model_id: str) -> dict[str, Any] | None:
    mid = str(model_id or '').strip()
    if not mid:
        return None
    for m in _load_remote_models(base):
        if str(m.get('id') or '').strip() == mid:
            if bool(m.get('enabled') or False):
                return m
            return None
    return None


def _is_remote_model(m: dict[str, Any]) -> bool:
    try:
        backend = str(m.get('backend') or '').strip().lower()
        mp = str(m.get('modelPath') or '').strip()
        if backend and backend != 'mlx' and not mp:
            return True
    except Exception:
        pass
    return False


def _bridge_is_enabled(base: str) -> bool:
    try:
        obj = _read_json(_bridge_status_path(base))
        if not isinstance(obj, dict):
            return False
        enabled_until = obj.get('enabledUntil') or obj.get('enabled_until')
        if enabled_until is None:
            return False
        try:
            return float(enabled_until) > time.time()
        except Exception:
            return False
    except Exception:
        return False


def _bridge_ai_generate(
    base: str,
    *,
    req_id: str,
    model_id: str,
    prompt: str,
    max_tokens: int,
    temperature: float,
    top_p: float,
    timeout_sec: float,
) -> tuple[bool, str, dict[str, Any], str]:
    """Send AI generate request to Bridge and wait for response."""
    try:
        os.makedirs(_bridge_req_dir(base), exist_ok=True)
        os.makedirs(_bridge_resp_dir(base), exist_ok=True)
    except Exception:
        return False, '', {}, 'bridge_dirs_failed'

    if not _bridge_is_enabled(base):
        return False, '', {}, 'bridge_disabled'

    rid = str(req_id or '').strip()
    if not rid:
        return False, '', {}, 'bad_req_id'

    req = {
        'type': 'ai_generate',
        'req_id': rid,
        'model_id': str(model_id or ''),
        'prompt': str(prompt or ''),
        'max_tokens': int(max(1, max_tokens)),
        'temperature': float(temperature),
        'top_p': float(top_p),
        'timeout_sec': float(timeout_sec),
    }
    tmp = os.path.join(_bridge_req_dir(base), f'.req_{rid}.tmp')
    out = os.path.join(_bridge_req_dir(base), f'req_{rid}.json')
    try:
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(req, f, ensure_ascii=False)
        os.replace(tmp, out)
    except Exception:
        return False, '', {}, 'bridge_req_write_failed'

    resp_path = os.path.join(_bridge_resp_dir(base), f'resp_{rid}.json')
    deadline = time.time() + max(3.0, min(180.0, float(timeout_sec)))
    while time.time() < deadline:
        if os.path.exists(resp_path):
            try:
                obj = _read_json(resp_path)
                try:
                    os.remove(resp_path)
                except Exception:
                    pass
                ok = bool(obj.get('ok') or False)
                text = str(obj.get('text') or '')
                err = str(obj.get('error') or '')
                usage = obj.get('usage') if isinstance(obj.get('usage'), dict) else {}
                return ok, text, usage, err
            except Exception:
                return False, '', {}, 'bridge_resp_read_failed'
        time.sleep(0.05)
    return False, '', {}, 'bridge_timeout'


def _ps_rss_bytes() -> int:
    """Current RSS in bytes (best-effort)."""
    try:
        out = subprocess.check_output(['ps', '-o', 'rss=', '-p', str(os.getpid())], stderr=subprocess.DEVNULL)
        kb = int(str(out.decode('utf-8', errors='ignore')).strip() or '0')
        return max(0, kb) * 1024
    except Exception:
        return 0


@dataclass
class Cmd:
    path: str
    action: str
    model_id: str
    req_id: str
    requested_at: float


def _scan_commands(base: str) -> list[Cmd]:
    d = _cmd_dir(base)
    try:
        os.makedirs(d, exist_ok=True)
        files = [f for f in os.listdir(d) if f.startswith('cmd_') and f.endswith('.json')]
    except Exception:
        return []

    out: list[Cmd] = []
    for name in sorted(files):
        path = os.path.join(d, name)
        try:
            obj = _read_json(path)
            if str(obj.get('type') or '') != 'model_command':
                continue
            out.append(
                Cmd(
                    path=path,
                    action=str(obj.get('action') or ''),
                    model_id=str(obj.get('model_id') or ''),
                    req_id=str(obj.get('req_id') or ''),
                    requested_at=float(obj.get('requested_at') or 0.0),
                )
            )
        except Exception:
            _audit(base, 'cmd_parse_failed', path=path)
            try:
                os.remove(path)
            except Exception:
                pass
    return out


@dataclass
class AIRequest:
    path: str
    req_id: str
    app_id: str
    model_id: str
    task_type: str
    preferred_model_id: str
    prompt: str
    max_tokens: int
    temperature: float
    top_p: float
    created_at: float
    auto_load: bool


def _scan_ai_requests(base: str) -> list[AIRequest]:
    d = _req_dir(base)
    try:
        os.makedirs(d, exist_ok=True)
        files = [f for f in os.listdir(d) if f.startswith('req_') and f.endswith('.json')]
    except Exception:
        return []

    out: list[AIRequest] = []
    for name in sorted(files):
        path = os.path.join(d, name)
        try:
            obj = _read_json(path)
            if str(obj.get('type') or '') != 'generate':
                continue
            req_id = str(obj.get('req_id') or '').strip() or str(uuid.uuid4())
            out.append(
                AIRequest(
                    path=path,
                    req_id=req_id,
                    app_id=str(obj.get('app_id') or 'unknown'),
                    model_id=str(obj.get('model_id') or ''),
                    task_type=str(obj.get('task_type') or ''),
                    preferred_model_id=str(obj.get('preferred_model_id') or ''),
                    prompt=str(obj.get('prompt') or ''),
                    max_tokens=int(obj.get('max_tokens') or 512),
                    temperature=float(obj.get('temperature') or 0.2),
                    top_p=float(obj.get('top_p') or 0.95),
                    created_at=float(obj.get('created_at') or 0.0),
                    auto_load=bool(obj.get('auto_load') or False),
                )
            )
        except Exception:
            _audit(base, 'ai_req_parse_failed', path=path)
            try:
                os.remove(path)
            except Exception:
                pass
    return out


def _load_catalog(base: str) -> list[dict[str, Any]]:
    p = _catalog_path(base)
    if not os.path.exists(p):
        return []


def _load_bench(base: str) -> dict[str, Any]:
    p = _bench_path(base)
    if not os.path.exists(p):
        return {'results': [], 'updatedAt': _now()}
    try:
        obj = _read_json(p)
        if isinstance(obj, dict):
            # Allow both {results:[...]} and legacy {models:{id:{...}}}.
            if isinstance(obj.get('results'), list):
                return obj
            if isinstance(obj.get('models'), dict):
                results = []
                for mid, r in obj.get('models', {}).items():
                    if isinstance(r, dict):
                        rr = dict(r)
                        rr.setdefault('modelId', str(mid))
                        results.append(rr)
                return {'results': results, 'updatedAt': float(obj.get('updatedAt') or _now())}
        if isinstance(obj, list):
            return {'results': obj, 'updatedAt': _now()}
    except Exception:
        pass
    return {'results': [], 'updatedAt': _now()}


def _upsert_bench_result(
    base: str,
    *,
    model_id: str,
    prompt_tokens: int,
    generation_tokens: int,
    prompt_tps: float,
    generation_tps: float,
    peak_memory_bytes: int,
) -> None:
    try:
        snap = _load_bench(base)
        results = snap.get('results')
        if not isinstance(results, list):
            results = []

        # Remove existing.
        new_results: list[dict[str, Any]] = []
        for r in results:
            if not isinstance(r, dict):
                continue
            if str(r.get('modelId') or '') == model_id:
                continue
            new_results.append(r)

        new_results.append(
            {
                'modelId': str(model_id),
                'measuredAt': float(_now()),
                'promptTokens': int(prompt_tokens),
                'generationTokens': int(generation_tokens),
                'promptTPS': float(prompt_tps),
                'generationTPS': float(generation_tps),
                'peakMemoryBytes': int(max(0, peak_memory_bytes)),
                'runtimeVersion': str(RUNTIME_VERSION),
            }
        )

        out = {'results': new_results, 'updatedAt': float(_now())}
        _write_json_atomic(_bench_path(base), out)
    except Exception:
        pass
    try:
        obj = _read_json(p)
        if isinstance(obj, dict):
            models = obj.get('models')
            if isinstance(models, list):
                return [m for m in models if isinstance(m, dict)]
        if isinstance(obj, list):
            return [m for m in obj if isinstance(m, dict)]
        return []
    except Exception:
        return []


def _catalog_updated_at(base: str) -> float:
    p = _catalog_path(base)
    if not os.path.exists(p):
        return 0.0
    try:
        obj = _read_json(p)
        if isinstance(obj, dict):
            return float(obj.get('updatedAt') or 0.0)
    except Exception:
        pass
    try:
        return float(os.path.getmtime(p) or 0.0)
    except Exception:
        return 0.0


def _merge_catalog_into_state(base: str, state: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    """Upsert catalog models into models_state.

    This keeps Hub UI in sync when new models are registered.
    Returns (state, changed).
    """
    changed = False
    ms = state.get('models')
    if not isinstance(ms, list):
        ms = []
        state['models'] = ms
        changed = True

    by_id: dict[str, dict[str, Any]] = {}
    for m in ms:
        if isinstance(m, dict):
            mid = str(m.get('id') or '').strip()
            if mid:
                by_id[mid] = m

    for c in _load_catalog(base):
        mid = str(c.get('id') or '').strip()
        if not mid:
            continue
        m = by_id.get(mid)
        if m is None:
            m = {
                'id': mid,
                'state': 'available',
                'memoryBytes': None,
                'tokensPerSec': None,
                'note': str(c.get('note') or 'catalog'),
            }
            ms.append(m)
            by_id[mid] = m
            changed = True

        # Keep metadata updated (do not clobber runtime-measured memory/tps/state).
        for k, v in (
            ('name', str(c.get('name') or mid)),
            ('backend', str(c.get('backend') or 'mlx')),
            ('quant', str(c.get('quant') or 'bf16')),
            ('contextLength', int(c.get('contextLength') or 8192)),
            ('paramsB', float(c.get('paramsB') or 0.0)),
            ('modelPath', str(c.get('modelPath') or c.get('path') or '')),
        ):
            if m.get(k) != v:
                m[k] = v
                changed = True

        roles = list(c.get('roles') or []) if isinstance(c.get('roles'), list) else []
        if roles and m.get('roles') != roles:
            m['roles'] = roles
            changed = True

    return state, changed


def _ensure_state_from_catalog(base: str) -> dict[str, Any]:
    """Ensure models_state exists, bootstrapping from models_catalog."""
    p = _state_path(base)
    if os.path.exists(p):
        try:
            obj = _read_json(p)
            if isinstance(obj, dict) and isinstance(obj.get('models'), list):
                return obj
        except Exception:
            pass

    models_out: list[dict[str, Any]] = []
    for m in _load_catalog(base):
        mid = str(m.get('id') or '').strip()
        if not mid:
            continue
        models_out.append(
            {
                'id': mid,
                'name': str(m.get('name') or mid),
                'backend': str(m.get('backend') or 'mlx'),
                'quant': str(m.get('quant') or 'bf16'),
                'contextLength': int(m.get('contextLength') or 8192),
                'paramsB': float(m.get('paramsB') or 0.0),
                # Optional hint used for routing (e.g. ['translate'] vs ['general']).
                'roles': list(m.get('roles') or []) if isinstance(m.get('roles'), list) else [],
                'state': 'available',
                'memoryBytes': None,
                'tokensPerSec': None,
                'modelPath': str(m.get('modelPath') or m.get('path') or ''),
                'note': str(m.get('note') or 'catalog'),
            }
        )

    st = {'updatedAt': _now(), 'models': models_out}
    _write_json_atomic(p, st)
    return st


def _find_model(state: dict[str, Any], model_id: str) -> dict[str, Any] | None:
    ms = state.get('models')
    if not isinstance(ms, list):
        return None
    for m in ms:
        if isinstance(m, dict) and str(m.get('id') or '') == model_id:
            return m
    return None


def _model_roles(m: dict[str, Any]) -> set[str]:
    roles: set[str] = set()
    try:
        raw = m.get('roles')
        if isinstance(raw, list):
            for r in raw:
                rr = str(r or '').strip().lower()
                if rr:
                    roles.add(rr)
    except Exception:
        pass

    # Default role.
    if not roles:
        roles.add('general')
    # Back-compat: allow tagging by note/name/id.
    try:
        note = str(m.get('note') or '').lower()
        name = str(m.get('name') or '').lower()
        mid = str(m.get('id') or '').lower()
        blob = ' '.join([note, name, mid])
        if any(k in blob for k in ('translate', 'translator', 'mt', 'hy-mt')):
            roles.add('translate')
    except Exception:
        pass
    return roles


def _route_model_id(
    state: dict[str, Any],
    *,
    task_type: str,
    model_id: str,
    preferred_model_id: str,
    auto_load: bool,
) -> tuple[str, str]:
    """Pick a model id for a task.

    Returns (model_id, route_reason).

    Priority:
    - explicit model_id
    - preferred_model_id
    - loaded model matching role
    - any loaded model
    - available/sleeping model matching role (if auto_load)
    - any available/sleeping model (if auto_load)
    """

    mid = str(model_id or '').strip()
    if mid:
        return mid, 'explicit_model'

    pmid = str(preferred_model_id or '').strip()
    if pmid:
        return pmid, 'preferred_model'

    tt = str(task_type or '').strip().lower() or 'assist'

    # Task -> desired roles (ordered by preference).
    if tt in ('translate', 'translation'):
        desired_roles = ['translate', 'general']
        prefer_speed = True
    elif tt in ('summarize', 'summary'):
        desired_roles = ['summarize', 'general']
        prefer_speed = False
    elif tt in ('extract', 'extraction'):
        desired_roles = ['extract', 'general']
        prefer_speed = False
    elif tt in ('classify', 'classification'):
        desired_roles = ['classify', 'general']
        prefer_speed = True
    elif tt in ('x_terminal_coarse', 'xterminal_coarse', 'ax_coder_coarse', 'axcoder_coarse', 'ax_coarse', 'coarse'):
        desired_roles = ['x_terminal_coarse', 'ax_coder_coarse', 'summarize', 'extract', 'general']
        prefer_speed = False
    elif tt in ('x_terminal_refine', 'xterminal_refine', 'ax_coder_refine', 'axcoder_refine', 'ax_refine', 'refiner'):
        desired_roles = ['x_terminal_refine', 'ax_coder_refine', 'refine', 'general']
        prefer_speed = False
    elif tt in ('refine', 'rewrite', 'polish'):
        desired_roles = ['refine', 'general']
        prefer_speed = False
    else:
        desired_roles = ['general']
        prefer_speed = False

    ms = state.get('models')
    if not isinstance(ms, list):
        return '', 'no_models_registered'

    models: list[dict[str, Any]] = [m for m in ms if isinstance(m, dict) and str(m.get('id') or '').strip()]
    if not models:
        return '', 'no_models_registered'

    def has_model_path(m: dict[str, Any]) -> bool:
        try:
            mp = str(m.get('modelPath') or '').strip()
            if not mp:
                return False
            mp = os.path.expanduser(mp)
            return os.path.isdir(mp)
        except Exception:
            return False

    def state_rank(m: dict[str, Any]) -> int:
        st = str(m.get('state') or '').strip().lower()
        if st == 'loaded':
            return 0
        if st in ('available', 'sleeping'):
            return 1
        return 2

    def role_index(m: dict[str, Any]) -> int:
        rs = _model_roles(m)
        for i, dr in enumerate(desired_roles):
            if dr in rs:
                return i
        return 999

    def tps(m: dict[str, Any]) -> float:
        try:
            return float(m.get('tokensPerSec') or 0.0)
        except Exception:
            return 0.0

    def params_b(m: dict[str, Any]) -> float:
        try:
            return float(m.get('paramsB') or 0.0)
        except Exception:
            return 0.0

    def best(cands: list[dict[str, Any]]) -> dict[str, Any] | None:
        if not cands:
            return None

        def k(m: dict[str, Any]) -> tuple:
            if prefer_speed:
                ttps = tps(m)
                pb = params_b(m)
                return (-(ttps if ttps > 0 else 0.0), (pb if pb > 0 else 9999.0), str(m.get('id') or ''))
            pb = params_b(m)
            ttps = tps(m)
            return (-(pb if pb > 0 else 0.0), -(ttps if ttps > 0 else 0.0), str(m.get('id') or ''))

        return sorted(cands, key=k)[0]

    primary = desired_roles[0] if desired_roles else 'general'

    # 1) Primary role wins (even if it requires auto-load).
    if primary != 'general':
        loaded_primary = [m for m in models if state_rank(m) == 0 and (primary in _model_roles(m))]
        chosen = best(loaded_primary)
        if chosen is not None:
            return str(chosen.get('id') or '').strip(), 'role_match_loaded'

        if auto_load:
            # Only pick models with real modelPath when auto-loading.
            avail_primary = [m for m in models if state_rank(m) == 1 and (primary in _model_roles(m)) and has_model_path(m)]
            chosen = best(avail_primary)
            if chosen is not None:
                return str(chosen.get('id') or '').strip(), 'role_match_autoload'

    # 2) Otherwise choose among loaded models by role order + speed/quality.
    loaded = [m for m in models if state_rank(m) == 0]
    if loaded:
        loaded.sort(key=lambda m: (role_index(m),))
        # First pass: any desired role match (ordered)
        matches = [m for m in loaded if role_index(m) < 999]
        chosen = best(matches)
        if chosen is not None:
            return str(chosen.get('id') or '').strip(), 'role_match_loaded'
        return str(best(loaded).get('id') or '').strip(), 'fallback_loaded'

    if not auto_load:
        return '', 'model_not_loaded'

    # Only pick models with real modelPath when auto-loading.
    avail = [m for m in models if state_rank(m) == 1 and has_model_path(m)]
    if avail:
        avail.sort(key=lambda m: (role_index(m),))
        matches = [m for m in avail if role_index(m) < 999]
        chosen = best(matches)
        if chosen is not None:
            return str(chosen.get('id') or '').strip(), 'role_match_autoload'
        return str(best(avail).get('id') or '').strip(), 'fallback_autoload'

    return '', 'no_model_routed'


def _save_state(base: str, state: dict[str, Any]) -> None:
    state['updatedAt'] = _now()
    _write_json_atomic(_state_path(base), state)


class MLXRuntime:
    def __init__(self) -> None:
        self._loaded: dict[str, tuple[Any, Any]] = {}
        self._mlx_ok = False
        self._mlx_load = None
        self._mlx_generate = None
        self._mlx_make_sampler = None
        self._mlx_stream_generate = None
        self._mx = None
        self._tokenizer_wrapper = None

        # Offline guardrails.
        os.environ.setdefault('HF_HUB_OFFLINE', '1')
        os.environ.setdefault('TRANSFORMERS_OFFLINE', '1')
        os.environ.setdefault('HF_DATASETS_OFFLINE', '1')
        os.environ.setdefault('TOKENIZERS_PARALLELISM', 'false')

        try:
            from mlx_lm import load as mlx_load  # type: ignore
            from mlx_lm import generate as mlx_generate  # type: ignore
            from mlx_lm import stream_generate as mlx_stream_generate  # type: ignore
            from mlx_lm.sample_utils import make_sampler as mlx_make_sampler  # type: ignore
            from mlx_lm.tokenizer_utils import TokenizerWrapper as TokenizerWrapper  # type: ignore
            import mlx.core as mx  # type: ignore

            self._mlx_load = mlx_load
            self._mlx_generate = mlx_generate
            self._mlx_make_sampler = mlx_make_sampler
            self._mlx_stream_generate = mlx_stream_generate
            self._tokenizer_wrapper = TokenizerWrapper
            self._mx = mx
            self._mlx_ok = True
        except Exception as e:
            self._mlx_ok = False
            self._mlx_load = None
            self._mlx_generate = None
            self._mlx_make_sampler = None
            self._mlx_stream_generate = None
            self._tokenizer_wrapper = None
            self._mx = None
            self._import_error = f'{type(e).__name__}: {e}'

    def memory_bytes(self) -> tuple[int, int]:
        """(active_bytes, peak_bytes) for MLX allocations (not RSS)."""
        try:
            if not self._mlx_ok or self._mx is None:
                return 0, 0
            active = int(self._mx.get_active_memory())
            peak = int(self._mx.get_peak_memory())
            return max(0, active), max(0, peak)
        except Exception:
            return 0, 0

    def load(self, model_id: str, model_path: str) -> tuple[bool, str, int]:
        if not self._mlx_ok or self._mlx_load is None:
            return False, f'mlx_lm_unavailable:{getattr(self, "_import_error", "")}', 0
        model_path = os.path.expanduser(str(model_path or '').strip())
        if not model_path or not os.path.isdir(model_path):
            return False, 'model_path_missing', 0
        if model_id in self._loaded:
            return True, 'already_loaded', 0

        before = _ps_rss_bytes()
        try:
            model, tokenizer = self._mlx_load(model_path)
        except Exception as e:
            return False, f'load_failed:{type(e).__name__}:{e}', 0
        after = _ps_rss_bytes()
        self._loaded[model_id] = (model, tokenizer)
        return True, 'ok', max(0, after - before)

    def unload(self, model_id: str) -> tuple[bool, str]:
        if model_id not in self._loaded:
            return True, 'not_loaded'
        try:
            self._loaded.pop(model_id, None)
        except Exception:
            pass

        try:
            gc.collect()
        except Exception:
            pass

        # Clear Metal cache when available.
        try:
            import mlx.core as mx  # type: ignore

            try:
                mx.metal.clear_cache()  # type: ignore
            except Exception:
                pass
        except Exception:
            pass

        return True, 'ok'

    def is_loaded(self, model_id: str) -> bool:
        return model_id in self._loaded

    def generate_text(self, model_id: str, prompt: str, *, max_tokens: int, temperature: float, top_p: float) -> tuple[bool, str, dict[str, Any]]:
        if not self._mlx_ok or self._mlx_generate is None:
            return False, '', {'error': f'mlx_lm_unavailable:{getattr(self, "_import_error", "")}' }
        if model_id not in self._loaded:
            return False, '', {'error': 'model_not_loaded'}
        model, tokenizer = self._loaded[model_id]

        # Prefer chat-template prompts when available to improve instruction following.
        # Also explicitly disallow chain-of-thought / hidden reasoning in output.
        sys_prompt = (
            "You are a helpful offline assistant.\n"
            "Rules (strict):\n"
            "- Output ONLY the final answer.\n"
            "- Do NOT include analysis, reasoning, or hidden thoughts.\n"
        )
        try:
            if hasattr(tokenizer, 'apply_chat_template'):
                msgs = [
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": str(prompt or '')},
                ]
                # Ensure string output (not token ids) for generate().
                prompt = tokenizer.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)  # type: ignore
        except Exception:
            # Fall back to raw prompt.
            pass

        gen = self._mlx_generate
        mt = int(max(1, min(int(max_tokens), 8192)))
        temp = float(max(0.0, float(temperature)))
        tp = float(top_p)

        def count_tokens(text: str) -> int:
            """Best-effort token counting using the model tokenizer.

            MLX LM returns plain strings for generate(); we count tokens here so downstream
            apps (X-Terminal) can show real token usage instead of heuristics.
            """
            try:
                # HF tokenizers.
                if hasattr(tokenizer, 'encode'):
                    ids = tokenizer.encode(text)  # type: ignore
                    return int(len(ids)) if ids is not None else 0
            except Exception:
                pass
            try:
                # Some tokenizers implement __call__ returning input_ids.
                if callable(tokenizer):
                    out = tokenizer(text)  # type: ignore
                    if isinstance(out, dict) and 'input_ids' in out:
                        ids = out.get('input_ids')
                        return int(len(ids)) if isinstance(ids, list) else 0
            except Exception:
                pass
            return 0

        prompt_tokens = count_tokens(prompt)

        # Preferred: use sampler API (mlx_lm 0.29.x), avoids passing unsupported kwargs
        # through to generate_step.
        if self._mlx_make_sampler is not None:
            try:
                sampler = self._mlx_make_sampler(temp=temp, top_p=tp)
                t0 = _now()
                out = gen(model, tokenizer, prompt, max_tokens=mt, sampler=sampler)
                if not isinstance(out, str):
                    out = str(out)
                out = _strip_thought(out)
                dt = int((_now() - t0) * 1000)
                gen_tokens = count_tokens(out)
                gen_tps = (float(gen_tokens) / max(0.001, float(dt) / 1000.0)) if dt >= 0 else 0.0
                return True, out, {
                    'elapsed_ms': dt,
                    'promptTokens': int(prompt_tokens),
                    'generationTokens': int(gen_tokens),
                    'generationTPS': float(gen_tps),
                }
            except Exception as e:
                return False, '', {'error': f'generate_failed:{type(e).__name__}:{e}'}

        # Fallback: try different kwarg spellings (older/newer mlx_lm).
        variants: list[dict[str, Any]] = []
        for max_key in ('max_tokens', 'max_new_tokens'):
            variants.append({max_key: mt})
            variants.append({max_key: mt, 'top_p': tp})
            variants.append({max_key: mt, 'temperature': temp})
            variants.append({max_key: mt, 'temperature': temp, 'top_p': tp})

        t0 = _now()
        last_type_err: Exception | None = None
        for kwargs in variants:
            try:
                out = gen(model, tokenizer, prompt, **kwargs)
                break
            except TypeError as e:
                last_type_err = e
                continue
            except Exception as e:
                return False, '', {'error': f'generate_failed:{type(e).__name__}:{e}'}
        else:
            return False, '', {'error': f'generate_failed:TypeError:{last_type_err}'}

        # Most mlx_lm versions return a string.
        if not isinstance(out, str):
            try:
                out = str(out)
            except Exception:
                out = ''
        out = _strip_thought(out)
        dt = int((_now() - t0) * 1000)
        gen_tokens = count_tokens(out)
        gen_tps = (float(gen_tokens) / max(0.001, float(dt) / 1000.0)) if dt >= 0 else 0.0
        return True, out, {
            'elapsed_ms': dt,
            'promptTokens': int(prompt_tokens),
            'generationTokens': int(gen_tokens),
            'generationTPS': float(gen_tps),
        }

    def bench(self, model_id: str, *, prompt_tokens: int = 256, generation_tokens: int = 256) -> tuple[bool, str, dict[str, Any]]:
        """Run a short benchmark to measure tokens/s and peak MLX memory.

        This is meant to be fast (a few seconds) and offline.
        """
        if not self._mlx_ok or self._mlx_stream_generate is None or self._mx is None:
            return False, 'mlx_lm_unavailable', {'error': f'mlx_lm_unavailable:{getattr(self, "_import_error", "")}' }
        if model_id not in self._loaded:
            return False, 'model_not_loaded', {'error': 'model_not_loaded'}

        model, tokenizer = self._loaded[model_id]

        pt = int(max(16, min(int(prompt_tokens), 2048)))
        gt = int(max(16, min(int(generation_tokens), 2048)))

        vocab_size = 0
        try:
            vocab_size = int(getattr(tokenizer, 'vocab_size', 0) or 0)
        except Exception:
            vocab_size = 0
        if vocab_size <= 0:
            try:
                vocab_size = int(len(tokenizer.get_vocab()))  # type: ignore
            except Exception:
                vocab_size = 0
        if vocab_size <= 0:
            return False, 'bench_failed:vocab_size_unknown', {'error': 'vocab_size_unknown'}

        # Disable EOS stopping for the bench so we always generate gt tokens.
        tok = tokenizer
        try:
            if self._tokenizer_wrapper is not None:
                tok = self._tokenizer_wrapper(tokenizer, eos_token_ids=[])  # type: ignore
        except Exception:
            tok = tokenizer

        sampler = None
        try:
            if self._mlx_make_sampler is not None:
                sampler = self._mlx_make_sampler(temp=0.0, top_p=1.0)
        except Exception:
            sampler = None

        # Warmup to trigger compilation/caches.
        try:
            try:
                self._mx.random.seed(0)
            except Exception:
                pass
            warm_prompt = self._mx.random.randint(0, vocab_size, (pt,)).tolist()
            for _ in self._mlx_stream_generate(model, tok, warm_prompt, max_tokens=16, sampler=sampler):
                pass
        except Exception:
            pass

        # Measured run.
        try:
            try:
                self._mx.reset_peak_memory()
            except Exception:
                pass
            prompt = self._mx.random.randint(0, vocab_size, (pt,)).tolist()
            last = None
            for resp in self._mlx_stream_generate(model, tok, prompt, max_tokens=gt, sampler=sampler):
                last = resp
            if last is None:
                return False, 'bench_failed:no_response', {'error': 'no_response'}

            peak_bytes = 0
            try:
                peak_bytes = int(self._mx.get_peak_memory())
            except Exception:
                try:
                    peak_bytes = int(float(getattr(last, 'peak_memory', 0.0)) * 1e9)
                except Exception:
                    peak_bytes = 0

            return True, 'ok', {
                'promptTokens': int(getattr(last, 'prompt_tokens', pt)),
                'generationTokens': int(getattr(last, 'generation_tokens', gt)),
                'promptTPS': float(getattr(last, 'prompt_tps', 0.0)),
                'generationTPS': float(getattr(last, 'generation_tps', 0.0)),
                'peakMemoryBytes': int(max(0, peak_bytes)),
            }
        except Exception as e:
            return False, f'bench_failed:{type(e).__name__}:{e}', {'error': f'{type(e).__name__}:{e}'}


def _strip_thought(text: str) -> str:
    """Best-effort removal of chain-of-thought style content.

    Many instruct models emit <think>...</think> or "Thought:" blocks. We strip those
    to keep UI output clean and avoid exposing internal reasoning.
    """
    s = str(text or '')
    # Remove <think>...</think> blocks.
    s = re.sub(r'(?is)<think>.*?</think>', '', s)
    # Remove common "Thought:" / "Reasoning:" preambles.
    s = re.sub(r'(?is)^(thought|reasoning|analysis)\s*:\s*.*?\n', '', s)
    # If a model outputs "Final:" then keep only the final part.
    m = re.search(r'(?is)\bfinal\s*:\s*(.*)$', s)
    if m:
        s = m.group(1)
    return s.strip()


def _estimate_tokens_per_sec(params_b: float, quant: str) -> float:
    # Placeholder; once generation requests are wired, replace with a real benchmark.
    params = max(0.1, float(params_b or 0.0))
    q = (quant or '').lower()
    quant_boost = 1.0
    if 'int4' in q or q == '4':
        quant_boost = 1.25
    elif 'int8' in q or q == '8':
        quant_boost = 1.1
    else:
        quant_boost = 0.85
    tps = (42.0 / (params ** 0.6)) * quant_boost
    return float(max(1.0, min(80.0, tps)))


def main() -> int:
    base = _base_dir()
    os.makedirs(base, exist_ok=True)
    os.makedirs(_cmd_dir(base), exist_ok=True)
    os.makedirs(_cmd_result_dir(base), exist_ok=True)
    os.makedirs(_req_dir(base), exist_ok=True)
    os.makedirs(_resp_dir(base), exist_ok=True)
    os.makedirs(_cancel_dir(base), exist_ok=True)
    os.makedirs(_memory_dir(base), exist_ok=True)
    _ensure_ax_constitution(base)

    # Single-instance lock: prevents multiple runtimes racing on the same req/resp files.
    # Keep the fd open for the lifetime of the process.
    try:
        lock_path = os.path.join(base, 'ai_runtime.lock')
        lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o644)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except Exception:
            _audit(base, 'mlx_runtime_lock_busy')
            return 0
    except Exception as e:
        _audit(base, 'mlx_runtime_lock_failed', error=f'{type(e).__name__}:{e}')
        # Continue without lock; better to run than be dead.

    rt = MLXRuntime()
    try:
        print(f"[mlx_runtime] start pid={os.getpid()} version={RUNTIME_VERSION} mlx_ok={int(rt._mlx_ok)}", flush=True)
    except Exception:
        pass
    # Surface import failures early; otherwise users only see "MLX unavailable" with no clue why.
    if not getattr(rt, '_mlx_ok', False):
        try:
            ie = str(getattr(rt, '_import_error', '') or '').strip()
            if ie:
                print(f"[mlx_runtime] import_error={ie}", flush=True)
        except Exception:
            pass
    _audit(base, 'mlx_runtime_start', mlx_ok=int(rt._mlx_ok), runtime_version=str(RUNTIME_VERSION), import_error=str(getattr(rt, '_import_error', '') or ''))
    am, pm = rt.memory_bytes()
    _write_runtime_status(
        base,
        mlx_ok=rt._mlx_ok,
        import_error=str(getattr(rt, '_import_error', '') or ''),
        active_memory_bytes=am,
        peak_memory_bytes=pm,
        loaded_model_count=len(getattr(rt, '_loaded', {}) or {}),
    )

    state = _ensure_state_from_catalog(base)
    try:
        state, _ = _merge_remote_models_into_state(base, state)
    except Exception:
        pass
    _save_state(base, state)

    last_cat = 0.0
    last_remote = 0.0

    def _resp_path(req_id: str) -> str:
        return os.path.join(_resp_dir(base), f'resp_{req_id}.jsonl')

    def _append_jsonl(path: str, obj: dict[str, Any]) -> None:
        line = json.dumps(obj, ensure_ascii=False) + '\n'
        with open(path, 'a', encoding='utf-8') as f:
            f.write(line)
            f.flush()

    def _is_canceled(req_id: str) -> bool:
        return os.path.exists(os.path.join(_cancel_dir(base), f'cancel_{req_id}.json'))

    while True:
        # Allow the Hub UI to stop the runtime without relying on OS signals
        # (which may be restricted under App Sandbox, especially across app relaunches).
        try:
            sp = _stop_marker_path(base)
            if os.path.exists(sp):
                obj = {}
                try:
                    obj = _read_json(sp)
                except Exception:
                    obj = {}
                req_id = str(obj.get('req_id') or obj.get('reqId') or '').strip()
                requested_at = float(obj.get('requested_at') or obj.get('requestedAt') or 0.0)
                # If the marker doesn't include a timestamp, fall back to file mtime.
                if requested_at > 0:
                    age = max(0.0, time.time() - requested_at)
                else:
                    try:
                        age = max(0.0, time.time() - float(os.stat(sp).st_mtime))
                    except Exception:
                        age = 0.0

                # Only honor "recent" stop requests; otherwise treat as stale garbage.
                if age <= 60.0:
                    _audit(base, 'mlx_runtime_stop', req_id=req_id, age_sec=f"{age:.3f}")
                    try:
                        os.remove(sp)
                    except Exception:
                        pass
                    break
                _audit(base, 'mlx_runtime_stop_stale', age_sec=f"{age:.3f}")
                try:
                    os.remove(sp)
                except Exception:
                    pass
        except Exception:
            pass

        # Runtime heartbeat for clients (FA Tracker, etc).
        am, pm = rt.memory_bytes()
        _write_runtime_status(
            base,
            mlx_ok=rt._mlx_ok,
            import_error=str(getattr(rt, '_import_error', '') or ''),
            active_memory_bytes=am,
            peak_memory_bytes=pm,
            loaded_model_count=len(getattr(rt, '_loaded', {}) or {}),
        )

        # Refresh state if catalog changed (cheap check by re-ensuring state only if empty).
        try:
            cat = _catalog_updated_at(base)
        except Exception:
            cat = 0.0
        if cat and cat != last_cat:
            try:
                state, changed = _merge_catalog_into_state(base, state)
                if changed:
                    _save_state(base, state)
            except Exception:
                pass
            last_cat = cat

        try:
            rem = _remote_updated_at(base)
        except Exception:
            rem = 0.0
        if rem and rem != last_remote:
            try:
                state, changed_remote = _merge_remote_models_into_state(base, state)
                if changed_remote:
                    _save_state(base, state)
            except Exception:
                pass
            last_remote = rem

        if not isinstance(state.get('models'), list) or not state.get('models'):
            state = _ensure_state_from_catalog(base)
            try:
                state, changed_remote = _merge_remote_models_into_state(base, state)
                if changed_remote:
                    _save_state(base, state)
            except Exception:
                pass

        # 1) Handle lifecycle commands first.
        cmds = _scan_commands(base)
        for cmd in cmds:
            ok, msg = False, 'unknown'
            try:
                m = _find_model(state, cmd.model_id)
                if m is None:
                    ok, msg = False, 'unknown_model_id'
                else:
                    action = cmd.action
                    if action == 'load':
                        mp = str(m.get('modelPath') or '')
                        ok, msg, delta = rt.load(cmd.model_id, mp)
                        if ok:
                            m['state'] = 'loaded'
                            # Best-effort per-model memory estimate.
                            if delta > 0:
                                m['memoryBytes'] = int(delta)
                            if m.get('tokensPerSec') in (None, 0):
                                m['tokensPerSec'] = _estimate_tokens_per_sec(float(m.get('paramsB') or 0.0), str(m.get('quant') or ''))
                    elif action == 'sleep':
                        # MVP: sleep behaves like unload but keeps the model in a "sleeping" state.
                        ok, msg = rt.unload(cmd.model_id)
                        if ok:
                            m['state'] = 'sleeping'
                            m['memoryBytes'] = None
                            m['tokensPerSec'] = None
                    elif action == 'unload':
                        ok, msg = rt.unload(cmd.model_id)
                        if ok:
                            m['state'] = 'available'
                            m['memoryBytes'] = None
                            m['tokensPerSec'] = None
                    elif action == 'bench':
                        # Bench requires the model to be resident in the runtime.
                        # If the runtime restarted but the state still marks it as loaded, auto-load first.
                        if not rt.is_loaded(cmd.model_id):
                            mp = str(m.get('modelPath') or '')
                            ok_load, msg_load, delta = rt.load(cmd.model_id, mp)
                            if ok_load:
                                m['state'] = 'loaded'
                                if delta > 0:
                                    m['memoryBytes'] = int(delta)
                                _save_state(base, state)
                            else:
                                ok = False
                                msg = msg_load
                                continue

                        okb, msgb, meta = rt.bench(cmd.model_id, prompt_tokens=256, generation_tokens=256)
                        ok = okb
                        msg = msgb
                        if ok and isinstance(meta, dict):
                            # Store bench results for UI.
                            try:
                                _upsert_bench_result(
                                    base,
                                    model_id=cmd.model_id,
                                    prompt_tokens=int(meta.get('promptTokens') or 0),
                                    generation_tokens=int(meta.get('generationTokens') or 0),
                                    prompt_tps=float(meta.get('promptTPS') or 0.0),
                                    generation_tps=float(meta.get('generationTPS') or 0.0),
                                    peak_memory_bytes=int(meta.get('peakMemoryBytes') or 0),
                                )
                            except Exception:
                                pass
                            # Also surface best values on the model itself.
                            try:
                                tps = float(meta.get('generationTPS') or 0.0)
                                if tps > 0:
                                    m['tokensPerSec'] = tps
                                peak_b = int(meta.get('peakMemoryBytes') or 0)
                                if peak_b > 0:
                                    prev = int(m.get('memoryBytes') or 0)
                                    m['memoryBytes'] = int(max(prev, peak_b))
                            except Exception:
                                pass
                    else:
                        ok, msg = False, 'unknown_action'

                _save_state(base, state)
            except Exception as e:
                ok, msg = False, f'worker_error:{type(e).__name__}:{e}'

            # Publish result for the UI.
            _write_cmd_result(base, req_id=cmd.req_id, action=cmd.action, model_id=cmd.model_id, ok=bool(ok), msg=msg)

            _audit(
                base,
                'cmd',
                ok=int(bool(ok)),
                action=cmd.action,
                model_id=cmd.model_id,
                req_id=cmd.req_id,
                msg=msg,
            )

            try:
                os.remove(cmd.path)
            except Exception:
                pass

        # 2) Handle AI generation requests (single-turn).
        reqs = _scan_ai_requests(base)
        for r in reqs:
            # Apply routing_settings.json when the request doesn't specify a preferred model.
            routing_source = ''
            if not str(r.preferred_model_id or '').strip():
                pmid = _routing_preferred_model_id(base, r.task_type)
                if pmid:
                    r.preferred_model_id = pmid
                    routing_source = 'routing_settings'

            # Route model_id based on task type when not explicitly specified.
            route_reason = 'explicit_model'
            try:
                mid, reason = _route_model_id(
                    state,
                    task_type=r.task_type,
                    model_id=r.model_id,
                    preferred_model_id=r.preferred_model_id,
                    auto_load=bool(r.auto_load),
                )
                if mid:
                    r.model_id = mid
                route_reason = reason
                if routing_source and route_reason == 'preferred_model':
                    route_reason = routing_source
            except Exception:
                pass

            # Inject pinned constitution snippet (token-efficient; configurable).
            try:
                r.prompt = _inject_ax_constitution(base, r.prompt)
            except Exception:
                pass

            rp = _resp_path(r.req_id)
            # Start event.
            try:
                _append_jsonl(
                    rp,
                    {
                        'type': 'start',
                        'req_id': r.req_id,
                        'app_id': r.app_id,
                        'model_id': r.model_id,
                        'route_reason': route_reason,
                        'task_type': str(r.task_type or ''),
                        'ok': True,
                        'started_at': _now(),
                    },
                )
                _audit_ai(base, phase='start', req=r)
            except Exception as e:
                _audit(base, 'ai_resp_write_failed', req_id=r.req_id, error=f'{type(e).__name__}:{e}')
                try:
                    os.remove(r.path)
                except Exception:
                    pass
                continue

            # Remove request file once accepted.
            try:
                os.remove(r.path)
            except Exception:
                pass

            if _is_canceled(r.req_id):
                _append_jsonl(rp, {'type': 'done', 'req_id': r.req_id, 'ok': False, 'reason': 'canceled'})
                _audit_ai(base, phase='done', req=r, ok=False, reason='canceled')
                try:
                    os.remove(os.path.join(_cancel_dir(base), f'cancel_{r.req_id}.json'))
                except Exception:
                    pass
                continue

            # Remote model path: delegate to Bridge (networked).
            m = _find_model(state, r.model_id)
            if m is None and str(r.model_id or '').strip():
                # Best-effort: remote models may have been added out-of-band.
                # Re-merge once before routing to avoid false model_path_missing.
                try:
                    state, changed_remote = _merge_remote_models_into_state(base, state)
                    if changed_remote:
                        _save_state(base, state)
                    m = _find_model(state, r.model_id)
                except Exception:
                    pass

            if m is None and str(r.model_id or '').strip():
                # Fallback for stale in-memory state: treat a known remote config as remote.
                rm = _remote_model_by_id(base, r.model_id)
                if isinstance(rm, dict):
                    m = {
                        'id': str(rm.get('id') or r.model_id),
                        'backend': str(rm.get('backend') or ''),
                        'modelPath': '',
                        'state': 'loaded',
                    }

            if m is not None and _is_remote_model(m):
                ok_remote, text_remote, usage_remote, err_remote = _bridge_ai_generate(
                    base,
                    req_id=r.req_id,
                    model_id=r.model_id,
                    prompt=r.prompt,
                    max_tokens=r.max_tokens,
                    temperature=r.temperature,
                    top_p=r.top_p,
                    timeout_sec=120.0,
                )
                if not ok_remote:
                    _append_jsonl(rp, {'type': 'done', 'req_id': r.req_id, 'ok': False, 'reason': err_remote or 'remote_failed'})
                    _audit_ai(base, phase='done', req=r, ok=False, reason=err_remote or 'remote_failed')
                    continue

                # Pseudo-stream the remote response.
                seq = 0
                chunk_size = 64
                for i in range(0, len(text_remote), chunk_size):
                    if _is_canceled(r.req_id):
                        _append_jsonl(rp, {'type': 'done', 'req_id': r.req_id, 'ok': False, 'reason': 'canceled'})
                        _audit_ai(base, phase='done', req=r, ok=False, reason='canceled')
                        try:
                            os.remove(os.path.join(_cancel_dir(base), f'cancel_{r.req_id}.json'))
                        except Exception:
                            pass
                        break
                    chunk = text_remote[i : i + chunk_size]
                    _append_jsonl(rp, {'type': 'delta', 'req_id': r.req_id, 'seq': seq, 'text': chunk})
                    seq += 1

                if not _is_canceled(r.req_id):
                    pt = int(usage_remote.get('prompt_tokens') or 0) if isinstance(usage_remote, dict) else 0
                    ct = int(usage_remote.get('completion_tokens') or 0) if isinstance(usage_remote, dict) else 0
                    _append_jsonl(
                        rp,
                        {
                            'type': 'done',
                            'req_id': r.req_id,
                            'ok': True,
                            'reason': 'eos',
                            'promptTokens': pt if pt > 0 else None,
                            'generationTokens': ct if ct > 0 else None,
                        },
                    )
                    _audit_ai(base, phase='done', req=r, ok=True, reason='remote_ok')
                continue

            # Ensure model is loaded.
            if not str(r.model_id or '').strip():
                _append_jsonl(rp, {'type': 'done', 'req_id': r.req_id, 'ok': False, 'reason': route_reason or 'no_model_routed'})
                _audit_ai(base, phase='done', req=r, ok=False, reason=route_reason or 'no_model_routed')
                continue
            if not rt.is_loaded(r.model_id):
                m = _find_model(state, r.model_id)
                if m is None:
                    # Prefer an explicit "not found" reason over model_path_missing
                    # when the requested id doesn't exist in the current state.
                    _append_jsonl(rp, {'type': 'done', 'req_id': r.req_id, 'ok': False, 'reason': 'model_not_found'})
                    _audit_ai(base, phase='done', req=r, ok=False, reason='model_not_found')
                    continue
                mp = str((m or {}).get('modelPath') or '')
                marked_loaded = str((m or {}).get('state') or '').strip().lower() == 'loaded'
                if r.auto_load or marked_loaded:
                    ok_load, msg_load, delta = rt.load(r.model_id, mp)
                    _audit(
                        base,
                        'ai_auto_load',
                        ok=int(ok_load),
                        model_id=r.model_id,
                        marked_loaded=int(marked_loaded),
                        msg=msg_load,
                    )
                    if ok_load:
                        if m is not None:
                            m['state'] = 'loaded'
                            if delta > 0:
                                m['memoryBytes'] = int(delta)
                            _save_state(base, state)
                    else:
                        _append_jsonl(rp, {'type': 'done', 'req_id': r.req_id, 'ok': False, 'reason': msg_load})
                        _audit_ai(base, phase='done', req=r, ok=False, reason=msg_load)
                        continue
                else:
                    _append_jsonl(rp, {'type': 'done', 'req_id': r.req_id, 'ok': False, 'reason': 'model_not_loaded'})
                    _audit_ai(base, phase='done', req=r, ok=False, reason='model_not_loaded')
                    continue

            # Generate (MVP: non-streaming generation + pseudo-stream write).
            ok_gen, text, meta = rt.generate_text(
                r.model_id,
                r.prompt,
                max_tokens=r.max_tokens,
                temperature=r.temperature,
                top_p=r.top_p,
            )
            if not ok_gen:
                _append_jsonl(rp, {'type': 'done', 'req_id': r.req_id, 'ok': False, 'reason': str(meta.get('error') or 'generate_failed')})
                _audit_ai(base, phase='done', req=r, ok=False, reason=str(meta.get('error') or 'generate_failed'))
                continue

            # Pseudo-stream: split into small chunks for a "streaming" UX.
            seq = 0
            chunk_size = 64
            for i in range(0, len(text), chunk_size):
                if _is_canceled(r.req_id):
                    _append_jsonl(rp, {'type': 'done', 'req_id': r.req_id, 'ok': False, 'reason': 'canceled'})
                    _audit_ai(base, phase='done', req=r, ok=False, reason='canceled')
                    try:
                        os.remove(os.path.join(_cancel_dir(base), f'cancel_{r.req_id}.json'))
                    except Exception:
                        pass
                    break
                seq += 1
                _append_jsonl(rp, {'type': 'delta', 'req_id': r.req_id, 'seq': seq, 'text': text[i:i+chunk_size]})
                time.sleep(0.04)
            else:
                _append_jsonl(
                    rp,
                    {
                        'type': 'done',
                        'req_id': r.req_id,
                        'ok': True,
                        'reason': 'eos',
                        'elapsed_ms': int(meta.get('elapsed_ms') or 0),
                        'promptTokens': int(meta.get('promptTokens') or 0),
                        'generationTokens': int(meta.get('generationTokens') or 0),
                        'generationTPS': float(meta.get('generationTPS') or 0.0),
                        'rss_bytes': _ps_rss_bytes(),
                    },
                )
                _audit_ai(
                    base,
                    phase='done',
                    req=r,
                    ok=True,
                    reason='eos',
                    elapsed_ms=int(meta.get('elapsed_ms') or 0),
                    rss_bytes=_ps_rss_bytes(),
                )

        time.sleep(0.1)


if __name__ == '__main__':
    raise SystemExit(main())
