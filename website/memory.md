# Governed Memory Control Plane

<p class="lead">
Your AI's memory shouldn't live inside the AI. When you switch from Claude to GPT, your project context shouldn't vanish. When the AI claims a task is done, the evidence shouldn't only exist in its own chat history. When a tool retrieves memory, the user should decide what gets read — not the model. X-Hub Memory is the layer that makes all of that work.
</p>

<div class="preview-note">
  <strong>Control-plane positioning</strong>
  X-Hub Memory is not about remembering one more sentence. It is built for high-risk, long-running, multi-role, multi-project agentic coding and personal-assistant work where memory must pass through Hub authority, policy, audit, and export boundaries before it reaches a model.
</div>

## Why Memory Is A Core Capability

Agent quality depends heavily on memory. If memory is just a chat summary, several failures appear quickly:

- wrong content becomes durable and keeps polluting later decisions
- important constraints get compressed away while the model remembers only the task goal
- project evidence, user preference, organization rule, and temporary conversation are mixed together
- every role receives the same context, wasting tokens and increasing leakage risk
- a terminal or plugin can influence durable truth too easily

X-Hub treats memory as a Hub-first governed object. Ordinary memory asks whether the model can remember. X-Hub Memory asks who is allowed to make the model remember, read, export, modify, or forget.

## Not Ordinary Memory

Many AI memory systems optimize for capture and recall: summarize the conversation, embed documents, search past facts, and feed the model the most relevant snippets. That is useful, but it is not enough when AI can operate tools, touch projects, route through paid models, or act from remote channels.

X-Hub's position is different: memory is part of the safety and runtime truth layer.

| Ordinary agent memory | X-Hub Governed Memory |
| --- | --- |
| Automatically remembers chats and preferences | New writes become candidates first and cannot directly pollute durable truth |
| Vector retrieval then prompt injection | Context assembly passes through role, policy, scope, and export gates |
| Agent-readable and writable memory blocks | X-Constitution and policy core are not ordinary blocks; they are pinned core and Hub policy |
| IDE or client-local memory can dominate context | XT local memory is cache, fallback, and edit buffer |
| Optimizes recall accuracy | Optimizes permissions, evidence, audit, revocation, and export boundaries as well |

The result is model-agnostic memory that can serve local models, paid models, Supervisor review, Project AI execution, skills, and remote channels without making any one client the new authority.

## Control planes

Many memory systems combine storage, retrieval, and prompt injection into one path. X-Hub separates them:

| Plane | Role | Why it matters |
| --- | --- | --- |
| Truth | Hub-first durable memory truth | XT local memory remains cache, fallback, and edit buffer, not the source of truth |
| Serving | role-aware context assembly | Supervisor, Project Coder, personal assistant, and remote channels receive different memory packs |
| Governance | policy, grants, X-Constitution, export gates, candidate approval | Relevant does not mean visible; readable does not mean exportable; extracted does not mean accepted |
| Explainability | selected / omitted trace, readiness, doctor, audit evidence | The system can explain why memory was selected, omitted, blocked, or considered not ready |

The five-layer structure answers how memory is retained. The control plane answers who can read, write, explain, revoke, and export it.

## The Five Layers

| Layer | Role | Why It Matters |
| --- | --- | --- |
| Raw Vault | Stores raw evidence, events, and inputs | Later review can trace back to evidence instead of model self-report |
| Observations | Turns raw material into structured facts | Reduces noise and supports review and promotion |
| Longterm | Stores long-lived goals, architecture, constraints, and documents | Gives the system stable background instead of guessing every turn |
| Canonical | Stores a small set of high-confidence facts that can be injected by default | Improves efficiency and reduces context pollution |
| Working Set | Holds active context needed for the current task | Keeps Project AI focused on execution |

## Core advantages

