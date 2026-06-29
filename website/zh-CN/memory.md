# Governed Memory Control Plane

<p class="lead">
你的 AI 的记忆,不该住在 AI 里。从 Claude 切到 GPT 时,你的项目上下文不该消失。AI 说任务完成时,证据不该只活在它自己的聊天历史里。工具检索记忆时,该读什么应该用户决定——不是模型。X-Hub Memory 就是把这些事都做了的那一层。
</p>

<div class="preview-note">
  <strong>控制面定位</strong>
  X-Hub Memory 的优势不是比普通 memory 更会“记住一句话”，而是更适合高风险、长周期、多角色、多项目的 agentic coding 和 personal assistant 场景：记忆进入模型前先经过 Hub 的权威、策略、审计和导出边界。
</div>

## 为什么 Memory 是核心能力

Agent 的长期能力很大程度取决于记忆。如果记忆只是聊天窗口里的摘要，系统很快会遇到几个问题：

- 错误内容被长期保存，后续继续污染决策
- 重要约束被压缩掉，模型只记得“要完成任务”
- 项目证据、用户偏好、组织规则和临时对话混在一起
- 不同角色看到同一堆内容，既浪费 token，也增加泄漏风险
- 终端或插件可以影响长期事实，安全边界变弱

X-Hub 的做法是把记忆作为 Hub-first 的治理对象。普通 memory 关注“模型能不能记住”；X-Hub Memory 更关注“谁有权让模型记住、读取、导出、修改和遗忘”。

## 不是普通 Memory

很多 AI memory 系统主要优化“捕获和召回”：总结对话、嵌入文档、搜索历史事实，再把相关片段喂给模型。这很有用，但当 AI 能操作工具、推进项目、使用付费模型、从远程通道接入时，仅有召回是不够的。

X-Hub 的定位不同：Memory 是安全和运行时真相的一部分。

| 普通 Agent Memory | X-Hub Governed Memory |
| --- | --- |
| 自动记住对话和偏好 | 写入先成为 candidate，不能直接污染长期真相 |
| 向量检索后塞回 prompt | 经过 role、policy、scope、export gate 后装配 |
| agent 可读写 memory block | X 宪章和 policy core 不作为普通 block，而是固定内核和 Hub policy |
| IDE 或客户端本地记忆可主导上下文 | XT 本地 memory 只是 cache、fallback、edit buffer |
| 关注 recall 准确率 | 同时关注权限、证据、审计、撤销和导出边界 |

所以 X-Hub 的目标是模型通用的记忆控制面：同一套 Memory 可以服务本地模型、付费模型、Supervisor review、Project AI execution、skill 和远程通道，同时不让任何单一客户端变成新的权威源。

## 控制面

市面上很多 memory 是“存储 + 检索 + prompt 注入”一锅。X-Hub 把它拆成四层：

| 层 | 作用 | 为什么重要 |
| --- | --- | --- |
| Truth | Hub-first durable memory truth | XT 本地记忆只能是 cache、fallback、edit buffer，不能自己变成真源 |
| Serving | role-aware context assembly | Supervisor、Project Coder、个人助手和远程通道拿到的 memory pack 不一样 |
| Governance | policy、grant、X 宪章、export gate、candidate approval | 相关不等于可见，能读不等于能外发，能抽取不等于能写入 |
| Explainability | selected / omitted trace、readiness、doctor、audit evidence | 让系统能解释这轮为什么选了这些记忆、拒绝了哪些记忆、是否具备运行条件 |

五层结构解决的是“记忆怎么沉淀”；治理控制面解决的是“谁能读、谁能写、怎么解释、怎么撤销”。

## 五层记忆

| 层 | 作用 | 为什么重要 |
| --- | --- | --- |
| Raw Vault | 保存原始证据、事件和输入 | 后续可以追溯，不靠模型自述 |
| Observations | 把原始材料整理成结构化事实 | 降低噪音，便于审查和升级 |
| Longterm | 保存长期目标、架构、约束和文档型记忆 | 让系统拥有稳定背景，而不是每轮重猜 |
| Canonical | 保存少量高置信、可默认注入的关键事实 | 提高效率，减少上下文污染 |
| Working Set | 当前任务真正需要的活动上下文 | 让 Project AI 聚焦眼前执行 |

## 核心优势

