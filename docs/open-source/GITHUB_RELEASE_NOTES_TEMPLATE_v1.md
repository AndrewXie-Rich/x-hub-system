# GitHub Release Notes 模板 v1

用途：

- 这是给 GitHub Release 页面直接复制使用的模板
- 对外表述必须保持在当前 validated release slice 内
- 不得借发布页扩大发布范围

建议配套阅读：

- `README.md`
- `RELEASE.md`
- `docs/WORKING_INDEX.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`

---

## 可直接复制模板

```md
# X-Hub v0.1.0-alpha

X-Hub is a trusted control plane for AI execution.

This release is intentionally narrow and only reflects the currently validated public release slice.

Internal work-order packs, operator docs, and in-progress implementation slices in this repository may extend beyond this public release slice. Do not mirror that internal progress directly into external release messaging.

## What This Release Covers

Validated release slice:

- `XT-W3-23 -> XT-W3-24 -> XT-W3-25`

Validated public statements for this release:

- XT memory UX adapter backed by Hub truth-source
- Hub-governed multi-channel gateway
- Hub-first governed automations

## Why It Matters

X-Hub keeps model routing, memory truth, grants, policy, audit, and execution safety inside one governed Hub, while terminals stay lightweight and untrusted by default.

If memory posture is mentioned in public wording, keep it in this boundary: the user chooses which AI executes memory jobs in X-Hub, `Memory-Core` is a governed Hub-side rule asset rather than a normal plugin, and durable writes still terminate through `Writer + Gate`.

Compared with a terminal-only AI setup, this release emphasizes:

- Hub-first trust boundaries
- unified governance for local and paid models
- memory-backed constitutional guardrails reinforced by Hub policy controls
- fail-closed readiness and execution behavior
- safer automation paths under Hub control

## Recommended Host Hardware

X-Hub is recommended to run on Apple silicon desktop Macs.

- **Mac mini**: default recommendation for most deployments
- **Mac Studio**: higher-capacity recommendation for heavier local-model load, more memory, or more concurrency

This makes X-Hub a strong fit for:

- enterprises
- public-sector teams
- regulated or security-sensitive environments
- individuals who want a safer and more controlled AI setup

## Included In This Release

- Root product and navigation docs
- Active Hub and terminal source trees
- Protocol contracts
- Open-source release and packaging docs

## Quick Start

Build the Hub app:

```bash
x-hub/tools/build_hub_app.command
```

Launch the built X-Hub app:

```bash
open build/X-Hub.app
```

Run X-Terminal from source:

```bash
cd x-terminal
swift run XTerminal
```

Run the XT release gate:

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

Developer note: the public Hub source-run entrypoint is `bash x-hub/tools/run_xhub_from_source.command`. The internal Swift package still lives under the historical compatibility directory `x-hub/macos/RELFlowHub/`.

## Security Posture

- high-risk paths fail closed when critical readiness is incomplete
- the terminal is not the trust anchor
- constitutional guidance is intended to be pinned on the Hub side and reinforced by policy controls
- any memory-control wording should keep `Memory-Core` on the governed rule layer and keep durable writes on `Writer + Gate`
- grants, routing, and execution safety stay under Hub control

If you mention constitutional or memory-backed guardrails in release notes, keep the wording in the system safety posture lane. Do not present them as extra validated feature claims beyond the approved release slice.

## Known Scope Limits

This release does **not** claim the full internal document set as publicly validated capability.

If a capability is not explicitly covered by the validated release slice above, treat it as outside the scope of this release.

## Release References

- `README.md`
- `RELEASE.md`
- `docs/WORKING_INDEX.md`
- `docs/REPO_LAYOUT.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`

## Rollback Reference

If rollback is required, use the last known good tag and the rollback procedure documented in `RELEASE.md`.
```

---

## 使用规则

发版前请确认：

1. tag、范围、已验证声明与 `README.md` 一致
2. 不新增未验证能力表述
3. 如果需要写 “What changed”，只写本次实际公开范围内可解释的变化
4. 如需写硬件建议，保持：
   - `Mac mini` 默认推荐
   - `Mac Studio` 高容量推荐
5. 不要把内部工单名、内部 slice 进度、或 operator 导航内容直接写成公开 release claim
