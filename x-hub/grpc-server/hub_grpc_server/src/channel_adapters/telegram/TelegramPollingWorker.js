function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeArray(input) {
  return Array.isArray(input) ? input : [];
}

function emitLog(log, line) {
  if (typeof log === 'function') log(line);
}

function sleep(ms, { set_timeout = setTimeout } = {}) {
  return new Promise((resolve) => {
    set_timeout(resolve, Math.max(0, safeInt(ms, 0)));
  });
}

function normalizeUpdatesResponse(response = {}) {
  if (Array.isArray(response)) return response;
  if (Array.isArray(response?.updates)) return response.updates;
  if (Array.isArray(response?.result)) return response.result;
  return [];
}

export function createTelegramPollingWorker({
  telegram_client = null,
  on_update = null,
  log = null,
  poll_timeout_sec = 15,
  poll_idle_ms = 400,
  allowed_updates = ['message', 'callback_query'],
  set_timeout = setTimeout,
} = {}) {
  const pollTimeoutSec = Math.max(0, Math.min(50, safeInt(poll_timeout_sec, 15)));
  const pollIdleMs = Math.max(100, safeInt(poll_idle_ms, 400));
  const allowedUpdates = safeArray(allowed_updates).map((item) => safeString(item)).filter(Boolean);

  let closed = false;
  let started = false;
  let loopPromise = null;
  let updateOffset = 0;
  let updateCount = 0;
  let errorCount = 0;
  let lastError = '';

  function snapshot() {
    return {
      started,
      update_offset: updateOffset,
      update_count: updateCount,
      error_count: errorCount,
      last_error: lastError,
      poll_timeout_sec: pollTimeoutSec,
      poll_idle_ms: pollIdleMs,
    };
  }

  async function runLoop() {
    while (!closed) {
      try {
        const response = await telegram_client.getUpdates({
          offset: updateOffset,
          timeout_sec: pollTimeoutSec,
          allowed_updates: allowedUpdates,
        });
        lastError = '';
        const updates = normalizeUpdatesResponse(response);
        if (!updates.length) {
          if (closed) break;
          await sleep(pollIdleMs, { set_timeout });
          continue;
        }
        for (const update of updates) {
          const updateId = safeInt(update?.update_id, 0);
          if (updateId > 0) updateOffset = updateId + 1;
          updateCount += 1;
          if (typeof on_update === 'function') {
            try {
              await on_update(update);
            } catch (error) {
              emitLog(
                log,
                `[telegram_polling_worker] update handler failed update_id=${updateId || 'unknown'} error=${safeString(error?.message || 'update_handler_failed') || 'update_handler_failed'}`
              );
            }
          }
          if (closed) break;
        }
      } catch (error) {
        errorCount += 1;
        lastError = safeString(error?.message || 'poll_failed') || 'poll_failed';
        emitLog(
          log,
          `[telegram_polling_worker] polling failed error=${lastError}`
        );
        if (closed) break;
        await sleep(pollIdleMs, { set_timeout });
      }
    }
  }

  return {
    async listen() {
      if (started) return snapshot();
      if (!telegram_client || typeof telegram_client.getUpdates !== 'function') {
        throw new Error('telegram_client_invalid');
      }
      started = true;
      loopPromise = runLoop();
      emitLog(
        log,
        `[telegram_polling_worker] polling started timeout_sec=${pollTimeoutSec} allowed_updates=${allowedUpdates.join(',') || 'none'}`
      );
      return snapshot();
    },
    snapshot,
    async close() {
      closed = true;
      try {
        await loopPromise;
      } catch {
        // ignore
      }
    },
  };
}
