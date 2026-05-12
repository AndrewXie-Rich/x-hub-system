# RHM-076 Route Authority Prep Runtime Guard

RHM-076 verifies that the provider/model route prep session environment is
visible to the currently running X-Hub Node process.

It reports only managed key names and booleans. It does not print provider
keys, access tokens, request bodies, or `detail_json`.

## Command

```bash
bash tools/route_authority_prep_runtime_guard.command
```

If the launchctl session env is applied but the running Node process does not
have the keys, X-Hub must be relaunched so the new process inherits the prep
environment.

The guard remains non-mutating and does not enable provider/model production
authority.
