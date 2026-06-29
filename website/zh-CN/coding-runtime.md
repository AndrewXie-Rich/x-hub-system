# Coding Runtime

<p class="lead">
Cursor 和 Claude Code 在第 1 分钟表现很好。当 AI 跑了 5 个小时,你回来发现工作做了一半、没有证据、有合并冲突、"我应该做完了吧?"——这是它们停下、X-Hub 接上的地方。这一页讲那段弧线的后半段。
</p>

<div class="preview-note">
  <strong>IDE 用 IDE agent。围绕 IDE 的事情用 X-Hub。</strong>
  X-Hub 不和 Cursor / Cline / Aider 抢内联编辑。它坐在它们后面回答:这次 run 跑到哪一步、"完成"靠什么证据、错的检查点怎么回滚。
</div>

## 一句话

X-Hub-System 更适合 **复杂项目稳着往前推**，而不是只追求“小活秒出”。

它最强的地方，是第 50 分钟、第 5 小时、第 5 天之后仍然能回答：

- 当前 run 到哪一步了？
- 哪些 step 已经验证？
- 哪些地方 blocked？
- Supervisor 做过什么纠偏？
- 哪些授权、额度和能力被用过？
- 如果中断，能从哪里恢复？
- 最终完成有没有证据？

## 强在哪

<div class="story-grid">
  <div class="story-card">
    <span>连续推进</span>
    <strong>不依赖一轮长上下文硬撑到底</strong>
    <p>系统方向是 run、checkpoint、resume、retry、recovery。项目可以跨设备、跨时段继续推进，不把全部状态押在当前聊天窗口。</p>
  </div>
  <div class="story-card">
    <span>治理</span>
    <strong>A-Tier、S-Tier、Heartbeat 和 Review 分开</strong>
    <p>执行上限、监督深度、复盘节奏和干预方式不是一个模糊自动化滑杆。这样项目可以更自动，但不必更失控。</p>
  </div>
  <div class="story-card">
    <span>分层记忆</span>
    <strong>Supervisor 和 Coder 不吃同一份上下文</strong>
    <p>Supervisor 看更宽，用来判断方向和风险；Project AI / Coder 看更聚焦，用来完成当前 step 和验证。战略脑和执行脑不会互相污染。</p>
  </div>
  <div class="story-card">
    <span>可恢复</span>
    <strong>失败不是只能重开一段聊天</strong>
    <p>blocked、evidence、review、guidance、ack、run truth 都可以回到 Hub。中断后能判断是继续、重试、修路由、补上下文还是等待用户裁决。</p>
  </div>
  <div class="story-card">
    <span>审计边界</span>
    <strong>代码执行仍在 Hub 治理下</strong>
    <p>repo 修改、build/test、skill 调用、模型使用、额度压力和高风险动作都走 grant、policy、audit 和 kill-switch 控制链。每个授权动作产生签名 <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md">Hub Receipt</a>——在 IDE 之外也能验证。</p>
  </div>
  <div class="story-card">
    <span>证据收口</span>
    <strong>Done 不是模型一句话</strong>
    <p>完成回到 build、test、diff、日志、截图、doctor、review note 和签名回执。证据不足时,它只能是 done candidate。审计员读的是回执链,不是聊天历史。</p>
  </div>
</div>

这也是 X-Hub Coding Runtime 和普通单会话 coding assistant 的差异之一：连续推进不靠一个越来越长的 prompt，而靠 Hub-governed memory control plane。Supervisor、Project Coder、个人助手和远程通道可以拿到不同的 memory pack；写入先进入 candidate；证据、导出和审计继续可追踪。

## 当前还在产品化什么

公开版本应该诚实：这套系统的优势很清楚，但它不是所有 coding 场景的最低摩擦选择。

