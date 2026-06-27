# WO-R-10 — Process detection: substring matching on `ps` output produces false positives

**Owner:** AI · **Effort:** ~2 hours · **Severity:** P1 (false alarms) · **Dependencies:** none

## Why this matters

Several helpers in `main.rs` classify processes by checking whether a substring appears anywhere in the `ps` command line:

- `product_process_label` (~2334)
- `is_x_hub_scoped_process` (~2342)
- `is_target_xhubd_command` (~2353)
- `is_x_hub_node_bridge_command` / `is_x_hub_python_runtime_command`

These match patterns like `" xhubd serve"`, `/target/debug/xhubd`, `node hub_grpc_server`, anywhere in the command line as a substring.

**Concrete false positives:**
- An operator runs `tail -f log | grep " xhubd serve"` → matches as a "xhubd" process.
- An editor with a file path containing `/target/debug/xhubd/` → matches.
- A documentation viewer with the string `hub_grpc_server` in its current file → matches.
- A grep over the source tree → matches.

The output drives `require_no_target_xhubd` and the `xhubd_process_count` / `target_xhubd_process_count` metrics. False positives cause:
- Spurious "target_xhubd_process_present" issues.
- Phantom xhubd masking a real "xhubd_process_not_found".
- Operators investigating ghost processes that don't exist.

## Scope

**In scope:**
- All `is_*_command` and `product_process_label` helpers in main.rs
- `parse_product_process_row` and how it provides argv

**Out of scope:**
- Changing the `ps` invocation itself.
- Cross-platform `ps` differences (this is macOS-targeted).

## Deliverables

1. Parse the command line into argv0 + arguments (`take_process_token` already exists; extend it to return a structured tuple).
2. Match on **argv0 basename + first subcommand**, not substring against the full line:
   - `argv0_basename == "xhubd"` AND first arg in {"serve", "supervise", ...} → it's a target xhubd.
   - `argv0_basename == "node"` AND any arg ends with `hub_grpc_server.js` → it's the Node bridge.
   - `argv0_basename == "python"` or `python3` AND any arg path-ends with `python_runtime/main.py` → Python runtime.
3. Fallback: if argv0 contains a `/`, take the basename. If the executable path is in a temp dir or user trash, treat as non-product.
4. Document in code comments that `ps` output is **untrusted text from other processes**: any user-controlled string can appear in argv. The matcher must therefore be position-aware.

## Acceptance criteria

1. New test: `tail -f log | grep " xhubd serve"` → `is_x_hub_scoped_process` returns false.
2. New test: `/path/to/some/file/named/xhubd-notes.txt` in editor argv → returns false.
3. New test: actual xhubd at `/Applications/X-Hub.app/Contents/MacOS/xhubd serve` → returns true.
4. New test: an editor opening a file whose name contains `hub_grpc_server` → not classified as Node bridge.
5. Existing tests for legitimate process detection still pass.

## References (read first)

- `product_process_label` (main.rs:~2334)
- `is_x_hub_scoped_process` (~2342)
- `is_target_xhubd_command` (~2353)
- `take_process_token` and `parse_product_process_row` (~2305 area)
- Existing tests `product_process_sanity_*` (toward end of main.rs)

## Anti-patterns

- **Do NOT add an allowlist of "known non-matching paths."** That fails the moment a new editor / IDE comes along with a different cache path.
- **Do NOT match on PID range or user — `ps` exposes all processes regardless.**
- **Do NOT require an exact full-path match for the executable.** Users running from build dirs, `cargo run`, etc. produce many valid prefixes.

## Handoff notes

This is more impactful than it looks because the metrics from this subsystem drive operator alerts. False positives erode trust ("the alert lies").

Can ship as its own PR. Independent of all other WO-Rs.

Future: add a small fuzz test that throws random `ps` lines (drawn from real user systems) at the matchers and asserts no spurious matches. That's a follow-up, not part of this WO.
