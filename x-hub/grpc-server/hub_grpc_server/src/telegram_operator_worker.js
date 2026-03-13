import { startTelegramOperatorWorker } from './channel_adapters/telegram/TelegramOperatorWorkerRuntime.js';

async function main() {
  const runtime = await startTelegramOperatorWorker({
    env: process.env,
  });

  const shutdown = async () => {
    try {
      await runtime?.close?.();
    } finally {
      process.exit(0);
    }
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error(`[hub_telegram_operator] failed: ${String(error?.message || error)}`);
  process.exit(1);
});
