# X-Hub分布式安全交互系统 - 精简版白皮书（Github发布版，2026-03-02）

## 0. 一句话定义

X-Hub 不是“更会聊天的 AI”，而是一套把 **不可信终端** 变成 **可托付执行入口** 的分布式安全交互系统：
**AI能力、记忆、授权、审计、支付与密钥治理统一收敛到 Hub，终端仅做轻量交互。**

## 0.1 为什么现在值得兴奋

这件事已经不只是白皮书叙事。

在当前公开预览版本里，已经能看到几条真正有冲击力的现实进展：

- 本地模型与付费 GPT 类模型开始进入同一 Hub 控制面；
- X-Terminal 开始真实显示配置模型、实际模型与降级路径；
- Supervisor 与 Project coder 已进入可运行的早期执行阶段；
- 打包路径正在从源码试玩走向可复制的 App 体验。

这意味着 X-Hub 最核心的价值主张已经开始成立，而不是停留在口号层。

## 0.2 当前公开状态

X-Hub 当前仍是 **公开测试版 / public tech preview**：

- 基本能力已经逐步跑通；
- 产品体验与细节仍未完善；
- 部分能力仍在快速迭代；
- 现在正是最适合外部贡献者参与塑形的阶段。

---

## 1. 核心价值（给用户与团队）

- **安全可控**：即使终端被入侵，关键动作仍需通过 Hub 签名、授权门禁与跨端校验。
- **多AI统一治理**：本地模型与付费模型都走 Hub 控制面，统一受 grants/quota/audit/kill-switch 约束。
- **长期稳定执行**：五层记忆（Raw/Observations/Longterm/Canonical/Working Set）降低上下文污染。
- **价值约束不漂移**：X-Constitution 作为 pinned 约束，确保“能做不等于该做”。
- **并行提效 + 低Token**：多泳池拆分 + 反阻塞续推 + 三段式提示词，在质量可控前提下提升吞吐、降低Token浪费。
- **可审计可回滚**：关键链路 machine-readable，可追溯、可复核、可回放、可回滚。

## 1.1 为什么现在欢迎贡献者

现在欢迎贡献，不是因为系统已经做完，而是因为它还没有被过早固化。

当前最值得加入的方向包括：

- Hub-first 运行时与安全边界；
- provider 兼容与模型路由；
- Supervisor 多项目编排；
- 语音与操作员体验；
- 测试、发布门禁与产品化打包。

对真正关心下一代 Agent 基础设施的人来说，现在加入的价值远大于后期做表层修补。

---

## 2. 系统设计总览

### 2.1 信任边界

- **唯一可信核心：X-Hub**
  - AI 推理与模型路由
  - 记忆治理与价值约束
  - 授权审批与支付管控
  - 审计证据与应急控制
- **终端默认不可信**
  - 普通终端：轻量调用，不参与核心安全决策
  - X-Terminal：增强交互与项目协同，但主状态与安全决策仍在 Hub

### 2.2 五层记忆（Memory）

1. Raw Vault（原始证据层）
2. Observations（结构化观测层）
3. Longterm（长期文档层）
4. Canonical（规范注入层）
5. Working Set（短期工作集）

配套原则：
- `fail-closed`（证据不足默认阻断）
- `evidence-first`（结论必须有机读证据）
- `deterministic`（同输入同输出可复现）

### 2.3 多AI能力管理（本地/付费）

- 同一项目可按任务混合编排本地模型与付费模型；
- 付费能力支持“首次人工一次性授权，后续策略内自动续签/自动放行”；
- 高风险能力统一走主链：`ingress -> risk -> policy -> grant -> execute -> audit`；
- 缺授权、授权过期、请求篡改均 fail-closed。

### 2.4 X-Constitution（价值观宪章）

- 作为长期记忆层固定约束（pinned），由 Hub 统一管理；
- 在高风险/价值冲突场景触发式注入，约束 AI 决策边界；
- 更新需受授权与审计约束，避免策略漂移与静默越权。

它的目标，是把正确价值观刻进 AGI 的“行为基因”中，使系统在面对现实 Agent 常见风险时不再只靠模型临场判断。具体来说，就是尽可能避免以下情况出现：网页隐藏指令诱导密钥泄露，误解用户意图后删除邮件或生产数据，恶意 Skills 窃取凭证或植入后门，以及底层漏洞被利用后一路扩散成大范围失控。X-Constitution 并不单独替代所有安全工程，但它会把这些路径前置为高危红线，并与授权、审计、最小权限和 fail-closed 机制一起收紧系统边界。

