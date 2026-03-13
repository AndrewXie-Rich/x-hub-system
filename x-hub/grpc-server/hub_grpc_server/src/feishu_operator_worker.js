import { startFeishuOperatorWorker } from './channel_adapters/feishu/FeishuOperatorWorkerRuntime.js';

async function main() {
  const runtime = await startFeishuOperatorWorker({
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
  console.error(`[hub_feishu_operator] failed: ${String(error?.message || error)}`);
  process.exit(1);
});
