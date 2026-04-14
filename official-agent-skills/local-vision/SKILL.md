---
name: local-vision
version: 1.0.0
description: Analyze images through Hub-governed local vision-understanding routing.
---

# Local Vision

Use this skill when the user needs to:

- describe an image with a governed local multimodal model
- inspect screenshots, diagrams, photos, or UI captures locally
- keep image understanding inside Hub audit, capability, and runtime policy

## Workflow

1. Confirm the image source and the exact question the user wants answered.
2. Let XT auto-bind the best runnable local vision model for this task kind unless the caller pins `model_id` or `preferred_model_id` on purpose.
3. Keep image understanding separate from OCR unless the user explicitly asks for text extraction.
4. Return only the observation text or runtime metadata the governed task actually produced.

## Output

- Which local vision model XT resolved or the caller pinned
- Image path or payload shape
- Image understanding text when available
- Any runtime or policy blocker

## Guardrails

- Do not downgrade image understanding into plain OCR unless that is the actual task.
- Do not use unmanaged local scripts or remote multimodal APIs.
- Do not fabricate objects, UI states, or text that runtime did not return.
