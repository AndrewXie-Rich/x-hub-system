---
name: local-embeddings
version: 1.0.0
description: Generate governed local embeddings through X-Hub without collapsing the request into text generation.
---

# Local Embeddings

Use this skill when the user needs to:

- create embeddings for search, retrieval, clustering, or indexing
- embed one text, many texts, or a query-plus-document batch with a local model
- keep embedding work inside Hub-governed local model routing instead of ad hoc scripts

## Workflow

1. Confirm the embedding unit first: `text`, `texts`, `query`, or `documents`.
2. Let XT auto-bind the best runnable local embedding model for this task kind unless the caller pins `model_id` or `preferred_model_id` on purpose.
3. Keep the request shape stable so downstream retrieval logic can trust the output dimensions.
4. Return vector-count or dimension facts from runtime output; do not invent vectors that were not produced.

## Output

- Which local embedding model XT resolved or the caller pinned
- What input shape was embedded
- Vector count and dimensions when runtime returns them
- Any readiness or policy gap that blocked completion

## Guardrails

- Do not reroute embedding work through unmanaged Python, shell, or remote APIs.
- Do not silently convert embedding requests into text generation or summarization.
- Do not claim the embedding succeeded unless the governed local task completes successfully.
