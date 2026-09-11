import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const MODULE_TOOLS_DIR = path.dirname(fileURLToPath(import.meta.url));

export const XHUB_SYSTEM_ROOT_MARKERS = Object.freeze([
  path.join('rust', 'xhubd', 'Cargo.toml'),
  path.join('rust', 'xhubd', 'tools', 'package_rust_hub.command'),
  path.join('x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'services.js'),
  path.join('x-terminal', 'Package.swift'),
]);

export const NODE_HUB_SOURCE_MARKERS = Object.freeze(['services.js']);

function safeString(value) {
  return String(value ?? '').trim();
}

function resolvedPath(value) {
  const text = safeString(value);
  return text ? path.resolve(text) : '';
}

function missingMarkers(candidate, markers) {
  return markers.filter((marker) => !fs.existsSync(path.join(candidate, marker)));
}

function ancestorPaths(startDir) {
  const paths = [];
  let current = path.resolve(startDir);
  for (;;) {
    paths.push(current);
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
  return paths;
}

function findSystemRoot(startDir) {
  for (const candidate of ancestorPaths(startDir)) {
    if (missingMarkers(candidate, XHUB_SYSTEM_ROOT_MARKERS).length === 0) {
      return candidate;
    }
  }
  return '';
}

function findContainingApp(startDir) {
  for (const candidate of ancestorPaths(startDir)) {
    if (path.basename(candidate) !== 'Resources') continue;
    const contentsDir = path.dirname(candidate);
    const appPath = path.dirname(contentsDir);
    if (path.basename(contentsDir) === 'Contents' && path.extname(appPath) === '.app') {
      return { appPath, resourcesDir: candidate };
    }
  }
  return null;
}

export function validateXHubSystemRoot(candidate, options = {}) {
  const resolved = resolvedPath(candidate);
  if (!resolved) {
    throw new Error('X-Hub system root is empty');
  }
  const markers = options.markers || XHUB_SYSTEM_ROOT_MARKERS;
  const missing = missingMarkers(resolved, markers);
  if (missing.length > 0) {
    throw new Error(
      `invalid X-Hub system root ${resolved}; missing markers: ${missing.join(', ')}`,
    );
  }
  return resolved;
}

export function validateNodeHubSourceDir(candidate, options = {}) {
  const resolved = resolvedPath(candidate);
  if (!resolved) {
    throw new Error('Node Hub source directory is empty');
  }
  const markers = options.markers || NODE_HUB_SOURCE_MARKERS;
  const missing = missingMarkers(resolved, markers);
  if (missing.length > 0) {
    throw new Error(
      `invalid Node Hub source directory ${resolved}; missing markers: ${missing.join(', ')}`,
    );
  }
  return resolved;
}

export function tryResolveXHubSystemRoot(options = {}) {
  const env = options.env || process.env;
  const startDir = options.startDir || MODULE_TOOLS_DIR;
  const explicit = safeString(env.XHUB_SYSTEM_ROOT);
  if (explicit) {
    return validateXHubSystemRoot(explicit);
  }

  return findSystemRoot(startDir);
}

export function resolveXHubSystemRoot(options = {}) {
  const startDir = options.startDir || MODULE_TOOLS_DIR;
  const resolved = tryResolveXHubSystemRoot(options);
  if (resolved) return resolved;

  throw new Error(
    `unable to locate the X-Hub system root from ${path.resolve(startDir)}; `
      + 'set XHUB_SYSTEM_ROOT to a canonical repository root',
  );
}

function explicitNodeHubSourceDir(env) {
  const primary = safeString(env.XHUB_NODE_HUB_SRC_DIR);
  const compatibility = safeString(env.XHUB_HUB_GRPC_SERVER_SRC_DIR);
  if (primary && compatibility && resolvedPath(primary) !== resolvedPath(compatibility)) {
    throw new Error(
      'conflicting Node Hub source overrides: '
        + 'XHUB_NODE_HUB_SRC_DIR and XHUB_HUB_GRPC_SERVER_SRC_DIR differ',
    );
  }
  return primary || compatibility;
}

export function resolveDefaultXHubAppPath(options = {}) {
  const env = options.env || process.env;
  const startDir = options.startDir || MODULE_TOOLS_DIR;
  const containingApp = findContainingApp(startDir);
  if (containingApp) return containingApp.appPath;

  const explicitRoot = safeString(env.XHUB_SYSTEM_ROOT);
  if (explicitRoot) {
    return path.join(validateXHubSystemRoot(explicitRoot), 'build', 'X-Hub.app');
  }

  const discoveredRoot = findSystemRoot(startDir);
  if (discoveredRoot) {
    return path.join(discoveredRoot, 'build', 'X-Hub.app');
  }

  return '/Applications/X-Hub.app';
}

export function resolveNodeHubSourceDir(options = {}) {
  const env = options.env || process.env;
  const startDir = options.startDir || MODULE_TOOLS_DIR;
  const markers = options.markers || NODE_HUB_SOURCE_MARKERS;
  const explicitRootText = safeString(env.XHUB_SYSTEM_ROOT);
  const explicitRoot = explicitRootText ? validateXHubSystemRoot(explicitRootText) : '';
  const explicitSource = explicitNodeHubSourceDir(env);
  if (explicitSource) {
    return validateNodeHubSourceDir(explicitSource, { markers });
  }

  if (explicitRoot) {
    return validateNodeHubSourceDir(
      path.join(explicitRoot, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src'),
      { markers },
    );
  }

  const containingApp = findContainingApp(startDir);
  if (containingApp) {
    return validateNodeHubSourceDir(
      path.join(containingApp.resourcesDir, 'hub_grpc_server', 'src'),
      { markers },
    );
  }

  const discoveredRoot = findSystemRoot(startDir);
  if (discoveredRoot) {
    return validateNodeHubSourceDir(
      path.join(discoveredRoot, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src'),
      { markers },
    );
  }

  const installedSource = path.join(
    '/Applications',
    'X-Hub.app',
    'Contents',
    'Resources',
    'hub_grpc_server',
    'src',
  );
  if (missingMarkers(installedSource, markers).length === 0) {
    return installedSource;
  }

  throw new Error(
    `unable to locate Node Hub source from ${path.resolve(startDir)}; `
      + 'set XHUB_NODE_HUB_SRC_DIR or XHUB_SYSTEM_ROOT to a validated location',
  );
}

export function validateHubProtocolPath(candidate) {
  const resolved = resolvedPath(candidate);
  if (!resolved) {
    throw new Error('Hub protocol path is empty');
  }
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    throw new Error(`invalid Hub protocol path ${resolved}; file does not exist`);
  }
  return resolved;
}

export function resolveHubProtocolPath(options = {}) {
  const env = options.env || process.env;
  const startDir = options.startDir || MODULE_TOOLS_DIR;
  const explicitRootText = safeString(env.XHUB_SYSTEM_ROOT);
  const explicitRoot = explicitRootText ? validateXHubSystemRoot(explicitRootText) : '';
  const explicitPath = safeString(options.explicitPath || env.XHUB_HUB_PROTOCOL_PATH);
  if (explicitPath) return validateHubProtocolPath(explicitPath);

  if (explicitRoot) {
    return validateHubProtocolPath(path.join(explicitRoot, 'protocol', 'hub_protocol_v1.proto'));
  }

  const containingApp = findContainingApp(startDir);
  if (containingApp) {
    return validateHubProtocolPath(
      path.join(containingApp.resourcesDir, 'protocol', 'hub_protocol_v1.proto'),
    );
  }

  const discoveredRoot = findSystemRoot(startDir);
  if (discoveredRoot) {
    return validateHubProtocolPath(
      path.join(discoveredRoot, 'protocol', 'hub_protocol_v1.proto'),
    );
  }

  for (const candidate of ancestorPaths(startDir)) {
    const packagedPath = path.join(candidate, 'assets', 'proto', 'hub_protocol_v1.proto');
    if (fs.existsSync(packagedPath) && fs.statSync(packagedPath).isFile()) {
      return packagedPath;
    }
  }

  const installedPath = path.join(
    '/Applications',
    'X-Hub.app',
    'Contents',
    'Resources',
    'protocol',
    'hub_protocol_v1.proto',
  );
  if (fs.existsSync(installedPath) && fs.statSync(installedPath).isFile()) {
    return installedPath;
  }

  throw new Error(
    `unable to locate hub_protocol_v1.proto from ${path.resolve(startDir)}; `
      + 'set XHUB_HUB_PROTOCOL_PATH or XHUB_SYSTEM_ROOT to a validated location',
  );
}
