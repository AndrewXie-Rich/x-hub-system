# WO-R-11 — Registry read rejected on benign substrings ("password", "sk-")

**Owner:** AI · **Effort:** ~1 hour · **Severity:** P1 (operator denial-of-service) · **Dependencies:** none

## Why this matters

`read_local_model_registry_file` calls `raw_contains_potential_secret_material` (model_bridge.rs:~1419) before parsing the JSON. The check substring-matches `password`, `sk-`, `api_key`, etc. across the whole raw file contents. If any benign-but-matching substring exists — a model named `gpt-sk-tuned`, a note containing "password reset assistant", a comment with `api_key_rotation_notes` — the function returns:

```
Err("refusing_to_read_secret_bearing_model_registry")
```

`upsert_local_model_registry_file` propagates this error, and the apply returns `registry_write_failed`. The operator is now **permanently blocked from registering new models** until they hunt down and remove the unrelated string from `models_catalog.json`.

This is a denial-of-service on legitimate operations triggered by benign content. The intent (don't accidentally write secrets to a catalog file) is good. The implementation creates worse failure modes than the problem it solves.

## Scope

**In scope:**
- `raw_contains_potential_secret_material` (model_bridge.rs:~1419)
- `read_local_model_registry_file`
- `upsert_local_model_registry_file`

**Out of scope:**
- Removing the secret-detection entirely. There's value in catching real accidental writes; just make the check usable.

## Deliverables

1. Move secret detection from **read-time** to **write-time validation of the new content being written**. When the operator submits a registration request, scan the NEW fields (display_name, artifact_path, capabilities, task_kinds, etc.) for the secret patterns. If a NEW field contains a secret-shaped string, reject the registration — not the read.
2. The existing catalog (which may already contain `gpt-sk-tuned`) is read without secret-detection. The detection runs only on incoming submissions.
3. Patterns: use the same set as WO-R-06 (JWTs, AWS keys, OpenAI / Anthropic API key formats, high-entropy base64 in suspicious positions). NOT generic substring matches like `password`.
4. If a real secret is found in the existing file (rare, but possible), the operator can manually fix it — DO NOT block all operations until then.
5. Error message MUST tell the operator WHICH field triggered the deny and what pattern fired. The current message gives the operator no path to resolve the issue.

## Acceptance criteria

1. New test: registering a model named `gpt-sk-tuned` succeeds (no longer triggers the substring match).
2. New test: registering with `display_name = "ghp_<40-char>"` (real-looking GitHub PAT pattern) is rejected with `field_contains_secret_pattern: display_name (github_pat)`.
3. New test: an existing catalog containing `"password reset assistant"` as a description does NOT block subsequent reads.
4. New test: registering with `artifact_path` containing what looks like a JWT is rejected.

## References (read first)

- `raw_contains_potential_secret_material` (model_bridge.rs:~1419)
- `read_local_model_registry_file` and `upsert_local_model_registry_file`
- The pattern set in WO-R-06 — reuse the same regex helpers if WO-R-06 has landed

## Anti-patterns

- **Do NOT keep the substring scan on read and just narrow the patterns.** The error mode is the bug: rejecting *reads* because of any matching string is the wrong shape.
- **Do NOT add an `IGNORE_SECRET_MATERIAL=1` env var escape hatch.** It will be on in everyone's shell within a week and the protection vanishes.
- **Do NOT delete the secret detection entirely.** Operators do occasionally paste secrets into config files; catching them at write-time is useful.

## Handoff notes

After this WO and WO-R-06 land, consider extracting the secret-detection patterns into a shared helper crate (or shared module in xhub-core). Two consumers + likely more in future = worth the small extraction. Not required for this WO; file a follow-up.

Independent of all other WO-Rs.
