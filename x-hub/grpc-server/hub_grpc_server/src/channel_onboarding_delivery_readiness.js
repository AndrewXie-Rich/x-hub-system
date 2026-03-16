import { createSlackApiClient, slackBotTokenFromEnv } from './channel_adapters/slack/SlackApiClient.js';
import { createTelegramApiClient, telegramBotTokenFromEnv } from './channel_adapters/telegram/TelegramApiClient.js';
import { createFeishuApiClient, feishuBotCredentialsFromEnv } from './channel_adapters/feishu/FeishuApiClient.js';
import { createWhatsAppCloudApiClient, whatsappCloudReplyCredentialsFromEnv } from './channel_adapters/whatsapp_cloud_api/WhatsAppCloudApiClient.js';

export const OPERATOR_CHANNEL_PROVIDER_IDS = Object.freeze([
  'slack',
  'telegram',
  'feishu',
  'whatsapp_cloud_api',
]);

function safeString(input) {
  return String(input ?? '').trim();
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

function buildReadiness({
  provider = '',
  reply_enabled = false,
  credentials_configured = false,
  deny_code = '',
  remediation_hint = '',
} = {}) {
  return {
    provider: safeString(provider).toLowerCase(),
    ready: !!reply_enabled && !!credentials_configured && !safeString(deny_code),
    reply_enabled: !!reply_enabled,
    credentials_configured: !!credentials_configured,
    deny_code: safeString(deny_code),
    remediation_hint: safeString(remediation_hint),
  };
}

function notConfiguredReadiness({
  provider = '',
  reply_enabled = false,
  credentials_configured = false,
  remediation_hint = '',
} = {}) {
  return buildReadiness({
    provider,
    reply_enabled,
    credentials_configured,
    deny_code: 'provider_delivery_not_configured',
    remediation_hint,
  });
}

function readinessForSlack(env = process.env) {
  const replyEnabled = safeBool(env.HUB_SLACK_OPERATOR_REPLY_ENABLE, true);
  const token = slackBotTokenFromEnv(env);
  const credentialsConfigured = !!token;
  if (!replyEnabled) {
    return notConfiguredReadiness({
      provider: 'slack',
      reply_enabled: false,
      credentials_configured: credentialsConfigured,
      remediation_hint: 'Set HUB_SLACK_OPERATOR_REPLY_ENABLE=1, ensure HUB_SLACK_OPERATOR_BOT_TOKEN is configured, then retry outbox.',
    });
  }
  if (!credentialsConfigured) {
    return notConfiguredReadiness({
      provider: 'slack',
      reply_enabled: true,
      credentials_configured: false,
      remediation_hint: 'Configure HUB_SLACK_OPERATOR_BOT_TOKEN, then retry outbox.',
    });
  }
  return buildReadiness({
    provider: 'slack',
    reply_enabled: true,
    credentials_configured: true,
  });
}

function readinessForTelegram(env = process.env) {
  const replyEnabled = safeBool(env.HUB_TELEGRAM_OPERATOR_REPLY_ENABLE, true);
  const token = telegramBotTokenFromEnv(env);
  const credentialsConfigured = !!token;
  if (!replyEnabled) {
    return notConfiguredReadiness({
      provider: 'telegram',
      reply_enabled: false,
      credentials_configured: credentialsConfigured,
      remediation_hint: 'Set HUB_TELEGRAM_OPERATOR_REPLY_ENABLE=1, ensure HUB_TELEGRAM_OPERATOR_BOT_TOKEN is configured, then retry outbox.',
    });
  }
  if (!credentialsConfigured) {
    return notConfiguredReadiness({
      provider: 'telegram',
      reply_enabled: true,
      credentials_configured: false,
      remediation_hint: 'Configure HUB_TELEGRAM_OPERATOR_BOT_TOKEN, then retry outbox.',
    });
  }
  return buildReadiness({
    provider: 'telegram',
    reply_enabled: true,
    credentials_configured: true,
  });
}

function readinessForFeishu(env = process.env) {
  const replyEnabled = safeBool(env.HUB_FEISHU_OPERATOR_REPLY_ENABLE, false);
  const credentials = feishuBotCredentialsFromEnv(env);
  const credentialsConfigured = !!(credentials.app_id && credentials.app_secret);
  if (!replyEnabled) {
    return notConfiguredReadiness({
      provider: 'feishu',
      reply_enabled: false,
      credentials_configured: credentialsConfigured,
      remediation_hint: 'Set HUB_FEISHU_OPERATOR_REPLY_ENABLE=1, configure HUB_FEISHU_OPERATOR_BOT_APP_ID and HUB_FEISHU_OPERATOR_BOT_APP_SECRET, then retry outbox.',
    });
  }
  if (!credentialsConfigured) {
    return notConfiguredReadiness({
      provider: 'feishu',
      reply_enabled: true,
      credentials_configured: false,
      remediation_hint: 'Configure HUB_FEISHU_OPERATOR_BOT_APP_ID and HUB_FEISHU_OPERATOR_BOT_APP_SECRET, then retry outbox.',
    });
  }
  return buildReadiness({
    provider: 'feishu',
    reply_enabled: true,
    credentials_configured: true,
  });
}

function readinessForWhatsAppCloud(env = process.env) {
  const replyEnabled = safeBool(env.HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE, false);
  const credentials = whatsappCloudReplyCredentialsFromEnv(env);
  const credentialsConfigured = !!(credentials.access_token && credentials.phone_number_id);
  if (!replyEnabled) {
    return notConfiguredReadiness({
      provider: 'whatsapp_cloud_api',
      reply_enabled: false,
      credentials_configured: credentialsConfigured,
      remediation_hint: 'Set HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE=1, configure HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN and HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID, then retry outbox.',
    });
  }
  if (!credentialsConfigured) {
    return notConfiguredReadiness({
      provider: 'whatsapp_cloud_api',
      reply_enabled: true,
      credentials_configured: false,
      remediation_hint: 'Configure HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN and HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID, then retry outbox.',
    });
  }
  return buildReadiness({
    provider: 'whatsapp_cloud_api',
    reply_enabled: true,
    credentials_configured: true,
  });
}

export function getChannelOnboardingDeliveryReadiness({
  provider = '',
  env = process.env,
} = {}) {
  const normalized = safeString(provider).toLowerCase();
  if (normalized === 'slack') return readinessForSlack(env);
  if (normalized === 'telegram') return readinessForTelegram(env);
  if (normalized === 'feishu') return readinessForFeishu(env);
  if (normalized === 'whatsapp_cloud_api') return readinessForWhatsAppCloud(env);
  return buildReadiness({
    provider: normalized,
    reply_enabled: false,
    credentials_configured: false,
    deny_code: 'provider_unsupported',
    remediation_hint: normalized
      ? `Provider ${normalized} is not supported for onboarding delivery.`
      : 'Provider is required for onboarding delivery.',
  });
}

export function listChannelOnboardingDeliveryReadiness({
  env = process.env,
  providers = OPERATOR_CHANNEL_PROVIDER_IDS,
} = {}) {
  const rows = Array.isArray(providers) ? providers : OPERATOR_CHANNEL_PROVIDER_IDS;
  return rows
    .map((provider) => getChannelOnboardingDeliveryReadiness({
      provider,
      env,
    }))
    .filter(Boolean);
}

export function createChannelOnboardingDeliveryTarget({
  provider = '',
  env = process.env,
  fetch_impl = globalThis.fetch,
} = {}) {
  const readiness = getChannelOnboardingDeliveryReadiness({
    provider,
    env,
  });
  const normalized = safeString(readiness.provider).toLowerCase();
  if (!readiness.ready) {
    return {
      ok: false,
      deny_code: safeString(readiness.deny_code || 'provider_delivery_not_configured'),
      readiness,
    };
  }

  if (normalized === 'slack') {
    return {
      ok: true,
      readiness,
      target: createSlackApiClient({
        token: slackBotTokenFromEnv(env),
        fetch_impl,
      }),
    };
  }
  if (normalized === 'telegram') {
    return {
      ok: true,
      readiness,
      target: createTelegramApiClient({
        token: telegramBotTokenFromEnv(env),
        fetch_impl,
      }),
    };
  }
  if (normalized === 'feishu') {
    const credentials = feishuBotCredentialsFromEnv(env);
    return {
      ok: true,
      readiness,
      target: createFeishuApiClient({
        app_id: credentials.app_id,
        app_secret: credentials.app_secret,
        fetch_impl,
      }),
    };
  }
  if (normalized === 'whatsapp_cloud_api') {
    const credentials = whatsappCloudReplyCredentialsFromEnv(env);
    return {
      ok: true,
      readiness,
      target: createWhatsAppCloudApiClient({
        access_token: credentials.access_token,
        phone_number_id: credentials.phone_number_id,
        fetch_impl,
      }),
    };
  }

  return {
    ok: false,
    deny_code: 'provider_unsupported',
    readiness,
  };
}
