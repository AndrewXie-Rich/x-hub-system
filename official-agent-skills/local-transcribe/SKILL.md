---
name: local-transcribe
version: 1.0.0
description: Transcribe audio through Hub-governed local speech-to-text routing.
---

# Local Transcribe

Use this skill when the user needs to:

- transcribe a local audio file with a governed local model
- pull speech into text for review, notes, or follow-on automation
- keep speech-to-text work inside Hub policy, routing, and audit

## Workflow

1. Confirm the audio source path and whether the user needs plain transcript or richer metadata.
2. Let XT auto-bind the best runnable local speech-to-text model for this task kind unless the caller pins `model_id` or `preferred_model_id` on purpose.
3. Keep the request modality honest: audio in, text out.
4. Report transcript text and runtime blockers exactly as returned by the governed task.

## Output

- Which speech-to-text model XT resolved or the caller pinned
- Audio input path
- Transcript text when available
- Any runtime or policy denial that stopped transcription

## Guardrails

- Do not convert audio work into a fake text-only request.
- Do not use unmanaged local scripts or remote transcription APIs.
- Do not claim timestamps, diarization, or transcript quality that runtime did not return.
