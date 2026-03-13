import assert from 'node:assert/strict';

import { createTelegramPollingWorker } from './TelegramPollingWorker.js';

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

await runAsync('TelegramPollingWorker polls updates and hands them to the update handler', async () => {
  const seen = [];
  let polls = 0;
  const worker = createTelegramPollingWorker({
    telegram_client: {
      async getUpdates({ offset }) {
        polls += 1;
        if (polls === 1) {
          return {
            updates: [
              { update_id: offset || 1001, message: { message_id: 88 } },
            ],
          };
        }
        return {
          updates: [],
        };
      },
    },
    on_update: async (update) => {
      seen.push(update);
      setTimeout(() => {
        worker.close().catch(() => {});
      }, 0);
    },
    poll_timeout_sec: 0,
    poll_idle_ms: 100,
  });

  await worker.listen();
  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.equal(seen.length, 1);
  assert.equal(Number(seen[0]?.update_id || 0) > 0, true);
});

await runAsync('TelegramPollingWorker backs off after empty polls and closes cleanly', async () => {
  const sleeps = [];
  let polls = 0;
  let worker = null;

  worker = createTelegramPollingWorker({
    telegram_client: {
      async getUpdates() {
        polls += 1;
        return {
          updates: [],
        };
      },
    },
    poll_timeout_sec: 0,
    poll_idle_ms: 125,
    set_timeout: (fn, ms) => {
      sleeps.push(ms);
      queueMicrotask(() => {
        worker?.close?.().catch(() => {});
        fn();
      });
      return 0;
    },
  });

  await worker.listen();
  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.equal(polls >= 1, true);
  assert.deepEqual(sleeps, [125]);
});
