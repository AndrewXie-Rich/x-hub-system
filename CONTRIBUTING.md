# Contributing

Thanks for contributing to X-Hub.

If you are new here, start with:

1. `README.md`
2. `docs/REPO_LAYOUT.md`
3. `x-hub/README.md`
4. `x-terminal/README.md`
5. `docs/WORKING_INDEX.md`

## Before You Change Code

Understand the active repo shape first:

- `x-hub/` is the active Hub control plane
- `x-terminal/` is the active terminal surface
- `archive/` is history, not runtime

Keep the Hub-first trust model intact:

- trust, grants, and final policy authority belong in `x-hub/`
- terminal UX, session UX, and supervisor flows belong in `x-terminal/`

## Local Setup

Recommended local prerequisites:

- macOS 13+
- Swift 6 toolchain
- recent Node.js LTS
- Python 3 for runtime-related work

## Common Local Commands

### Build The Hub App

```bash
x-hub/tools/build_hub_app.command
```

### Run X-Hub From Source

```bash
cd x-hub/macos/RELFlowHub
swift run RELFlowHub
```

### Run X-Terminal From Source

```bash
cd x-terminal
swift run XTerminal
```

### Build X-Terminal

```bash
cd x-terminal
swift build
```

### Run The XT Release Gate

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

### Run The Hub gRPC Server

```bash
cd x-hub/grpc-server/hub_grpc_server
npm ci
npm run start
```

## Contribution Rules

- Do not commit build artifacts, local runtime state, or private data.
- Do not commit secrets, tokens, private keys, or local credentials.
- Do not reintroduce archived paths as active entrypoints.
- Do not vendor AGPL code into this MIT repository.
- If you vendor MIT-compatible third-party code, keep original licenses and attribution.

## Design Expectations

- Prefer small, reviewable pull requests with a clear purpose.
- Preserve fail-closed behavior on high-risk paths.
- Keep protocol changes backward-compatible when possible.
- If behavior changes, update the relevant docs or specs in the same pull request.
- If a change touches trust, grants, routing, or audit behavior, explain the boundary impact clearly.

## Validation Expectations

Before opening a pull request, try to include:

- the commands you ran
- the tests you ran
- the files or modules affected
- any risk notes
- rollback notes when the change is operationally sensitive

If you could not run a test, say so directly.

## Documentation Expectations

Use these layers consistently:

- product and validated scope: `README.md`
- repo navigation: `docs/REPO_LAYOUT.md`
- working navigation: `docs/WORKING_INDEX.md`
- module boundaries: module `README.md` files
- implementation packs: `x-terminal/work-orders/` and targeted docs under `docs/`

## Security Reports

For vulnerabilities, do not use public bug issues.

Use the process in `SECURITY.md`.
