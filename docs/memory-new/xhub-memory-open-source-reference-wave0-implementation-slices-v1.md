# X-Hub Memory 开源借鉴 Wave-0 实现切片 v1

- version: v1.0
- updatedAt: 2026-03-19
- owner: Hub Memory / Runtime / XT-L2 / Security / QA
- status: proposed-active
- scope: 将 `xhub-memory-open-source-reference-wave0-execution-pack-v1.md` 继续下沉为 ready-to-claim 的实现切片，供后续直接认领、排期、合并与回归。所有切片都必须挂在现有父工单之下推进，不形成平行主线。
- parent:
  - `docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-adoption-checklist-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
- related:
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.test.js`

## 0) 使用方式

- 本文不是新的主设计文档，而是 `Wave-0` 的认领面。
- 每个切片都回答 7 个问题：
  - 做什么
  - 挂到哪份父文档
  - 主要改哪些文件
  - 完成标准是什么
  - 哪些测试必须补
  - 是否触碰 frozen contract
  - 建议谁认领
- 默认执行顺序：
  - 先 `A1`
  - 再 `A2`
  - 再 `A8`
  - 最后 `A9`

## 1) 全局约束

1. 不改 `search_index -> timeline -> get_details` 已冻结接口。
2. 不改 M3 grant / lineage / XT-Ready contract。
3. 不新增第二套 memory truth source。
4. 不给 Wave-0 发明新的总架构名字。
5. 每个切片完成后都必须补可追溯证据：
   - 文档变更
   - 测试
   - 指标或 explain 输出

## 2) Ready-to-Claim 切片总览

| Slice ID | 对应条目 | 目标 | 父轨 | 建议 owner | 预计粒度 |
| --- | --- | --- | --- | --- | --- |
| `W0-A1-S1` | `MRA-A1-01` | 冻结 memory job taxonomy | Memory Model Preferences Contract | Hub Runtime | 0.5-1d |
| `W0-A1-S2` | `MRA-A1-02` | 固定 route explain/audit 词典 | Memory Model Preferences Contract | Hub Runtime + QA | 0.5-1d |
| `W0-A1-S3` | `MRA-A1-03` | 形成 diagnostics-first route surface | LPR / diagnostics | Hub Runtime + XT-L2 | 0.5-1d |
| `W0-A2-S1` | `MRA-A2-01` | 冻结 expansion routing 输入因子 | M2 Retrieval | Hub Memory | 0.5-1d |
| `W0-A2-S2` | `MRA-A2-02` | 固定 routing outcome explain schema | M2 Retrieval + Supervisor Serving | Hub Memory + XT-L2 | 0.5-1d |
| `W0-A2-S3` | `MRA-A2-03` | 扩充 golden/adversarial 回归 | M2 Bench | QA + Hub Memory | 0.5-1d |
| `W0-A8-S1` | `MRA-A8-01` | 新增 property extractor v1 | M2 Retrieval / Index | Hub Memory | 1d |
| `W0-A8-S2` | `MRA-A8-02` | 接入 pipeline 粗筛 | M2 Retrieval | Hub Memory | 0.5-1d |
| `W0-A8-S3` | `MRA-A8-03` | 接入 explain/metrics | M2 Explain + Observability | Hub Memory + QA | 0.5-1d |
| `W0-A9-S1` | `MRA-A9-01` | 固定 replay/repair checklist | M2 Reliability | Hub Memory + QA | 0.5-1d |
| `W0-A9-S2` | `MRA-A9-02` | 固定 migration invariant set | M2 Reliability / Release | Hub Memory + Security | 0.5-1d |
| `W0-A9-S3` | `MRA-A9-03` | retention consistency audit | M2 Reliability + Metrics | Hub Memory | 0.5-1d |

## 3) `A1` 切片

### `W0-A1-S1` Freeze Memory Job Taxonomy

- 目标：
  - 把 memory job type 从“实现约定”升级为“contract + schema + tests 同步冻结”。
- 父轨：
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/schema/xhub_memory_model_preferences_contract.v1.json`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.test.js`
- 最低交付：
  - 冻结 job type 词典
  - 未知 job type fail-closed 行为文档化
  - 对应校验测试
