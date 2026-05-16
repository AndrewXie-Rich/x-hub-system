# X-Hub-System

<p>
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License MIT" />
  <img src="https://img.shields.io/badge/status-public%20tech%20preview-yellow.svg" alt="Public tech preview" />
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/trust-Hub--first-blue.svg" alt="Hub first trust model" />
  <img src="https://img.shields.io/badge/security-fail--closed-critical.svg" alt="Security fail-closed" />
  <img src="https://img.shields.io/badge/runtime-Swift%20%2B%20Node%20%2B%20Rust-orange.svg" alt="Swift Node Rust" />
</p>

**X-Hub-System is a Hub-first, user-owned architecture for governable AI Agent execution.**

It is not just another terminal wrapper. The Hub is the trust anchor: model routing, memory truth, policy, grants, audit, skill trust, and execution readiness are governed from X-Hub, while X-Terminal acts as the paired deep client and other clients remain replaceable surfaces.

The repository currently contains:

- `X-Hub`: the macOS Hub app and Node-backed service layer.
- `X-Terminal`: the paired terminal and Supervisor surface.
- `Rust backend work`: an efficiency and reliability rewrite path under guarded authority gates.
- `official-agent-skills`: governed official skill packages, manifests, trust roots, and distribution artifacts.
- `website`: the VitePress public documentation site source.

Repository license note: this repository is released under the **MIT License**. Trademark rights are not granted by the software license; see `TRADEMARKS.md`.

## Status

X-Hub-System is currently a **public tech preview**.

Core paths already run, but this is not a polished production release. Onboarding, packaging, product UX, protocol details, and some capability surfaces are still changing.

Use this status table when reading the repository:

| Area | Current status |
|---|---|
| Hub and X-Terminal macOS app build | Preview-working |
| Hub-governed local and paid model routing | Preview-working |
| Paired Hub to X-Terminal execution surface | Preview-working |
| Hub-backed memory governance | Validated direction with active implementation |
| Governed official skills catalog, package pinning, and trust roots | Preview-working |
| Supervisor, project governance tiers, voice authorization, and channel ingress | Preview-working / in progress by surface |
| Rust backend rewrite | Active implementation work for latency, daemon stability, and long-running reliability |

For surface-by-surface truth, use `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`.
For XT integration work, use the Hub kernel capability contract:
`GET /xt/hub-contract` (`xhub.rust_hub.xt_contract.v1`). XT and agents updating
XT should read it before adding memory, skills, model route, provider route,
grant, audit, or remote-entry behavior.

## What It Solves

Most Agent stacks make models more capable by putting prompts, tools, memory, browser state, secrets, and side-effect execution into one runtime. That is powerful, but it also makes the runtime hard to govern.

X-Hub-System takes the opposite approach: clients can stay useful and powerful, but the authority to route, grant, deny, remember, audit, and stop execution stays in a user-owned Hub.

| Problem in common Agent stacks | X-Hub-System answer |
|---|---|
| The terminal owns prompts, tools, memory, secrets, and execution together | Hub owns trust, grants, policy, memory truth, route truth, and audit; terminals become governed surfaces |
| Plugin installation silently expands privilege | Skills are packaged, pinned, reviewed, denied, revoked, and audited through Hub governance |
| Local models and paid APIs drift into separate control paths | Local models, paid providers, fallback, downgrade, quotas, and readiness are routed through one governed plane |
| Remote channels become shadow control planes | Slack, Telegram, Feishu, voice, and mobile-style ingress converge through Hub authz, replay guard, grants, and audit before higher-trust execution |
| "Auto mode" hides supervision and risk | A-Tier, S-Tier, heartbeat, review, grants, kill switches, and runtime clamps keep autonomy governable |
| Memory drifts across clients and plugins | Hub-backed memory truth stays anchored to `Writer + Gate`, while clients consume governed projections |
| Runtime failures are masked as success | X-Hub surfaces actual route, fallback, downgrade, blocked reasons, quota pressure, and evidence refs |

## What X-Hub Can Govern

X-Hub-System is designed as a governed Agent control plane, not a single chat UI. The Hub can sit above:

- model routing across local models and paid providers
- provider accounts, OAuth/key state, quotas, usage windows, and reset timing
- memory truth, constitutional guidance, and durable-write boundaries
- official skills, manifests, trust roots, pins, preflight gates, and revocation
- X-Terminal tool execution, local permission ownership, and device-capable actions
- Supervisor autonomy tiers, review cadence, heartbeat state, and intervention surfaces
- external operator channels, voice authorization, and mobile confirmation paths
- audit, evidence, runtime truth, deny reasons, fallback truth, and recovery diagnostics

The point is not that every surface is finished. The point is that they are designed to enter through one governable authority boundary instead of becoming independent control planes.

## Download And Install

For normal users, use packaged macOS builds from GitHub Releases:

```text
https://github.com/AndrewXie-Rich/x-hub-system/releases
```

Current Rust preview package:

```text
XHub-System-Rust-<version>-macos-arm64.dmg
```

