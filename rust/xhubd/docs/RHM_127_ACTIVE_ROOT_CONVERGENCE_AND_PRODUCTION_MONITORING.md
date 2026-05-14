# RHM-127 Active Root Convergence And Production Monitoring

Date: 2026-05-13

## Scope

Converge the live active Rust Hub root to the final package-store package after
the memory writer and skills execution live cutover.

## Result

- Active package: `/Users/andrew.xie/Library/Application Support/AX/rust-hub/packages/rust-hub-20260513T072202Z`
- Source package: `/Users/andrew.xie/Documents/AX/rust/rust hub/dist/rust-hub-20260513T072202Z`
- `current` symlink and launchctl `XHUB_RUST_HUB_ROOT` both point at the active package.
- X-Hub was relaunched and Node inherited the final Rust Hub root.
- Rust memory writer authority is active.
- Rust skills execution authority is active.
- Product UI was not changed.

## Monitoring Change

`production_live_stability_gate.js` now treats pre-existing slow-request
carryover as acceptable when memory/skills production authority is explicitly
allowed or required and the new slow-request delta remains within budget. This
keeps post-cutover monitoring focused on new regressions instead of historical
slow samples collected before the active-root convergence.

## Verification

- Runtime production guard: ok.
- Memory/skills live smoke: ok.
- Daemon ops gate with `--require-memory-skills-production`: ok.
- UI compatibility gate: ok.
- Package-store rolling checkpoint sidecar: two latest checkpoints ok.
- No packaged Swift product UI files.
- No `target/debug/xhubd` or `target/release/xhubd` process.
