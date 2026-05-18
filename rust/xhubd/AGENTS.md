# Repository Guidelines

## Active Rust Hub Root Guard
This is the active Rust kernel source for Hub: `/Users/andrew.xie/Documents/AX/rust/rust hub`.

The active Swift shell/UI repo is `/Users/andrew.xie/Documents/AX/x-hub-system`. Build the full Hub app from there with:

- `./x-hub/tools/build_hub_app.command`
- `./x-hub/tools/install_hub_app.command`

Do not use `/Users/andrew.xie/Documents/AX/x-hub-system-github-clean` as the source of truth. It is an old/clean preview copy. Do not treat `RELFlowHub` names as proof that an old UI is active; the current installed app should be `/Applications/X-Hub.app` with executable `Contents/MacOS/XHub`.

## XT Contract Surface
When changing Rust behavior that XT consumes, keep these surfaces aligned:

- `xhubd xt contract`
- Rust HTTP `GET /xt/hub-contract`
- Rust HTTP `GET /network/remote-entry-candidates`
- Swift shell proxy `GET /xt/hub-contract` in `/Users/andrew.xie/Documents/AX/x-hub-system/x-hub/grpc-server/hub_grpc_server/src/pairing_http.js`

The contract must make Hub authority explicit for memory, skills, grants, audit, provider/model routing, readiness, pairing, and stable remote-entry guidance.
