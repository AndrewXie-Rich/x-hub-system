"""Write a demo model state snapshot for X-Hub.

This is for local UI testing before the Python model service is wired.

Usage:
  python3 tools/write_models_state_demo.py
"""

from __future__ import annotations

import json
import os
import time


def main() -> int:
    base = os.path.expanduser('~/Library/Group Containers/group.rel.flowhub')
    os.makedirs(base, exist_ok=True)
    path = os.path.join(base, 'models_state.json')

    snap = {
        'updatedAt': time.time(),
        'models': [
            {
                'id': 'qwen3_1_7b_mlx',
                'name': 'Qwen3 1.7B',
                'backend': 'mlx',
                'quant': 'bf16',
                'contextLength': 8192,
                'paramsB': 1.7,
                'state': 'loaded',
                'memoryBytes': 3200000000,
                'tokensPerSec': None,
            },
            {
                'id': 'llama_8b_mlx',
                'name': 'Llama 8B',
                'backend': 'mlx',
                'quant': 'int4',
                'contextLength': 8192,
                'paramsB': 8.0,
                'state': 'available',
                'memoryBytes': None,
                'tokensPerSec': None,
            },
            {
                'id': 'llama_14b_mlx',
                'name': 'Llama 14B',
                'backend': 'mlx',
                'quant': 'int4',
                'contextLength': 8192,
                'paramsB': 14.0,
                'state': 'available',
                'memoryBytes': None,
                'tokensPerSec': None,
            },
        ],
    }

    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(snap, f, ensure_ascii=False)
    os.replace(tmp, path)

    print('OK', path)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
