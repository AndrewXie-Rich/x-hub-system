"""Enable RELFlowHubBridge for a limited time.

This is a deterministic alternative to clicking the UI button.

Usage:
  python3 tools/bridge_enable.py 1800   # enable for 30 minutes
"""

from __future__ import annotations

import json
import os
import sys
import time
import uuid


def _group_dir() -> str:
    return os.path.expanduser('~/Library/Group Containers/group.rel.flowhub')


def main(argv: list[str]) -> int:
    secs = 30 * 60
    if len(argv) > 1:
        try:
            secs = int(argv[1])
        except Exception:
            secs = 30 * 60
    secs = max(10, min(secs, 24 * 3600))

    base = _group_dir()
    os.makedirs(base, exist_ok=True)

    enabled_until = time.time() + float(secs)
    settings_path = os.path.join(base, 'bridge_settings.json')
    cmd_dir = os.path.join(base, 'bridge_commands')
    os.makedirs(cmd_dir, exist_ok=True)

    settings = {
        'enabled_until': enabled_until,
        'updated_at': time.time(),
    }
    tmp = settings_path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(settings, f, ensure_ascii=False)
    os.replace(tmp, settings_path)

    cmd = {
        'type': 'enable_until',
        'enabled_until': enabled_until,
    }
    out = os.path.join(cmd_dir, f'cmd_{uuid.uuid4()}.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(cmd, f, ensure_ascii=False)

    print('OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))

