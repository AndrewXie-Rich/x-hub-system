# Contributing

Thanks for contributing to X-Hub.

If you are new here, start with:

1. `README.md`
2. `docs/open-source/CONTRIBUTOR_START_HERE.md`
3. `docs/REPO_LAYOUT.md`
4. `x-hub/README.md`
5. `x-terminal/README.md`
6. `docs/WORKING_INDEX.md`

## Start With A Small Win

This repository is currently maintained primarily by one person.

That means the fastest-moving contributions are usually:

- one bug fix with one focused test
- one diagnostics improvement with evidence
- one setup or documentation fix verified locally
- one narrow UX improvement in a single module

If you want to understand the repo before choosing a task, use
`docs/open-source/CONTRIBUTOR_START_HERE.md`.

If you want pre-scoped issue ideas, use
`docs/open-source/STARTER_ISSUES_v1.md`.

## Before You Change Code

Understand the active repo shape first:

- `x-hub/` is the active Hub control plane
- `x-terminal/` is the active terminal surface
- `archive/` is history, not runtime

Path casing rule:

- `x-terminal/` is the only canonical repository path
- `X-Terminal` is the product/app name and may appear in UI copy, app bundles, entitlements, or Application Support paths, but not as a source tree path

Keep the Hub-first trust model intact:

- trust, grants, and final policy authority belong in `x-hub/`
- terminal UX, session UX, and supervisor flows belong in `x-terminal/`

## Good First Contribution Areas

These are strong first-contribution paths:

- docs and release wording that reduce setup or navigation confusion
- tests and CI gates for fail-closed or regression-prone behavior
- launch diagnostics, blocked-capability reporting, and runtime recovery UX
- isolated reliability fixes in Hub services or X-Terminal UI

Changes that should start with an issue before code is written:

- protocol changes in `protocol/`
- trust-boundary, grant, routing, or audit redesign
- public release-scope expansion
- large renames or cross-module rewrites

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
bash x-hub/tools/run_xhub_from_source.command
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
- Do not vendor AGPL code into this repository.
- If you vendor third-party code, keep original licenses and attribution.

## License And Contribution Terms

- This repository is open source under the MIT License.
- By submitting a contribution, you represent that you have the right to submit
  it.
- Unless agreed otherwise in writing before submission, you agree that your
  contribution may be distributed as part of this project under the MIT
  License.
- If you do not agree with those terms, do not submit a contribution.
- Project stewardship is described in `GOVERNANCE.md`.
- The software license does not grant trademark rights. See `TRADEMARKS.md`.

## Design Expectations

- Prefer small, reviewable pull requests with a clear purpose.
- Preserve fail-closed behavior on high-risk paths.
- Keep protocol changes backward-compatible when possible.
- If behavior changes, update the relevant docs or specs in the same pull request.
- If a change touches trust, grants, routing, or audit behavior, explain the boundary impact clearly.

## AI-Assisted Contributions

AI-assisted contributions are welcome, but the submitter is still responsible for the change.

If you used AI tools while preparing a pull request:

- say so in the pull request description
- review the diff yourself before submission
- note what you actually tested
- include any important risk notes or assumptions that the reviewer should verify

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