<div class="story-grid">
  <div class="story-card">
    <span>Policy &gt; Prompt</span>
    <strong>约束不是 prompt 里的一句提醒</strong>
    <p>raw evidence、remote export、Project Coder personal memory 等路径应先过 policy 和 readiness。缺少权限或边界不清楚时，记忆装配应 fail closed。</p>
  </div>
  <div class="story-card">
    <span>Hub Truth</span>
    <strong>长期真相回到 Hub</strong>
    <p>XT 本地 memory 被定位成 cache、fallback 和 edit buffer。长期事实、项目真相和治理约束不能由本地 IDE 或终端私自变成最终来源。</p>
  </div>
  <div class="story-card">
    <span>Candidate Writeback</span>
    <strong>抽取不等于污染长期记忆</strong>
    <p>模型或 extractor 产出的新记忆应先成为 candidate，经过 review、approval、policy 和 evidence 后再 active，避免自动写入造成长期污染。</p>
  </div>
  <div class="story-card">
    <span>Role-aware</span>
    <strong>Supervisor 和 Coder 不吃同一份上下文</strong>
    <p>Supervisor 可以看 personal、project、cross-link、review 维度；Project Coder 默认 project-domain-first，避免个人记忆污染项目执行。</p>
  </div>
  <div class="story-card">
    <span>Continuity Floor</span>
    <strong>近期原始对话是底线</strong>
    <p>不是所有东西都应过早摘要化。recent raw / recent project dialogue floor 解决的是“刚才那步忘了”的真实体验问题。</p>
  </div>
  <div class="story-card">
    <span>证据优先</span>
    <strong>长期事实要能回到证据</strong>
    <p>测试结果、用户决定、项目状态和约束不应该只来自模型总结。X-Hub 让关键记忆能关联 evidence、audit 和原始材料。</p>
  </div>
  <div class="story-card">
    <span>Doctor</span>
    <strong>可审计、可诊断</strong>
    <p>memory readiness、candidate count、selected / omitted trace、shadow compare、cutover readiness 和 Doctor evidence 应是 machine-readable，而不是靠人肉读日志。</p>
  </div>
  <div class="story-card">
    <span>Local-first</span>
    <strong>先安全和权威，再智能和体验</strong>
    <p>Rust object store、derived index、candidate queue 和 gateway 先把 authority、policy、evidence 做稳，再继续叠 semantic retrieval、temporal graph 和 Memory Inspector。</p>
  </div>
</div>

## 当前真实进度

X-Hub 仍处在公开技术预览阶段。下面列的是已经可用或预览运行中的底座；仍在规划和打磨的层单独列出。

已经可用或预览运行中的部分：

- Rust memory object 存储、对象历史和 readiness 报告
- XT project canonical memory 优先同步到 Rust memory object
- Rust memory gateway prepare 路径，用于受策略约束的上下文装配
- 基于活跃项目 memory object 的 lexical / hybrid retrieval，并带 explainable evidence
- Supervisor 和 Project AI 的 role-aware XT memory assembly
- heartbeat、review、route、memory 诊断进入 Doctor 证据面
- 受治理 writeback candidate：抽取出的 memory 写入先成为候选，再经过 review/approval 才能 durable promotion
- remote export / prompt gate 设计主线已经把“能装进上下文”和“能外发给远端模型”拆开治理

仍在继续扩展的部分：

- semantic embeddings 和更深层 rerank
- 覆盖所有运行面的统一 Observations / Longterm 底座
- 面向用户的 Memory Inspector，用来查看 candidate、approval 和 lineage
- Rust model-call gateway authority；当前 Rust memory gateway 仍是 prepare-first
- 完全移除所有 legacy local / Node memory authority 路径

## 记忆写入也是签名回执

每次穿过 Writer + Gate 边界的 durable 写入都产生 [Hub Receipt v0.1](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) envelope:谁写的、用什么证据、走的哪条策略、什么被晋升、什么被拒。回执:

- **X-Hub 之外也能验证**——任何拿到 issuer 公钥的审计方都能验真伪,不必联系 Hub
- 跟 `mcp-trust-registry` 的 skill 回执、`agent-2fa` 的 per-action 回执共用同一 envelope,所以 memory writeback 是同一条审计链路的一部分,不是孤岛
- 可以嵌入 commit、IDE 元数据、合规导出——支撑 EU AI Act / ISO 42001 / SOC2 敏感采购场景

记忆真相不再是"系统记录了一笔写入";而是"系统产生了一个外部可验证 artifact,说明写了什么、为什么写、以谁的权威写"。

## Memory 和 X-Terminal 怎么配合

Project AI 需要的是“当前要做什么、手上有哪些证据、下一步怎么验证”。Supervisor 需要的是“这个项目有没有偏航、是否有更好的路线、多个项目谁更需要注意”。

所以 X-Hub 不把 A-Tier、S-Tier 和记忆深度揉成一个总开关：

- A-Tier 只决定 Project AI 的执行上限和项目记忆上限
- S-Tier 只决定 Supervisor 的监督强度和 review 记忆上限
- Recent context、Project Context Depth、Review Memory Depth 继续是独立控制项
- configured、recommended、effective 三值让系统能解释“为什么这轮看到这些”

这让系统既能有长期记忆，又不会每次把全部历史灌给每个模型。

## 一个具体例子

如果 Project AI 说“任务已完成”，普通 Agent 可能把这句话直接写进总结。

X-Hub 的记忆链路会更严格：

1. Raw Vault 保留原始输出、命令、测试和日志。
2. Observations 记录可验证事实：哪些测试跑过、哪些失败、哪些文件改了。
3. Supervisor 在 pre-done review 时检查证据强度。
4. Canonical 只保存真正稳定的完成状态。
5. 如果证据弱，User Digest 看到的是“候选完成，需要补验证”，而不是假完成。

这就是受治理记忆的价值：它不是让 AI 记得更多，而是让 AI 记得更可靠。

继续看：
[X-Terminal](/zh-CN/x-terminal)、[X 宪章](/zh-CN/constitution)、[治理模型](/zh-CN/governed-autonomy)。
