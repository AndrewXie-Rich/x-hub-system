function safeString(input) {
  return String(input ?? '').trim();
}

function uniqueOrderedStrings(values = []) {
  const out = [];
  const seen = new Set();
  for (const raw of Array.isArray(values) ? values : []) {
    const value = safeString(raw);
    if (!value || seen.has(value)) continue;
    seen.add(value);
    out.push(value);
  }
  return out;
}

function providerEventPath(provider = '') {
  switch (safeString(provider).toLowerCase()) {
    case 'slack':
      return '/slack/events';
    case 'feishu':
      return '/feishu/events';
    case 'whatsapp_cloud_api':
      return '/whatsapp/events';
    default:
      return '';
  }
}

function connectorTokenHint(provider = '') {
  const normalized = safeString(provider).toLowerCase();
  const providerLabel = normalized || '该 provider';
  return `专用 connector token 缺失或失效。把 HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN 重新注入当前运行中的 Hub / connector，并确认 ${providerLabel} 使用的是专用 connector token，而不是 admin token。若刚轮换过 token，请重启相关进程后再刷新状态。`;
}

function replyEnableHint(provider = '') {
  switch (safeString(provider).toLowerCase()) {
    case 'slack':
      return 'Slack 回复投递当前未开启。设置 HUB_SLACK_OPERATOR_REPLY_ENABLE=1 后，再刷新状态或重试待发送回复。';
    case 'telegram':
      return 'Telegram 回复投递当前未开启。设置 HUB_TELEGRAM_OPERATOR_REPLY_ENABLE=1 后，再刷新状态或重试待发送回复。';
    case 'feishu':
      return '飞书回复投递当前未开启。设置 HUB_FEISHU_OPERATOR_REPLY_ENABLE=1 后，再刷新状态或重试待发送回复。';
    case 'whatsapp_cloud_api':
      return 'WhatsApp Cloud 回复投递当前未开启。设置 HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE=1 后，再刷新状态或重试待发送回复。';
    default:
      return '';
  }
}

function credentialsHint(provider = '') {
  switch (safeString(provider).toLowerCase()) {
    case 'slack':
      return 'Slack 回复凭据不完整。确认 HUB_SLACK_OPERATOR_BOT_TOKEN 已注入当前运行中的 Hub。';
    case 'telegram':
      return 'Telegram bot token 缺失。确认 HUB_TELEGRAM_OPERATOR_BOT_TOKEN 已注入当前运行中的 Hub，并保持 HUB_TELEGRAM_OPERATOR_REPLY_ENABLE=1。';
    case 'feishu':
      return '飞书回复凭据不完整。确认 HUB_FEISHU_OPERATOR_BOT_APP_ID 和 HUB_FEISHU_OPERATOR_BOT_APP_SECRET 已注入当前运行中的 Hub。';
    case 'whatsapp_cloud_api':
      return 'WhatsApp Cloud 回复凭据不完整。确认 HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN 和 HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID 已注入当前运行中的 Hub。';
    default:
      return '';
  }
}

