import assert from 'node:assert/strict';

import { requireOperatorChannelConnectorAuth } from './auth.js';

function run(name, fn) {
  try {
    fn();
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

function makeCall({ token = '', peer = 'ipv4:127.0.0.1:54321' } = {}) {
  return {
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() === 'authorization') {
          return token ? [`Bearer ${token}`] : [];
        }
        return [];
      },
    },
    getPeer() {
      return peer;
    },
  };
}

run('requireOperatorChannelConnectorAuth denies when dedicated connector token is missing', () => {
  withEnv(
    {
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: '',
      HUB_OPERATOR_CHANNEL_CONNECTOR_ALLOW_REMOTE: '',
      HUB_OPERATOR_CHANNEL_CONNECTOR_ALLOWED_CIDRS: '',
    },
    () => {
      const auth = requireOperatorChannelConnectorAuth(makeCall({ token: 'anything' }));
      assert.equal(auth.ok, false);
      assert.equal(String(auth.code || ''), 'permission_denied');
      assert.equal(
        String(auth.message || ''),
        'Operator-channel connector token is not configured on this Hub'
      );
    }
  );
});

run('requireOperatorChannelConnectorAuth is loopback-only by default even with the correct token', () => {
  withEnv(
    {
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token',
      HUB_OPERATOR_CHANNEL_CONNECTOR_ALLOW_REMOTE: '',
      HUB_OPERATOR_CHANNEL_CONNECTOR_ALLOWED_CIDRS: '',
    },
    () => {
      const auth = requireOperatorChannelConnectorAuth(
        makeCall({ token: 'connector-token', peer: 'ipv4:10.20.30.40:54321' })
      );
      assert.equal(auth.ok, false);
      assert.equal(String(auth.code || ''), 'permission_denied');
      assert.match(String(auth.message || ''), /Operator-channel connector RPCs are local-only/);
    }
  );
});

run('requireOperatorChannelConnectorAuth allows explicit remote CIDR for the dedicated connector token', () => {
  withEnv(
    {
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token',
      HUB_OPERATOR_CHANNEL_CONNECTOR_ALLOW_REMOTE: '',
      HUB_OPERATOR_CHANNEL_CONNECTOR_ALLOWED_CIDRS: '10.20.0.0/16',
    },
    () => {
      const auth = requireOperatorChannelConnectorAuth(
        makeCall({ token: 'connector-token', peer: 'ipv4:10.20.30.40:54321' })
      );
      assert.equal(auth.ok, true);
    }
  );
});
