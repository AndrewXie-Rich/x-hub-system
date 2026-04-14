# X-Hub 公开采用差距路线图 v1

- status: working draft
- updated_at: 2026-03-18
- goal: 在不削弱 Hub-first 信任模型的前提下，让 X-Hub 更容易被外界理解、试用和参与贡献
- benchmark lens: 对比 `aipyapp` 这类 execution-first 开源项目，重点看传播与上手方式，而不是照搬其信任模型

## 1. 当前判断

X-Hub 现在已经明显强于大多数 execution-first agent 项目的地方：

- Hub-first trust boundary
- user-owned control plane
- governed autonomy，而不是一个模糊的 auto mode
- governed skills，带审计、授权、拒绝码和 fail-closed 行为
- memory truth、runtime truth、audit 作为系统级原语，而不是聊天附属品

但公开层还需要把 memory 的边界再讲得更短更准：
用户在 X-Hub 中选择哪个 AI 执行 memory jobs，`Memory-Core` 是 Hub 侧受治理规则资产，而 durable truth 仍只经 `Writer + Gate` 落库。

当前主要差距不是“再多做几个功能”。
当前主要差距是**公开可理解性**：
外部开发者通常几分钟就能理解 execution-first 项目，但理解 X-Hub 仍然需要读很多材料。

## 2. 可以从 `aipyapp` 借鉴什么

最值得借鉴的是**包装方式、传播方式、上手路径**，不是它的信任边界哲学。

### 值得借鉴

1. **单入口叙事**
   - `aipyapp` 很容易用一句话讲清楚。
   - X-Hub 也需要一个压缩后的公开定义，先讲“它是什么”，再讲架构深度。

2. **极简首跑路径**
   - `pip install ...` + 一条命令这种模式非常利于传播。
   - X-Hub 需要一个等价的“5 分钟首次成功”路径，让用户快速跑通 Hub + X-Terminal。

3. **examples / showcase 与深文档分离**
   - `aipyapp` 的示例和 showcase 很容易找到。
   - X-Hub 也应该把公开 demo、截图、recipes 与深层架构文档分开。

4. **headless / task API 入口清晰**
   - `aipyapp` 的 task server 故事很直观。
   - X-Hub 也应该把最小的 headless / control-plane 接入方式讲清楚。

5. **命令菜谱化**
   - `examples/commands/` 这种组织方式非常利于快速理解能力边界。
   - X-Hub 也应该提供一小组 public recipes，展示 governed flows 怎么用。

### 不应该借鉴

1. 不要把信任边界压平到“直接本地执行就是全部答案”。
2. 不要用 “no agents / no workflow” 这种口号把治理层讲没了。
3. 不要让“代码可以执行”演变成“代码天然就是 trust root”。
4. 不要为了首次爽感而隐藏 downgrade truth、grant truth、blocked-state truth。

## 3. 当前最缺的公开层能力

这些是现在最值得补的公开缺口。

### P0：先把系统讲明白

- 一句首页 / README 定义，明确说明 X-Hub 为什么存在
- 一句能讲清 memory 控制面边界的话，避免外界把它误读成“某个 agent 自己维护全部 memory”
- 一页 “Why not just use an agent?” 对比页，配一张图和一张表
- 一条 5 分钟 quickstart，能跑到一个真实的 governed success state
- 三个标准公开 demo：
  - governed project execution
  - governed skill execution
  - remote / voice approval loop
- 一页架构总览，单屏讲清 Hub、X-Terminal、generic terminal、remote channels 的关系

Definition of done:

- 第一次来的读者能在 30 秒内复述 X-Hub 是什么
- 第一次试用的用户不必先读深层设计文档，也能跑通一个成功路径

### P1：先把首次体验做好

- 更顺滑的 Hub discovery 和 pairing
- 更明确的 blocked-state 诊断与一键修复建议
- 一个 starter project / guided first task 路径
- 一个最小内置 skill starter pack
- 清楚区分 local-only 和 paid-provider posture 的建议

Definition of done:

- 新用户可以在没有维护者陪同的情况下安装、配对、跑通一个 demo，并理解阻塞原因

### P2：让开发者更容易加入

- 一个公开的 API / headless entrypoint 页面
- 5 到 10 个公开 example recipes，最好带截图或期望输出
- 一个和当前代码所有权一致的“best first contribution lanes”页面
- 一个 pairing / runtime readiness / grants / local runtime 的 troubleshooting 页面
- 一个更清晰的 public release slice，明确区分 preview 与 validated mainline

Definition of done:

- 贡献者 10 分钟内能找到一个真实可做的 first PR 方向
- 外部开发者不用翻内部 planning packs，也能判断 X-Hub 是否适合接入自己的系统

### P3：把护城河证据化

- 一个 evidence-backed security walkthrough
- 一个基于 A/S tiers 的 governed autonomy case study
- 一个展示 approval / audit / retry / evidence 的 skill governance case study
- 一个展示 provider truth 与 fail-closed 行为的 local-first runtime case study
- 一个聚焦治理可信度而不是纯速度的公开 benchmark / compare 页面

Definition of done:

- 外界不再把 X-Hub 看成“另一个 agent UI”，而是看成一种独立的 control-plane architecture

## 4. 建议发布顺序

### 下一版先做什么

1. 收紧首页和根 `README.md`，先把一句话定义和对比表打磨好
2. 发布一个短 quickstart，跑通一个真实 governed demo
3. 发布一个 public demos 页面，并补截图 / 视频
4. 补一个最小 troubleshooting 页面，优先解决 pairing 和 runtime readiness

### 再下一步

1. 增加 skills、supervision、remote-channel flows 的 public recipes
2. 增加一个小型 headless / API 使用页
3. 发布第一篇 security case study 和第一篇 governed-autonomy case study

### 更后面再做

1. 扩展 contributor onramp
2. 发布 public capability matrix
3. 用案例、证据和对比 demo 继续强化产品故事

## 5. 一个简短工作规则

以后如果要在“再做功能”和“先做公开层”之间取舍，优先顺序建议固定为：

1. 先让系统更容易被理解
2. 再让首次成功更容易到达
3. 再让架构优势更容易被验证
4. 最后才是继续扩张公开功能面

这样做能保持 X-Hub 的差异化。
目标不是把 X-Hub 做成 execution-first 项目的简化复制品。
目标是把一套 user-owned、governed 的 agent control plane 讲清楚、做顺、做得足够可信，让更多人愿意试、愿意参与、愿意贡献。
