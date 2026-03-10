# X-Terminal (Planned)

This directory is a placeholder for the new **X-Terminal** implementation.

Decision (2026-02-12): X-Terminal is **not** a rename of AX Coder; it will be a new terminal client that connects to X-Hub via gRPC.

Key goals:
- Thin client: memory + skills live on X-Hub; X-Terminal keeps minimal local state.
- Multi-model orchestration (Supervisor pattern) to manage multiple projects from one chat.

See:
- `docs/xhub-client-modes-and-connectors-v1.md`
- `docs/xhub-multi-model-orchestration-and-supervisor-v1.md`

