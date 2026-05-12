# RHM-073 Scheduler Production Authority Guard

RHM-073 provides a single pass/fail guard for the scheduler-only production
authority cutover.

It verifies:

- the running X-Hub Node process has the managed Rust scheduler authority keys
- the launchctl session env is applied for future app launches
- the persistent session LaunchAgent is installed and loaded
- the Rust daemon is healthy, ready, and within the slow-request budget
- the product UI was not changed

It reports only managed key names and booleans. It does not print provider keys,
access tokens, request bodies, or `detail_json`.

## Command

```bash
bash tools/scheduler_production_authority_guard.command
```

The guard remains scheduler-only. Memory writer authority, skills execution,
provider route authority, and model route authority remain disabled.
