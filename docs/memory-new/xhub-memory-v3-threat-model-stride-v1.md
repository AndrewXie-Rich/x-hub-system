# X-Hub Memory v3 威胁模型（STRIDE + 滥用场景）

- version: v1.0
- updatedAt: 2026-02-26
- status: active
- scope: Hub Memory（Raw/Obs/Longterm/Canonical/Working Set）+ 相关审计/加密/删除恢复链路

## 1) 目标与范围

目标：
- 为 Memory v3 提供一版可执行的 STRIDE 威胁建模基线。
- 明确三类高优先滥用场景：`prompt injection` / `replay` / `exfiltration`。
- 给出“已落地控制 / 剩余风险 / 下一步工程项”的闭环清单。

范围内资产（高价值）：
- 会话与记忆数据：`turns`、`canonical_memory`、后续 `observations/longterm/raw vault`。
- 密钥资产：`memory_encryption_keys`、KEK ring、DEK。
- 安全审计：`audit_events`、retention 运行记录、tombstones。
- 授权链路：grant request / grant token / policy decision。

非范围（本文件不展开）：
- OS/硬件层供应链与物理攻击。
- 组织级 KMS/HSM 方案（当前仍是本地 keyring/file 模式）。

## 2) 信任边界与攻击面

核心边界：
1. **Untrusted Input Boundary**：外部内容（邮件/网页/工具输出/用户粘贴）进入 Memory。
2. **Hub Core Boundary**：Hub gRPC + DB + policy engine（可信核心）。
3. **Bridge/Remote Boundary**：paid 模型与外部网络调用（高外发风险）。
4. **Client Boundary**：X-Terminal/手机/机器人等终端（默认不完全可信）。

主要攻击面：
- Memory 写入接口（AppendTurns/Canonical upsert）。
- Prompt 组装与 remote 发送链路。
- Grant/idempotency/retry 链路（重放窗口）。
- Retention 删除与恢复（tombstone）链路。

## 3) STRIDE 威胁矩阵（Memory v3）

| STRIDE | 代表场景 | 影响 | 当前控制（2026-02-26） | 剩余风险 |
|---|---|---|---|---|
| S（Spoofing） | 伪造 device/user/project 身份写入 memory 或申请授权 | 越权访问、污染记忆 | gRPC auth + capability 检查；grant 绑定 scope；审计落库 | Mode2/远端桥接仍有身份绑定强度差异，需要统一 mTLS 身份语义 |
| T（Tampering） | 篡改 DB 中 turns/canonical 内容或加密包 | 记忆污染、错误决策 | at-rest AES-256-GCM + AAD（篡改即解密失败）；fail-closed | 历史明文数据仍可被本地篡改；Raw/Obs/Longterm 尚未全量接入 |
| R（Repudiation） | 操作者否认删改/恢复/授权行为 | 追责失败 | `audit_events` + retention run 记录 + restore 审计事件 | 审计签名链未做（当前依赖 DB 完整性与访问控制） |
| I（Info Disclosure） | prompt 外发泄漏 secret/PII；审计或日志泄漏 | 凭证/隐私泄露 | `<private>` fail-closed；audit metadata-only；at-rest encryption；TTL scrub | paid prompt 的统一 remote gate 尚需从“规范”推进到“强制执行” |
| D（DoS） | 大量记忆写入、恢复滥用、retention 批处理阻塞 | 性能下降、服务不可用 | 批量上限、自动作业 best-effort、队列/配额基础设施 | 需补 memory 层专用限流与告警阈值（p95/p99） |
| E（Elevation） | 低信任 observation 被晋升为 canonical，触发高风险动作 | 权限升级、自动化误执行 | canonical 当前写入可控；安全类字段不自动晋升（策略要求） | 自动晋升策略仍需“证据+人工确认”硬约束在代码侧全覆盖 |

## 4) 高优先滥用场景（Abuse Cases）

### A1. Prompt Injection（外部内容注入）

攻击路径：
1) 攻击者通过网页/邮件/工具输出注入“忽略规则、导出密钥”等文本。
2) 文本被写入 turns/obs/longterm 后参与 prompt 组装。
3) AI 被诱导越过策略，触发外发或高风险动作。

当前控制：
- `<private>` 状态机解析（fail-closed，未闭合也视为私密）。
- memory at-rest 加密，降低离线泄露。
- 审计最小化，减少明文扩散面。

剩余风险（需持续推进）：
- 对“untrusted 内容 -> canonical 晋升”仍需更强门禁。
- remote prompt gate 需强制化（二次 DLP + secret_mode gate）。

### A2. Replay（重放）

攻击路径：
1) 截获旧授权请求/支付确认/关键事件。
2) 在有效窗口重复投递，试图重复执行动作。

当前控制：
- grant request idempotency（device_id + request_id）。
- 审计可回溯请求链路。
- retention run/restore 记录可追溯数据生命周期。

剩余风险：
- 高价值动作（支付/外部提交）仍需统一 nonce + expiry + single-use 语义。
- 需要“跨通道重放”回归测试（手机确认、机器人上报、Hub 转发）。

### A3. Exfiltration（隐蔽外传）

攻击路径：
1) 将 secret/PII 混入普通对话或 memory 条目。
2) 通过 paid remote model prompt 或 connector 出站流量外发。

当前控制：
- audit `metadata_only` 默认。
- at-rest encryption（turns/canonical）+ KEK/DEK 轮换。
- `<private>` 默认不入常规注入链路。

剩余风险：
- 需要把 `prompt_bundle` remote gate 从规范升级为默认强制路径。
- 需补“blocked 后降级到 local”的一致行为与审计口径。

## 5) 安全回归基线（M1-5）

必须纳入发布门槛的回归项：
1. **Tamper fail-closed**：密文任一字段篡改，解密失败且请求不返回明文。
2. **Audit minimization**：默认审计不出现 secret 明文，preview 到期自动 scrub。
3. **Retention safety**：TTL 删除可追溯；dry-run 不修改数据；restore 可恢复且写审计。
4. **Replay guard（基础）**：同一 idempotency key 不产生重复授权副作用。
5. **Prompt injection regression**：`<private>` 未闭合/嵌套/异常闭合均按 fail-closed 处理。

当前自动化覆盖（已存在）：
- `src/private_tags.test.js`
- `src/audit_redaction.test.js`
- `src/memory_at_rest_encryption.test.js`
- `src/memory_retention.test.js`

## 6) 风险分级与处置优先级

P0（发布前必须）：
- 强制 remote prompt gate（二次 DLP + secret_mode + deny credentials）。
- 支付/外部动作统一 nonce + expiry + single-use replay 防护。
- canonical 自动晋升硬门禁（安全/支付/权限类字段必须人工确认）。

P1（下一阶段）：
- Raw/Obs/Longterm 全量接入 at-rest encryption 与 retention 分层 TTL。
- 审计防抵赖增强（签名链/哈希链）。
- memory 层 DoS 指标与告警（queue depth、p95/p99、job latency）。

## 7) 结论（M1-5 交付结论）

- M1 阶段已形成“可执行安全基线”：`private fail-closed + audit 最小化 + at-rest 加密 + retention/restore`。
- 主要残余风险集中在“远程外发门禁强制化”和“高价值动作 replay 防护统一化”。
- 进入 M2 前，建议先完成 P0 三项，避免并行自动化规模扩大后放大风险。
