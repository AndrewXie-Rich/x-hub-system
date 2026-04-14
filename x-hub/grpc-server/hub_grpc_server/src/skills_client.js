import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

import { makeClientCredentials } from './client_credentials.js';
import { resolveHubProtoPath } from './proto_path.js';

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

function metadataFromEnv() {
  const tok = (process.env.HUB_CLIENT_TOKEN || '').trim();
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

function reqClientFromEnv({ project_id_override = '' } = {}) {
  return {
    device_id: (process.env.HUB_DEVICE_ID || 'terminal_device').trim(),
    user_id: (process.env.HUB_USER_ID || '').trim(),
    app_id: (process.env.HUB_APP_ID || 'x_terminal').trim(),
    project_id: (project_id_override || process.env.HUB_PROJECT_ID || '').trim(),
    session_id: (process.env.HUB_SESSION_ID || '').trim(),
  };
}

function usage() {
  // eslint-disable-next-line no-console
  console.log(`skills_client.js - HubSkills helper (client kit)

Usage:
  node src/skills_client.js search --query "email" [--source <id>] [--limit 20]
  node src/skills_client.js upload --file <skill.tgz> [--source <id>] [--manifest <skill.json>]
  node src/skills_client.js import --file <skill.tgz> --scope global|project [--project-id <id>] [--note "..."] [--source <id>] [--manifest <skill.json>]
  node src/skills_client.js pin --scope global|project --skill <skill_id> --sha <package_sha256> [--project-id <id>] [--note "..."]
  node src/skills_client.js resolved [--project-id <id>]
  node src/skills_client.js manifest --sha <package_sha256>
  node src/skills_client.js download --sha <package_sha256> --out <file.tgz>

Env:
  HUB_HOST/HUB_PORT/HUB_CLIENT_TOKEN/HUB_DEVICE_ID (from axhubctl install-client)
  HUB_USER_ID/HUB_APP_ID/HUB_PROJECT_ID (optional; server overrides user_id when paired)
`);
}

function readFileBuf(fp) {
  const p = String(fp || '').trim();
  if (!p) throw new Error('missing file path');
  return fs.readFileSync(p);
}

function readString(buf, off, len) {
  return buf.slice(off, off + len).toString('utf8').replace(/\0.*$/g, '').trim();
}

function parseOctalInt(s) {
  const t = String(s || '').replace(/\0.*$/g, '').trim();
  if (!t) return 0;
  // Some tars may include leading spaces.
  return Number.parseInt(t, 8) || 0;
}

function isAllZero(buf) {
  for (let i = 0; i < buf.length; i += 1) {
    if (buf[i] !== 0) return false;
  }
  return true;
}

function extractManifestFromTarBytes(tarBytes) {
  // Minimal tar reader (512-byte blocks). Best-effort support for GNU longname entries.
  let off = 0;
  let nextLongName = '';

  while (off + 512 <= tarBytes.length) {
    const header = tarBytes.slice(off, off + 512);
    if (isAllZero(header)) break;

    const name = readString(header, 0, 100);
    const prefix = readString(header, 345, 155);
    const size = parseOctalInt(readString(header, 124, 12));
    const typeflag = header[156]; // '0' or 0 for file; 'L' for GNU longname

    const dataOff = off + 512;
    const dataEnd = dataOff + size;
    const padded = Math.ceil(size / 512) * 512;
    const nextOff = dataOff + padded;

    let fullName = name;
    if (nextLongName) {
      fullName = nextLongName;
      nextLongName = '';
    } else if (prefix) {
      fullName = `${prefix}/${name}`;
    }

    if (typeflag === 76 /* 'L' */) {
      // GNU longname: data contains the full name for the next entry.
      if (dataEnd <= tarBytes.length) {
        nextLongName = tarBytes.slice(dataOff, dataEnd).toString('utf8').replace(/\0.*$/g, '').trim();
      }
      off = nextOff;
      continue;
    }

    const isFile = typeflag === 0 || typeflag === 48 /* '0' */;
    if (isFile && dataEnd <= tarBytes.length) {
      const lower = String(fullName || '').toLowerCase();
      if (lower === 'skill.json' || lower.endsWith('/skill.json')) {
        const text = tarBytes.slice(dataOff, dataEnd).toString('utf8');
        // Validate parseable JSON early.
        JSON.parse(text);
        return text;
      }
    }

    off = nextOff;
  }

  throw new Error('skill.json not found in tar archive (use --manifest to provide it explicitly)');
}

function extractManifestFromPackageBytes(pkgBytes) {
  const b = Buffer.isBuffer(pkgBytes) ? pkgBytes : Buffer.from(pkgBytes || []);
  if (b.length < 2) throw new Error('empty package');

  // gzip magic: 1F 8B
  const isGzip = b[0] === 0x1f && b[1] === 0x8b;
  const tarBytes = isGzip ? zlib.gunzipSync(b) : b;
  return extractManifestFromTarBytes(tarBytes);
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (!a.startsWith('--')) {
      args._.push(a);
      continue;
    }
    const k = a.slice(2);
    const v = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : 'true';
    if (v !== 'true') i += 1;
    args[k] = v;
  }
  return args;
}

