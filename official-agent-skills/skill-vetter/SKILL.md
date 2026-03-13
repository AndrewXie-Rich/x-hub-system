---
name: skill-vetter
description: Review a local Agent skill package by reading its manifest and instructions, listing its files, and scanning for risky code patterns before Hub promotion.
---

# Skill Vetter

Use this skill when the user needs to:

- inspect a local Agent skill package before import or promotion
- review the Hub staged import record for a skill and see the latest vetter verdict
- read `skill.json`, `SKILL.md`, or supporting files inside a skill folder
- scan skill code for high-signal risky patterns such as command execution, dynamic code execution, env harvesting, obfuscation, or suspicious network usage
- prepare an evidence-backed review before handing off to the Hub-native import vetter

## Workflow

1. Start with the smallest high-signal surface: the skill tree, `skill.json`, and `SKILL.md`.
2. Read only the files needed to understand execution surface, permissions, and dispatch mapping.
3. Run focused scans against the skill folder instead of broad repository-wide grep.
4. If the skill is already staged in X-Hub, review the Hub import record and compare the Hub-native vetter verdict with your local findings.
5. Separate confirmed evidence from heuristic warnings; pattern hits are signals, not automatic proof.
6. Require the Hub-native vetter verdict before claiming a staged skill is safe to promote.

## Output

- A short risk summary with confirmed evidence
- The latest staged import status and Hub vetter status when a staging id or a selector such as the latest project import is available
- Files or patterns that still need manual review
- Missing checks or blind spots
- A clear recommendation: continue review, block, or escalate to Hub vetter

## Guardrails

- Treat this skill as advisory only. It does not replace the Hub-native import vetter or trust gate.
- Keep the workflow read-only. Do not modify, install, or promote the target skill through this skill.
- Prefer path-scoped scans that focus on the target skill folder.
- Call out likely false positives when a pattern match is only heuristic.

## Bundled References

- `references/risk-patterns.md`: suggested review sequence and the fixed pattern families used by the manifest-driven scan variants
