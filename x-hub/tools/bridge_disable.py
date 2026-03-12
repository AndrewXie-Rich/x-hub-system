"""Disable/stop X-Hub Bridge.

Usage:
  python3 tools/bridge_disable.py
"""

from __future__ import annotations

import json
import os
import sys
import uuid


def _group_dir() -> str:
    return os.path.expanduser('~/Library/Group Containers/group.rel.flowhub')


def main() -> int:
    base = _group_dir()
    cmd_dir = os.path.join(base, 'bridge_commands')
    os.makedirs(cmd_dir, exist_ok=True)

    cmd = {'type': 'stop'}
    out = os.path.join(cmd_dir, f'cmd_{uuid.uuid4()}.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(cmd, f, ensure_ascii=False)

    # Best-effort delete settings.
    try:
        os.remove(os.path.join(base, 'bridge_settings.json'))
    except FileNotFoundError:
        pass
    except Exception:
        pass

    print('OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
