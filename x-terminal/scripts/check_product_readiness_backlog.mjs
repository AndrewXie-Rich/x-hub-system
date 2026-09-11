import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const xtRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const idPattern = /^XT-R\d+-\d{2}$/;

function expandDependencies(text) {
  if (text === 'none') return [];
  return text.split(',').flatMap((entry) => {
    const token = entry.trim();
    if (idPattern.test(token)) return [token];
    const range = token.match(/^(XT-R\d+-)(\d{2})\.\.(XT-R\d+-)(\d{2})$/);
    if (!range || range[1] !== range[3] || Number(range[2]) > Number(range[4])) {
      throw new Error(`invalid dependency range: ${token}`);
    }
    return Array.from({ length: Number(range[4]) - Number(range[2]) + 1 }, (_, index) =>
      range[1] + String(Number(range[2]) + index).padStart(2, '0'));
  });
}

export function validateBacklog(backlog, markdown) {
  const errors = [];
  const orders = backlog.work_orders;
  if (!Array.isArray(orders) || orders.length === 0) return ['work_orders must be nonempty'];
  const indexed = new Map();
  const sections = new Map();
  for (const match of markdown.matchAll(/^## (XT-R\d+-\d{2}) —[^\n]*\n([\s\S]*?)(?=^## |$(?![\s\S]))/gm)) {
    if (sections.has(match[1])) errors.push(`duplicate Markdown id: ${match[1]}`);
    sections.set(match[1], match[2]);
  }
  for (const order of orders) {
    if (!idPattern.test(order.id)) errors.push(`invalid id: ${order.id}`);
    if (indexed.has(order.id)) errors.push(`duplicate id: ${order.id}`);
    indexed.set(order.id, order);
  }
  const dependenciesFor = (order, profile) => [
    ...(Array.isArray(order.depends_on) ? order.depends_on : []),
    ...(Array.isArray(order.conditional_dependencies?.[profile]) ? order.conditional_dependencies[profile] : [])
  ];
  const profiles = new Set(['baseline', ...Object.keys(backlog.release_profiles ?? {})]);
  for (const order of orders) {
    const section = sections.get(order.id);
    if (!section) errors.push(`missing Markdown order: ${order.id}`);
    const declared = section?.match(/^- depends_on: (.+)$/m)?.[1];
    try {
      const expected = expandDependencies(declared ?? '');
      if (JSON.stringify([...expected].sort()) !== JSON.stringify([...(order.depends_on ?? [])].sort())) {
        errors.push(`dependency drift: ${order.id}`);
      }
    } catch (error) {
      errors.push(`${order.id}: ${error.message}`);
    }
    const conditional = order.conditional_dependencies ?? {};
    for (const [profile, dependencies] of Object.entries(conditional)) {
      profiles.add(profile);
      const baseProfile = profile.split('_when_')[0];
      if (!backlog.release_profiles?.[baseProfile]) errors.push(`unknown profile: ${profile}`);
      const line = section?.split('\n').find((entry) => entry.startsWith(`- conditional_depends_on: ${profile} requires `));
      try {
        const expected = expandDependencies(line?.split(' requires ')[1] ?? '');
        if (JSON.stringify(expected.sort()) !== JSON.stringify([...dependencies].sort())) {
          errors.push(`conditional dependency drift: ${order.id}/${profile}`);
        }
      } catch (error) {
        errors.push(`${order.id}/${profile}: ${error.message}`);
      }
    }
    for (const match of (section ?? '').matchAll(/^- conditional_depends_on: (\S+) requires /gm)) {
      if (!Object.hasOwn(conditional, match[1])) errors.push(`missing conditional dependencies: ${order.id}/${match[1]}`);
    }
    for (const dependencies of [order.depends_on, ...Object.values(conditional)]) {
      if (!Array.isArray(dependencies)) {
        errors.push(`dependencies must be arrays: ${order.id}`);
        continue;
      }
      if (new Set(dependencies).size !== dependencies.length) errors.push(`duplicate dependency: ${order.id}`);
      for (const dependency of dependencies) {
        if (!indexed.has(dependency)) errors.push(`unknown dependency: ${order.id} -> ${dependency}`);
      }
    }
  }
  for (const id of sections.keys()) {
    if (!indexed.has(id)) errors.push(`missing backlog order: ${id}`);
  }
  for (const profile of profiles) {
    const complete = new Set();
    const active = [];
    const visit = (id) => {
      if (active.includes(id)) {
        errors.push(`dependency cycle (${profile}): ${[...active.slice(active.indexOf(id)), id].join(' -> ')}`);
        return;
      }
      if (complete.has(id) || !indexed.has(id)) return;
      active.push(id);
      for (const dependency of dependenciesFor(indexed.get(id), profile)) visit(dependency);
      active.pop();
      complete.add(id);
    };
    for (const id of indexed.keys()) visit(id);
  }
  return errors;
}

export function readCanonicalBacklog() {
  return {
    backlog: JSON.parse(fs.readFileSync(path.join(xtRoot, 'work-orders/xt-v1-product-readiness-backlog.v1.json'), 'utf8')),
    markdown: fs.readFileSync(path.join(xtRoot, 'work-orders/xt-v1-product-readiness-golden-path-execution-pack-v1.md'), 'utf8')
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { backlog, markdown } = readCanonicalBacklog();
  const errors = validateBacklog(backlog, markdown);
  for (const error of errors) console.error(`[xt-backlog] FAIL ${error}`);
  if (errors.length === 0) console.log(`[xt-backlog] PASS ${backlog.work_orders.length} orders: references, acyclic dependencies, Markdown parity`);
  process.exitCode = errors.length === 0 ? 0 : 1;
}
