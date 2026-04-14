# X-Hub v1 下一阶段 4 周执行计划 v1

- status: active
- updated_at: 2026-03-23
- owner: Product / Hub Runtime / X-Terminal / Supervisor / Security
- purpose: 把当前 public tech preview 的未完成部分压缩成一条可执行主线，避免继续在多方向同时膨胀
- related:
  - `README.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
  - `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
  - `docs/WORKING_INDEX.md`
  - `x-terminal/work-orders/README.md`

## 0) 一句话目标

未来 4 周不追求“再加更多能力”。
未来 4 周的目标是：

**把 X-Hub v1 的 Preview Spine 收口成一条稳定、诚实、可演示、可协作推进的主线。**

如果某项工作不能明显加强这条主线，就不要抢这 4 周的资源。

## 1) 这份计划怎么用

这不是新 backlog 池。
这是一份压缩执行顺序的交付计划，用来回答三个问题：

1. 这 4 周先收口什么
2. 哪些方向可以并行推进
3. 哪些方向现在先冻结，不要继续膨胀

使用规则：

- 先看 `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md` 判断能力状态，再看本计划决定接下来 4 周怎么投人力
- 默认最多同时重压 3 条泳道，不允许再临时开第 4 条主线
- 每周只接受一个“可演示闭环”作为主交付，不接受十个半成品并行摊开
- 如果某项任务会削弱 `Hub-first / user-owned / governed / fail-closed` 这条产品主线，应直接降级优先级

## 2) 三条固定泳道

未来 4 周固定只保留下面三条泳道：

### Lane A - Preview Spine

负责用户第一感知的主链收口：

- 配对 / doctor / route truth
- configured model vs actual model truth
- project / supervisor / coder 职责边界
- UI 基础可用性
- build / package / launch / diagnostics
- 性能和“不要让用户迷惑”的问题

这条线是 **P0 主线**。
如果 Lane A 不稳定，其他线默认不能扩张公开口径。

### Lane B - Supervisor Action Loop

负责把 Supervisor 从“会说话的状态面板”收口成“真的能推进任务的执行层”：

- 不乱建项目
- 正确理解用户意图
- 多项目 / 多泳道推进
- blocked 检测和 rescue
- guidance / acknowledgement / safe point
- project coder 真正执行而不是复述

### Lane C - Secure Interaction

负责把安全交互闭环做实：

- Secret Vault 最小闭环
- browser / skill / agent 对 Vault 的受控访问
- 敏感信息不在 terminal 明文长期暴露
- voice authorization / TTS / spoken brief
- Hub 下载 voice pack 后的实际可用性

说明：

- 语音在这份计划里归到 `Secure Interaction`，因为它承载授权和 brief，而不是单纯 UI 特效

## 3) 固定执行规则

### 3.1 每个工单都必须写清楚完成定义

任何工单没有下面 6 条 Done 标准，就不算完成：

1. 源码构建通过
2. 打包版可运行
3. 至少一条真实端到端路径跑通
4. 失败路径对用户可见
5. 不会静默假装成功
6. 文档与能力矩阵同步更新

### 3.2 先修“减少用户疑惑”的问题

未来 4 周优先处理这类问题：

- 用户到底选中了什么模型
- 实际到底用了什么模型
- 为什么降级
- 为什么被拒绝
- 为什么没执行
- 当前是谁在推进项目，下一步是谁应该行动

### 3.3 README 不能跑在代码前面

口径规则保持不变：

- `validated` 才能当成稳定公开主张
- `preview-working` 只能写成 working preview surface
- `implementation-in-progress` 不能包装成“已经完成”

### 3.4 每周只交付一个主演示闭环

不允许一周同时把语音、browser、persona、channel、personal plane 全部扩张。
每周必须能回答一句话：

**本周我们让哪一条用户主线从“能跑”变成了“更可用、更可信、更少疑惑”？**

## 4) 4 周交付计划

## Week 1 - Preview Spine 收口周

- theme: `让用户知道系统现在到底在做什么`
- primary lane: `Lane A`
- support lanes: `Lane B`

### 本周目标

- 收口模型真相链路
- 收口 project / supervisor / coder 的角色边界
- 清理误导性的 UI / tool result / 错误入口
- 继续压性能和卡顿问题

### 必做项

1. 模型真相统一
   - Supervisor、project coder、顶部状态栏都只显示真实 configured route / actual route / fallback reason
   - 同一轮回复不能再出现“界面选 GPT，但实际悄悄跑本地模型”的不透明状态
2. Project / Supervisor 行为边界收口
   - 只有用户明确提出新项目时才建项目
   - Project coder 不能只复述用户输入
   - Supervisor heartbeat 默认要朝“推进项目”收口，而不只是播报状态
3. UI 基础减噪
   - 无意义 `Tool Result` 默认隐藏
   - 错误摘要合并进自然语言回复
   - 输入框遮挡、历史区可见性、顶部状态噪音继续收口
4. 性能收口
   - 继续沿着主线程样本清理同步磁盘读取和重布局热点
   - 目标不是“更炫”，而是“不明显卡”

### 本周验收

