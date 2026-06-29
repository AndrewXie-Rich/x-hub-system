# Get Started

<p class="lead">
The shortest action path for downloading, trying, building, or contributing to X-Hub-System. macOS is the only currently shipping platform; Linux daemon and Web thin client are in flight. The two extracted specs can be used independently — you don't need to take X-Hub to take the specs.
</p>

<div class="preview-note">
  <strong>Public technical preview.</strong>
  Macos DMG is the only shipping path today. Linux daemon (via <code>docker-compose</code>) and Web thin client are the 90-day P0 direction. Per-surface status: <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md">capability matrix</a>.
</div>

## How to run it

**macOS, today.** Apple Silicon. Combined DMG with `X-Hub.app` + `X-Terminal.app`. See [Download The Preview](#download-the-preview) below.

**Linux daemon, in flight.** `docker-compose up` deployment, abstracting launchd-specific calls behind a trait. Not released yet; track [Status & Roadmap](/status-roadmap) for the cutover.

**Spec-only consumer (no X-Hub needed).** If you only want one of the extracted specs:
- [`mcp-trust-registry`](https://github.com/AndrewXie-Rich/mcp-trust-registry) — federated trust layer above MCP
- [`agent-2fa`](https://github.com/AndrewXie-Rich/agent-2fa) — per-action 2FA for AI agent actions
- [`hub-receipt`](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) — shared signed-receipt envelope

These are independent v0.1 drafts. X-Hub is one implementation; you can write your own.

## Download The Preview

Normal users should use GitHub Releases:

```text
https://github.com/AndrewXie-Rich/x-hub-system/releases
```

Recommended package:

```text
XHub-System-<version>-macos-arm64.dmg
```

The combined package should contain:

- `X-Hub.app`: native macOS Hub UI shell with the Rust kernel/runtime embedded
- `X-Terminal.app`: paired terminal and Supervisor workspace

(The `rust-xtd` sidecar that previously shipped here is frozen at scaffold; the Web thin client direction subsumes it.)

Install flow:

1. Open the combined DMG.
2. Drag `X-Hub.app` and `X-Terminal.app` to Applications.
3. Launch `X-Hub.app` first.
4. Launch `X-Terminal.app` and pair it with X-Hub.
5. Confirm model route, bridge, Rust runtime readiness, and pairing status before relying on automation.

If the Release notes say the apps are unsigned or not notarized, macOS may require manual approval in System Settings. That is part of preview status, not a production-quality release claim.

## Build From Source

Recommended environment:

- macOS 13+
- Apple silicon Mac
- Xcode Command Line Tools
- Git
- Node.js
- Swift toolchain
- Rust toolchain

Clone with HTTPS:

```bash
git clone https://github.com/AndrewXie-Rich/x-hub-system.git
cd x-hub-system
git status --short
```

If you already have a GitHub SSH key, SSH is also fine:

```bash
git clone git@github.com:AndrewXie-Rich/x-hub-system.git
cd x-hub-system
```

Build the Hub app:

```bash
bash x-hub/tools/build_hub_app.command
```

Build the X-Terminal app and Rust `xtd` sidecar:

```bash
bash x-terminal/tools/build_xt_with_rust_sidecar.command
```

Maintainers or diagnostic workflows can build the Rust Hub kernel/runtime separately:

```bash
bash rust/xhubd/tools/build_rust_hub.command --release
```

Source-run entry points:

```bash
bash rust/xhubd/tools/run_rust_hub.command serve
bash x-hub/tools/run_xhub_from_source.command
bash x-terminal/tools/run_xterminal_from_source.command
```

Run the source doctor:

```bash
bash scripts/run_xhub_doctor_from_source.command all --workspace-root /path/to/workspace --out-dir /tmp/xhub_doctor_bundle
```

## Repository Layout

| Path | Contents |
| --- | --- |
| `x-hub/` | macOS Hub app, Node-backed service layer, Hub tools |
| `x-terminal/` | X-Terminal, Supervisor, project workspace, XT runtime sidecar integration |
| `rust/xhubd/` | Rust Hub kernel/runtime migration and diagnostic path |
| `rust/xtd/` | X-Terminal Rust sidecar direction |
| `official-agent-skills/` | official skill packages, manifests, trust roots, distribution index |
| `docs/` | protocols, working index, governance designs, public material |
| `website/` | VitePress source for this site |

## Contributing Safely

Recommended starting points:

- `README.md`
- `RELEASE.md`
- `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
- `docs/WORKING_INDEX.md`
- `x-hub/README.md`
- `x-terminal/README.md`

Release and public-claim hygiene:

- Generated artifacts (`build/`, `.app`, `.dmg`, runtime databases) belong in GitHub Releases or local runtime directories, not in source commits.
- Public product claims should describe the shipping Hub as `X-Hub.app`: a native Swift shell with the Rust runtime embedded.
- Preview, shadow, candidate, and diagnostics-only paths stay labeled as preview or diagnostics until the capability matrix marks them as production authority.
- Changes touching trust, memory, skills, grants, audit, or runtime readiness should start from the relevant contracts and tests.

## Release Assets

Git should contain source, scripts, docs, and tests. Generated DMG, ZIP, and `.app` artifacts should be uploaded to GitHub Releases, not committed.

Maintainer package command:

```bash
XHUB_RELEASE_VERSION=v1.2.10 scripts/package_macos_release.command
```

Output directory:

```text
build/release/<version>/
```

Continue with:
[Status & Roadmap](/status-roadmap), [Coding Runtime](/coding-runtime), and [Trust Model](/security).
