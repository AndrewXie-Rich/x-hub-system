# RHM-129 Domain Activation Plan

Date: 2026-05-14

## Scope

Add a non-mutating activation plan for the real domain/tunnel cutover path.
This keeps the current local daemon stable while making the public endpoint
steps explicit and reviewable.

## Tooling

- `tools/cross_network_domain_activation_plan.command`

The plan prints ordered commands for:

- creating or repairing the `0600` access-key file;
- running cross-network readiness preflight;
- dry-running launchd installation;
- updating the existing local daemon label into public-endpoint mode;
- installing the watchdog timer;
- running the strict installed gate;
- exporting the XT pairing bundle;
- running the public domain smoke.

The tool rejects placeholder URLs such as `hub.example.com`, loopback public
URLs unless explicitly allowed for tests, non-HTTP(S) URLs, and non-HTTPS
public URLs for real activation.

## Operational Shape

The preferred production shape is a localhost-bound daemon behind a tunnel or
reverse proxy:

- `launchd_label`: `com.ax.xhubd.local`
- bind host: `127.0.0.1`
- public URL: real `https://...` domain/tunnel endpoint
- auth: access-key required for `/ready` and operational APIs
- `/health`: unauthenticated for process managers

This avoids opening a raw LAN/public socket while still letting XT connect from
home, office, and road networks through a stable domain.

## Example

```bash
bash tools/cross_network_domain_activation_plan.command \
  --public-base-url https://hub.your-domain.com \
  --access-key-file secrets/xhubd_domain_access_key \
  --require-memory-skills-production
```

Review the JSON `steps` first. Run each command in order only after the real
domain/tunnel points to the local Hub endpoint.

## Verification

- `node --check tools/cross_network_domain_activation_plan.js`: ok
- `bash -n tools/cross_network_domain_activation_plan.command`: ok
- `bash tools/cross_network_domain_activation_plan.command --self-test`: ok
- placeholder URL rejection: ok