- 用户在 project 或 supervisor 中问“你现在用的是什么模型”，系统给出的答案是可验证、统一、真实的
- project coder 不再无故创建项目或只回显用户话
- tool result 不再污染主聊天流
- Hub 和 XT 均能源码构建通过

### 本周不做

- 不扩更多 remote channel
- 不做 persona center 扩张
- 不做更重的本地 provider 能力扩面

## Week 2 - Secret Vault 最小闭环周

- theme: `让敏感信息走受控链路，而不是继续散在 terminal`
- primary lane: `Lane C`
- support lanes: `Lane A`

### 本周目标

- 建立最小 Secret Vault 使用闭环
- 把 browser / skill / agent 的敏感信息读取方式切到 Hub 授权链

### 必做项

1. Vault 最小闭环
   - 用户输入敏感信息后，terminal 不长期保存明文
   - Hub 侧保存密文或受控引用
   - 用到时通过授权链调取
2. Browser / skill 适配
   - `agent-browser` 等需要密码/令牌的 skill 改成从 Vault 取值
   - 明确哪些参数允许原文传、哪些必须走 secret reference
3. 审计与 revoke
   - 至少记录 secret 使用动作、调用来源、结果状态
   - 支持 revoke / disable 这类最小治理动作
4. 失败策略
   - 没授权、secret 缺失、scope 不匹配时 fail-closed

### 本周验收

- 一条 browser 或 skill 的真实 secret 使用路径可跑通
- X-Terminal 不需要长期展示用户密码原文
- 缺 secret / 无授权时，系统给出明确 blocked reason

### 本周不做

- 不做复杂企业级 vault 全家桶
- 不做过早的权限矩阵大扩张

## Week 3 - Voice Operational Loop 收口周

- theme: `让语音成为真实操作面，而不是只会播一个生硬声音`
- primary lane: `Lane C`
- support lanes: `Lane A`, `Lane B`

### 本周目标

- 让 Hub 下载的 voice pack 能被 Supervisor 真实使用
- 把 voice 状态和授权链打通

### 必做项

1. TTS 包状态显式化
   - `downloaded`
   - `imported`
   - `runtime unavailable`
   - `ready`
2. Voice route truth
   - 用户能看到当前到底用的是哪条 TTS 路线
   - 不能显示 ready 但实际还是旧硬声 fallback
3. 语音基础控制
   - 中英文切换
   - 音色切换
   - 语速调整
4. Supervisor 语音主链
   - brief
   - pending grant / challenge
   - progress update
   - repeat / cancel
   - spoken follow-up 回到 Hub brief truth

### 本周验收

- 用户从 Hub 下载 voice pack 后，Supervisor 可以实际切过去播报
- XT / Hub 状态面能诚实展示当前 voice readiness
- 至少一条“spoken brief -> 用户响应 -> 系统继续执行”的链路可验证

### 本周不做

- 不做 voice clone
- 不做重资产声纹功能

## Week 4 - Supervisor Action Loop 收口周

- theme: `让 Supervisor 真正推进项目，而不是做一个更复杂的聊天面板`
- primary lane: `Lane B`
- support lanes: `Lane A`, `Lane C`

### 本周目标

- 让 heartbeat 变成执行推进器
- 让多项目推进开始可解释、可控

### 必做项

1. 心跳从播报改为推进
   - 检测 blocked age
   - 检测 idle coder
   - 触发 review / replan / unblock
2. 项目拆分和泳道
   - 至少打通一个“复杂任务 -> 子任务 / lane -> 顺序推进”的最小闭环
3. Guidance / acknowledgement
   - Supervisor 给出的 guidance 不只是聊天文本
   - 能落成结构化 note / ack / defer / escalate
4. 防误操作
   - 不要因为用户问“你是不是 GPT”之类的话就乱建项目
   - 不要把普通聊天误解成 project-control command

### 本周验收

- 用户发出一个明确复杂任务时，Supervisor 能稳定建一条执行主链
- 心跳会在 blocked / stalled 场景中主动推进，而不是只播报
- 项目不会再因为无关对话被误创建

### 本周不做

- 不扩更大的 persona center
- 不做过度复杂的 portfolio cockpit

## 5) 冻结项

下面这些方向先冻结，不作为这 4 周主线目标：

- Persona Center / Personal longterm assistant 大扩张
- 完整 OpenClaw parity 扩面
- 更多 remote channel 的数量扩张
- 更大的本地多模态 runtime 能力面铺开
- 以“更炫 UI”替代主链收口

这些不是不要做，而是要等本计划四周主线稳定后再回来看。

## 6) 周复盘模板

每周结束时统一回答下面 6 个问题：

1. 本周收口的是哪一条主演示链
2. 哪个用户疑惑被明显缩短了
3. 哪条失败路径现在更诚实了
4. 哪个能力状态需要在 capability matrix 升级或降级
5. 哪些探索项应该继续冻结
6. 下周只允许保留哪一个主主题

## 7) 和现有文档的关系

- `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - 回答“这项能力现在算什么状态”
- `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
  - 回答“这项能力该不该抢 v1 主线资源”
- `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
  - 回答“有哪些具体 backlog 可以拿”
- 本文件
  - 回答“未来 4 周按什么顺序推进，才能最快把 preview 主线收口”
