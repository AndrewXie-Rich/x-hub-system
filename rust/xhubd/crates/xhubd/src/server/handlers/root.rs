pub(crate) fn root_body() -> String {
    r#"<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Rust Hub</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f7f7f4;
      --panel: #ffffff;
      --text: #202124;
      --muted: #5f6368;
      --line: #d8d9d2;
      --ok: #16794c;
      --warn: #9a5b00;
      --bad: #b3261e;
      --chip: #eef2f0;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #111315;
        --panel: #1b1d20;
        --text: #f1f3f4;
        --muted: #bdc1c6;
        --line: #34373b;
        --chip: #252a2d;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.45;
    }
    main {
      width: min(1040px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 28px 0 40px;
    }
    header {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: flex-start;
      padding-bottom: 20px;
      border-bottom: 1px solid var(--line);
    }
    h1 {
      margin: 0;
      font-size: 28px;
      line-height: 1.15;
      letter-spacing: 0;
    }
    h2 {
      margin: 0 0 12px;
      font-size: 16px;
      letter-spacing: 0;
    }
    p { margin: 6px 0 0; color: var(--muted); }
    a { color: inherit; }
    .status {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 7px 10px;
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 8px;
      font-weight: 600;
      white-space: nowrap;
    }
    .dot {
      width: 9px;
      height: 9px;
      border-radius: 999px;
      background: var(--muted);
    }
    .ok .dot { background: var(--ok); }
    .warn .dot { background: var(--warn); }
    .bad .dot { background: var(--bad); }
    .grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
      margin-top: 18px;
    }
    .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 16px;
      min-width: 0;
    }
    .full { grid-column: 1 / -1; }
    dl {
      margin: 0;
      display: grid;
      grid-template-columns: minmax(120px, 180px) minmax(0, 1fr);
      gap: 8px 12px;
    }
    dt { color: var(--muted); }
    dd {
      margin: 0;
      min-width: 0;
      overflow-wrap: anywhere;
    }
    .checks {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 8px;
    }
    .check {
      border: 1px solid var(--line);
      background: var(--chip);
      border-radius: 8px;
      padding: 9px 10px;
      display: flex;
      justify-content: space-between;
      gap: 10px;
    }
    .check span:last-child { font-weight: 700; }
    .check.good span:last-child { color: var(--ok); }
    .check.fail span:last-child { color: var(--bad); }
    .links {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }
    .links a {
      display: inline-flex;
      align-items: center;
      min-height: 34px;
      padding: 7px 10px;
      border: 1px solid var(--line);
      background: var(--chip);
      border-radius: 8px;
      text-decoration: none;
      font-weight: 600;
    }
    pre {
      margin: 0;
      padding: 12px;
      overflow: auto;
      border: 1px solid var(--line);
      background: var(--chip);
      border-radius: 8px;
      max-height: 360px;
      font-size: 12px;
    }
    @media (max-width: 760px) {
      header { display: block; }
      .status { margin-top: 14px; }
      .grid { grid-template-columns: 1fr; }
      dl { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>Rust Hub</h1>
        <p>Local shadow daemon for scheduler, provider, model inventory, and route readiness.</p>
      </div>
      <div id="overall" class="status"><span class="dot"></span><span>Loading</span></div>
    </header>

    <section class="grid">
      <div class="panel">
        <h2>Daemon</h2>
        <dl id="daemon"></dl>
      </div>
      <div class="panel">
        <h2>Runtime</h2>
        <dl id="runtime"></dl>
      </div>
      <div class="panel full">
        <h2>Checks</h2>
        <div id="checks" class="checks"></div>
      </div>
      <div class="panel">
        <h2>API</h2>
        <div class="links">
          <a href="/health">Health JSON</a>
          <a href="/ready">Ready JSON</a>
          <a href="/model/inventory">Model Inventory</a>
          <a href="/model/capabilities">Local Model Capabilities</a>
          <a href="/model/repair-plan">Local Model Repair Plan</a>
          <a href="/model/repair-apply">Local Model Repair Apply</a>
          <a href="/model/repair-jobs">Local Model Repair Jobs</a>
          <a href="/model/route">Model Route</a>
          <a href="/model/diagnostics">Model Diagnostics</a>
          <a href="/xt/hub-contract">XT Hub Contract</a>
          <a href="/network/remote-entry-candidates">Remote Entry Candidates</a>
          <a href="/provider/readiness">Provider Readiness</a>
          <a href="/skills/readiness">Skills Readiness</a>
          <a href="/skills/preflight">Skills Preflight</a>
        </div>
      </div>
      <div class="panel">
        <h2>Bridge Env</h2>
        <pre>export XHUB_RUST_MODEL_INVENTORY_BRIDGE=1
export XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL=http://127.0.0.1:50151</pre>
      </div>
      <div class="panel full">
        <h2>Raw Readiness</h2>
        <pre id="raw">Loading...</pre>
      </div>
    </section>
  </main>
  <script>
    const text = (value) => value === undefined || value === null || value === '' ? '-' : String(value);
    const row = (name, value) => `<dt>${name}</dt><dd>${text(value)}</dd>`;
    async function load() {
      const overall = document.getElementById('overall');
      try {
        const response = await fetch('/ready', { headers: { accept: 'application/json' } });
        const ready = await response.json();
        overall.className = ready.ready ? 'status ok' : 'status bad';
        overall.lastElementChild.textContent = ready.ready ? 'Ready' : 'Not ready';
        document.getElementById('daemon').innerHTML = [
          row('Mode', ready.mode),
          row('Version', ready.version),
          row('HTTP', ready.http_addr),
          row('Schema', ready.schema_version),
          row('SQLite', ready.storage && ready.storage.db_path)
        ].join('');
        document.getElementById('runtime').innerHTML = [
          row('Runtime dir', ready.runtime && ready.runtime.runtime_base_dir),
          row('Runtime status', ready.runtime && ready.runtime.runtime_status_file_exists),
          row('Provider store', ready.runtime && ready.runtime.provider_store_file_exists),
          row('Model inventory HTTP', ready.capabilities && ready.capabilities.model_inventory_http),
          row('Local model repair plan HTTP', ready.capabilities && ready.capabilities.model_local_repair_plan_http),
          row('Local model repair apply HTTP', ready.capabilities && ready.capabilities.model_local_repair_apply_http),
          row('Local model repair jobs HTTP', ready.capabilities && ready.capabilities.model_local_repair_jobs_http),
          row('Model diagnostics HTTP', ready.capabilities && ready.capabilities.model_route_diagnostics_http),
          row('Provider route HTTP', ready.capabilities && ready.capabilities.provider_route_http),
          row('Provider import HTTP', ready.capabilities && ready.capabilities.provider_key_import_http),
          row('Provider quota plan HTTP', ready.capabilities && ready.capabilities.provider_openai_quota_plan_http),
          row('Provider quota apply HTTP', ready.capabilities && ready.capabilities.provider_openai_quota_apply_http),
          row('Provider quota failure HTTP', ready.capabilities && ready.capabilities.provider_openai_quota_failure_http),
          row('Provider OAuth apply HTTP', ready.capabilities && ready.capabilities.provider_oauth_refresh_apply_http),
          row('Provider OAuth failure HTTP', ready.capabilities && ready.capabilities.provider_oauth_refresh_failure_http),
          row('Provider Codex OAuth plan HTTP', ready.capabilities && ready.capabilities.provider_oauth_refresh_codex_plan_http),
          row('Provider Codex OAuth HTTP', ready.capabilities && ready.capabilities.provider_oauth_refresh_codex_http),
          row('Skills catalog HTTP', ready.capabilities && ready.capabilities.skills_catalog_http),
          row('Skills preflight HTTP', ready.capabilities && ready.capabilities.skills_preflight_http)
        ].join('');
        document.getElementById('checks').innerHTML = (ready.checks || []).map((item) => {
          const klass = item.ok ? 'check good' : 'check fail';
          return `<div class="${klass}"><span>${text(item.name)}</span><span>${item.ok ? 'OK' : 'FAIL'}</span></div>`;
        }).join('');
        document.getElementById('raw').textContent = JSON.stringify(ready, null, 2);
      } catch (error) {
        overall.className = 'status bad';
        overall.lastElementChild.textContent = 'Unavailable';
        document.getElementById('raw').textContent = String(error && error.message || error);
      }
    }
    load();
  </script>
</body>
</html>
"#
    .to_string()
}
