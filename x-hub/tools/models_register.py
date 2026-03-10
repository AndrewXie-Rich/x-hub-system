"""Register local MLX models for X-Hub.

This writes `models_catalog.json` into the App Group directory so the
MLX runtime can publish them into `models_state.json`.

Usage:
  python3 x-hub/tools/models_register.py add \
    --id qwen3_1_7b_mlx --name "Qwen3 1.7B" --path "/path/to/model_dir" \
    --quant bf16 --ctx 8192 --paramsB 1.7

  python3 x-hub/tools/models_register.py list
"""

from __future__ import annotations

import argparse
import json
import os
import time
from typing import Any


def _candidate_hub_status_paths() -> list[str]:
    env_base = (os.environ.get('REL_FLOW_HUB_BASE_DIR') or '').strip()
    if env_base:
        return [os.path.join(os.path.expanduser(env_base), 'hub_status.json')]

    home = os.path.expanduser('~')
    return [
        os.path.join(home, 'Library/Group Containers/group.rel.flowhub', 'hub_status.json'),
        os.path.join(home, 'Library/Containers/com.rel.flowhub/Data/RELFlowHub', 'hub_status.json'),
        os.path.join(home, 'RELFlowHub', 'hub_status.json'),
        '/private/tmp/RELFlowHub/hub_status.json',
        '/tmp/RELFlowHub/hub_status.json',
    ]


def _discover_hub_status() -> dict[str, Any] | None:
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


def _base() -> str:
    env = (os.environ.get('REL_FLOW_HUB_BASE_DIR') or '').strip()
    if env:
        return os.path.expanduser(env)
    st = _discover_hub_status()
    if st:
        base = str(st.get('baseDir') or '').strip()
        if base:
            return os.path.expanduser(base)
    return os.path.expanduser('~/Library/Group Containers/group.rel.flowhub')


def _catalog_path() -> str:
    return os.path.join(_base(), 'models_catalog.json')


def _load() -> dict[str, Any]:
    p = _catalog_path()
    if not os.path.exists(p):
        return {'updatedAt': time.time(), 'models': []}
    try:
        with open(p, 'r', encoding='utf-8') as f:
            obj = json.load(f)
        if isinstance(obj, dict) and isinstance(obj.get('models'), list):
            return obj
    except Exception:
        pass
    return {'updatedAt': time.time(), 'models': []}


def _save(obj: dict[str, Any]) -> None:
    os.makedirs(_base(), exist_ok=True)
    obj['updatedAt'] = time.time()
    p = _catalog_path()
    tmp = p + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    os.replace(tmp, p)


def cmd_list(_: argparse.Namespace) -> int:
    obj = _load()
    ms = obj.get('models') or []
    for m in ms:
        if not isinstance(m, dict):
            continue
        print(f"{m.get('id')}\t{m.get('name')}\t{m.get('modelPath') or m.get('path')}")
    return 0


def cmd_add(ns: argparse.Namespace) -> int:
    obj = _load()
    ms = obj.get('models')
    if not isinstance(ms, list):
        ms = []
        obj['models'] = ms

    mid = str(ns.id).strip()
    name = str(ns.name or mid)
    path = os.path.expanduser(str(ns.path))
    if not os.path.isdir(path):
        raise SystemExit(f'Not a directory: {path}')

    # Upsert.
    found = None
    for m in ms:
        if isinstance(m, dict) and str(m.get('id') or '') == mid:
            found = m
            break
    if found is None:
        found = {}
        ms.append(found)

    found.update(
        {
            'id': mid,
            'name': name,
            'backend': 'mlx',
            'quant': str(ns.quant or 'bf16'),
            'contextLength': int(ns.ctx or 8192),
            'paramsB': float(ns.paramsB or 0.0),
            'modelPath': path,
            # Optional routing hint. Examples: --role translate, --role general
            'roles': [str(x).strip().lower() for x in (ns.role or []) if str(x).strip()],
            'note': str(ns.note or 'catalog'),
        }
    )

    _save(obj)
    print('OK', _catalog_path())
    return 0


def cmd_remove(ns: argparse.Namespace) -> int:
    obj = _load()
    ms = obj.get('models')
    if not isinstance(ms, list):
        return 0
    mid = str(ns.id).strip()
    obj['models'] = [m for m in ms if not (isinstance(m, dict) and str(m.get('id') or '') == mid)]
    _save(obj)
    print('OK')
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)

    p_list = sub.add_parser('list')
    p_list.set_defaults(fn=cmd_list)

    p_add = sub.add_parser('add')
    p_add.add_argument('--id', required=True)
    p_add.add_argument('--name', default='')
    p_add.add_argument('--path', required=True)
    p_add.add_argument('--quant', default='bf16')
    p_add.add_argument('--ctx', type=int, default=8192)
    p_add.add_argument('--paramsB', type=float, default=0.0)
    p_add.add_argument('--role', action='append', default=[], help='routing role tag (e.g. translate, general)')
    p_add.add_argument('--note', default='')
    p_add.set_defaults(fn=cmd_add)

    p_rm = sub.add_parser('remove')
    p_rm.add_argument('--id', required=True)
    p_rm.set_defaults(fn=cmd_remove)

    ns = ap.parse_args()
    return int(ns.fn(ns))


if __name__ == '__main__':
    raise SystemExit(main())
