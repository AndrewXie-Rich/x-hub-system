# CANONICAL X-TERMINAL ROOT

This `<repository-root>/x-terminal/` directory is the only canonical,
version-controlled X-Terminal source tree.

Implement, test, build, and package X-Terminal here. The standard entrypoints
are:

- `tools/build_xt_with_rust_sidecar.command`
- `tools/build_xterminal_app.command`
- `tools/run_xterminal_from_source.command`
- `scripts/ci/xt_release_gate.sh`

The sibling `<AX-root>/rust/rust xt/swift-xterminal` tree
is a migration/reference copy only. Do not use it as a build or release input.
Migrate any useful changes into this directory and validate them here.

Here `<AX-root>` means the parent directory of `<repository-root>`.

The tools under `tools/` verify that this directory is the tracked
`x-terminal/` component of the enclosing X Hub repository. They fail closed if
copied into an external migration tree.

X-Terminal is the paired deep client for the Hub-first architecture. Hub
remains the authority for pairing, grants, skills, memory, model routing,
quota, policy, kill-switch, and audit.
