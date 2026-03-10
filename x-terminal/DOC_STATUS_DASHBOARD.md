# X-Terminal 文档状态面板（Single Source of Truth）

> 自动生成文件；请勿手工编辑。

- generated_at: 2026-02-28T09:29:20+00:00
- scope: `x-terminal/*.md`（排除本文件）
- source_script: `scripts/generate_doc_status_dashboard.py`

## 总览
- completed: 4
- in_progress: 3
- planned: 1
- stale: 1
- unknown: 0

## Phase 裁决
| Phase | 面板状态 | 依据文档 | 依据摘录 |
|---|---|---|---|
| Phase 1 | completed | `PHASE1_COMPLETION_RECORD.md` | ✅ 100% 完成 |
| Phase 2 | completed | `PHASE2_COMPLETE.md` | ✅ 100% 完成 |
| Phase 3 | in_progress | `PHASE3_PROGRESS.md` | 🚧 进行中（并行泳道推进） |

## 文档明细
| 文件 | 类型 | Phase | 文档日期 | 提取状态 | 面板状态 | 备注 |
|---|---|---:|---|---|---|---|
| `PHASE1_COMPLETION_RECORD.md` | completion | 1 | 2026-02-27 | ✅ 100% 完成 | completed | - |
| `PHASE2_COMPLETE.md` | completion | 2 | 2026-02-27 | ✅ 100% 完成 | completed | - |
| `PHASE2_PENDING_TASKS.md` | pending | 2 | 2026-02-27 | 🗃️ 已归档（历史计划，Phase 2 已完成） | stale | 已被 PHASE2_COMPLETE.md 覆盖（Phase 2 已完成） |
| `PHASE2_SUMMARY.md` | summary | 2 | 2026-02-27 | ✅ 完成 | completed | - |
| `PHASE3_EXECUTIVE_SUMMARY.md` | exec_summary | 3 | 2026-02-28 | 🚧 进行中（以 work-orders + Gate 为准） | in_progress | - |
| `PHASE3_PLAN.md` | plan | 3 | 2026-02-28 | - | planned | - |
| `PHASE3_PROGRESS.md` | progress | 3 | 2026-02-28 | 🚧 进行中（并行泳道推进） | in_progress | - |
| `PROJECT_STATUS.md` | status | - | 2026-02-27 | - | in_progress | - |
| `vs deer-flow-main.md` | comparison | - | 2026-02-27 | - | completed | - |

## 冲突与风险
- `PHASE2_PENDING_TASKS.md`: 已被 PHASE2_COMPLETE.md 覆盖（Phase 2 已完成）

## 维护约定
- 本文件为唯一状态入口；其它文档允许保留历史叙述，但不再作为进度裁决依据。
- 每次更新任意 Phase 文档后，执行一次生成脚本刷新状态面板。
- 若新增文档，请保持文件命名包含 `PHASE{n}`，便于自动归档。

## 刷新命令
```bash
cd x-hub-system/x-terminal
python3 ./scripts/generate_doc_status_dashboard.py
```

## 校验命令（CI/本地）
```bash
cd x-hub-system/x-terminal
python3 ./scripts/generate_doc_status_dashboard.py --check
```
