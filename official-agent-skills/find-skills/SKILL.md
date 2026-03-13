---
name: find-skills
version: 1.0.0
description: Discover governed Agent skills from X-Hub, explain what each skill does, and recommend the safest install path.
---

# Find Skills

Use this skill when the user asks:

- what skill can handle a task
- how to install or update a skill
- whether a capability already exists in the governed skill set

## Workflow

1. Query the governed Hub skill catalog before making a recommendation.
2. Check resolved skills so you do not claim a skill is already installed when it is not.
3. Prefer official pinned packages first, then trusted publishers, then staged local imports.
4. Explain why a skill matches the task: capability surface, likely grants, risk, and suggested scope.

## Output

- Recommended `skill_id`
- Why it matches the task
- Required capabilities or grants
- Whether the skill belongs at project or global scope
- Clear fallback if Hub has no installable package yet

## Guardrails

- Do not bypass Hub review, pin, revoke, or audit flow.
- Do not invent skills that discovery does not return.
- Do not tell the model to fetch or install packages directly from the open internet when a governed Hub path exists.
