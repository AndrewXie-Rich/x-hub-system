---
name: skill-creator
description: Create or update governed Agent skill folders inside the current project by inspecting existing skills, drafting SKILL.md and skill.json, and writing template files under project-root control.
---

# Skill Creator

Use this skill when the user needs to:

- create a new local Agent skill
- update an existing skill package
- inspect current skill manifests before editing
- scaffold `SKILL.md`, `skill.json`, or supporting reference files inside the project

## Workflow

1. Start by inspecting the current project and any existing skill folders.
2. Reuse nearby skill patterns before inventing a new manifest shape.
3. Draft the smallest useful package first: `SKILL.md`, `skill.json`, then optional `references/` or `scripts/`.
4. Keep writes inside the governed project root so the result can be reviewed, staged, and imported through Hub later.
5. Separate authoring from release. Creating the source folder does not imply the skill is signed, published, or auto-enabled.

## Output

- A short creation or update plan
- The files written or inspected
- Any missing validation, signing, or publication step
- Clear next-step guidance for import, review, or release

## Guardrails

- Do not write outside the governed project root.
- Do not claim a skill is published or trusted unless the signed Hub promotion flow completed.
- Prefer updating the smallest relevant files instead of overwriting an entire skill package blindly.
- Keep manifests honest about current execution surfaces and permission requirements.

## Bundled References

- `references/template-skill.md`: minimal source template for a new official Agent skill
- `references/template-manifest.json`: minimal manifest template showing governed dispatch structure
