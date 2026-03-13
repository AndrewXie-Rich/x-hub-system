---
name: summarize
version: 1.0.0
description: Summarize webpages, PDFs, and long documents through X-Hub governed fetch and model routing, without unmanaged network access.
---

# Summarize

Use this skill when the user needs:

- a concise summary of a webpage
- key points from a PDF or long document
- extraction of action items, risks, or decisions from dense text

## Workflow

1. Fetch or read the source through governed Hub or X-Terminal surfaces.
2. Identify the document type and the summary shape the user needs.
3. Produce a tight summary first, then add details only where the user asked for depth.
4. Separate confirmed facts from inference, especially when the source is partial.

## Output

- One-paragraph summary
- Key bullets or action items when useful
- Important unknowns or missing sections
- Follow-up prompt if the document is ambiguous or too broad

## Guardrails

- Do not use unmanaged direct network access.
- Do not hallucinate details missing from the source.
- Do not expose secrets, tokens, or private data found in raw evidence.
- Prefer governed deterministic summarization when no approved model route is present.
