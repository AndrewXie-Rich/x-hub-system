---
name: code-review
description: Review governed repo state through git status, diffs, file reads, and scoped search without writing to the workspace.
---

# Code Review

Use this skill when the user needs to:

- inspect pending repository changes
- review a diff before merge or handoff
- read the exact files behind a suspected bug or regression
- search related call sites, flags, tests, or config around a change

## Workflow

1. Start with the smallest high-signal surface: `status`, `diff`, or `staged_diff`.
2. Narrow to the relevant files before reading full contents.
3. Use scoped search to find related code paths, tests, feature flags, or schema usage.
4. Separate confirmed findings from hypotheses and call out missing evidence.
5. Keep the review read-only. If a fix is needed, hand off a concrete patch plan instead of modifying files through this skill.

## Output

- Findings ordered by severity
- File-level evidence for each finding
- Open questions or missing coverage
- A short verification checklist

## Guardrails

- Do not write, stage, commit, or delete repository content through this skill.
- Do not claim a bug without citing the diff, file content, or search evidence that supports it.
- Prefer targeted file reads over dumping large files or unrelated generated artifacts.
- Treat secrets, credentials, and sensitive configs as confidential evidence and avoid echoing them unnecessarily.