function codeHints(provider = '', code = '') {
  const normalizedProvider = safeString(provider).toLowerCase();
  switch (safeString(code).toLowerCase()) {
    case 'connector_token_missing':
    case 'unauthenticated':
      return [connectorTokenHint(normalizedProvider)];
    case 'signing_secret_missing':
      return [
        `Slack signing secret 还没加载。补上 HUB_SLACK_OPERATOR_SIGNING_SECRET，并确认 Slack Request URL 仍然命中 ${providerEventPath('slack')}。`,
      ];
    case 'verification_token_missing':
    case 'verification_token_missing_in_payload':
    case 'verification_token_invalid':
      return [
        `飞书 verification token 缺失或不匹配。补上 HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN，并确认 url_verification 和正式回调都命中 ${providerEventPath('feishu')}，且代理没有改写 token 字段。`,
      ];
    case 'verify_token_missing':
    case 'verify_token_invalid':
      return [
        'WhatsApp Cloud verify token 缺失或不匹配。补上 HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN，并重新完成 Meta webhook 的 GET verify challenge。',
      ];
    case 'signature_missing':
    case 'signature_invalid':
    case 'webhook_signature_invalid':
    case 'signature_timestamp_missing':
    case 'request_timestamp_out_of_range':
      if (normalizedProvider === 'slack') {
        return [
          `Slack 签名校验失败。检查 HUB_SLACK_OPERATOR_SIGNING_SECRET，确认代理或隧道保留原始请求体和 X-Slack-* 头，不要在到达 ${providerEventPath('slack')} 前改写 body。`,
        ];
      }
      if (normalizedProvider === 'whatsapp_cloud_api') {
        return [
          `WhatsApp Cloud 签名校验失败。检查 HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET，确认代理保留原始请求体和 Meta 签名头，不要在到达 ${providerEventPath('whatsapp_cloud_api')} 前改写 body。`,
        ];
      }
      return [
        'Webhook 签名校验失败。检查 provider 对应的 signing secret / app secret，并确认代理没有改写原始请求体或签名头。',
      ];
    case 'replay_detected':
    case 'webhook_replay_detected':
      return [
        'Hub 因重放嫌疑已 fail-closed。先检查 provider 是否重复投递、代理是否重放旧请求；修复后请在目标会话重新发送一条新消息生成新工单，不要直接复用旧 payload。',
      ];
    case 'replay_guard_error':
      return [
        'Hub 的 replay guard 当前自身异常，这批外部事件不能被当作可信输入。先修复 Hub 本地运行时或存储，再让对方重新发送一条新消息。',
      ];
    case 'bot_token_missing':
      return [credentialsHint(normalizedProvider)];
    case 'slack_bot_token_missing':
      return ['Slack 回复 token 缺失。把 HUB_SLACK_OPERATOR_BOT_TOKEN 注入当前运行中的 Hub，再刷新状态或重试待发送回复。'];
    case 'feishu_app_secret_missing':
    case 'tenant_access_token_missing':
      return [credentialsHint('feishu')];
    case 'app_secret_missing':
      if (normalizedProvider === 'whatsapp_cloud_api') {
        return [
          'WhatsApp Cloud app secret 缺失。补上 HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET，让带签名回调恢复 fail-closed 校验。',
        ];
      }
      return [];
    case 'channel_delivery_degraded':
      return [
        '当前 provider 的回复投递处于降级状态。先修复最近一次投递错误，再执行 Retry Pending Replies，确认外发回复重新回到 delivered。',
      ];
    case 'webhook_not_allowlisted':
      return [
        '当前 webhook source 不在 Hub allowlist。修正 source allowlist 或 connector 身份后，再从外部会话重新发送一条真实消息。',
      ];
    default:
      return [];
  }
}

export function buildOperatorChannelDeliveryRepairHints({
  provider = '',
  reply_enabled = false,
  credentials_configured = false,
  deny_code = '',
  remediation_hint = '',
} = {}) {
  const normalizedProvider = safeString(provider).toLowerCase();
  const hints = [];
  hints.push(...codeHints(normalizedProvider, deny_code));
  if (!reply_enabled) hints.push(replyEnableHint(normalizedProvider));
  if (!credentials_configured) hints.push(credentialsHint(normalizedProvider));
  const remediation = safeString(remediation_hint);
  if (remediation) hints.push(remediation);
  return uniqueOrderedStrings(hints);
}

export function buildOperatorChannelRuntimeRepairHints({
  provider = '',
  runtime_state = '',
  delivery_ready = false,
  command_entry_ready = false,
  last_error_code = '',
  release_blocked = false,
} = {}) {
  const normalizedState = safeString(runtime_state).toLowerCase();
  const hints = [];
  hints.push(...codeHints(provider, last_error_code));

  if (!hints.length) {
    if (release_blocked) {
      hints.push('这个 provider 当前仍处于受控发布或 require-real-evidence 阶段，不能把它当成默认稳定通道。');
    } else if ((normalizedState === 'degraded' || normalizedState === 'error') && !delivery_ready) {
      hints.push('当前 provider 的回复投递处于降级状态。先修复最近一次投递错误，再执行 Retry Pending Replies，确认外发回复重新回到 delivered。');
    } else if (normalizedState === 'disabled') {
      hints.push('当前 Hub 运行时里，这个 provider 的 connector 还没有启用。先补齐环境变量并重启相关组件，再刷新运行时状态。');
    } else if (normalizedState === 'not_configured') {
      hints.push('当前 Hub 运行时里，这个 provider 还没有完成配置。先补齐专用 connector 凭据和 provider 凭据，再刷新运行时状态。');
    } else if (normalizedState === 'ingress_ready' && !command_entry_ready) {
      hints.push('入口链路已经连通，但受治理命令入口还未就绪。确认专用 connector token 和 provider 校验密钥都已进入当前运行中的 Hub / connector 后，再刷新状态。');
    } else if (!delivery_ready && command_entry_ready) {
      hints.push('命令入口已经可用，但回复投递还未就绪。补齐 provider 回复凭据后，再执行 Retry Pending Replies。');
    }
  }

  return uniqueOrderedStrings(hints);
}