<div class="story-grid">
  <div class="story-card">
    <span>Policy &gt; Prompt</span>
    <strong>Safety is not one line in the prompt</strong>
    <p>raw evidence, remote export, and Project Coder personal memory paths should pass through policy and readiness first. Missing authority or unclear scope should fail closed.</p>
  </div>
  <div class="story-card">
    <span>Hub Truth</span>
    <strong>Durable truth returns to the Hub</strong>
    <p>XT local memory is cache, fallback, and edit buffer. Long-term facts, project truth, and governed constraints should not become final truth inside a local IDE or terminal.</p>
  </div>
  <div class="story-card">
    <span>Candidate Writeback</span>
    <strong>Extraction does not mean durable pollution</strong>
    <p>New memory produced by a model or extractor should become a candidate first, then pass review, approval, policy, and evidence before becoming active.</p>
  </div>
  <div class="story-card">
    <span>Role-aware</span>
    <strong>Supervisor and Coder do not consume the same context</strong>
    <p>Supervisor may see personal, project, cross-link, and review context. Project Coder defaults to project-domain-first context so personal memory does not pollute execution.</p>
  </div>
  <div class="story-card">
    <span>Continuity Floor</span>
    <strong>Recent raw dialogue remains a floor</strong>
    <p>Not everything should be summarized too early. Recent raw and recent project dialogue floors solve the practical problem of forgetting what just happened.</p>
  </div>
  <div class="story-card">
    <span>Evidence first</span>
    <strong>Durable facts should point back to evidence</strong>
    <p>Test results, user decisions, project state, and constraints should not come only from model summaries. X-Hub connects important memory to evidence, audit, and raw material.</p>
  </div>
  <div class="story-card">
    <span>Doctor</span>
    <strong>Auditable and diagnosable</strong>
    <p>memory readiness, candidate count, selected / omitted trace, shadow compare, cutover readiness, and Doctor evidence should be machine-readable instead of hidden in logs.</p>
  </div>
  <div class="story-card">
    <span>Local-first</span>
    <strong>Authority first, intelligence second</strong>
    <p>Rust object store, derived index, candidate queue, and gateway work make authority, policy, and evidence stable before adding semantic retrieval, temporal graph, and Memory Inspector experiences.</p>
  </div>
</div>

## What Is Working Today

X-Hub is in public technical preview, so the memory page should be read as a product direction with a real runtime foundation, not as a claim that every planned layer is complete.

Currently implemented or preview-working:

- Rust memory object storage with object history and readiness reporting
- Hub-first project canonical sync from XT into Rust memory objects
- policy-gated Rust memory gateway prepare path for context assembly
- lexical / hybrid object retrieval over active project memory objects, with explainable retrieval evidence
- role-aware XT memory assembly for Supervisor and Project AI
- heartbeat, review, route, and memory diagnostics surfaced through Doctor-style evidence
- governed writeback candidates, where extracted memory writes become reviewable candidates before durable promotion
- remote export and prompt gating design paths that keep memory externalization separate from model context assembly

Still being expanded:

- semantic embeddings and deeper rerank
- a full generalized Observations / Longterm substrate across every surface
- a public Memory Inspector experience for candidate review, approval, and lineage browsing
- Rust model-call gateway authority; the current Rust memory gateway is prepare-first
- full removal of every legacy local/Node memory authority path

## Memory Writes as Signed Receipts

Every durable write that passes the Writer + Gate boundary produces a [Hub Receipt v0.1](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) envelope: who wrote, what evidence, which policy applied, what was promoted, what was denied. Receipts:

- are verifiable outside X-Hub — any auditor with the issuer public key can verify authenticity without contacting the Hub
- share the same envelope as `mcp-trust-registry` skill receipts and `agent-2fa` per-action receipts, so memory writeback is part of one audit chain, not a separate silo
- can be embedded in commits, IDE metadata, or compliance exports — supporting EU AI Act / ISO 42001 / SOC2-conscious procurement contexts

Memory truth is no longer "the system logged a write"; it's "the system produced an externally verifiable artifact about what was written, why, and on whose authority."

## How It Works With X-Terminal

Project AI needs "what should I do now, what evidence do I have, and how do I verify the next step." Supervisor needs "is this project drifting, is there a better path, and which project needs attention first."

X-Hub therefore keeps autonomy tiers, supervision tiers, and memory depth separate:

- A-Tier sets Project AI execution ceiling and project-memory ceiling.
- S-Tier sets Supervisor intervention strength and review-memory ceiling.
- Recent context, Project Context Depth, and Review Memory Depth remain independent controls.
- configured, recommended, and effective values explain why this run saw this context.

That lets the system have long memory without dumping everything into every model call.

## A Concrete Example

If Project AI says "the task is done," a normal agent might write that into a summary.

X-Hub's memory path is stricter:

1. Raw Vault keeps original output, commands, tests, and logs.
2. Observations record verifiable facts: which tests ran, which failed, which files changed.
3. Supervisor checks evidence strength during pre-done review.
4. Canonical memory stores only the stable completion state.
5. If evidence is weak, the user digest says "done candidate, verification needed" instead of pretending the work is complete.

That is the value of governed memory: not remembering more, but remembering more reliably.

Continue with:
[X-Terminal](/x-terminal), [X-Constitution](/constitution), and [Governance](/governed-autonomy).
