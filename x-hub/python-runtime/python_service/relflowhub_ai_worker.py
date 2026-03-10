"""REL Flow Hub local AI worker (skeleton).

This worker is intentionally offline-only.

Protocol: JSONL on stdin/stdout.

Example request:
  {"type":"echo","req_id":"1","text":"hello"}

Example response:
  {"type":"echo_ok","req_id":"1","ok":true,"text":"hello"}
"""

from __future__ import annotations

import json
import os
import sys


def _write(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main() -> int:
    # Hard-disable common online codepaths.
    os.environ.setdefault('HF_HUB_OFFLINE', '1')
    os.environ.setdefault('TRANSFORMERS_OFFLINE', '1')
    os.environ.setdefault('HF_DATASETS_OFFLINE', '1')
    os.environ.setdefault('TOKENIZERS_PARALLELISM', 'false')

    _write({"type": "ready", "ok": True})

    for line in sys.stdin:
        s = (line or '').strip()
        if not s:
            continue
        try:
            req = json.loads(s)
        except Exception as e:
            _write({"type": "error", "ok": False, "error": f"invalid_json: {e}"})
            continue

        typ = str(req.get('type') or '').strip()
        req_id = str(req.get('req_id') or '').strip()

        if typ in ('ping',):
            _write({"type": "pong", "req_id": req_id, "ok": True})
            continue

        if typ in ('echo',):
            _write({"type": "echo_ok", "req_id": req_id, "ok": True, "text": str(req.get('text') or '')})
            continue

        _write({"type": "error", "req_id": req_id, "ok": False, "error": f"unknown_type: {typ}"})

    return 0


if __name__ == '__main__':
    raise SystemExit(main())

