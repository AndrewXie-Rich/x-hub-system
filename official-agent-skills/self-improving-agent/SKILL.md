---
name: self-improving-agent
version: 1.0.0
description: Run governed retrospectives on failed or slow workflows, then write back concrete improvements without bypassing constitution or policy.
---

# Self Improving Agent

Use this skill when the user asks the system to:

- learn from a failed run
- improve a repeated workflow
- reduce repeated mistakes or stalls
- convert observations into a better next execution plan

## Workflow

1. Gather the latest failure evidence, blocked reasons, and recent execution history.
2. Separate signal into root cause, trigger, user-facing impact, and missing safeguards.
3. Produce a concrete improvement plan:
   - what to change
   - where to change it
   - how to verify it
4. Write improvements back as governed memory or work-order updates, not hidden prompt mutation.

## Output

- Root cause summary
- Immediate fix
- Structural prevention step
- Verification checklist for the next run

## Guardrails

- Do not rewrite constitution or permission policy silently.
- Do not claim self-improvement succeeded without verification evidence.
- Do not expand permissions as a shortcut for weak planning.