| 方向 | 当前产品化重点 |
| --- | --- |
| 小任务低摩擦体验 | 快速改一两个文件、写小 demo、UI spike，要保留更轻的模式，不能所有事都走重治理 |
| A4 执行面 | browser、device、connector、extension、丰富 skill result contract 和 plan graph 仍在继续收口 |
| 更厚验证链 | 不只看命令退出码，还要把 build、test、e2e、evidence、done contract 和 release gate 串起来 |
| Guidance Ack 闭环 | Supervisor 建议需要结构化进入 Coder 执行链，ack、defer、reject 都要可追踪 |
| Hub Run Scheduler | run truth、wake、grant、audit、clamp 和 recovery 需要成为更强的一等事实源 |

这意味着 X-Hub-System 不应该被包装成“最快的快速原型工具”。它应该被理解成：**长期软件项目的受治理执行系统**。

## 实际工作中 Coder Loop 长什么样

X-Hub 的 coding runtime 内部有分层(harness、delivery loop、checklist loop、spec boundary)——但用户看到的形状更简单:

- **快速原型:** fast mode。轻量 checklist、轻量 review。10 分钟的小活,不必付完整治理的代价。
- **常规特性:** default mode。Agentic delivery + checklist execution + 高风险点上加轻量 spec。这是大部分工作。
- **长周期或高风险项目:** full mode。强 spec 边界、深度 Supervisor review、A3/A4 执行 + 紧 S2/S3 监督。

系统挑默认值;按项目可以覆盖。

## A-Tier / S-Tier 如何映射 coding 场景

| 场景 | 推荐模式 | A-Tier | S-Tier | 说明 |
| --- | --- | --- | --- | --- |
| 快速原型 / 小 demo | Fast Prototype + 轻量清单执行 | A1 / A2 | S1 | 快速出结果，限制在项目 scope 内 |
| 单功能开发 / 中型 feature | Agentic Delivery + Checklist Loop + 轻量 Spec | A2 / A3 | S2 | 默认主力模式 |
| 中大型项目持续推进 | Harness + Agentic Delivery + Checklist Loop + Spec-first 边界 | A3 | S2 / S3 | 最适合 X-Hub-System 的主场景 |
| 高风险自动执行 | Harness + Agentic Delivery + 强 Spec-first 边界 | A4 | S3 | 只有 runtime readiness、grant、policy 和 recovery 满足时才上 |
| 从零到一产品 | Product Discovery -> Agentic Delivery -> Spec-first 边界 | A1 -> A2 -> A3 | S2 / S3 | 先收敛需求，再进入执行 |

默认 coding 主模式不应该是纯快速原型，也不应该是过重的多角色流程，而是：

**A2/A3 + S2/S3 下的 Governed Agentic Delivery。**

## Project Coder Loop 应该长什么样

一个成熟的 Project Coder Loop 至少需要这些步骤：

1. 接收目标、scope、A/S 档位和 done contract。
2. 生成 step list，不把任务只留在自然语言愿望里。
3. 每个 step 执行后做验证。
4. 失败时按 retry budget 重试。
5. 超出预算时捕获 blocked reason，而不是无限循环。
6. 到 checkpoint 时写 evidence 和 run truth。
7. 接收 Supervisor guidance，并 ack、defer 或 reject。
8. 完成前做 pre-done review。
9. 只有证据成立时进入 delivery closure。

这就是 X-Hub-System 在 coding 上的核心差异：不是“模型更会写代码”这一句，而是“写代码这件事被放进了可持续、可复盘、可恢复的运行结构里”。

## 什么时候轻量就够了

不是所有任务都值得上完整治理流程。

- 小 UI polish
- 一次性脚本
- 低风险 demo
- 快速 API spike
- 本地临时工具

这些应该走更轻的 Fast Prototype Mode，仍受项目 scope 和基础安全限制，但不强行要求完整 spec、深 review 和长周期 heartbeat。

真正需要完整治理的，是跨边界、难回滚、高风险、多人协作、会长期运行的 coding 工作。

继续看：
[X-Terminal](/zh-CN/x-terminal)、[治理模型](/zh-CN/governed-autonomy)、[记忆控制面](/zh-CN/memory)。
