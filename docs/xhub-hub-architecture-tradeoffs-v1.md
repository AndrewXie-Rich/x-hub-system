# X-Hub Architecture Design Points & Tradeoffs v1（可执行清单 / Draft）

- Status: Draft（工程落地用；与白皮书互补：白皮书偏“对外承诺”，本文偏“怎么实现/怎么兜底”）
- Applies to: X-Hub Core + Bridge + hub_grpc_server + Connectors +（未来）X-Terminal
- Updated: 2026-02-12

> 目标：把 X-Hub 的关键设计点列齐：每个点的优势、潜在缺点（风险/成本/复杂度），以及可执行的改进方向（怎么改）。

---

## 0) 总原则（不变的底层约束）

1) **Hub 是唯一可信核心（TCB）**：Secrets、权限、审计、Kill-Switch、记忆治理都应在 Hub。
2) **终端默认不可信**：终端可以被恶意用户/恶意软件/提示注入操控；所以“不可逆外部动作”要尽量收敛到 Hub。
3) **不牺牲体验**：默认允许 skills ecosystem 风格的全自动；安全靠“Hub 控制面 + 可审计 + 可冻结 + 配额/撤销窗口/异常检测”兜底。
4) **最小权限**：能在 Hub 侧以更小权限实现的，就不要下放到终端或第三方脚本。

---

## 1) 信任边界与威胁模型（必须说清楚）

### 1.1 你能“强保证”的边界
- **强保证**（Hub 内部经由 Hub API 的行为）：模型调用、Web Fetch、Connectors 调用、Secrets 存储、Grant 决策、Kill-Switch、Audit 落库。
- **弱保证**（Hub 无法强制控制）：Generic Terminal 的本机网络直连、本机文件读写、本机执行命令。

### 1.2 主要攻击面
- 恶意终端（被黑、插件被改、用户装了木马）
- prompt injection（来自邮件/网页/文档内容，不需要恶意 skill）
- 供应链（skills/插件/依赖被投毒）
- Hub 被入侵（尤其是 Hub 运行可执行第三方代码时）
- 密钥泄漏（API keys/OAuth tokens/邮箱密码等）

### 1.3 关键对策（落地优先级）
- 外部动作走 Hub Connectors + grants + audit + kill-switch
- Secrets 只在 Hub Vault
- Hub Core 不加载第三方可执行插件；Connectors/扩展要隔离
- 远程模型外发遵守“敏感级别 + DLP + fail-closed”策略

---

## 2) 进程分层：Core vs Bridge vs Connectors

### 2.1 设计点
- Bridge 为唯一联网进程（有 network entitlement）；Core 尽量 offline。
- Connectors 尽量独立进程（或至少独立模块 + 最小权限），避免把 Hub Core 变成 RCE 平台。

### 2.2 优势
- 集中 egress 审计与 Kill-Switch
- 更容易做 allowlist（域名/端口/协议）

### 2.3 缺点 / 风险
- 工程复杂度增加（进程间通信、崩溃恢复、版本兼容）
- 若 connector/模块绕过 Bridge 外联，会破坏安全承诺

### 2.4 怎么改（可执行）
- 统一所有外联走 Bridge 的“egress API”（HTTP + IMAP/SMTP 等也统一由 Bridge 代发）
- 每个 connector 在 Bridge 侧做域名/端口 allowlist
- 给 connectors 单独的运行账号/沙箱（macOS：独立 helper + 最小 entitlement）

---

## 2.5) 运行模式与连接（Mode 0/1/2/3）

### 2.5.1 设计点
- 支持白皮书的 Mode 0/1/2/3（离线/安全局域网/普通局域网/远程公网加密通道）
- 传输层使用 TLS/mTLS；配对后写入 allowlist（token + 可选证书指纹绑定）
- “只通过域名连接、不存明文 IP”改为**推荐/可选**（不是强制承诺）

### 2.5.2 优势
- Mode 3（tunnel）让 Hub 真正成为“独立设备”，跨网络可用

### 2.5.3 缺点 / 风险
- 远程模式下 IP/网络环境不稳定，allowed CIDRs 与证书管理更复杂

### 2.5.4 怎么改（可执行）
- 默认在 LAN 用 `allowed_cidrs=["private","loopback"]`；远程模式建议绑定稳定 VPN 子网（Tailscale/Headscale）
- mTLS client cert pin（可选）用于强绑定设备身份
- 域名连接作为推荐：优先保存 device hostname / tailnet name；IP 仅作为 fallback（并在 UI 标记风险）

