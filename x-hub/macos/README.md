# X-Hub macOS

`x-hub/macos/` contains the active macOS application layer for X-Hub.

This is where the Hub becomes a desktop control plane instead of just a service boundary.

Public product name: `X-Hub`

Developer note: the source package still lives under the historical internal directory `RELFlowHub/` for compatibility, but the preferred public source-run entrypoint is `bash x-hub/tools/run_xhub_from_source.command`.

Release scope note: this directory is an implementation surface for the active Hub desktop app. It does not expand the validated public release scope on its own; external wording still follows the repository root `README.md` and release docs.

## What Lives Here

- `RELFlowHub/`: internal Swift package root for the public X-Hub desktop app
- `app_template*`: packaging and template app surfaces
- `assets/`: app assets and packaging resources

## Runtime Responsibilities

- Hub settings and pairing surfaces
- Remote model management UI
- Bridge process wiring
- Dock agent behavior
- Local app packaging surfaces

## Active Entry Points

Build the app bundle from the repository root:

```bash
x-hub/tools/build_hub_app.command
```

Launch the built app:

```bash
open build/X-Hub.app
```

Developer source run:

```bash
bash x-hub/tools/run_xhub_from_source.command
```

## Boundary

Keep native Hub UI, app lifecycle, bridge app wiring, and desktop-specific runtime behavior here. Shared protocol or terminal UX concerns belong elsewhere.

## Read Next

- `x-hub/README.md`
- `docs/REPO_LAYOUT.md`
- `docs/WORKING_INDEX.md`
- `README.md`
