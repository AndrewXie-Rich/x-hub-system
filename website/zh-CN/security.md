# 信任模型

<p class="lead">
一台被入侵的终端。一个恶意网页。一个有问题的 MCP server。一次提示词注入。今天任何一个都能把你的整个 AI 拉下水。X-Hub 的工作就是让它们做不到。这一页讲清楚:我们在哪里拦、用什么拦、以及我们诚实地拦不住什么。
</p>

<div class="preview-note">
  <strong>公开安全立场</strong>
  这一页描述公开信任模型和产品方向。它会讲清楚安全链路，但不会把每个内部实现边界和仍在演进的控制细节全部公开。
</div>

## 简短版本

X-Hub 把安全当作第一产品优势：

- **首次配对保持本地**：新的高信任终端应在同一个 Wi-Fi 下建立信任，而不是从任意远程表面直接绑定
- **Hub 是信任根**：终端可以执行，但不拥有策略、授权、记忆真相、路由真相或最终控制权
- **缺失信任就 fail-closed**：无 readiness、配对过期、授权目标含糊、签名无效、授权过期，都应该阻断而不是猜测
- **高风险动作必须可验证**：不可逆或外部副作用路径应走 Hub-generated manifest、Hub signature、SAS、grant 和 audit
- **记忆与技能受治理**：长期记忆、X-Constitution、skill package、pin、vetting、grant 和 revoke 都在 Hub 治理下
- **本地模型和付费模型共享策略平面**：local runtime 与 provider API 都受 route truth、quota posture 和 capability grant 约束

## 安全链路

| 阶段 | X-Hub 尝试强制的事情 |
| --- | --- |
| 配对 | 新高信任客户端从同 Wi-Fi 本地配对、设备身份、token 状态和显式撤销路径开始 |
| 认证 | device UUID、token 状态、可选证书、allowed network posture 和来源限制都是安全输入 |
| 治理 | 策略、授权、额度、路由真相、记忆真相、readiness 和能力范围在 Hub 检查 |
| 执行 | 终端、本地 runtime、付费 API、skills、channels 和 connectors 只在 Hub 允许的范围内行动 |
| 验证 | 签名 manifest、SAS、拒绝原因、证据引用和审计引用让执行可解释 |
| 恢复 | revoke、grant expiry、provider disable、device freeze 和 kill switch 给操作者回收路径 |

## 为什么首配必须同 Wi-Fi 很重要

配对是分布式 Agent 系统里风险最高的时刻之一。如果远程配对过于便利，攻击者只需要诱导操作者一次，就可能让未知客户端变成可信入口。

X-Hub 的姿态更严格：

- 首次信任应该从本地网络建立，操作者可以对设备和环境有物理层面的判断
- 配对设备拿到的是有边界的身份和 token 状态，而不是宽泛的隐式控制权
- 后续远程访问可以存在，但必须建立在显式设备绑定之上，并且可撤销
- denied source IP、allowed networks、token rotation 和 device freeze 都是运行模型的一部分

这不等于“局域网天然安全”。它降低的是：公开 URL、隧道、聊天通道或复制出来的设置链接成为第一信任根的概率。

## Hub-First 控制权

终端不是最终控制中心。

这个设计选择支撑了后面的整套系统：

- 被攻破的终端不应该能改写 durable memory truth
- plugin 或 skill 不应因为被导入就继承高权限
- 远程通道不应变成影子控制平面
- 本地 UI 状态不应成为高风险执行的数据真相
- 云 provider 默认配置不应静默持有策略、路由真相或运行证据

Hub 是长期控制权汇聚的地方：配对、授权、模型路由、模型准备状态、记忆治理、技能信任、额度状态、审计和应急控制。

## X-Constitution 作为安全层

X-Constitution 是系统的价值与行为约束层。它被设计为高于任何单个任务目标：

- 作为 durable governed memory 被 pinned
- 只通过授权路径更新
- 在高风险、价值冲突或策略敏感场景触发式注入
- 与 policy、grant、audit、least privilege 和 fail-closed 一起生效

