# xtd

`xtd` is the future Rust sidecar for XT runtime hot paths.

Current status: scaffold only. It intentionally does not own Hub authority, durable memory, grants, audit, kill-switches, or skill authority.

Planned responsibilities:

1. Subscribe to Hub runtime events.
2. Maintain local execution queues.
3. Assemble runtime snapshots off the SwiftUI main actor.
4. Handle automation checkpoint and recovery helpers.
5. Dispatch approved skill runner work after Hub authorization.

Build:

```bash
cargo build --release
```

Health:

```bash
cargo run -- health
```