- DoD：
  - contract / schema / implementation / tests 四处 job list 一致
  - route 对未知 job 返回稳定 deny_code 或 fallback deny 行为
  - 无新增 undocumented job type
- 必补测试：
  - job type 正向枚举
  - job type 非法值
  - disabled profile + invalid job 组合路径
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Runtime

### `W0-A1-S2` Freeze Route Explain + Audit Dictionary

- 目标：
  - 让 route 成功、fallback、deny 三种结果都有稳定 explain 字典。
- 父轨：
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.test.js`
  - 可能还会触及 local provider 相关 explain 输出接线
- 最低交付：
  - 统一字段：
    - `route_source`
    - `route_reason_code`
    - `fallback_applied`
    - `fallback_reason`
    - `model_id`
    - `selected_by_user`
  - 典型 route outcome 样例
- DoD：
  - 同一逻辑结果在 memory route 和 local provider route 上解释一致
  - audit / diagnostics 至少能复现 winning profile 与 fallback path
  - 如需 UI 友好输出，可派生 `derived_fallback_action`，但不得替代冻结后的 route result 字段
- 必补测试：
  - success route explain
  - local downgrade explain
  - deny explain
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Runtime + QA

### `W0-A1-S3` Diagnostic-First Route Surface

- 目标：
  - 不先做复杂 UI，而是先做 route diagnostics / doctor surface。
- 父轨：
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
- 主要文件：
  - doctor / diagnostics 相关脚本或输出面
  - route explain 读取入口
- 最低交付：
  - 当前 effective preference 输出
  - winning profile 输出
  - route outcome 输出
- DoD：
  - 能区分 `user_default / mode / project / project_mode / system fallback`
  - QA 可在不翻数据库的情况下复现 route 结果
- 必补测试：
  - diagnostics payload 结构
  - missing preference fallback
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Runtime + XT-L2

## 4) `A2` 切片

### `W0-A2-S1` Freeze Expansion Routing Inputs

- 目标：
  - 固定 expansion routing 的输入因子词典。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`
- 最低交付：
  - 输入因子定义：
    - `candidate_count`
    - `requested_depth`
    - `token_risk_ratio`
    - `broad_time_range_indicator`
    - `multi_hop_indicator`
    - `needs_raw_chunk`
- DoD：
  - 输入含义 deterministic
  - 允许阈值按 profile 变，但不允许语义漂移
- 必补测试：
  - 每个输入因子边界值测试
  - 多因子组合测试
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Memory

### `W0-A2-S2` Freeze Routing Outcome Explain Schema

- 目标：
  - 固定 expansion route 的输出词典与 explain 结构。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
- 最低交付：
  - 输出词典：
    - `answer_directly`
    - `expand_shallow`
    - `delegate_traversal`
  - explain 字段：
    - `trigger_flags`
    - `budget_pressure`
    - `policy_floor`
    - `raw_evidence_allowed`
- DoD：
  - 同一 route outcome 在 Hub explain 与 Supervisor explain 语义一致
  - route 不确定时默认保守
- 必补测试：
  - 三类 route outcome 全覆盖
  - high budget / low budget 差异
  - broad-range + multi-hop 组合
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Memory + XT-L2

### `W0-A2-S3` Expansion Routing Bench Coverage

- 目标：
  - 把 expansion route 纳入 golden / adversarial。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- 主要文件：
  - `docs/memory-new/benchmarks/m2-w1/golden_queries.json`
  - `docs/memory-new/benchmarks/m2-w1/adversarial_queries.json`
  - bench / regression 脚本
- 最低交付：
  - 增补 route-sensitive 查询样本
  - 报告字段显示 route decision 偏差
- DoD：
  - “该直答却展开” / “该展开却直答” 可被机器识别
  - adversarial 覆盖诱导 broad-range / multi-hop 深挖
- 必补测试：
  - regression script coverage
  - sample fixture validation
- frozen contract 风险：
  - `none`
- 建议认领：
  - QA + Hub Memory

## 5) `A8` 切片

### `W0-A8-S1` Property Extractor v1

