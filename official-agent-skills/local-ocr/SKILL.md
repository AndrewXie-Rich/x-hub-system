---
name: local-ocr
version: 1.0.0
description: Extract text from images through Hub-governed local OCR routing.
---

# Local OCR

Use this skill when the user needs to:

- extract text from screenshots, scans, forms, slides, or photos
- run OCR locally under Hub governance
- keep OCR separate from generic image understanding

## Workflow

1. Confirm the image source and whether the user needs raw extracted text or a short OCR summary.
2. Let XT auto-bind the best runnable local OCR model for this task kind unless the caller pins `model_id` or `preferred_model_id` on purpose.
3. Keep OCR requests scoped to text extraction rather than general image narration.
4. Return extracted text and any runtime metadata exactly as produced by the governed task.

## Output

- Which OCR model XT resolved or the caller pinned
- Image source path or payload shape
- Extracted text when available
- Any runtime or policy blocker

## Guardrails

- Do not route OCR through unmanaged local scripts or remote APIs.
- Do not claim text spans, language tags, or layout structure unless runtime returned them.
- Do not silently convert OCR work into a general vision request.
