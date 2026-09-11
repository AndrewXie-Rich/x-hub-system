import assert from 'node:assert/strict';
import test from 'node:test';
import { readCanonicalBacklog, validateBacklog } from '../scripts/check_product_readiness_backlog.mjs';

test('canonical backlog is acyclic and agrees with Markdown', () => {
  const { backlog, markdown } = readCanonicalBacklog();
  assert.deepEqual(validateBacklog(backlog, markdown), []);
});

test('original R1 dependency cycle and authority drift are rejected', () => {
  const { backlog, markdown } = readCanonicalBacklog();
  backlog.work_orders.find((order) => order.id === 'XT-R1-05').depends_on.push('XT-R1-08');
  const errors = validateBacklog(backlog, markdown);
  assert(errors.some((error) => error.includes('dependency drift: XT-R1-05')));
  assert(errors.some((error) => error.includes('XT-R1-05 -> XT-R1-08 -> XT-R1-07 -> XT-R1-05')));
});

test('duplicate and missing dependencies and orders fail closed', () => {
  const { backlog, markdown } = readCanonicalBacklog();
  backlog.work_orders[0].depends_on = ['XT-R9-99', 'XT-R9-99'];
  backlog.work_orders.push(structuredClone(backlog.work_orders[0]));
  backlog.work_orders.splice(2, 1);
  const errors = validateBacklog(backlog, markdown);
  for (const expected of ['duplicate id', 'duplicate dependency', 'unknown dependency', 'missing backlog order']) {
    assert(errors.some((error) => error.includes(expected)), expected);
  }
});

test('conditional profile cycles are rejected independently of baseline', () => {
  const { backlog, markdown } = readCanonicalBacklog();
  backlog.work_orders.find((order) => order.id === 'XT-R4-07')
    .conditional_dependencies.governed_remote_preview.push('XT-R4-07');
  const errors = validateBacklog(backlog, markdown);
  assert(errors.some((error) => error.includes('dependency cycle (governed_remote_preview)')));
  assert(!errors.some((error) => error.includes('dependency cycle (baseline)')));
});

test('missing Markdown sections and conditional mappings are rejected', () => {
  const { backlog, markdown } = readCanonicalBacklog();
  delete backlog.work_orders.find((order) => order.id === 'XT-R4-07').conditional_dependencies;
  const errors = validateBacklog(backlog, markdown.replace('## XT-R1-05 —', '## Removed —'));
  assert(errors.some((error) => error.includes('missing Markdown order: XT-R1-05')));
  assert(errors.some((error) => error.includes('missing conditional dependencies: XT-R4-07')));
});