That combined package contains one user-facing Hub: `X-Hub.app`, the native Swift macOS UI shell with the Rust kernel/runtime embedded inside the app bundle. It also contains X-Terminal and the Rust `xtd` sidecar.
Normal users should not need to start or understand a separate Rust Hub daemon.

Install flow:

1. Open the combined Rust preview DMG or ZIP.
2. Drag `X-Hub.app` and `X-Terminal.app` to Applications.
3. Launch `X-Hub.app` first.
4. Launch `X-Terminal.app` and pair it with X-Hub.
5. Confirm model route, bridge, Rust runtime readiness, and pairing status before relying on automation.

Advanced users can install one side at a time:

```text
X-Hub-<version>-macos-arm64.zip
XHub-Rust-Hub-<version>-macos-arm64.zip
X-Terminal-RustXT-<version>-macos-arm64.zip
```

`XHub-Rust-Hub-*` is the daemon/runtime package for CLI or service workflows. It is not the primary user-facing Hub UI.

If no packaged release is available yet, build from source using the steps below.

Release artifacts are uploaded to GitHub Releases and are intentionally not committed to this repository. If a release is unsigned or not notarized, the GitHub Release notes should say so explicitly.

Legacy note: `XHub-System-v0.1.0-alpha.1-macos-arm64.dmg` was built from the older Swift/Node Hub app path. For the Rust refactor preview, use the `XHub-System-Rust-*` assets and the matching source tag.

## Requirements

Recommended development environment:

- macOS 13+
- Apple silicon Mac recommended for the current local-runtime direction
- Xcode Command Line Tools
- Git
- Node.js for the Hub service layer and scripts
- Swift toolchain compatible with the package targets
- Rust toolchain for `rust/xhubd` and `rust/xtd`

## Developer Quick Start

Clone with HTTPS:

```bash
git clone https://github.com/AndrewXie-Rich/x-hub-system.git
cd x-hub-system
git status --short
```

Maintainers who already have a GitHub SSH key can use SSH:

```bash
git clone git@github.com:AndrewXie-Rich/x-hub-system.git
cd x-hub-system
```

Build the Hub Rust kernel/runtime for diagnostics or maintainer work:

```bash
bash rust/xhubd/tools/build_rust_hub.command --release
```

Build the X-Terminal app and Rust `xtd` sidecar:

```bash
bash x-terminal/tools/build_xt_with_rust_sidecar.command
```

Run the Hub kernel directly for diagnostics, then launch X-Terminal:

```bash
bash rust/xhubd/tools/xhubd_daemon.command start
bash rust/xhubd/tools/xhubd_daemon.command ready
open build/X-Terminal.app
```

Developer source-run entrypoints:

```bash
bash rust/xhubd/tools/run_rust_hub.command serve
bash x-hub/tools/run_xhub_from_source.command
bash x-terminal/tools/run_xterminal_from_source.command
```

Run the aggregate source doctor:

```bash
bash scripts/run_xhub_doctor_from_source.command all --workspace-root /path/to/workspace --out-dir /tmp/xhub_doctor_bundle
```

## Build Release Assets

Maintainers can build the Rust preview release assets with one command:

```bash
XHUB_RELEASE_VERSION=v0.1.0-alpha.2-rust-preview scripts/package_rust_preview_release.command
```

The output is written under:

```text
build/release/<version>/
```

Expected assets:

```text
XHub-System-Rust-<version>-macos-arm64.dmg
XHub-System-Rust-<version>-macos-arm64.zip
X-Hub-<version>-macos-arm64.zip
XHub-Rust-Hub-<version>-macos-arm64.zip
X-Terminal-RustXT-<version>-macos-arm64.zip
SHA256SUMS.txt
```

The release script fails before packaging if the required Swift Hub UI, Rust kernel contract, Swift pairing proxy, and XT contract client files are missing from Git tracking. It also checks the staged app for `X-Hub.app/Contents/Resources/rust-hub/bin/xhubd` before archive creation. This prevents publishing a source tag or release asset that only contains the Rust daemon/runtime lane.
To run only that source gate without building the release:

```bash
XHUB_RELEASE_GATE_ONLY=1 scripts/package_rust_preview_release.command
```

Upload those files to the matching GitHub Release. Do not commit generated `.app`, `.dmg`, or `build/` outputs.

For the release process, use `RELEASE.md`.

## Architecture In 30 Seconds

X-Hub-System separates the trust root from the terminal.

Baseline path:

```text
pair / ingress
-> decide client capability profile
-> retrieve governed memory and policy context when allowed
-> resolve model and capability route
-> check grants, policy, readiness, and kill switches
-> execute through a governed surface
-> audit and report runtime truth
```

Trust and control plane:

![X-Hub trust and control plane](docs/open-source/assets/xhub_trust_control_plane.svg)

Governed capability map:

![X-Hub governed capability map](docs/open-source/assets/xhub_deployment_runtime_topology.svg)

## Implementation Note: Rust Backend Work

Parts of the Hub backend are being rewritten in Rust to improve latency, daemon stability, backpressure handling, long-running reliability, and future cutover safety. That is an implementation upgrade, not the core thesis. The product architecture remains Hub-first: authority stays governed by explicit gates, release notes, and subsystem-specific cutover rules.

