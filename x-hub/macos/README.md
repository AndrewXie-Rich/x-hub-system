# X-Hub macOS

`x-hub/macos/` contains the active macOS application layer for X-Hub.

This is where the Hub becomes a desktop control plane instead of just a service boundary.

## What Lives Here

- `RELFlowHub/`: primary macOS app source
- `app_template*`: packaging and template app surfaces
- `assets/`: app assets and packaging resources

## Runtime Responsibilities

- Hub settings and pairing surfaces
- Remote model management UI
- Bridge process wiring
- Dock agent behavior
- Local app packaging surfaces

## Active Entry Point

```bash
cd x-hub/macos/RELFlowHub
swift run RELFlowHub
```

## Boundary

Keep native Hub UI, app lifecycle, bridge app wiring, and desktop-specific runtime behavior here. Shared protocol or terminal UX concerns belong elsewhere.
