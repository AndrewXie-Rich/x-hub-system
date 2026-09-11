import crypto from 'node:crypto';

export function verifyConnectorWebhook({ headers = {}, pathname, connector, targetId, rawBody, body = {}, env = process.env, nowMs = Date.now() }) {
  const deny = (code, status = 401) => ({ ok: false, code, status });
  if (!/^[a-z0-9_-]+$/.test(connector || '') || !/^[a-zA-Z0-9._-]+$/.test(targetId || '')) {
    return deny('webhook_source_invalid', 400);
  }
  const sourceId = `${connector}:${targetId}`;
  let keys;
  try {
    keys = JSON.parse(env.HUB_CONNECTOR_WEBHOOK_KEYS_JSON || '{}');
  } catch {
    return deny('webhook_auth_not_configured', 503);
  }
  const secret = keys && Object.hasOwn(keys, sourceId) ? keys[sourceId] : null;
  if (typeof secret !== 'string' || Buffer.byteLength(secret) < 32) {
    return deny('webhook_auth_not_configured', 503);
  }
  const timestamp = headers['x-hub-timestamp'];
  const signature = headers['x-hub-signature'];
  const replayKey = headers['x-replay-key'];
  if (typeof timestamp !== 'string' || !/^\d{10,12}$/.test(timestamp)
    || Math.abs(nowMs - Number(timestamp) * 1000) > 300_000) {
    return deny('webhook_timestamp_invalid');
  }
  if (typeof replayKey !== 'string' || !/^[a-zA-Z0-9._:-]{1,200}$/.test(replayKey)) {
    return deny('webhook_replay_key_invalid');
  }
  if (typeof signature !== 'string' || !/^v1=[a-f0-9]{64}$/.test(signature) || !Buffer.isBuffer(rawBody)) {
    return deny('webhook_signature_invalid');
  }
  const expected = crypto.createHmac('sha256', secret)
    .update(`v1\n${timestamp}\nPOST\n${pathname}\n${replayKey}\n`)
    .update(rawBody)
    .digest();
  if (!crypto.timingSafeEqual(expected, Buffer.from(signature.slice(3), 'hex'))) {
    return deny('webhook_signature_invalid');
  }
  for (const input of [body, body?.payload]) {
    for (const field of ['source_id', 'webhook_source_id']) {
      if (input?.[field] != null && input[field] !== sourceId) return deny('webhook_source_mismatch', 403);
    }
    if (input?.signature_valid === false) return deny('webhook_signature_invalid');
  }
  return { ok: true, source_id: sourceId, replay_key: replayKey };
}
