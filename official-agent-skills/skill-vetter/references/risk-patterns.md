# Skill Vetter Risk Patterns

Use this reference when reviewing a skill package with `skill-vetter`.

## Review Order

1. List the target skill directory.
2. If the skill is already staged in Hub, review the staged import record first to capture `status`, `vetter_status`, counts, and audit refs.
3. Read `skill.json` to confirm declared permissions, risk level, and dispatch mapping.
4. Read `SKILL.md` to confirm the instructions match the manifest and do not overclaim current execution rights.
5. Run the fixed scan variants inside the target skill path.
6. Escalate to the Hub-native vetter before promotion or trust decisions.

## Fixed Scan Families

- `scan_exec`
  - Looks for host command execution primitives such as `child_process.exec`, `subprocess.run`, `os.system`, or `ProcessBuilder`.
- `scan_dynamic`
  - Looks for dynamic evaluation primitives such as `eval`, `new Function`, or `vm.runInContext`.
- `scan_exfil`
  - Looks for environment access and common outbound request helpers that often appear in exfiltration paths.
- `scan_obfuscation`
  - Looks for base64 decoding and character-code rebuilding patterns that often hide payloads.
- `scan_network`
  - Looks for direct socket or websocket connection primitives.

## Interpretation

- A pattern hit is a review signal, not a final verdict.
- False positives are possible, especially in tests, samples, or documentation.
- Promotion, trust, quarantine, and audit decisions still belong to the Hub-native import vetter chain.
