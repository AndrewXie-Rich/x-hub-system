import assert from 'node:assert/strict';

import {
  createWhatsAppCloudApiClient,
  whatsappCloudReplyCredentialsFromEnv,
} from './WhatsAppCloudApiClient.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

run('WhatsAppCloudApiClient reads reply credentials from environment', () => {
  withEnv({
    HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN: 'wa-access-token-1',
    HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID: 'phone-number-id-1',
  }, () => {
    const creds = whatsappCloudReplyCredentialsFromEnv(process.env);
    assert.equal(String(creds.access_token || ''), 'wa-access-token-1');
    assert.equal(String(creds.phone_number_id || ''), 'phone-number-id-1');
  });
});

await runAsync('WhatsAppCloudApiClient posts reply messages through Graph API shape', async () => {
  const calls = [];
  const client = createWhatsAppCloudApiClient({
    access_token: 'wa-access-token-1',
    phone_number_id: 'phone-number-id-1',
    api_version: 'v23.0',
    fetch_impl: async (url, options = {}) => {
      calls.push({ url: String(url), options });
      return {
        ok: true,
        status: 200,
        async text() {
          return JSON.stringify({
            messaging_product: 'whatsapp',
            contacts: [{ wa_id: '15551234567' }],
            messages: [{ id: 'wamid.HBgMNTU1NTEyMzQ1Njc=' }],
          });
        },
      };
    },
  });

  const out = await client.postMessage({
    to: 'whatsapp:+1 (555) 123-4567',
    text: 'status',
    reply_to_message_id: 'wamid.anchor.1',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.message_id || ''), 'wamid.HBgMNTU1NTEyMzQ1Njc=');
  assert.match(String(calls[0].url || ''), /\/v23\.0\/phone-number-id-1\/messages$/);
  assert.equal(String(calls[0].options?.headers?.authorization || ''), 'Bearer wa-access-token-1');
  assert.match(String(calls[0].options?.body || ''), /"to":"15551234567"/);
  assert.match(String(calls[0].options?.body || ''), /"message_id":"wamid\.anchor\.1"/);
});

await runAsync('WhatsAppCloudApiClient fails closed on provider API errors', async () => {
  const client = createWhatsAppCloudApiClient({
    access_token: 'wa-access-token-1',
    phone_number_id: 'phone-number-id-1',
    fetch_impl: async () => ({
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({
          error: {
            message: 'permission denied',
          },
        });
      },
    }),
  });

  await assert.rejects(
    async () => {
      await client.postMessage({
        to: '+15551234567',
        text: 'status',
      });
    },
    /whatsapp_cloud_api_error:permission denied/
  );
});
