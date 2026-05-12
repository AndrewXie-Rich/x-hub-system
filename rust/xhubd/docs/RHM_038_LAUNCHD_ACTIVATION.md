# RHM-038 Launchd Activation

Status: implemented

## Goal

Make the Rust Hub shadow HTTP daemon recover as a user-level macOS LaunchAgent
instead of relying only on manual `xhubd_daemon.command start`.

The LaunchAgent runs from a copied runtime under
`~/Library/Application Support/AX/rust-hub/<profile>` instead of executing
directly from the source checkout. This avoids macOS background-service privacy
denials for paths under `~/Documents` while keeping the source tree as the
operator-controlled build and install origin.

## Boundary

- This is process management only.
- Rust Hub remains `shadow_http`.
- Node/XT production authority is unchanged.
- Rust does not become model-selection authority.
- Rust memory writer remains disabled.
- Rust skills execution authority remains disabled.
- No auth token or access-key secret is printed.

## Commands

```bash
bash tools/xhubd_daemon.command launchd-install --replace-running
bash tools/xhubd_daemon.command launchd-status
bash tools/xhubd_daemon.command launchd-uninstall
```

Dry-run evidence:

```bash
bash tools/xhubd_daemon.command launchd-install --dry-run
bash tools/xhubd_daemon.command launchd-uninstall --dry-run
```

## Behavior

`launchd-install`:

1. Resolves the daemon profile exactly like `start`.
2. Copies the `xhubd` binary plus required assets/config/migrations/reports
   into the Application Support runtime root.
3. Ad-hoc signs the copied runtime `xhubd` binary on macOS before launchd
   bootstrap so the LaunchAgent does not inherit a stale source-build
   signature.
4. Writes an absolute-path LaunchAgent plist for that runtime copy.
5. Defaults the install plist to `~/Library/LaunchAgents/<label>.plist`.
6. Boots out any already-loaded service with the same label.
7. Stops the manually started daemon only when `--replace-running` is provided.
8. Bootstraps, enables, and kickstarts the user service.
9. Waits for `/health` and `/ready`.

`launchd-status` reports:

- launchd label and service target,
- installed plist path,
- launchd loaded state,
- HTTP health/readiness,
- current pid-file state when present,
- launchctl-reported pid when launchd owns the process directly.

`launchd-uninstall`:

- boots out the label and plist,
- removes the installed plist by default,
- keeps the plist when `--keep-plist` is provided.

## Validation

Required non-mutating validation:

```bash
node --check tools/xhubd_daemon.js
bash tools/xhubd_daemon.command launchd-install --dry-run --install-plist-path /private/tmp/com.ax.xhubd.rhm038.test.plist --launchd-runtime-root /private/tmp/xhubd-rhm038-runtime --launchd-label com.ax.xhubd.rhm038.test --port 50152
bash tools/xhubd_daemon.command launchd-uninstall --dry-run --install-plist-path /private/tmp/com.ax.xhubd.rhm038.test.plist --launchd-label com.ax.xhubd.rhm038.test --port 50152
plutil -lint /private/tmp/com.ax.xhubd.rhm038.test.plist
```

Optional live validation:

```bash
bash tools/xhubd_daemon.command launchd-install --replace-running
bash tools/xhubd_daemon.command launchd-status
curl -I http://127.0.0.1:50151/
curl -fsS 'http://127.0.0.1:50151/model/diagnostics?limit=1'
```

Live evidence captured on 2026-05-07:

- `launchd-install --replace-running` bootstrapped
  `gui/501/com.ax.xhubd.local`.
- `launchd-status` reported loaded/running/ready.
- `curl -I http://127.0.0.1:50151/` returned `200 OK` with HTML content.
- `/model/diagnostics?limit=1` returned `ready=true`.
- Killing the launched `xhubd` process was followed by a launchd KeepAlive
  restart.
- Follow-up on 2026-05-07: `launchd-install --replace-running` signs the
  runtime copy with `/usr/bin/codesign --force --sign -` before bootstrap;
  dry-run reports the signing plan without mutating the runtime.
- Follow-up validation: `node --check tools/xhubd_daemon.js`, isolated
  `launchd-install --dry-run`, `plutil -lint`, live
  `launchd-install --replace-running`, `launchd-status`, `/health`,
  `/xt/classic-hub-compat`, and `codesign --verify --verbose=2` all passed.
