# Repository Guidelines

## Active Hub Root Guard
This is the active Hub/X-Terminal repository: `/Users/andrew.xie/Documents/AX/x-hub-system`.
When updating Hub, build and install from this root only:

- `./x-hub/tools/build_hub_app.command`
- `./x-hub/tools/install_hub_app.command`

The active app bundle is `/Applications/X-Hub.app` and its executable must be `Contents/MacOS/XHub`.
The internal Swift package directory is still named `x-hub/macos/RELFlowHub/` for historical reasons; do not use that name as proof that the old product is active. Do not treat `/Users/andrew.xie/Documents/AX/x-hub-system-github-clean` or any `/Applications/X-Hub.app.*RELFlowHub*` backup as the source of truth.

The active Rust kernel source is `/Users/andrew.xie/Documents/AX/rust/rust hub`; `x-hub/tools/build_hub_app.command` embeds its latest packaged `rust-hub-*` output.
XT-facing Hub capability truth should stay exposed through `GET /pairing/discovery`, `GET /xt/hub-contract`, and Rust `GET /network/remote-entry-candidates`.

## Active X-Terminal Root Guard
The active refactored X-Terminal source is:

- `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal`

The active X-Terminal build command is:

- `/Users/andrew.xie/Documents/AX/rust/rust xt/commands/build_xt.command`

The old `/Users/andrew.xie/Documents/AX/x-hub-system/x-terminal` tree is
legacy/read-only. Do not implement XT changes there, and do not package
X-Terminal from that directory. Its build/run scripts intentionally fail closed
unless an archival/debug override is explicitly set.

## Project Structure & Module Organization
`x-hub/` is the active Hub control plane; keep trust, grants, routing, audit, and memory-backed policy here. Active XT implementation work belongs in `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal`; this repository's `x-terminal/` directory is legacy/read-only. Shared contracts live in `protocol/`, official skill assets in `official-agent-skills/`, repo-wide automation in `scripts/`, and docs in `docs/` and `website/`. Treat `archive/` as historical only. `build/` and `data/` are generated output, not source.

## Build, Test, and Development Commands
Run the Hub from source with `bash x-hub/tools/run_xhub_from_source.command`, or build it with `x-hub/tools/build_hub_app.command`. For active X-Terminal, build with `/Users/andrew.xie/Documents/AX/rust/rust xt/commands/build_xt.command`; do not build from this repository's legacy `x-terminal/`. For the Hub macOS package, use `cd x-hub/macos/RELFlowHub && swift build && swift test`. For the Node gRPC service, use `cd x-hub/grpc-server/hub_grpc_server && npm ci && npm run start`; run focused tests with `node src/local_runtime_python_resolution.test.js`. For the Python runtime, run `python3 x-hub/python-runtime/python_service/test_xhub_local_service_runtime.py`. For docs, use `cd website && npm ci && npm run docs:dev` or `npm run docs:build`.

## Coding Style & Naming Conventions
Match the surrounding style and keep diffs narrow. Swift uses 4-space indentation, `UpperCamelCase` type/file names, and Swift Testing (`@Suite`, `@Test`, `#expect`). Node uses ES modules, semicolons, single quotes, and mostly lower_snake_case service filenames such as `pairing_http.js`; adapter-facing classes use `UpperCamelCase` filenames such as `FeishuIngress.js`. Python uses 4-space indentation, type hints where practical, and `test_*.py` naming. No repo-wide formatter config is committed, so avoid reformatting unrelated files.

## Testing Guidelines
Add at least one targeted regression test for behavior changes. Keep tests in the owning surface: active XT tests under `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Tests/`, `x-hub/macos/RELFlowHub/Tests/`, `x-hub/grpc-server/hub_grpc_server/src/*.test.js`, and `x-hub/python-runtime/python_service/test_*.py`. Run focused module tests first, then the active terminal release gate with `bash "/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/scripts/ci/xt_release_gate.sh"` for changes that affect runtime behavior or release evidence.

## Commit & Pull Request Guidelines
Recent history favors short, scoped, imperative commit subjects such as `x-terminal: align supervisor memory tests with explicit seed intents`. Prefer prefixes like `x-terminal:`, `docs:`, or `feat:` when they clarify ownership. Keep PRs small and reviewable. Include the commands and tests you ran, modules affected, risk notes, and rollback notes for operational changes. For trust, grants, routing, or audit changes, explain the boundary impact clearly. Add screenshots for UI changes, and disclose AI assistance when used.

## Security & Boundary Rules
Do not commit secrets, tokens, private keys, build artifacts, or local runtime state. Do not route new build or runtime entrypoints through `archive/`. Vulnerability reports follow `SECURITY.md`, not public issues.
