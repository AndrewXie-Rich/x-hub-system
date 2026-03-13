---
name: tavily-websearch
description: Run governed live web search through the current Agent search backend using a Tavily-compatible search contract, without unmanaged network access.
---

# Tavily Websearch

Use this skill when the user needs:

- fresh web search results
- current documentation, announcements, product pages, or references
- quick follow-up queries to refine or cross-check a fact

## Workflow

1. Restate the search target and the freshness or coverage needed.
2. Use governed `web_search` instead of unmanaged browser scraping or direct network calls.
3. Treat provider routing as runtime-owned. The contract is Tavily-compatible, but the active backend may differ until the operator wires a specific provider.
4. Return the top results with short relevance notes and flag weak coverage or ambiguity.
5. Refine the query when the first pass is too broad, stale, or noisy.

## Output

- Search goal
- Top results with short relevance notes
- Freshness, coverage, or ambiguity caveats
- Suggested follow-up query when useful

## Guardrails

- Do not claim the backend is Tavily unless runtime evidence confirms it.
- Do not use unmanaged direct network access outside the governed search surface.
- Do not present snippets as verified facts without checking the linked source context.
- Keep search queries aligned with the user task and avoid unnecessary disclosure of sensitive project details.
