import net from 'node:net';
import process from 'node:process';

function safeString(v) {
  return String(v ?? '').trim();
}

function parseIntPort(v, def) {
  const n = Number.parseInt(String(v ?? ''), 10);
  if (!Number.isFinite(n)) return def;
  if (n <= 0 || n > 65535) return def;
  return n;
}

function parseArgs(argv) {
  const out = {
    localHost: safeString(process.env.AXHUB_TUNNEL_LOCAL_HOST || '127.0.0.1') || '127.0.0.1',
    localPort: parseIntPort(process.env.AXHUB_TUNNEL_LOCAL_PORT, 50051),
    remoteHost: safeString(process.env.AXHUB_TUNNEL_REMOTE_HOST || process.env.HUB_HOST || '') || '',
    remotePort: parseIntPort(process.env.AXHUB_TUNNEL_REMOTE_PORT || process.env.HUB_PORT, 50051),
    quiet: false,
  };

  const args = Array.isArray(argv) ? argv.slice(2) : [];
  for (let i = 0; i < args.length; i += 1) {
    const a = String(args[i] || '');
    if (a === '--quiet' || a === '-q') {
      out.quiet = true;
      continue;
    }
    if (a === '--local-host') {
      out.localHost = safeString(args[i + 1] || '') || out.localHost;
      i += 1;
      continue;
    }
    if (a === '--local-port') {
      out.localPort = parseIntPort(args[i + 1], out.localPort);
      i += 1;
      continue;
    }
    if (a === '--remote-host') {
      out.remoteHost = safeString(args[i + 1] || '') || out.remoteHost;
      i += 1;
      continue;
    }
    if (a === '--remote-port') {
      out.remotePort = parseIntPort(args[i + 1], out.remotePort);
      i += 1;
      continue;
    }
    if (a === '--remote') {
      const v = safeString(args[i + 1] || '');
      i += 1;
      const idx = v.lastIndexOf(':');
      if (idx > 0) {
        out.remoteHost = safeString(v.slice(0, idx)) || out.remoteHost;
        out.remotePort = parseIntPort(v.slice(idx + 1), out.remotePort);
      } else if (v) {
        out.remoteHost = v;
      }
      continue;
    }
    if (a === '--help' || a === '-h') {
      out.help = true;
      continue;
    }
  }

  return out;
}

function usage() {
  // eslint-disable-next-line no-console
  console.log(`axhub tcp tunnel (MVP)

Usage:
  node tcp_tunnel.js --remote <host:port> [--local-host 127.0.0.1] [--local-port 50051]

Env (preferred when launched via axhubctl):
  AXHUB_TUNNEL_REMOTE_HOST / AXHUB_TUNNEL_REMOTE_PORT
  AXHUB_TUNNEL_LOCAL_HOST / AXHUB_TUNNEL_LOCAL_PORT
`);
}

function logEnabled(quiet) {
  return !quiet;
}

function main() {
  const cfg = parseArgs(process.argv);
  if (cfg.help) {
    usage();
    process.exit(0);
  }

  if (!cfg.remoteHost) {
    // eslint-disable-next-line no-console
    console.error('tcp_tunnel: missing remote host (set AXHUB_TUNNEL_REMOTE_HOST or pass --remote-host/--remote)');
    process.exit(2);
  }

  const active = new Set();
  let nextId = 1;

  const server = net.createServer((down) => {
    const id = nextId++;
    active.add(down);

    // Each inbound connection gets its own upstream connection.
    const up = net.connect({ host: cfg.remoteHost, port: cfg.remotePort });
    active.add(up);

    // Keep idle connections alive across NAT/VPN transitions.
    down.setKeepAlive(true, 10_000);
    up.setKeepAlive(true, 10_000);

    down.on('error', () => {});
    up.on('error', () => {});

    const closeBoth = () => {
      try {
        down.destroy();
      } catch {
        // ignore
      }
      try {
        up.destroy();
      } catch {
        // ignore
      }
    };

    down.on('close', () => {
      active.delete(down);
      closeBoth();
    });
    up.on('close', () => {
      active.delete(up);
      closeBoth();
    });

    // Bi-directional pipe.
    down.pipe(up);
    up.pipe(down);

    if (logEnabled(cfg.quiet)) {
      // eslint-disable-next-line no-console
      console.log(`[tunnel] #${id} connected`);
    }
  });

  server.on('error', (err) => {
    // eslint-disable-next-line no-console
    console.error(`[tunnel] listen failed on ${cfg.localHost}:${cfg.localPort}: ${String(err?.message || err)}`);
    process.exit(1);
  });

  server.listen(cfg.localPort, cfg.localHost, () => {
    if (logEnabled(cfg.quiet)) {
      // eslint-disable-next-line no-console
      console.log(`[tunnel] listening on ${cfg.localHost}:${cfg.localPort} -> ${cfg.remoteHost}:${cfg.remotePort}`);
      // eslint-disable-next-line no-console
      console.log('[tunnel] ctrl+c to stop');
    }
  });

  const shutdown = () => {
    try {
      server.close();
    } catch {
      // ignore
    }
    for (const s of Array.from(active)) {
      try {
        s.destroy();
      } catch {
        // ignore
      }
    }
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main();