它的目标很实际，不是装饰性口号。它让系统在活跃模型临场发挥之前，就把 prompt injection、破坏性误操作、凭证外泄、恶意 skill 和静默越权当作高风险路径处理。

如果想看隐藏网页指令、恶意 skill、假完成、远程诱导配对、支付或外发 payload 篡改这类更具体的例子，请看单独的 [X 宪章页面](/zh-CN/constitution)。

## 记忆安全

记忆不只是上下文。在 Agent 系统里，记忆会影响系统后续相信什么、复述什么、检索什么、基于什么行动。

X-Hub 的记忆方向基于五层：

- Raw Vault：原始证据
- Observations：结构化事实和事件
- Longterm：长期文档与约束
- Canonical：紧凑注入真相
- Working Set：短期活动上下文

安全姿态是：

- durable writes 终止在受治理的 Hub 侧路径，而不是任意 terminal-local 状态
- memory maintenance 仍挂在用户选择和 Hub-side gates 上
- evidence-first 和 fail-closed 减少假完成与不可追溯篡改
- X-Constitution 作为 pinned long-term constraint，不会沉入一次性聊天历史

更重要的是，memory read、memory export 和 memory writeback 本身也是安全边界。X-Hub 不把“相关”直接等同于“可见”，不把“抽取到了”直接等同于“可以写入长期真相”，也不把“能进入上下文”直接等同于“能发给远端模型”。

更完整的记忆控制面、五层记忆、角色分层、candidate writeback 和项目恢复解释在 [Governed Memory Control Plane](/zh-CN/memory)。

## Skill 安全

Skill 被当作受治理能力单元，而不是 install-equals-trust 插件。

预期链路包括：

- package manifest
- publisher trust root
- official catalog 和 package pin
- compatibility check 与 package doctor
- 风险执行前 vetting
- grant、deny code、revoke 和 audit

这样 skill 可以成为可复用执行单元，但每个 package 不会自动成为新的信任根。

## 本地模型、付费 Provider 和额度

Local-first 不只是“运行本地模型”。它意味着可信控制平面可以留在用户自己手里。

X-Hub 把本地和付费路线放进同一治理平面：

- 配置模型和实际模型都应可见
- fallback 与 downgrade 应显式展示，而不是静默发生
- provider accounts、OAuth/key 状态和 quota pressure 应对操作者可见
- paid capability 应该可授权、可撤销、可审计，并受 policy 约束
- 敏感工作可以优先走本地模型，同时继续使用同一套 memory、skill 和 audit 姿态

这比把 local models 和 paid APIs 拆成两个互不相干的操作世界更强。

## 高风险动作

对不可逆或外部可见动作,X-Hub 的方向是:

- Hub 创建 `ActionManifest` 或 `TxManifest`
- 终端渲染或执行签名 intent,而不是本地拼接可信 payload
- 确认表面验证 Hub signature 并显示 SAS 类校验
- grant 带 scope、TTL 和 policy constraints
- 执行返回 evidence 和 audit references