---

## 3) 客户端接入模式（Mode 1 / Mode 2）

参考：`docs/xhub-client-modes-and-connectors-v1.md`

### 3.1 设计点
- 默认 Mode 2（AI + Connectors），用户可选 Mode 1（AI-only）
- Generic Terminal 默认 capability 预设：Full

### 3.2 优势
- Mode 2 才能让 “Secrets / 审计 / Kill-Switch” 覆盖到外部动作

### 3.3 缺点 / 风险
- Generic Terminal 依然可能本机直连绕过 Hub
- 默认 Full 扩大“可请求能力”面（尤其 paid/web）

### 3.4 怎么改（可执行）
- 文案上明确：“Hub 只对经由 Hub 能力的行为强保证”
- 通过 grants + quota + kill-switch 把风险留在 Hub
- 提供可选“全流量代理/Network Shim 指南”（不是强制）

---

## 4) 能力模型：Capabilities（静态）+ Grants（动态）

### 4.1 设计点
- Capabilities：设备允许的 RPC/能力族（例如 `ai.generate.paid`, `connectors.email`）
- Grants：临时授权（TTL + token cap + spend cap + allowlists），可撤销、可审计

### 4.2 优势
- 默认全自动也可控：小额度 auto-approve，异常时 kill-switch

### 4.3 缺点 / 风险
- 规则复杂时容易误配（放行/拦截错误）

### 4.4 怎么改（可执行）
- 所有拒绝/排队必须写 audit（可解释 why）
- capability keys 与 grant keys 固化为 stable string（协议层 + DB 层一致）
- 为 connectors 引入统一的 prepare/commit 语义与 idempotency

---

## 5) Paid models：首次人工一次性授权 + 自动续签

参考：`docs/xhub-client-modes-and-connectors-v1.md`（4.2）

### 5.1 设计点（已确认）
- `ai.generate.paid` 第一次必须人工批准一次
- 批准后在策略内自动批准（等价“自动续签”）

### 5.2 优势
- 不牺牲体验（只打断一次），避免 silent burn

### 5.3 缺点 / 风险
- entitlement 一旦开闸，后续误用仍会烧钱

### 5.4 怎么改（可执行）
- entitlement 里写死 `max_ttl_sec/max_token_cap_per_grant/daily_cap/allowed_models`
- Hub UI 提供“一键暂停 paid”（等同 revoke entitlement）
- 审计里按日聚合成本，触发阈值报警（先本地通知即可）

---

## 6) Connectors：Email（IMAP+SMTP）+ Outbox + UndoSend=30s

参考：`docs/xhub-client-modes-and-connectors-v1.md`（5.5）

### 6.1 设计点（已确认）
- Email connector MVP：IMAP + SMTP
- 默认全自动 commit
- SendDraft -> Outbox job，30s 撤销窗口

### 6.2 优势
- “不牺牲体验”的前提下，显著降低误发不可逆损失

### 6.3 缺点 / 风险
- 仍可能在 30s 后误发；IMAP/SMTP 凭证风险高；不同邮箱服务商兼容复杂

### 6.4 怎么改（可执行）
- 推荐 app password + TLS；凭证只存 Hub Vault（加密）
- 支持域名 allowlist/denylist（可选，不默认拦）
- v2 增加 OAuth（Gmail/Graph）提升权限粒度与安全性

---

## 7) 记忆系统：5 层 + Memory-Core 治理

参考：`docs/xhub-memory-core-policy-v1.md`

补充边界：

- 产品层可以继续沿用 `Memory-Core Skill` 命名。
- 实现边界上，`Memory-Core` 应理解为 Hub 内建 governed rule asset，而不是一个拥有跨层直写权限的单体执行 AI。
- memory 维护模型由用户在 X-Hub 上显式选择；Hub 通过 `memory_model_preferences -> Memory Scheduler -> Memory Worker -> Writer + Gate` 执行这条控制面。

### 7.1 设计点
- Raw Vault / Observations / Longterm / Canonical / Working Set
- Progressive Disclosure（Search -> Timeline -> Get）
- 多 AI 分工，但单写入者 + 强校验 + 全审计 + 可回滚
- `Memory-Core` 只管规则、门禁与晋升纪律；用户选模型，Scheduler 派单，Worker 执行，Writer + Gate 落库