- 目标：
  - 新增 deterministic property extractor。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
- 最低交付：
  - 第一批 property：
    - `has_code`
    - `has_todo`
    - `has_error`
    - `has_decision`
    - `has_approval`
    - `has_blocker`
    - `has_link`
    - `title_like`
- DoD：
  - 提取稳定
  - 不依赖昂贵模型
  - 不替代 scope/sensitivity/trust gate
- 必补测试：
  - property extractor positive/negative cases
  - multilingual / code-heavy sample mix
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Memory

### `W0-A8-S2` Integrate Property Hit Into Pipeline

- 目标：
  - 把 property 接入粗筛与 explain。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`
- 最低交付：
  - property-aware prefilter 或粗排序
  - property hit explain hook
- DoD：
  - 编程项目类 query 对 `has_code/has_error/has_blocker` 有正向收益
  - personal assistant 类 query 不被 code property 过度偏置
- 必补测试：
  - coding query bucket
  - personal query bucket
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Memory

### `W0-A8-S3` Property Explain + Metrics

- 目标：
  - 让 property 成为可观察信号。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
- 最低交付：
  - explain 暴露 property hit
  - metrics 暴露 property hit ratio 或命中计数
- DoD：
  - report 能看见 property 的价值，不只是代码里存在
- 必补测试：
  - explain payload test
  - metrics schema test
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Memory + QA

## 6) `A9` 切片

### `W0-A9-S1` Freeze Replay / Repair Checklist

- 目标：
  - 固定哪些一致性问题必须有 repair 入口。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- 主要文件：
  - reliability / rebuild / consumer 相关代码与文档
- 最低交付：
  - replay / repair checklist
  - 责任边界说明：只修派生层，不修 Raw Vault 原始真相
- DoD：
  - 常见 drift 场景有统一 checklist
  - QA 能按 checklist 复现与核对
- 必补测试：
  - repair checklist fixture
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Memory + QA

### `W0-A9-S2` Freeze Migration Invariants

- 目标：
  - 固定 memory migration 的 invariant。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- 主要文件：
  - migration / rebuild / release gate 相关文档与测试
- 最低交付：
  - invariant 列表
  - destructive / append-only / backfill-required 分类
- DoD：
  - 任何新 migration 都能对照 invariant 自检
  - release/doctor 可引用 invariant 结论
- 必补测试：
  - invariant drift negative case
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Memory + Security

### `W0-A9-S3` Retention Consistency Audit

- 目标：
  - retention delete / restore 后自动做一致性审计。
- 父轨：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- 主要文件：
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
- 最低交付：
  - consistency audit 规则
  - drift metric / audit 字段
- DoD：
  - delete / restore / rebuild 后可发现 index drift
  - 有失败提示，不靠人工猜
- 必补测试：
  - retention delete -> consistency audit
  - restore -> consistency audit
- frozen contract 风险：
  - `none`
- 建议认领：
  - Hub Memory

## 7) 认领顺序建议

### 第一组：先冻结词典

- `W0-A1-S1`
- `W0-A2-S1`

原因：

- 没有词典冻结，后面的 explain、metrics、bench 都会漂。

### 第二组：再做 explain

- `W0-A1-S2`
- `W0-A2-S2`
- `W0-A8-S3`

原因：

- 先把系统解释能力做出来，后面任何质量讨论才有抓手。

### 第三组：补效率与质量底座

- `W0-A8-S1`
- `W0-A8-S2`
- `W0-A9-S1`
- `W0-A9-S2`
- `W0-A9-S3`

### 第四组：补认领面与回归样本

- `W0-A1-S3`
- `W0-A2-S3`

## 8) 本文完成定义

本文存在的意义只有一个：

`让 Wave-0 不再只是“原则正确”，而是已经被拆成可以直接认领的切片。`

只有满足以下条件，才算本文完成：

1. 每个 Wave-0 子项都至少有一个 ready-to-claim slice。
2. 每个 slice 都有：
   - 父轨
   - 文件面
   - DoD
   - 测试
   - 建议 owner
3. 没有任何 slice 需要回改 frozen M2/M3 contract。
