"""Ping X-Hub.

Usage:
  python3 tools/ping_hub.py

Exit code:
  0: hub is reachable
  1: hub not reachable
"""

from __future__ import annotations

import os
import sys


_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, '..', 'python_client'))

import relflowhub_ipc


def main() -> int:
    ok = bool(relflowhub_ipc.ping())
    if ok:
        print('OK')
        return 0
    tried = relflowhub_ipc.sock_path_candidates(None)
    tried_txt = ', '.join(tried)
    print('NO; tried: ' + tried_txt)
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
