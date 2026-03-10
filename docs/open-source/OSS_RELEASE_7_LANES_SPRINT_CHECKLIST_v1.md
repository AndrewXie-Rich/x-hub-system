# OSS 发布 7 泳道冲刺检查单 v1（`v0.1.0-alpha`）

- version: `v1.0`
- updated_at: `2026-03-02`
- owner: `AI-COORD-PRIMARY + Hub-L1..L5 + XT-L1..L2`
- profile: `minimal-runnable-package`
- target_window: `发布前 3 小时冲刺`
- source_of_truth:
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md`
  - `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`

## 0) 全泳道统一规则（必须）

- [ ] `critical_path_mode` 开启：`SKC-W1-04 -> SKC-W2-05 -> SKC-W2-06 -> SKC-W2-07 -> SKC-W3-08`
- [ ] 双绿门禁：实现证据绿 + Gate 绿（缺一不可）
- [ ] fail-closed：依赖不满足只允许 blocked checkpoint，不允许越依赖推进
- [ ] require-real：性能/成功率样本禁止 synthetic
- [ ] checkpoint 节奏：每 30 分钟回填一次 7 件套（冲刺窗口内）
- [ ] 输出格式统一：`Scope / DoD / Gate / KPI / Risks / Handoff`

---

## 1) Hub-L1（`SKC-W1-01+SKC-W1-02`，证据协同）

### 冲刺检查单

- [ ] 保持 ABI 与 bridge 契约冻结，不引入新字段漂移
- [ ] 复核 `SKC-G0/SKC-G1` 仍为 PASS
- [ ] 对齐 Hub-L5 的 require-real 样本口径（`>=30 matched rows`）
- [ ] 接收 Hub-L5 采样结果后更新 `SKC-G3` 判定与缺口说明
- [ ] 回填 Hub-L1 分区 7 件套（仅增量）

### 出口条件

- [ ] `SKC-G0=PASS` 且 `SKC-G1=PASS`
- [ ] `SKC-G3=PASS` 或 `INSUFFICIENT_EVIDENCE`（必须给样本缺口数和下一步）

### 发送给 Hub-L1 的定向消息（可直接复制）

```text
[Release Sprint | Hub-L1]
Scope: SKC-W1-01+SKC-W1-02（证据协同，禁止新增功能）
Checklist:
1) 维持 ABI/bridge/deny_code 冻结；
2) 复核 SKC-G0/G1=PASS；
3) 与 Hub-L5 对齐 require-real 样本门槛（>=30 matched rows）；
4) 收到采样后更新 SKC-G3 结论并回填 7件套。
Exit: G0/G1 保持 PASS；G3 PASS 或给出 INSUFFICIENT_EVIDENCE+缺口数。
```

---

## 2) Hub-L2（`SKC-W1-04`，上游已交付守门）

### 冲刺检查单

- [ ] 维持 `SKC-W1-04` 已交付范围，不新增跨泳道改动
- [ ] 执行 dependency probe，核验 Hub-L3/XT-L1 最新证据可用性
- [ ] 监控 `SKC-W1-04` 双绿状态，准备下游 handoff
- [ ] 每 30 分钟落盘 blocked/ready checkpoint

### 出口条件

- [ ] `SKC-W1-04` 在 Hub-L2 侧无回归
- [ ] 可给出“立即可交接”或“阻塞缺口明细（责任泳道+证据路径）”

### 发送给 Hub-L2 的定向消息（可直接复制）

```text
[Release Sprint | Hub-L2]
Scope: SKC-W1-04（守门态）
Checklist:
1) 不新增功能，只做依赖探测与双绿守门；
2) 核验 Hub-L3/XT-L1 证据链是否闭合；
3) 若未闭合，输出责任泳道+缺口键+证据路径；
4) 每30分钟回填 checkpoint。
Exit: W1-04 可交接或 fail-closed 阻塞明细完整。
```

---

## 3) Hub-L3（`SKC-W1-04`，关键解阻位）

### 冲刺检查单

- [ ] 优先接收 XT-L1 的 runner execute 主链接线证据
- [ ] 复跑 `SKC-G4` 相关契约/安全回归（只跑本泳道要求集）
- [ ] 更新 `SKC-G4` 判定（PASS/INSUFFICIENT_EVIDENCE）
- [ ] 一旦转绿，第一时间通知 XT-L1 + XT-L2 + Hub-L2

### 出口条件

- [ ] `SKC-G4=PASS`，或给出结构化缺口清单（不得模糊）

### 发送给 Hub-L3 的定向消息（可直接复制）

```text
[Release Sprint | Hub-L3]
Scope: SKC-W1-04（G4 关键解阻）
Checklist:
1) 先吃 XT-L1 execute-chain 证据；
2) 复跑 G4 必要回归并更新 gate；
3) 通过即广播 XT-L1/XT-L2/Hub-L2；
4) 不通过则 fail-closed 输出缺口键+下一步。
Exit: SKC-G4 PASS 或结构化缺口清单。
```

---

## 4) Hub-L4（`SKC-W2-07`，precheck 挂起）

### 冲刺检查单

- [ ] 维持 precheck-only，禁止提前进入 runtime 主链接入
- [ ] 等待并校验 XT-L2 提供的 `SKC-W2-06 verified_handoff`
- [ ] 校验通过后将状态切到 `execution_ready`
- [ ] 校验不通过时落盘 fail-closed 原因与补证指引

### 出口条件

- [ ] `SKC-W2-06 verified_handoff` 已验真，或阻塞条件写全

### 发送给 Hub-L4 的定向消息（可直接复制）

```text
[Release Sprint | Hub-L4]
Scope: SKC-W2-07（precheck-only）
Checklist:
1) 严禁越依赖接 runtime 主链；
2) 等 XT-L2 verified_handoff 并做验真；
3) 通过则切 execution_ready；
4) 不通过则给 fail-closed 缺口与补证指引。
Exit: verified_handoff 已验真或阻塞原因完整。
```

---

## 5) Hub-L5（`SKC-W3-08`，release 证据主责）

### 冲刺检查单

- [ ] 牵头补齐 require-real 样本（3 类 incident）
- [ ] 样本门槛达标后重跑 `scripts/m3_run_hub_l5_skc_g5_gate.sh`
- [ ] 回填 `SKC-G3` 与 `SKC-G5` 判定到 release evidence
- [ ] 向 Hub-L1/XT-L2/AI-COORD 广播最新 gate 结论

### 出口条件

- [ ] `SKC-G3` 与 `SKC-G5` 至少可判定（PASS 或缺口可计算）

### 发送给 Hub-L5 的定向消息（可直接复制）

```text
[Release Sprint | Hub-L5]
Scope: SKC-W3-08（release 证据主责）
Checklist:
1) 先补 require-real 三类 incident 样本；
2) 达标后重跑 m3_run_hub_l5_skc_g5_gate.sh；
3) 回填 G3/G5 到 release evidence；
4) 广播 Hub-L1/XT-L2/总控。
Exit: G3/G5 可判定（PASS 或可计算缺口）。
```

---

## 6) XT-L1（`SKC-W2-05`，主链关键前置）

### 冲刺检查单

- [ ] 最高优先补齐 execute-chain -> evaluateSkillExecutionGate 接线证据
- [ ] 推进 `SKC-W2-05` 到 `SKC-G1/G3/G4` 可判定态
- [ ] require-real 路径禁止 synthetic
- [ ] 转绿后立即通知 XT-L2 进入 `SKC-W2-06` 交接

### 出口条件

- [ ] `SKC-W2-05` 转绿，或输出结构化阻塞原因（可执行）

### 发送给 XT-L1 的定向消息（可直接复制）

```text
[Release Sprint | XT-L1]
Scope: SKC-W2-05（主链关键前置）
Checklist:
1) 先完成 execute-chain->evaluateSkillExecutionGate 证据；
2) 推 G1/G3/G4 到可判定；
3) require-real 禁 synthetic；
4) 转绿立即 handoff XT-L2。
Exit: W2-05 PASS 或可执行阻塞清单。
```

---

## 7) XT-L2（`SKC-W2-06`，主链接力中枢）

### 冲刺检查单

- [ ] 维持 wait-for 图与 unblock baton 派发
- [ ] 盯 `SKC-W2-05 -> SKC-W2-06` 转换点（收到转绿即接管）
- [ ] 完成 `SKC-W2-06 verified_handoff`（含 heartbeat/cleanup 联动证据）
- [ ] 完成后立即通知 Hub-L4 切换 `SKC-W2-07`
- [ ] `XT-W2-27-F` 仅可在不抢占 SKC 主链资源时推进

### 出口条件

- [ ] `SKC-W2-06 verified_handoff` 已通过并被 Hub-L4 接收

### 发送给 XT-L2 的定向消息（可直接复制）

```text
[Release Sprint | XT-L2]
Scope: SKC-W2-06（主链接力中枢）
Checklist:
1) 维护 wait-for 图 + unblock baton；
2) W2-05 转绿后立即接管 W2-06；
3) 产出 verified_handoff（含 heartbeat/cleanup 证据）；
4) 通知 Hub-L4 切 W2-07；
5) XT-W2-27-F 不得抢占主链资源。
Exit: W2-06 verified_handoff 通过并被 Hub-L4 接收。
```

---

## 8) 冲刺结束统一回执模板（7 泳道同版）

```text
ACK | <lane_id> | <timestamp>
Scope:
- <task_id>

DoD:
- [x]/[ ] ...

Gate:
- <gate>: PASS|FAIL|INSUFFICIENT_EVIDENCE

KPI Snapshot:
- <metric>=<value>

Risks:
- <top1>
- <top2>

Handoff:
- next_owner_lane: <lane>
- unblock_condition: <condition>
- evidence_refs:
  - <path1>
  - <path2>
```
