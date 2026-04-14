---
name: supervisor-voice
version: 1.0.0
description: Inspect and drive the Supervisor voice playback path through governed XT voice controls, including preview, short speech, and stop.
---

# Supervisor Voice

Use this skill when the user asks to:

- check which playback route Supervisor voice currently resolves to
- preview the configured Supervisor voice
- make Supervisor say a short governed line out loud
- stop active Supervisor playback without changing other voice settings

## Workflow

1. Read the current Supervisor voice playback state first when the request is ambiguous.
2. Use `action=preview` to test the active voice path without extra setup.
3. Use `action=speak` with short text only; keep the script concise and directly relevant.
4. Use `action=stop` to interrupt playback cleanly when the user asks to silence it.

## Output

- The requested action and whether playback actually started
- The resolved playback route and selected Hub Voice Pack, if any
- The last real playback outcome and fallback path when relevant
- Any next-step hint if XT had to fall back or suppress playback

## Guardrails

- Do not bypass XT or Hub voice routing with unmanaged local TTS commands.
- Do not use long or hidden scripts; keep spoken text short and reviewable.
- Do not change the user's saved voice preferences as part of a one-shot preview or speak action.
