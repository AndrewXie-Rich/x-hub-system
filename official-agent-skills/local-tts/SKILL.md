---
name: local-tts
version: 1.0.0
description: Synthesize speech through Hub-governed local text-to-speech routing.
---

# Local TTS

Use this skill when the user needs to:

- synthesize speech from text with a governed local TTS model
- produce an audio artifact locally under Hub routing and policy
- keep generic TTS work separate from the dedicated Supervisor voice surface

## Workflow

1. Confirm the text to synthesize and any speaker or voice hint that runtime supports.
2. Let XT auto-bind the best runnable local TTS model for this task kind unless the caller pins `model_id` or `preferred_model_id` on purpose.
3. Keep the request in text-to-speech form; do not substitute a different voice or playback path without saying so.
4. Report the resulting audio path or runtime blocker exactly as returned by the governed task.

## Output

- Which TTS model XT resolved or the caller pinned
- Text length or short text summary
- Audio output path when runtime returns one
- Any runtime or policy blocker

## Guardrails

- Do not bypass Hub/XT routing with unmanaged local TTS commands.
- Do not silently replace this generic TTS surface with Supervisor voice playback.
- Do not claim an audio artifact exists unless runtime returned a concrete path or success payload.
