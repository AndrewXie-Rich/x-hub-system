# RHM-124 Production Stability Session Refresh

## Status

Live-verified on 2026-05-13.

## Purpose

After the X-Hub.app relaunch hardening, keep the already applied production
authority stable instead of moving the active root unnecessarily. The current
live root remains:

```text
/Users/andrew.xie/Documents/AX/rust/rust hub/dist/rust-hub-20260512T152203Z
```

The newer package remains verified for packaging and documentation, but it is
not forced into the live launchctl session until a separate root migration is
needed.

## Live Session

Started from the active root:

```bash
bash dist/rust-hub-20260512T152203Z/tools/production_live_stability_session.command --start --duration-ms 28800000 --interval-ms 5000 --max-status-age-ms 7000 --status-read-timeout-ms 3000 --max-slow-requests 0 --replace --live-base-dir /Users/andrew.xie/RELFlowHub --http-base-url http://127.0.0.1:50151
```

Started the rolling checkpoint sidecar:

```bash
bash dist/rust-hub-20260512T152203Z/tools/production_live_stability_session.command --start-checkpoint-loop --duration-ms 14400000 --interval-ms 2000 --max-status-age-ms 7000 --status-read-timeout-ms 3000 --max-slow-requests 0 --checkpoint-duration-ms 10000 --checkpoint-interval-ms 900000 --max-checkpoints 0 --replace --live-base-dir /Users/andrew.xie/RELFlowHub --http-base-url http://127.0.0.1:50151
```

## Verification

- provider/model production authority session status: ok
- scheduler production authority session status: ok
- production runtime guard after app relaunch: ok
- latest package `xhubd doctor`: ok
- latest package UI compatibility gate: ok
- latest package contains no Swift sources: ok
- new 8h live stability session started: ok
- new rolling checkpoint sidecar started: ok
- first rolling checkpoint: ok
- supervision status: ok
- daemon ops gate recent slow request budget: ok
- temporary `target/debug/xhubd` and `target/release/xhubd` processes: none

## Authority Boundary

Still allowed:

- provider/model route authority in Rust;
- scheduler authority in Rust;
- XT live status heartbeat under explicit cutover gates.

Still blocked:

- Rust memory writer authority;
- Rust skills execution authority;
- SwiftUI/product UI changes.
