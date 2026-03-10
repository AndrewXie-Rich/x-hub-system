"""REL Flow Hub IPC client (Python).

This is a tiny, dependency-free helper that other local tools (FA Tracker, etc)
can vendor/copy and use to:
  - detect if the hub is running (ping)
  - push notifications into the hub inbox

Transport: AF_UNIX stream socket, JSON Lines.
Socket path (default): ~/RELFlowHub/.rel_flow_hub.sock
"""

from __future__ import annotations

import json
import os
import socket
import time
import uuid
from dataclasses import dataclass
from typing import Any


DEFAULT_SOCK_PATH = os.path.expanduser('~/RELFlowHub/.rel_flow_hub.sock')


def _group_base_dir() -> str:
    return os.path.expanduser('~/Library/Group Containers/group.rel.flowhub')


def _base_dir() -> str:
    # Allow the Hub to advertise an explicit shared base directory.
    # In distributed builds we prefer App Group; this env var makes the client tolerant
    # of future base-dir changes (e.g. /private/tmp fallback in dev).
    env = (os.environ.get('REL_FLOW_HUB_BASE_DIR') or '').strip()
    if env:
        return os.path.expanduser(env)
    return _group_base_dir()


def _file_ipc_events_dir() -> str:
    return os.path.join(_base_dir(), 'ipc_events')


def _file_ipc_status_path() -> str:
    return os.path.join(_base_dir(), 'hub_status.json')


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


def _discover_file_ipc_events_dir() -> str | None:
    st = _discover_hub_status()
    if not st:
        return None
    ipc_path = str(st.get('ipcPath') or '').strip()
    if not ipc_path:
        return None
    return os.path.expanduser(ipc_path)



def sock_path_candidates(sock_path: str | None = None) -> list[str]:
    # Highest priority: explicit override.
    env = (os.environ.get('REL_FLOW_HUB_SOCK_PATH') or '').strip()
    if env:
        return [os.path.expanduser(env)]

    if sock_path and sock_path != DEFAULT_SOCK_PATH:
        return [os.path.expanduser(sock_path)]

    # Prefer the stable contract path first.
    paths = [
        DEFAULT_SOCK_PATH,
        '/private/tmp/RELFlowHub/.rel_flow_hub.sock',
        '/tmp/RELFlowHub/.rel_flow_hub.sock',
    ]

    # Sandbox fallback for the default bundle id (ad-hoc builds often end up here).
    paths.append(os.path.expanduser('~/Library/Containers/com.rel.flowhub/Data/RELFlowHub/.rel_flow_hub.sock'))

    # Future: App Group path (if you switch IPC to group containers).
    paths.append(os.path.expanduser('~/Library/Group Containers/group.rel.flowhub/.rel_flow_hub.sock'))

    # De-dup while preserving order.
    out: list[str] = []
    for p in paths:
        if p and p not in out:
            out.append(p)
    return out


@dataclass
class HubResponse:
    ok: bool
    type: str | None = None
    req_id: str | None = None
    id: str | None = None
    error: str | None = None
    raw: str | None = None


def _json_dumps(obj: dict[str, Any]) -> str:
    return json.dumps(obj, ensure_ascii=False, separators=(',', ':'))


def _readline(sock: socket.socket, max_bytes: int = 1024 * 1024) -> str:
    # Simple newline framing.
    chunks: list[bytes] = []
    total = 0
    while True:
        b = sock.recv(4096)
        if not b:
            break
        total += len(b)
        if total > max_bytes:
            raise RuntimeError('response_too_large')
        chunks.append(b)
        if b'\n' in b:
            break
    data = b''.join(chunks)
    if b'\n' in data:
        data = data.split(b'\n', 1)[0]
    return data.decode('utf-8', errors='replace').strip()


def request(
    payload: dict[str, Any],
    sock_path: str = DEFAULT_SOCK_PATH,
    timeout_s: float = 0.35,
) -> HubResponse:
    """Send one request and read one response."""

    last: HubResponse | None = None
    for path in sock_path_candidates(sock_path):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.settimeout(timeout_s)
            s.connect(path)
            s.sendall((_json_dumps(payload) + '\n').encode('utf-8'))
            raw = _readline(s)
            if not raw:
                return HubResponse(ok=False, error='empty_response')
            try:
                obj = json.loads(raw)
            except Exception:
                return HubResponse(ok=False, error='invalid_json', raw=raw)
            return HubResponse(
                ok=bool(obj.get('ok')),
                type=str(obj.get('type') or '') or None,
                req_id=str(obj.get('req_id') or '') or None,
                id=str(obj.get('id') or '') or None,
                error=str(obj.get('error') or '') or None,
                raw=raw,
            )
        except FileNotFoundError:
            # Keep a more informative prior error if we already have one.
            if last is None or last.error in (None, '', 'socket_not_found'):
                last = HubResponse(ok=False, error='socket_not_found')
        except ConnectionRefusedError:
            last = HubResponse(ok=False, error='connection_refused')
        except (TimeoutError, socket.timeout):
            last = HubResponse(ok=False, error='timeout')
        except Exception as e:
            last = HubResponse(ok=False, error=f'error:{type(e).__name__}:{e}')
        finally:
            try:
                s.close()
            except Exception:
                pass

    return last or HubResponse(ok=False, error='socket_not_found')


def ping(sock_path: str = DEFAULT_SOCK_PATH, timeout_s: float = 0.25) -> bool:
    resp = request({'type': 'ping', 'req_id': str(uuid.uuid4())}, sock_path=sock_path, timeout_s=timeout_s)
    if resp.ok:
        return True

    # Fallback to file IPC heartbeat.
    try:
        st = _discover_hub_status()
        if not st:
            return False
        ts = float(st.get('updatedAt') or 0.0)
        # Consider hub alive if heartbeat is recent.
        return (time.time() - ts) < 3.0
    except Exception:
        return False


def push_notification(
    *,
    source: str,
    title: str,
    body: str,
    dedupe_key: str | None = None,
    action_url: str | None = None,
    created_at: float | None = None,
    unread: bool = True,
    sock_path: str = DEFAULT_SOCK_PATH,
    timeout_s: float = 0.5,
) -> HubResponse:
    """Push a notification into the hub inbox."""

    payload = {
        'type': 'push_notification',
        'req_id': str(uuid.uuid4()),
        'notification': {
            'id': '',
            'source': str(source),
            'title': str(title),
            'body': str(body),
            'created_at': float(created_at if created_at is not None else time.time()),
            'dedupe_key': dedupe_key,
            'action_url': action_url,
            'unread': bool(unread),
        },
    }
    resp = request(payload, sock_path=sock_path, timeout_s=timeout_s)
    if resp.ok:
        return resp

    # Fallback to file IPC dropbox when sockets are blocked (common with App Sandbox).
    try:
        d = _discover_file_ipc_events_dir() or _file_ipc_events_dir()
        os.makedirs(d, exist_ok=True)
        tmp = os.path.join(d, f'.{uuid.uuid4()}.tmp')
        out = os.path.join(d, f'{uuid.uuid4()}.json')
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write(_json_dumps(payload))
        os.replace(tmp, out)  # atomic on same filesystem
        return HubResponse(ok=True, type='file_enqueue_ok')
    except Exception as e:
        return HubResponse(ok=False, error=f'file_ipc_error:{type(e).__name__}:{e}')