async function unary(client, method, req, md) {
  return await new Promise((resolve, reject) => {
    client[method](req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out);
    });
  });
}

async function main() {
  const argv = process.argv.slice(2);
  const cmd = (argv[0] || '').trim();
  if (!cmd || cmd === 'help' || cmd === '--help' || cmd === '-h') {
    usage();
    return;
  }

  const host = (process.env.HUB_HOST || '127.0.0.1').trim();
  const port = Number(process.env.HUB_PORT || 50051);
  const addr = `${host}:${port}`;

  const proto = loadProto(resolveHubProtoPath(process.env));
  if (!proto?.HubSkills) {
    throw new Error('failed to load HubSkills service from proto');
  }

  const md = metadataFromEnv();
  const { creds, options } = makeClientCredentials(process.env);
  const skillsClient = new proto.HubSkills(addr, creds, options);

  const args = parseArgs(argv.slice(1));

  if (cmd === 'search') {
    const query = String(args.query || '').trim();
    const source = String(args.source || args['source-filter'] || '').trim();
    const limit = Number(args.limit || 20);
    const resp = await unary(
      skillsClient,
      'SearchSkills',
      { client: reqClientFromEnv(), query, source_filter: source, limit },
      md
    );
    const results = Array.isArray(resp?.results) ? resp.results : [];
    // eslint-disable-next-line no-console
    console.log(`Hub connected: ${addr}`);
    // eslint-disable-next-line no-console
    console.log(`Results: ${results.length}`);
    for (const r of results) {
      const sid = String(r?.skill_id || '');
      const ver = String(r?.version || '');
      const name = String(r?.name || sid);
      const sha = String(r?.package_sha256 || '');
      const src = String(r?.source_id || '');
      // eslint-disable-next-line no-console
      console.log(`- ${name} | ${sid}@${ver} | src=${src}${sha ? ` | sha256=${sha}` : ''}`);
    }
    return;
  }

  if (cmd === 'upload' || cmd === 'import') {
    const filePath = String(args.file || '').trim();
    if (!filePath) throw new Error('--file is required');
    const source_id = String(args.source || 'local:upload').trim() || 'local:upload';

    const pkgBytes = readFileBuf(filePath);
    let manifestText = '';
    const manifestPath = String(args.manifest || '').trim();
    if (manifestPath) {
      manifestText = fs.readFileSync(manifestPath, 'utf8');
      JSON.parse(manifestText);
    } else {
      manifestText = extractManifestFromPackageBytes(pkgBytes);
    }

    const uploadResp = await unary(
      skillsClient,
      'UploadSkillPackage',
      {
        client: reqClientFromEnv(),
        request_id: '',
        source_id,
        package_bytes: pkgBytes,
        manifest_json: manifestText,
        created_at_ms: String(Date.now()),
      },
      md
    );

    const sha = String(uploadResp?.package_sha256 || '');
    const skillId = String(uploadResp?.skill?.skill_id || '');
    // eslint-disable-next-line no-console
    console.log(`Uploaded: ${path.basename(filePath)} -> sha256=${sha} skill_id=${skillId}`);

    if (cmd === 'upload') return;

    const scope = String(args.scope || '').trim().toLowerCase();
    if (scope !== 'global' && scope !== 'project') {
      throw new Error('--scope global|project is required for import');
    }
    const project_id = scope === 'project' ? String(args['project-id'] || '').trim() : '';
    const note = String(args.note || '').trim();

    const clientIdent = reqClientFromEnv({ project_id_override: project_id });
    const pinResp = await unary(
      skillsClient,
      'SetSkillPin',
      {
        client: clientIdent,
        request_id: '',
        scope: scope === 'global' ? 'SKILL_PIN_SCOPE_GLOBAL' : 'SKILL_PIN_SCOPE_PROJECT',
        skill_id: skillId,
        package_sha256: sha,
        note,
        created_at_ms: String(Date.now()),
      },
      md
    );

    // eslint-disable-next-line no-console
    console.log(
      `Pinned: scope=${String(pinResp?.scope || '')} skill_id=${String(pinResp?.skill_id || '')} sha256=${String(
        pinResp?.package_sha256 || ''
      )}`
    );
    return;
  }

  if (cmd === 'pin') {
    const scope = String(args.scope || '').trim().toLowerCase();
    if (scope !== 'global' && scope !== 'project') {
      throw new Error('--scope global|project is required');
    }
    const skill_id = String(args.skill || '').trim();
    const sha = String(args.sha || '').trim();
    if (!skill_id) throw new Error('--skill is required');
    if (!sha) throw new Error('--sha is required');
    const project_id = scope === 'project' ? String(args['project-id'] || '').trim() : '';
    const note = String(args.note || '').trim();

    const clientIdent = reqClientFromEnv({ project_id_override: project_id });
    const resp = await unary(
      skillsClient,
      'SetSkillPin',
      {
        client: clientIdent,
        request_id: '',
        scope: scope === 'global' ? 'SKILL_PIN_SCOPE_GLOBAL' : 'SKILL_PIN_SCOPE_PROJECT',
        skill_id,
        package_sha256: sha,
        note,
        created_at_ms: String(Date.now()),
      },
      md
    );
    // eslint-disable-next-line no-console
    console.log(
      `Pinned: scope=${String(resp?.scope || '')} user_id=${String(resp?.user_id || '')} project_id=${String(
        resp?.project_id || ''
      )} skill_id=${String(resp?.skill_id || '')} sha256=${String(resp?.package_sha256 || '')}`
    );
    return;
  }

  if (cmd === 'resolved') {
    const project_id = String(args['project-id'] || '').trim();
    const resp = await unary(
      skillsClient,
      'ListResolvedSkills',
      { client: reqClientFromEnv({ project_id_override: project_id }) },
      md
    );
    const skills = Array.isArray(resp?.skills) ? resp.skills : [];
    // eslint-disable-next-line no-console
    console.log(`Resolved skills: ${skills.length}`);
    for (const r of skills) {
      const scope = String(r?.scope || '');
      const s = r?.skill || {};
      // eslint-disable-next-line no-console
      console.log(`- ${String(s?.skill_id || '')}@${String(s?.version || '')} | ${scope} | ${String(s?.package_sha256 || '')}`);
    }
    return;
  }

  if (cmd === 'manifest') {
    const sha = String(args.sha || '').trim();
    if (!sha) throw new Error('--sha is required');
    const resp = await unary(skillsClient, 'GetSkillManifest', { client: reqClientFromEnv(), package_sha256: sha }, md);
    // eslint-disable-next-line no-console
    console.log(String(resp?.manifest_json || '').trim());
    return;
  }

  if (cmd === 'download') {
    const sha = String(args.sha || '').trim();
    const outPath = String(args.out || '').trim();
    if (!sha) throw new Error('--sha is required');
    if (!outPath) throw new Error('--out is required');

    await new Promise((resolve, reject) => {
      const ws = fs.createWriteStream(outPath);
      const call = skillsClient.DownloadSkillPackage({ client: reqClientFromEnv(), package_sha256: sha }, md);
      call.on('data', (msg) => {
        const b = msg?.data;
        if (Buffer.isBuffer(b) && b.length) ws.write(b);
      });
      call.on('end', () => {
        try {
          ws.end();
        } catch {
          // ignore
        }
        resolve();
      });
      call.on('error', (err) => {
        try {
          ws.close();
        } catch {
          // ignore
        }
        reject(err);
      });
    });

    // eslint-disable-next-line no-console
    console.log(`Downloaded: sha256=${sha} -> ${outPath}`);
    return;
  }

  throw new Error(`unknown command: ${cmd}`);
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error('skills client failed:', e?.message || e);
  process.exit(1);
});
