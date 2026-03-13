---
name: agent-backup
description: Create or inspect governed local project backup bundles inside the current project root without unmanaged export or remote upload.
---

# Agent Backup

Use this skill when the user needs to:

- create a governed local backup of the current project
- inspect existing local backup bundles
- capture a project-state checkpoint before a risky refactor or automation run

## Workflow

1. Confirm whether the user wants a local checkpoint or just to inspect existing backups.
2. Keep backup artifacts inside the governed project root.
3. Exclude transient or oversized folders that should not be re-packed into every checkpoint.
4. Treat backup creation as local state mutation, not as publish or sync.
5. If the user asks for remote, scheduled, or off-device backup, report that as a separate capability gap instead of faking it.

## Output

- The action taken: snapshot, create, or list
- The backup location or command result
- Any missing restore, scheduling, or remote-retention capability

## Guardrails

- Do not export project contents off-device through this skill.
- Do not claim a backup is remote, scheduled, or redundant if it is only a local tarball.
- Keep backup outputs under the governed project root so they remain reviewable.

## Bundled References

- `references/restore-notes.md`: current restore expectations and limitations for local backup bundles