Rust-specific details:

- `rust/xhubd/README.md`
- `rust/xtd/README.md`

## What Makes It Different

X-Hub-System is designed around a few hard boundaries:

- The terminal is not the trust root.
- Memory truth, route truth, grants, audit, and policy belong in the Hub.
- High-risk paths should fail closed when identity, pairing, bridge health, grants, or readiness are incomplete.
- Local models and paid model providers are governed through one operational plane.
- Skills are governed capability units, not full-trust plugins.
- Runtime status should show what actually ran, what downgraded, what fell back, and what was blocked.

The longer architecture narrative lives in:

- `docs/REPO_LAYOUT.md`
- `X_MEMORY.md`
- `docs/xhub-scenario-map-v1.md`
- `website/`

## Validated Public Scope

Public claims for this repository are intentionally narrower than the full internal roadmap.

Validated external claims for the current public package are limited to:

- XT memory UX adapter backed by Hub truth-source
- Hub-governed multi-channel gateway
- Hub-first governed automations

Everything else should be read as implementation context, preview capability, or active direction unless the release notes and capability matrix mark it as validated.

Release discipline:

- `no_scope_expansion=true`
- `no_unverified_claims=true`
- `allowlist-first=true`
- `fail_closed_by_default=true`

## Repository Layout

| Path | Purpose |
|---|---|
| `x-hub/` | Active Hub app, Node service layer, model routing, grants, pairing, audit, and trust surfaces |
| `x-terminal/` | Active X-Terminal app, session runtime, Supervisor surfaces, readiness checks, and tools |
| `rust/xhubd/` | Hub Rust kernel/runtime rewrite, daemon service, bridges, authority gates, and migration tooling |
| `rust/xtd/` | XT Rust sidecar scaffold |
| `official-agent-skills/` | Official Agent skill sources, manifests, trust roots, and distribution artifacts |
| `protocol/` | Shared contracts between Hub, terminal, and runtime surfaces |
| `specs/` | Executable spec packs and traceability material |
| `docs/` | Specs, release docs, security guidance, memory docs, work orders, and operating guidance |
| `scripts/` | Repo-level validation, release packaging, diagnostics, and evidence scripts |
| `website/` | VitePress public website source |

Detailed layout:

- `docs/REPO_LAYOUT.md`
- `docs/WORKING_INDEX.md`
- `x-hub/README.md`
- `x-terminal/README.md`
- `protocol/README.md`
- `scripts/README.md`
- `specs/README.md`

## Security Model

The security claim is structural, not magical:

- One compromised terminal should not automatically own Hub policy decisions.
- No valid grant means no high-risk execution.
- No readiness means no pretend-recovery.
- Skills should be pinned, reviewed, denied, revoked, and audited through Hub governance.
- Memory control should remain Hub anchored; durable writes remain bounded to `Writer + Gate`.
- Audit and runtime truth are first-class outputs, not afterthoughts.

## Contributing

Start here:

1. `docs/open-source/CONTRIBUTOR_START_HERE.md`
2. `CONTRIBUTING.md`
3. `docs/WORKING_INDEX.md`

Good first contribution lanes:

- documentation and release wording that reduce repo-entry friction
- tests and gates that preserve fail-closed behavior
- launch diagnostics and operator recovery improvements
- small reliability fixes in Hub services or X-Terminal UX
- Rust migration work that preserves the existing authority gates

Open an issue before changing protocol contracts, trust boundaries, authority switches, or validated public release claims.

## Documentation Map

Product and architecture:

- `docs/REPO_LAYOUT.md`
- `X_MEMORY.md`
- `docs/xhub-scenario-map-v1.md`
- `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
- `website/`

Module docs:

- `x-hub/README.md`
- `x-terminal/README.md`
- `rust/xhubd/README.md`
- `rust/xtd/README.md`
- `protocol/README.md`
- `scripts/README.md`
- `specs/README.md`

Release and governance:

- `RELEASE.md`
- `CHANGELOG.md`
- `GOVERNANCE.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
- `docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.md`
- `docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.en.md`

## FAQ

### Is X-Hub-System production-ready?

Not yet. Treat it as a public tech preview with meaningful working paths and active productization work.

### Should normal users clone the repository?

No. Normal users should download packaged builds from GitHub Releases when available. Developers and reviewers should clone the repository.

### Does Rust replace the current Hub today?

Not globally. `rust/xhubd` is the active Rust rewrite and migration surface, but authority remains guarded and subsystem-specific. Check the Rust README, gates, and release notes before treating a Rust path as production authority.

### Is this only for enterprises?

No. It is especially relevant for teams that need stronger governance, audit, and model-routing control, but individual users can also benefit from a safer local control plane.

### Is the safety model just prompt engineering?

No. Prompt guidance is only one layer. X-Hub-System is designed around Hub-side grants, readiness gates, audit, skill trust, memory boundaries, policy checks, and fail-closed behavior.

## License

MIT. See `LICENSE`.

Trademark rights are not granted by the software license. See `TRADEMARKS.md`.
