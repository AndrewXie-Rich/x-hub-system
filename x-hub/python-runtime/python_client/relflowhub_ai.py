"""REL Flow Hub AI request client (file-based, streaming).

This is meant to be vendored by local apps (FA Tracker, etc.).

Transport:
- request: write `ai_requests/req_<req_id>.json`
- response: read `ai_responses/resp_<req_id>.jsonl`
- cancel: write `ai_cancels/cancel_<req_id>.json`

This works for sandboxed Hub builds (no AF_UNIX socket required).
"""

from __future__ import annotations

import json
import os
import time
import uuid
from dataclasses import dataclass
from typing import Any, Iterator


def _candidate_hub_status_paths() -> list[str]:
    env_base = (os.environ.get('REL_FLOW_HUB_BASE_DIR') or '').strip()
    if env_base:
        # If a base dir is forced, only trust that location.
        return [os.path.join(os.path.expanduser(env_base), 'hub_status.json')]

    home = os.path.expanduser('~')
    return [
        # Signed builds: App Group base dir.
        os.path.join(home, 'Library/Group Containers/group.rel.flowhub', 'hub_status.json'),
        # Sandboxed Hub default bundle id.
        os.path.join(home, 'Library/Containers/com.rel.flowhub/Data/RELFlowHub', 'hub_status.json'),
        # Legacy/dev location.
        os.path.join(home, 'RELFlowHub', 'hub_status.json'),
        # Shared tmp fallbacks.
        '/private/tmp/RELFlowHub/hub_status.json',
        '/tmp/RELFlowHub/hub_status.json',
    ]


def _discover_hub_status() -> dict[str, Any] | None:
    """Load the freshest hub_status.json (best-effort)."""
    best: tuple[float, dict[str, Any]] | None = None
    for sp in _candidate_hub_status_paths():
        try:
            with open(sp, 'r', encoding='utf-8') as f:
                obj = json.load(f)
            ts = float(obj.get('updatedAt') or 0.0)
            if best is None or ts > best[0]:
                best = (ts, obj)
        except Exception:
            continue
    return best[1] if best else None


def _base_dir() -> str:
    # Keep consistent with relflowhub_ipc.py.
    env = (os.environ.get('REL_FLOW_HUB_BASE_DIR') or '').strip()
    if env:
        return os.path.expanduser(env)
    st = _discover_hub_status()
    if st:
        base = str(st.get('baseDir') or '').strip()
        if base:
            return os.path.expanduser(base)
    return os.path.expanduser('~/Library/Group Containers/group.rel.flowhub')


def _req_dir() -> str:
    return os.path.join(_base_dir(), 'ai_requests')


def _resp_dir() -> str:
    return os.path.join(_base_dir(), 'ai_responses')


def _cancel_dir() -> str:
    return os.path.join(_base_dir(), 'ai_cancels')


def _req_path(req_id: str) -> str:
    return os.path.join(_req_dir(), f'req_{req_id}.json')


def _resp_path(req_id: str) -> str:
    return os.path.join(_resp_dir(), f'resp_{req_id}.jsonl')


def _cancel_path(req_id: str) -> str:
    return os.path.join(_cancel_dir(), f'cancel_{req_id}.json')


def enqueue_generate(
    *,
    model_id: str,
    prompt: str,
    app_id: str,
    req_id: str | None = None,
    max_tokens: int = 512,
    temperature: float = 0.2,
    top_p: float = 0.95,
    auto_load: bool = True,
) -> str:
    os.makedirs(_req_dir(), exist_ok=True)
    os.makedirs(_resp_dir(), exist_ok=True)
    os.makedirs(_cancel_dir(), exist_ok=True)

    rid = (req_id or str(uuid.uuid4())).strip()
    obj = {
        'type': 'generate',
        'req_id': rid,
        'app_id': str(app_id),
        'model_id': str(model_id),
        'prompt': str(prompt),
        'max_tokens': int(max_tokens),
        'temperature': float(temperature),
        'top_p': float(top_p),
        'auto_load': bool(auto_load),
        'created_at': time.time(),
    }
    p = _req_path(rid)
    tmp = p + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, p)
    return rid


def cancel(req_id: str) -> None:
    os.makedirs(_cancel_dir(), exist_ok=True)
    p = _cancel_path(req_id)
    tmp = p + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump({'req_id': req_id, 'created_at': time.time()}, f, ensure_ascii=False)
    os.replace(tmp, p)


@dataclass
class StreamEvent:
    type: str
    req_id: str
    ok: bool | None = None
    text: str | None = None
    seq: int | None = None
    reason: str | None = None
    raw: dict[str, Any] | None = None


def stream_response(req_id: str, *, timeout_s: float = 60.0, poll_s: float = 0.05) -> Iterator[StreamEvent]:
    """Yield StreamEvent from resp_<req_id>.jsonl.

    This is a simple tail implementation. Caller can build UI streaming on top.
    """
    p = _resp_path(req_id)
    t0 = time.time()
    offset = 0
    buf = ''

    while True:
        if time.time() - t0 > timeout_s:
            yield StreamEvent(type='done', req_id=req_id, ok=False, reason='timeout')
            return

        if os.path.exists(p):
            try:
                with open(p, 'r', encoding='utf-8', errors='replace') as f:
                    f.seek(offset)
                    chunk = f.read()
                    if chunk:
                        offset = f.tell()
                        buf += chunk
            except Exception:
                pass

            while '\n' in buf:
                line, buf = buf.split('\n', 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                typ = str(obj.get('type') or '')
                if typ == 'delta':
                    yield StreamEvent(type='delta', req_id=req_id, text=str(obj.get('text') or ''), seq=int(obj.get('seq') or 0), raw=obj)
                elif typ == 'done':
                    yield StreamEvent(type='done', req_id=req_id, ok=bool(obj.get('ok')), reason=str(obj.get('reason') or ''), raw=obj)
                    return
                else:
                    yield StreamEvent(type=typ or 'event', req_id=req_id, ok=obj.get('ok'), raw=obj)

        time.sleep(poll_s)
