"""Send a streaming generate request to X-Hub and print deltas.

Usage:
  python3 x-hub/tools/ai_stream_test.py --model qwen3_1_7b_mlx "Hello"
"""

from __future__ import annotations

import argparse

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PY_CLIENT = os.path.abspath(os.path.join(HERE, '..', 'python_client'))
if PY_CLIENT not in sys.path:
    sys.path.insert(0, PY_CLIENT)

from relflowhub_ai import enqueue_generate, stream_response  # type: ignore


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', required=True)
    ap.add_argument('--app', default='tools')
    ap.add_argument('--max_tokens', type=int, default=256)
    ap.add_argument('--temp', type=float, default=0.2)
    ap.add_argument('prompt')
    ns = ap.parse_args()

    rid = enqueue_generate(
        model_id=ns.model,
        prompt=ns.prompt,
        app_id=ns.app,
        max_tokens=ns.max_tokens,
        temperature=ns.temp,
        auto_load=True,
    )
    print('req_id:', rid)
    for ev in stream_response(rid, timeout_s=120.0):
        if ev.type == 'delta' and ev.text:
            print(ev.text, end='', flush=True)
        if ev.type == 'done':
            print('\nDONE ok=', ev.ok, 'reason=', ev.reason)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
