"""Send a test notification to X-Hub via its unix socket.

Usage:
  python3 tools/push_test_notification.py "Title" "Body" "rdar://123"
"""

from __future__ import annotations

import sys

import os


# Allow running this file directly without installing anything.
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, '..', 'python_client'))

import relflowhub_ipc


def main(argv: list[str]) -> int:
    title = argv[1] if len(argv) > 1 else 'Test'
    body = argv[2] if len(argv) > 2 else 'Hello from CLI'
    action_url = argv[3] if len(argv) > 3 else ''

    resp = relflowhub_ipc.push_notification(
        source='CLI',
        title=str(title),
        body=str(body),
        action_url=str(action_url) if action_url else None,
    )
    print(resp.raw or '')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
