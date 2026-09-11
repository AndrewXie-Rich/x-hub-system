# Active Hub Codebase

This file is the handoff marker for AIs and humans updating Hub.

## Source Of Truth

- Canonical Hub system repository: `<repository-root>` (resolve with `git rev-parse --show-toplevel`)
- Active Hub app and Swift shell source: `x-hub/`
- Canonical Rust kernel source: `rust/xhubd/`
- Canonical X-Terminal source: `x-terminal/`
- Active installed app: `/Applications/X-Hub.app`
- Required app executable: `Contents/MacOS/XHub`

Here `<AX-root>` means the parent directory of `<repository-root>`.

Do not use `<AX-root>/x-hub-system-github-clean` as the source of truth. It is a clean/old preview copy and previously produced the slow old UI path.

The Swift package directory is still named `x-hub/macos/RELFlowHub/` for historical compatibility. That directory name does not mean the old app is active.

## Build And Install

From `<repository-root>`:

```bash
./x-hub/tools/build_hub_app.command
./x-hub/tools/install_hub_app.command
```

The build script embeds the latest packaged Rust kernel from
`rust/xhubd/dist/rust-hub-*`. External roots/packages are refused by default;
the full release build forbids external and prebuilt package overrides.

## XT-Facing Hub Contracts

Keep these endpoints current when changing Hub behavior that XT consumes:

- `GET /pairing/discovery`
- `GET /xt/hub-contract`
- Rust kernel `GET /network/remote-entry-candidates`

`/xt/hub-contract` is the machine-readable capability registry for XT and for AIs updating XT. It should state which authority lives in Hub, including memory, skills, grants, audit, provider/model routing, readiness, pairing, and remote-entry guidance.

## Before Editing

1. Confirm the working directory matches `git rev-parse --show-toplevel`.
2. Do not copy old UI code or package outputs from `x-hub-system-github-clean`.
3. If touching Rust kernel behavior, edit `rust/xhubd/` and rebuild/package it before rebuilding Hub.
4. Preserve unrelated dirty work. This repo often has concurrent AI/user edits.

The sibling `<AX-root>/rust/rust hub` and
`<AX-root>/rust/rust xt/swift-xterminal` trees are migration/reference copies
only, not build or release sources.
