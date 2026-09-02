# Repository Guidelines

## Canonical Source Root Guard
This repository is the only canonical, version-controlled source tree for the
X Hub system. Keep all production changes and release inputs under this root:

- Hub Swift shell/control plane: `x-hub/`
- Rust Hub kernel: `rust/xhubd/`
- X-Terminal: `x-terminal/`

The sibling trees `/Users/andrew.xie/Documents/AX/rust/rust hub` and
`/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal` are
migration/reference copies only. Do not build, package, install, or land new
work from them. If they contain useful work, migrate it into this repository
and validate it here before treating it as current.

When updating Hub, build and install from this repository root only:

- `./x-hub/tools/build_hub_app.command`
- `./x-hub/tools/install_hub_app.command`

The active app bundle is `/Applications/X-Hub.app` and its executable must be `Contents/MacOS/XHub`.
The internal Swift package directory is still named `x-hub/macos/RELFlowHub/` for historical reasons; do not use that name as proof that the old product is active. Do not treat `/Users/andrew.xie/Documents/AX/x-hub-system-github-clean` or any `/Applications/X-Hub.app.*RELFlowHub*` backup as the source of truth.

The canonical Rust kernel source is `rust/xhubd/`.
`x-hub/tools/build_hub_app.command` embeds packages from
`rust/xhubd/dist/`. External Rust roots/packages are refused by default and
must never be used for a release build; the explicit external-package override
is reserved for one-off diagnostics only.
XT-facing Hub capability truth should stay exposed through `GET /pairing/discovery`, `GET /xt/hub-contract`, and Rust `GET /network/remote-entry-candidates`.

## Canonical X-Terminal Root Guard
The canonical X-Terminal source is `x-terminal/`. Build it from this repository
with:

- `./x-terminal/tools/build_xt_with_rust_sidecar.command`
- `./x-terminal/tools/build_xterminal_app.command`

The XT build/run/package entrypoints verify that they are operating on the
version-controlled `x-terminal/` component of this repository and fail closed
when copied into an external migration tree.

## Project Structure & Module Organization
`x-hub/` is the active Hub control plane; keep trust, grants, routing, audit, and memory-backed policy here. Active XT implementation work belongs in `x-terminal/`, and active Rust kernel work belongs in `rust/xhubd/`. Shared contracts live in `protocol/`, official skill assets in `official-agent-skills/`, repo-wide automation in `scripts/`, and docs in `docs/` and `website/`. Treat `archive/` and sibling migration/reference trees as historical inputs only. `build/` and `data/` are generated output, not source.

## Build, Test, and Development Commands
Run the Hub from source with `bash x-hub/tools/run_xhub_from_source.command`, or build it with `x-hub/tools/build_hub_app.command`. Build X-Terminal with `x-terminal/tools/build_xt_with_rust_sidecar.command`. Package the complete macOS release from the canonical roots with `scripts/package_macos_release.command`; use `scripts/package_macos_release.command --check-canonical-roots` for its non-building root preflight. For the Hub macOS package, use `cd x-hub/macos/RELFlowHub && swift build && swift test`. For the Node gRPC service, use `cd x-hub/grpc-server/hub_grpc_server && npm ci && npm run start`; run focused tests with `node src/local_runtime_python_resolution.test.js`. For the Python runtime, run `python3 x-hub/python-runtime/python_service/test_xhub_local_service_runtime.py`. For docs, use `cd website && npm ci && npm run docs:dev` or `npm run docs:build`.

## Coding Style & Naming Conventions
Match the surrounding style and keep diffs narrow. Swift uses 4-space indentation, `UpperCamelCase` type/file names, and Swift Testing (`@Suite`, `@Test`, `#expect`). Node uses ES modules, semicolons, single quotes, and mostly lower_snake_case service filenames such as `pairing_http.js`; adapter-facing classes use `UpperCamelCase` filenames such as `FeishuIngress.js`. Python uses 4-space indentation, type hints where practical, and `test_*.py` naming. No repo-wide formatter config is committed, so avoid reformatting unrelated files.

## Testing Guidelines
Add at least one targeted regression test for behavior changes. Keep tests in the owning surface: `x-terminal/Tests/`, `x-hub/macos/RELFlowHub/Tests/`, `x-hub/grpc-server/hub_grpc_server/src/*.test.js`, and `x-hub/python-runtime/python_service/test_*.py`. Run focused module tests first, then the terminal release gate with `bash x-terminal/scripts/ci/xt_release_gate.sh` for changes that affect runtime behavior or release evidence.

## Commit & Pull Request Guidelines
Recent history favors short, scoped, imperative commit subjects such as `x-terminal: align supervisor memory tests with explicit seed intents`. Prefer prefixes like `x-terminal:`, `docs:`, or `feat:` when they clarify ownership. Keep PRs small and reviewable. Include the commands and tests you ran, modules affected, risk notes, and rollback notes for operational changes. For trust, grants, routing, or audit changes, explain the boundary impact clearly. Add screenshots for UI changes, and disclose AI assistance when used.

## Security & Boundary Rules
Do not commit secrets, tokens, private keys, build artifacts, or local runtime state. Do not route new build or runtime entrypoints through `archive/`. Vulnerability reports follow `SECURITY.md`, not public issues.
