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
- `Rust Hub`: the ongoing Rust rewrite and daemon/bridge migration work under guarded authority gates.
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
| Rust `xhubd` rewrite | Active guarded migration, with shadow, prep, and subsystem-specific cutover gates |
| Rust `xtd` sidecar | Scaffold / future runtime hot-path sidecar |

For surface-by-surface truth, use `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`.

## Download And Install

For normal users, use packaged macOS builds from GitHub Releases:

```text
https://github.com/AndrewXie-Rich/x-hub-system/releases
```

Recommended package:

```text
XHub-System-<version>-macos-arm64.dmg
```

That combined DMG contains both `X-Hub.app` and `X-Terminal.app`.

Install flow:

1. Drag both apps to Applications.
2. Launch `X-Hub` first.
3. Launch `X-Terminal`.
4. Pair X-Terminal with X-Hub.
5. Confirm model route, bridge, and readiness status before relying on automation.

Advanced users can install one side at a time:

```text
X-Hub-<version>-macos-arm64.dmg
X-Terminal-<version>-macos-arm64.dmg
```

If no packaged release is available yet, build from source using the steps below.

DMG files are release artifacts. They are uploaded to GitHub Releases and are intentionally not committed to this repository. If a release is unsigned or not notarized, the GitHub Release notes should say so explicitly.

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

Build the Hub app:

```bash
x-hub/tools/build_hub_app.command
```

Build the X-Terminal app:

```bash
bash x-terminal/tools/build_xterminal_app.command
```

Launch the built apps:

```bash
open build/X-Hub.app
open build/X-Terminal.app
```

Developer source-run entrypoints:

```bash
bash x-hub/tools/run_xhub_from_source.command
bash x-terminal/tools/run_xterminal_from_source.command
```

Run the aggregate source doctor:

```bash
bash scripts/run_xhub_doctor_from_source.command all --workspace-root /path/to/workspace --out-dir /tmp/xhub_doctor_bundle
```

## Build Release Assets

Maintainers can build the combined and separate macOS DMGs with one command:

```bash
XHUB_RELEASE_VERSION=v0.1.0-alpha.1 scripts/package_macos_release.command
```

The output is written under:

```text
build/release/<version>/
```

Expected assets:

```text
XHub-System-<version>-macos-arm64.dmg
X-Hub-<version>-macos-arm64.dmg
X-Terminal-<version>-macos-arm64.dmg
SHA256SUMS.txt
```

Upload those files to the matching GitHub Release. Do not commit generated `.app`, `.dmg`, or `build/` outputs.

For the release process, use `RELEASE.md`.

## Rust Migration Status

Rust is a real part of the repository, but it should be read precisely.

| Path | Role |
|---|---|
| `rust/xhubd/` | Rust rewrite of X-Hub core, daemon work, scheduler/model/skills/memory bridge surfaces, shadow compare, readiness gates, and guarded cutover tooling |
| `rust/xtd/` | Future Rust sidecar for XT runtime hot paths; currently scaffolded and intentionally not the authority for grants, durable memory, audit, kill-switches, or skill execution |

Current authority is subsystem-specific and gate-controlled. Do not assume a Rust path owns production authority unless the relevant gate, environment switch, and release notes say so.

Rust quick checks:

```bash
cd rust/xhubd
cargo test
```

```bash
cd rust/xtd
cargo test
```

Rust-specific details:

- `rust/xhubd/README.md`
- `rust/xtd/README.md`

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

Deployment and runtime topology:

![X-Hub deployment and runtime topology](docs/open-source/assets/xhub_deployment_runtime_topology.svg)

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
| `rust/xhubd/` | Rust Hub rewrite, daemon, bridges, shadow/authority gates, and migration tooling |
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
