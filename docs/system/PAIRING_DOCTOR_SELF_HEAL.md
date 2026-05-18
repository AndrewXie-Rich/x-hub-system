# Pairing, Doctor, and Self-Heal

Pairing establishes trust. Doctor explains what is blocked. Self-heal routes the user or system to the right repair action.

## Pairing

Pairing is Hub-authoritative.

The first pair requires:

- same LAN
- preauth and replay protection
- invite token checks
- Hub owner local approval
- trusted connection material

This prevents an arbitrary remote XT from becoming trusted just because it can reach a port.

## Connection Material

After trust is established, XT can use stored connection material and route hints.

Route quality matters:

- missing route
- LAN-only
- raw IP
- stable named host
- tunnel or internet route

The long-term product path should prefer stable named remote access over raw IP.

## Doctor

XT Doctor answers:

- can the user start work?
- can XT reach Hub?
- is pairing valid?
- is model route ready?
- are skills compatible?
- is runtime ready?
- what is the current failure code?

Hub Doctor answers:

- is Hub runtime healthy?
- are providers ready?
- is local runtime healthy?
- is capability/policy blocking?
- what recovery guidance applies?

## Self-Heal

Self-heal is currently guided repair plus partial auto-retry.

It should route to:

- pairing repair
- Hub reachability repair
- port conflict repair
- model setup
- paid access setup
- system permission setup
- local runtime repair
- skill compatibility repair

## Rust Ops Plane

Rust Hub adds backend operational diagnosis:

- launchd status
- readiness
- latency metrics
- recent slow requests
- daemon ops report
- maintenance dry-run
- ops gate
- watchdog
- timer support

This is not just UI doctor. It is an operational evidence plane.

## Future Direction

Next product-quality step:

- paired route set
- route scoring
- route cooldown
- network-change handoff
- repair ledger
- continuous doctor
- require-real network switching validation
