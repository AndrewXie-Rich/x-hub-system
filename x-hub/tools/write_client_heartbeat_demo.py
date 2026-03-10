"""Write demo app heartbeats for REL Flow Hub satellites.

By default the hub considers a client "connected" only if its heartbeat is refreshed
within a short TTL. This script can either write once, or keep heartbeats alive for a
while so you can preview the 1..6 satellites layout.

Usage:
  python3 tools/write_client_heartbeat_demo.py
  python3 tools/write_client_heartbeat_demo.py --count 6 --duration 300
  python3 tools/write_client_heartbeat_demo.py --count 6 --duration 0   # write once
"""

from __future__ import annotations

import argparse
import json
import os
import time


def _clients_dir() -> str:
    # Matches RELFlowHubCore.ClientStorage.dir() default (App Group).
    return os.path.expanduser('~/Library/Group Containers/group.rel.flowhub/clients')


def _write_json_atomic(path: str, obj: dict) -> None:
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def _make_demo(i: int, now: float) -> dict:
    # Keep these stable and readable in UI.
    return {
        'appId': f'demoapp{i}',
        'appName': f'Demo App {i}',
        'activity': 'active' if (i % 3) != 0 else 'idle',
        'aiEnabled': (i % 2) == 0,
        'modelMemoryBytes': 1200000000 + i * 350000000,
        'updatedAt': now,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--count', type=int, default=1, help='Number of demo clients to write (1..6 recommended)')
    ap.add_argument('--interval', type=float, default=5.0, help='Seconds between refresh writes (when duration > 0)')
    ap.add_argument(
        '--duration',
        type=float,
        default=120.0,
        help='Seconds to keep refreshing. Use 0 to write once and exit.',
    )
    args = ap.parse_args(argv)

    count = max(1, min(24, int(args.count)))
    base = _clients_dir()
    os.makedirs(base, exist_ok=True)

    def write_once() -> None:
        now = time.time()
        for i in range(1, count + 1):
            obj = _make_demo(i, now)
            path = os.path.join(base, f"{obj['appId']}.json")
            _write_json_atomic(path, obj)

    write_once()
    print(f'OK wrote {count} clients in {base}')

    if float(args.duration) <= 0:
        return 0

    t0 = time.time()
    try:
        while True:
            if (time.time() - t0) > float(args.duration):
                break
            time.sleep(max(0.5, float(args.interval)))
            write_once()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