---

## 3. X-Terminal Supervisor 创新（本系统差异化核心）

### 3.1 多泳池自适应拆分（Pool -> Lane）

Supervisor 按复杂度、模块图、依赖密度、风险面、Token 预算自动拆分：
- 一级：`pool`（模块/风险域）
- 二级：`lane`（最小可验收子任务）

支持三档策略：
- `conservative`（稳态）
- `balanced`（默认）
- `aggressive`（冲刺）

### 3.2 用户介入等级可选

- `zero_touch`：尽量不打断，仅关键授权打断
- `critical_touch`：关键节点介入（默认）
- `guided_touch`：高频协同

### 3.3 三段式提示词（Token 最优）

所有泳道提示词统一为：
- **Stable Core**（固定规则与边界）
- **Task Delta**（本轮增量目标）
- **Context Refs**（引用 ID，不贴全文）

目标：在质量不降前提下，减少提示词冗余与 Token 浪费。

### 3.4 反阻塞自动续推（Anti-Block Orchestration）

通过以下链路减少“互等卡死”：
- wait-for dependency graph
- dual-green dependency gate（`contract_green + runtime_green`）
- dependency escrow package
- unblock router（blocker 转绿后即时指导等待泳道续推）
- block SLA escalator（超时自动升级）

---

## 4. 安全机制（执行级）

### 4.1 高风险动作统一协议

- Hub 生成并签名 `ActionManifest/TxManifest`
- 终端仅可展示/执行签名对象，不可本地拼接高风险参数
- 跨端确认使用 SAS（一次性校验码）

### 4.2 操作安全硬规则

- 高风险无授权：禁止执行
- Gate 未过/证据不足：禁止宣告完成
- require-real 路径：禁止 synthetic/smoke 证据冒绿
- 禁止跨泳道直接改写他人状态

### 4.3 应急与恢复

- 全局 Kill-Switch
- 授权一键回收
- 审计追踪与责任归因
- 回滚点强制定义（工单级）

---

## 5. 当前工程状态（截至 2026-03-02）

### ✅ 已可用

- Hub 统一会话通道（auto/grpc/file，gRPC优先）
- 多AI能力管理主链（本地/付费统一授权与审计框架）
- Supervisor heartbeat 态势汇总
- 并发调度公平队列（压测收益已验证）
- Command Board v2 单文件分区协作（CR/claim TTL/7件套）
- 用户介入等级 + Auto-Continue 协议
- X-Constitution 触发式注入基础链路

### 🟡 推进中

- 多泳池自适应拆分执行链路
- 三段式提示词编译与上下文胶囊优化
- 反阻塞全链路（wait-for/dual-green/unblock/SLA）
- Observations/Longterm 全量落地
- Connector 与端到端治理闭环

### 🟡/🔵 路线图

- 存储加密扩面（Raw/Observations/Longterm/终端本地）
- 冷存储 Token 授权更新与回滚体系完善
- 更强支付执行侧安全（硬件钱包/多签/阈值签名）

---

## 6. 源码可见与生态策略（FSL-1.1-MIT）

X-Hub 当前采用 `FSL-1.1-MIT` 的源码可见许可模型。目标不是把当前仓库状态描述成 OSI 开源，而是在保留代码可读、可评审、可协作的同时，降低直接拿现有代码做同款商业竞争的风险：

- 透明发布：`CHANGELOG` + `RELEASE`
- 协作治理：Issue/PR 模板、CODEOWNERS、Dependabot
- 门禁可机判：Gate/KPI/证据矩阵
- 生态兼容：支持 Agent Skill 兼容桥接（在安全边界内）
- 未来方向：每个版本按 `LICENSE` 在发布满两周年后转换为 MIT；若未来版本要进一步放宽许可，会在仓库治理文件中明确宣布，而不是靠隐含承诺或贡献人数阈值触发

---

## 7. 典型落地场景

- 家庭与个人：低打断、多设备连续协作
- 中小企业：多项目并行推进 + 可审计交付
- 支付与高风险执行：Manifest + SAS + 授权门禁
- 具身机器人：现实证据 -> 数字授权 -> 安全执行闭环

---

## 8. 结语

X-Hub 的目标是把 AI 从“会回答”升级到“可托付执行”：
在保证安全、可审计、可回滚、可约束的前提下，实现多 AI 并行协作与高质量自动推进。

如果一句话总结：
**X-Hub = 安全中枢（Hub） + 自治编排（Supervisor） + 价值约束（Constitution） + 证据门禁（Gate） + 低Token高质量协作。**
