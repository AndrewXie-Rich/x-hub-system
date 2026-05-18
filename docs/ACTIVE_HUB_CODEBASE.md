# Active Hub Codebase

This file is the handoff marker for AIs and humans updating Hub.

## Source Of Truth

- Active Hub app and Swift shell repo: `/Users/andrew.xie/Documents/AX/x-hub-system`
- Active Rust kernel source: `/Users/andrew.xie/Documents/AX/rust/rust hub`
- Active installed app: `/Applications/X-Hub.app`
- Required app executable: `Contents/MacOS/XHub`

Do not use `/Users/andrew.xie/Documents/AX/x-hub-system-github-clean` as the source of truth. It is a clean/old preview copy and previously produced the slow old UI path.

The Swift package directory is still named `x-hub/macos/RELFlowHub/` for historical compatibility. That directory name does not mean the old app is active.

## Build And Install

From `/Users/andrew.xie/Documents/AX/x-hub-system`:

```bash
./x-hub/tools/build_hub_app.command
./x-hub/tools/install_hub_app.command
```

The build script embeds the latest packaged Rust kernel from `/Users/andrew.xie/Documents/AX/rust/rust hub/dist/rust-hub-*` unless `XHUB_RUST_HUB_PACKAGE_DIR` overrides it.

## XT-Facing Hub Contracts

Keep these endpoints current when changing Hub behavior that XT consumes:

- `GET /pairing/discovery`
- `GET /xt/hub-contract`
- Rust kernel `GET /network/remote-entry-candidates`

`/xt/hub-contract` is the machine-readable capability registry for XT and for AIs updating XT. It should state which authority lives in Hub, including memory, skills, grants, audit, provider/model routing, readiness, pairing, and remote-entry guidance.

## Before Editing

1. Confirm the working directory is `/Users/andrew.xie/Documents/AX/x-hub-system`.
2. Do not copy old UI code or package outputs from `x-hub-system-github-clean`.
3. If touching Rust kernel behavior, edit `/Users/andrew.xie/Documents/AX/rust/rust hub` and rebuild/package it before rebuilding Hub.
4. Preserve unrelated dirty work. This repo often has concurrent AI/user edits.