这套模式对应的规范是 [`agent-2fa`](https://github.com/AndrewXie-Rich/agent-2fa)。三个风险档位——`notify`、`confirm`、`dual_confirm`——对应到配对 Authorizer Device 上的 per-action 确认(Touch ID、Face ID、voice phrase、passphrase)。提示词注入的 `DROP TABLE prod_logs` 在打到数据库之前先打到配对设备;外发支付在 API call 落地前先打到 Face ID。agent-2fa 独立于 X-Hub——你可以只拿规范,不带走实现。

这个模式适用于支付、外发消息、connector 写入、代码合并、远程命令和其他高后果动作。

## 回执

每次授权动作——以及每次拒绝、降级、超时和升级——都产生用 [Hub Receipt v0.1](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) envelope 签名的回执。回执:

- 把 `subject`(动作、skill 调用、agent-2fa challenge 等)绑定到 `issuer_key_id` 和可验证的签名
- content-addressable,可以嵌入 git commit、IDE 元数据、聊天消息、合规导出
- **X-Hub 之外也能验证**——任何拿到 issuer 公钥的验证者都能验真伪,不必联系 Hub
- 跟 `mcp-trust-registry`(skill 执行回执)和 `agent-2fa`(per-action 确认回执)共用同一个 envelope,所以单一审计链路覆盖两套表面

签名回执把审计从"系统记录了什么"提升到"系统产生了外部可验证 artifact"。这个区别正是审计链路在 EU AI Act / ISO 42001 / SOC2 敏感采购场景里有用的关键。

## 风险模式到控制链路

| 风险模式 | X-Hub 用什么拦 |
| --- | --- |
| 全量文件、邮箱、数据库或记忆读取 | capability scope、project binding、role-aware memory、least privilege、audit |
| 敏感数据外发、上传、Webhook、外部 API | outbound grant、destination allowlist、signed intent、TTL、audit |
| 长期记忆泄露或记忆污染 | five-layer memory、durable write gate、X-Constitution pinned、memory export grant |
| 批量删除、覆盖、系统配置修改 | destructive action preflight、A-Tier、tool policy、manifest、safe-point review、[`agent-2fa`](https://github.com/AndrewXie-Rich/agent-2fa) `dual_confirm` |
| shell/root 命令执行和装依赖 | command allow/deny policy、working-directory scope、runtime readiness、evidence refs |
| 插件/Skill 供应链攻击 | manifest、publisher trust、package pin、compat doctor、vetting、revoke、[`mcp-trust-registry`](https://github.com/AndrewXie-Rich/mcp-trust-registry) attestation chain |
| 公网暴露、弱认证、错误配对 | same-Wi-Fi first trust、device identity、token rotation、allowed source、device freeze |
| 横向移动和提权 | scoped grants、connector boundary、secret policy、audit trail、kill-switch |
| 目标漂移、过度执行、成本爆炸 | execution budget、quota posture、TTL、heartbeat anomaly、Supervisor review、clamp |
| 假完成、编造日志、弱证据收口 | evidence-first memory、pre-done review、audit refs、done-candidate state、[Hub Receipt](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) envelope |
| 身份冒充、越权签批、转账或外发 | actor binding、grant target、SAS、approval surface、signed manifest、`agent-2fa` 配对设备确认 |
| 审计缺失和事后不可追溯 | Hub-side audit、deny reason、evidence refs、grant history、doctor/explainability、签名 Hub Receipts |

这些控制不会把所有风险消灭，但会把风险从“一个活跃 Agent 私下决定”变成“Hub 可解释地放行、拒绝、降级、等待确认或停止”。

## 它改善了什么

| 常见默认形态 | X-Hub 立场 |
| --- | --- |
| 活跃客户端成为信任根 | Hub 继续是信任根 |
| 远程配对被当成便利功能 | 首次信任保持本地且显式 |
| 插件安装等于能力信任 | Skill 是带 vetting 和 revoke 的受治理 package |
| 记忆在客户端和 prompt 之间漂移 | Durable memory truth 留在 Hub 治理下 |
| 本地与付费模型分裂治理 | 两条路线进入同一个模型和额度平面 |
| Auto mode 隐藏风险 | Autonomy、review、heartbeat、grant 和 clamp 保持显式 |
| 失败被平滑掩盖 | 缺失信任 fail-closed，并产生运行时真相 |

## 剩余风险

X-Hub 不声称绝对安全。本地入侵、恶意文件、实现缺陷、凭证泄露、操作者误操作和 provider 侧事故仍然可能存在。

这套架构的价值在于把风险约束在：

- 更小的风险扩散范围
- 更清楚的控制权边界
- 可撤销的 device 与 grant 状态
- 更可见的 runtime truth
- 更强的 audit 与 recovery 路径
- 更少依赖“当前哪个 prompt 或终端处于激活状态”

这就是安全主张：不是“AI 永不失败”，而是“AI 执行应该在受治理边界内失败”。
