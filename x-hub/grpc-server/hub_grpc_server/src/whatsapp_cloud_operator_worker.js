import { startWhatsAppCloudOperatorWorker } from './channel_adapters/whatsapp_cloud_api/WhatsAppCloudOperatorWorkerRuntime.js';

async function main() {
  const runtime = await startWhatsAppCloudOperatorWorker({
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
  console.error(`[hub_whatsapp_cloud_operator] failed: ${String(error?.message || error)}`);
  process.exit(1);
});
