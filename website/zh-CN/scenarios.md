# 使用场景

<p class="lead">
如果 AI 只是聊天,你不需要 X-Hub。如果 AI 开始删文件、发消息、扣信用卡、或在你睡觉时跨多个项目工作——这时候控制权才重要。三类受众因为三种不同的原因来到这里。
</p>

<div class="preview-note">
  <strong>三类受众,不是六类。</strong>
  产品形态保持简单：家庭、团队、个人开发者都使用同一个 Hub。个人开发者是单用户模式，不是另一条产品线。
</div>

## 最短理解

当 AI 只是聊天,普通客户端就够了。
当 AI 开始使用账号、记忆、技能、文件、浏览器、远程通道、付费模型或外部动作时,关键决定就该回到 Hub。

## 团队与企业

<div class="story-grid">
  <div class="story-card">
    <span>为什么是这个受众</span>
    <strong>代码、提示词、记忆不能走 SaaS-only AI 工具。</strong>
    <p>面对 EU AI Act 暴露、ISO 42001 采购要求或 SOC2 敏感买家的行业,无法把敏感上下文交给不可控的 vendor cloud。商业许可在 MIT 内核之上加入多用户角色(admin / operator / observer)、SSO / OIDC、SIEM 友好的审计导出、合规报告生成。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>具体证据</span>
    <strong>"PDF 解析器"不该顺手开远程 Shell。</strong>
    <p>团队使用某个 skill 前,Hub 检查 manifest、来源、版本 pin、兼容性、能力声明。即使 skill 可用,它也只能在授权 scope 内读写,并留下 grant 和 audit 记录。这套子系统是 <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a> 规范的参考实现。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>具体证据</span>
    <strong>"完成"需要证据、预算、复盘。</strong>
    <p>多项目 Supervisor 场景,heartbeat 看是否真有进展,quota 暴露额度压力,pre-done review 检查证据。系统不会因为模型说"完成了"就把任务写成完成。签名 Hub Receipt 让审计链在 X-Hub 之外也能验证。</p>
  </div>
</div>

详见 [ENTERPRISE_zh.md](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/ENTERPRISE_zh.md),含面向采购的细节和商业许可咨询路径。

## 家庭

<div class="story-grid">
  <div class="story-card">
    <span>为什么是这个受众</span>
    <strong>共享 AI,家长用 Hub 控制额度、白名单、高风险动作确认,孩子的客户端绕不过。</strong>
    <p>这里的定位是结构性的,不是 feature-based:家庭使用 = 最小的多用户团队。家长 = Hub admin。孩子 = 受治理客户端。不分开产品线、不分开许可——支撑团队的同一个 MIT 内核也支撑家庭。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>具体证据</span>
    <strong>一个链接不能变成高信任设备。</strong>
    <p>首次高信任配对保持同 Wi-Fi 本地确认。远程通道可以用,但必须建立在已绑定设备、token 状态、可撤销访问之上。孩子点开聊天链接,绝不能产生新的 admin 设备。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>具体证据</span>
    <strong>高风险动作要配对设备触确认。</strong>
    <p>支付确认、账号变更、破坏性命令都走配对设备确认。这就是 <a href="https://github.com/AndrewXie-Rich/agent-2fa">agent-2fa</a> 规范形式化的 primitive——动作落地前,先打到家长手机上的 Touch ID / Face ID。</p>
  </div>
</div>

详见 [FAMILY.md](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/FAMILY.md),家庭部署形态。

## 开发者(含个人 / 独立使用)

<div class="story-grid">
  <div class="story-card">
    <span>为什么是这个受众</span>
    <strong>自托管 Hub,看清楚到底跑了什么。</strong>
    <p>路由真相、fallback、降级、阻塞原因、签名回执全部摆出来。一个 Hub 管:敏感任务的本地模型、需要时切付费 provider、跨会话项目状态、Writer + Gate 之下的长期记忆。个人 / 独立使用就是"一人团队",不需要单列。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>具体证据</span>
    <strong>"帮我查一个公开资料"不该读整机。</strong>
    <p>开发者让 AI 搜索公开信息时,X-Hub 把任务限制在浏览和项目相关文件上。SSH key、API key、浏览器缓存、私聊、长期记忆不会因为"方便"自动进入上下文。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>具体证据</span>
    <strong>两份规范可以独立使用。</strong>
    <p>你可以只拿 <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a> 作为 MCP 之上的信任层,或只拿 <a href="https://github.com/AndrewXie-Rich/agent-2fa">agent-2fa</a> 作为 per-action 确认,不必带走 X-Hub。X-Hub 是这两份规范的一个实现,不是唯一实现。</p>
  </div>
</div>

## 真正打动人的不是"能自动",而是"自动时仍能收得住"

很多 Agent 演示强调"它可以自己做更多事"。X-Hub-System 问的是另一组问题:

- 它做错时,谁能停?
- 它要用付费模型时,谁知道额度在消耗?
- 它要读长期记忆时,谁决定看到多少?
- 它要装 skill 或调 connector 时,谁审查来源和范围?
- 它要发邮件、合并代码、跑命令、发起支付时,谁签发意图?
- 它声称完成任务时,证据在哪里?

X-Hub 把这些问题放进产品结构,不是靠操作者在聊天窗口里盯每一步。

## 不只是更漂亮的聊天窗口

X-Hub-System 更像一个 AI 执行控制平面:聊天、终端、语音、远程通道、本地 runtime 都可以是入口——而模型、记忆、技能、额度、授权、审计和终止权由 Hub 统一治理。

继续看:
[X 宪章](/zh-CN/constitution)、[受治理记忆](/zh-CN/memory)、[X-Terminal](/zh-CN/x-terminal)、[信任模型](/zh-CN/security)。
