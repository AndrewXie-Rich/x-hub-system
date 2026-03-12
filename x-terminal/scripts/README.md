# X-Terminal Scripts

`x-terminal/scripts/` contains terminal-local gates, probes, fixtures, and support utilities.

These scripts exist to validate the terminal surface, not to replace Hub-side trust logic.

## Main Areas

- `ci/`: release gates, smoke checks, and CI-facing entrypoints
- `fixtures/`: sample inputs, contract fixtures, and probe support data

## Most Important Entry Point

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

## Boundary

Keep repo-wide release reporting and cross-module packaging scripts in the top-level `scripts/` directory. Use this directory for terminal-scoped validation only.