### 7.2 优势
- 可扩展、可控、可解释；不会因为“记忆越多越强”而污染上下文

### 7.3 缺点 / 风险
- 实现成本高；晋升器可能误判导致污染；远程模型参与会引入外发风险
- 如果 `memory_model_preferences` 不是唯一真相源，Hub/worker/UI 可能各自保留一套模型选择逻辑，最后出现静默切模与不可复现实验

### 7.4 怎么改（可执行）
- promotion 先 shadow mode + 人工确认，再逐步全自动
- `secret` 默认禁止远程外发（fail-closed）
- 所有 canonical/skill 晋升必须带 provenance（证据指针）并可回滚
- 把 `memory_model_preferences` 冻结成唯一模型选择真相源，route explain 固定进 audit / doctor / diagnostics
- 所有模型结果都先进入 candidate / structured output，再由 `Writer + Gate` 决定是否落 durable truth

---

## 7.5) 多模型并行编排（X-Terminal Orchestrator + Supervisor）

参考：`docs/xhub-multi-model-orchestration-and-supervisor-v1.md`

### 7.5.1 设计点
- X-Terminal 并行调用多个模型（worker）处理不同 project
- Supervisor 模型统一对用户输出（用户只跟 Supervisor 对话）
- Hub 提供统一的审计/额度/kill-switch；并用 project_id/thread_id 实现项目隔离

### 7.5.2 优势
- 同一时间推进多个项目，且用户交互成本最低（单入口）
- worker 输出结构化可被监督与复用（可进一步进入 Hub 的 candidate / review / promotion 流水线）

### 7.5.3 缺点 / 风险
- 成本与资源放大（并发 4 路）
- 跨项目信息泄漏风险（Supervisor 汇总时可能混淆）
- 质量不一致（worker 输出不合规、幻觉、缺证据）

### 7.5.4 怎么改（可执行）
- 并发与预算硬限制（max_parallel/per_model_inflight/max_tokens/timeout）
- worker 强制 JSON report schema + Orchestrator 结构校验（失败直接标记并重跑/降级）
- Supervisor 默认只看 worker_report；需要证据时走 progressive disclosure（Search/Timeline/Get）

---

## 8) Skills：不要把可执行代码放进 Hub Core

### 8.1 设计点
- Skills 是生产力核心，但 Hub Core 不应执行第三方脚本

### 8.2 优势
- 降低 Hub 被攻破的可能性（不把 Hub 变成“万能执行器”）

### 8.3 缺点 / 风险
- 终端执行 skills 仍可能被篡改/投毒

### 8.4 怎么改（可执行）
- Hub 只做 skills 分发与签名校验（内容寻址 hash + 签名 + 版本锁定）
- 执行放在 X-Terminal 或独立 Runner（沙箱/容器）
- 高风险操作统一改为调用 Hub Connectors（不要让 skill 自己拿 key 自己联网）

---

## 9) Audit + Kill-Switch（体验不牺牲的安全兜底）

### 9.1 设计点
- Audit：对 AI/Web/Grants/KillSwitch/Connectors 全量记账（默认 metadata-only）
- Kill-Switch：全局冻结 models/network/connectors

### 9.2 优势
- 出事可一键止血；事后可追责复盘

### 9.3 缺点 / 风险
- 审计也可能泄漏隐私；kill-switch 对终端本机直连无能为力

### 9.4 怎么改（可执行）
- 审计字段分级脱敏；保留周期与归档；可选 hash chain 防篡改
- 对外承诺明确“仅对经由 Hub 的能力强保证”

---

## 10) 存储加密 / 密钥管理 / 备份恢复（当前最大缺口之一）

### 10.1 设计点
- Secrets/Vault 必须加密 at-rest
- Canonical/Longterm/Raw Vault 逐步加密
- 密钥轮换与恢复流程必须可操作

### 10.2 优势
- Hub 丢盘/被拷贝时的抗性显著提升

### 10.3 缺点 / 风险
- 实现门槛高；密钥丢失会导致不可恢复的数据丢失

### 10.4 怎么改（可执行）
- 先做 Vault（Keychain/Secure Enclave 管主密钥）
- 再扩展到 DB（SQLCipher 或表级加密）
- 做可验证备份（加密备份 + 恢复演练）
