# WO-02 — CI script for schema validation

**Owner:** AI · **Effort:** 30 min · **Task ID:** #2 · **Dependencies:** WO-01 (examples must exist)

## Why this matters

The mcp-trust-registry JSON Schemas will be referenced from an RFC submitted to the MCP community. After submission, contributors will fork and propose changes. Without automated validation, a typo in a schema or a contradictory example can land silently and only be discovered when a downstream user pastes the broken schema URL into their validator. By then it's a public credibility hit.

CI for the schemas is cheap (one bash script + one GitHub Actions workflow) and forces every PR to confirm:
1. Each schema compiles under JSON Schema Draft 2020-12 with format checking.
2. Each example payload (from WO-01) validates against its corresponding schema.

## Scope

**In scope:**
- One shell script that runs schema compile + example validation locally.
- One GitHub Actions workflow that runs the same script on every PR touching `specs/mcp-trust-registry/**`.

**Out of scope:**
- CI for any other spec (agent-2fa, hub-receipt). When those land, they get their own scripts.
- Caching, matrix builds, multi-OS testing. v0.1 = single Ubuntu runner, single Node version, no caching.
- Auto-generation of examples from schemas, or vice versa.

## Deliverables

### 1. `scripts/check_mcp_trust_schemas.sh`

A bash script that:
- Locates all `specs/mcp-trust-registry/schemas/*.schema.json`.
- Runs `ajv compile --spec=draft2020 -c ajv-formats` on each. Failure on any schema is a script failure.
- For each schema, locates a corresponding `examples/<name>.example.json` and validates it. Missing example is a warning (not error) for v0.1 — log it but continue.
- Reports pass/fail summary.
- Exits with non-zero status if any schema or example fails.
- Uses `npx -p ajv-cli -p ajv-formats` (no global installs).
- Includes `set -euo pipefail` at the top.

Stylistic constraints:
- POSIX-portable bash where possible (avoid bashisms not needed).
- No colors / emoji (CI logs render plainly).
- Exit codes: 0 = all pass, 1 = any failure.

### 2. `.github/workflows/mcp-trust-schemas.yml`

GitHub Actions workflow:
- Triggers: `pull_request` and `push` to `main`, but only when paths under `specs/mcp-trust-registry/**` change. Use `paths:` filter to avoid spurious runs.
- Runs on `ubuntu-latest`.
- Steps:
  1. `actions/checkout@v4`
  2. `actions/setup-node@v4` with `node-version: 20`
  3. Run `./scripts/check_mcp_trust_schemas.sh`
- Workflow name: `mcp-trust-registry: schemas`
- Permissions: `contents: read` only (no write access needed).

### 3. README pointer (small)

Add one line to `specs/mcp-trust-registry/README.md`'s "Status" section:

```markdown
Schemas validated in CI: see `scripts/check_mcp_trust_schemas.sh`.
```

Place this in the existing "Status" table, do not invent a new section.

## Acceptance criteria

1. Running `./scripts/check_mcp_trust_schemas.sh` from the repo root exits 0 and reports all 6 schemas valid plus all 6 examples valid (assuming WO-01 is complete).
2. Deliberately corrupting one schema (e.g., replacing `"type": "object"` with `"type": "objct"`) causes the script to exit non-zero with a clear error message.
3. Deliberately corrupting one example causes the script to exit non-zero with a clear error message identifying the example file.
4. The GitHub Actions workflow YAML passes `actionlint` (or basic `yq` parse) without warnings.
5. `paths:` filter in the workflow correctly limits runs to PRs touching `specs/mcp-trust-registry/**`.

## References (read first)

- `specs/mcp-trust-registry/schemas/*.schema.json` (the 6 schemas)
- The validation command the user already verified works:
  ```bash
  npx --yes -p ajv-cli -p ajv-formats ajv compile --spec=draft2020 -c ajv-formats -s <file>
  ```

## Anti-patterns

- Don't add Prettier / linting / coverage / publishing as side effects. Single-purpose CI is robust; bloated CI is fragile.
- Don't pin `ajv-cli` or `ajv-formats` versions in the script. Floating to latest at CI time is fine for v0.1; pin in v0.2 when stable.
- Don't add a "watch" mode or pre-commit hook variant. Out of scope.
- Don't use Docker. Native runner is simpler and faster.
- Don't make the script chatty. CI logs are read mostly when something breaks; minimize noise on the happy path.

## Handoff notes

The script is the primary artifact; the workflow is just a thin trigger. The user may want to run the script locally before pushing. Test the script locally on the actual `specs/mcp-trust-registry/schemas/` dir before declaring this WO complete.

After this WO completes, the user can proceed to U-A1 (commit + push). If WO-01 isn't done yet, the script will warn but not fail on missing examples — that's intentional, so this WO can ship in parallel with WO-01.
