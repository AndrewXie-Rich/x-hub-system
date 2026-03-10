# Contributing

Thanks for helping improve X-Hub System.

## Quick Start (macOS)

Prereqs:
- macOS 13+
- Swift 6 toolchain (Xcode 16+ or a Swift 6 toolchain)
- Node.js (any recent LTS)
- Python 3 (optional; only needed for the local MLX runtime tools)

Build the Hub app bundle:
```bash
x-hub/tools/build_hub_app.command
```

Build a DMG (optional):
```bash
x-hub/tools/build_hub_dmg.command
```

## gRPC Server (Node)

Install deps:
```bash
cd x-hub/grpc-server/hub_grpc_server
npm ci
```

Run:
```bash
npm run start
```

## Repo Rules

- Do not commit build artifacts (`build/`, `*.app`, `*.dmg`) or user data (`data/`, `.axcoder/`).
- Do not vendor AGPL code into this MIT repository (Claude-Mem is method/reference only).
- If you vendor MIT third-party code (e.g. Openclaw), put it under `third_party/` and keep original licenses + attribution.

## Style / Hygiene

- Prefer small PRs with a clear purpose.
- Keep protocol changes backwards-compatible when possible; document breaking changes in `protocol/`.
- Add/adjust specs in `docs/` when behavior changes (treat specs as executable design).

