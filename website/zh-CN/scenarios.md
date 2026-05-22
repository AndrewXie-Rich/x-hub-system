# 使用场景

<p class="lead">
X-Hub-System 适合那些“AI 不只是回答一句话，而是要跨设备、跨项目、跨模型、跨通道持续做事”的场景。它的价值不是把所有能力放开，而是让能力进入一个可授权、可审计、可撤销、可恢复的 Hub 边界。
</p>

<div class="preview-note">
  <strong>白皮书场景摘要</strong>
  这一页把白皮书里的家庭、中小企业、多项目 Supervisor、离线/局域网/远程访问、高风险动作和模型额度场景，整理成更容易被产品读者理解的公开版本。
</div>

## 最短理解

当 AI 只是在聊天，普通客户端就够了。  
当 AI 开始使用账号、记忆、技能、文件、浏览器、远程通道、付费模型或外部动作时，X-Hub 的优势就出现了：所有关键决定都回到 Hub。

## 六类典型场景

<div class="story-grid">
  <div class="story-card">
    <span>个人开发者</span>
    <strong>一个 Hub 管多个项目、模型、额度和记忆</strong>
    <p>你可以让 X-Terminal 同时跟进多个代码项目。敏感内容优先走本地模型，难题再切付费模型；实际用了哪个模型、额度压力、项目进展、测试证据和长期记忆都回到 Hub。</p>
  </div>
  <div class="story-card">
    <span>多项目执行</span>
    <strong>让 AI 持续推进，但不变成黑箱</strong>
    <p>Project AI 负责写代码、跑测试、修 blocker；Supervisor 定期或事件触发 review；Hub 记录运行真相、授权、审计和停止开关。用户只看关键摘要和需要裁决的点。</p>
  </div>
  <div class="story-card">
    <span>家庭设备</span>
    <strong>终端有用，但不掌握核心控制权</strong>
    <p>孩子或家人可以通过轻量客户端使用 AI，但 provider key、长期记忆、技能、模型路由和撤销权不放在每台终端上。首次高信任配对保持同 Wi-Fi，本地确认后再开启远程使用。</p>
  </div>
  <div class="story-card">
    <span>中小团队</span>
    <strong>员工可以用 AI，组织仍能治理能力边界</strong>
    <p>团队成员用 AI 做会议纪要、文档总结、代码检查或运营任务。管理员可以统一管理模型账号、技能来源、外部动作、审计记录和设备撤销，避免每个客户端各自持有一套关键权限。</p>
  </div>
  <div class="story-card">
    <span>敏感知识工作</span>
    <strong>本地模型优先，不把隐私和安全拆成两套系统</strong>
    <p>法律、财务、研发、个人隐私和内部资料可以优先走本地 runtime；需要更强能力时再按策略使用付费模型。两条路线仍共享 Hub 的记忆、授权、额度、审计和降级显示。</p>
  </div>
  <div class="story-card">
    <span>高后果动作</span>
    <strong>支付、外发、合并和远程命令先经过签名意图</strong>
    <p>不可逆或外部可见动作可以强制走 Hub-generated manifest、Hub signature、SAS、grant、TTL、audit 和 kill-switch，而不是让一个活跃终端临场拼接可信 payload。</p>
  </div>
</div>

## 四个更具体的故事

<div class="story-grid">
  <div class="story-card story-card--risk">
    <span>密钥泄露防线</span>
    <strong>“帮我查一个公开资料”不应该读取整个电脑</strong>
    <p>个人开发者让 AI 搜索公开信息时，X-Hub 可以把任务限制在浏览和项目相关文件上。SSH key、API key、浏览器缓存、私人聊天和长期记忆库不会因为“方便”自动进入上下文。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>Skill 供应链</span>
    <strong>“PDF 解析器”不应该顺手开远程 Shell</strong>
    <p>小团队安装 skill 前，Hub 检查 manifest、来源、版本 pin、兼容性和能力声明。即使 skill 可用，它也只能在授权 scope 内读写，并留下 grant 和 audit 记录。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>远程配对</span>
    <strong>一个链接不能变成高信任设备</strong>
    <p>家庭或远程办公场景里，X-Hub 把首次高信任配对留在同 Wi-Fi 和本地确认。远程通道可以用，但必须建立在已绑定设备、token 状态和可撤销访问上。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>成本和假完成</span>
    <strong>“一直做直到完成”需要预算、证据和复盘</strong>
    <p>多项目 Supervisor 场景下，heartbeat 负责看是否真有进展，quota 页面暴露额度压力，pre-done review 检查证据。系统不会只因为模型说“完成了”就把任务写成完成。</p>
  </div>
</div>

## 最打动人的不是“能自动”，而是“自动时仍能收得住”

很多 Agent 产品的演示会强调“它可以自己做更多事”。X-Hub-System 的重点是另一个问题：

- 它做错时，谁能停？
- 它要用付费模型时，谁知道额度在消耗？
- 它要读长期记忆时，谁决定看到多少？
- 它要安装 skill 或调用 connector 时，谁审查来源和范围？
- 它要发送邮件、合并代码、执行命令或发起支付时，谁签发意图？
- 它声称完成任务时，证据在哪里？

X-Hub 把这些问题放进产品结构，而不是靠操作者在聊天窗口里手动盯每一步。

## 适合的使用者

- 希望把本地模型和付费模型放进同一治理面的个人开发者
- 同时管理多个长期项目的独立创作者、小团队或技术负责人
- 想让员工使用 AI，但不想把密钥、工具和长期记忆散落在每台设备上的组织
- 对离线、局域网、远程访问、设备配对和权限撤销有明确要求的用户
- 希望 AI 能执行更多任务，但仍保留授权、审计、停止和恢复路径的用户

## 不只是一个更漂亮的聊天窗口

X-Hub-System 更像一个 AI 执行控制平面：聊天、终端、语音、远程通道和本地 runtime 都可以成为入口，但模型、记忆、技能、额度、授权、审计和停止权由 Hub 统一治理。

继续看：
[X 宪章](/zh-CN/constitution)、[受治理记忆](/zh-CN/memory)、[X-Terminal](/zh-CN/x-terminal)、[信任模型](/zh-CN/security)。
