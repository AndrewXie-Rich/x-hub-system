import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { loadSkillSources, searchSkills } from './skills_store.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function makeTmpDir(label) {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const dir = path.join(os.tmpdir(), `xhub_skills_catalog_${token}`);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function cleanupDir(dir) {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch {
    // ignore
  }
}

run('builtin catalog includes default agent baseline skill entries', () => {
  const runtimeBaseDir = makeTmpDir('baseline_catalog');
  try {
    const sources = loadSkillSources(runtimeBaseDir);
    const builtin = Array.isArray(sources.sources)
      ? sources.sources.find((it) => String(it?.source_id || '') === 'builtin:catalog')
      : null;
    assert.ok(builtin);

    const discovery = Array.isArray(builtin.discovery_index) ? builtin.discovery_index : [];
    const skillIds = discovery.map((it) => String(it?.skill_id || ''));

    assert.ok(skillIds.includes('find-skills'));
    assert.ok(skillIds.includes('agent-browser'));
    assert.ok(skillIds.includes('self-improving-agent'));
    assert.ok(skillIds.includes('summarize'));
  } finally {
    cleanupDir(runtimeBaseDir);
  }
});

run('searchSkills surfaces default baseline skills with official install hints', () => {
  const runtimeBaseDir = makeTmpDir('baseline_search');
  try {
    const results = searchSkills(runtimeBaseDir, {
      query: '',
      sourceFilter: 'builtin:catalog',
      limit: 20,
    });
    const byId = new Map(results.map((it) => [String(it.skill_id || ''), it]));

    for (const skillId of ['find-skills', 'agent-browser', 'self-improving-agent', 'summarize']) {
      assert.ok(byId.has(skillId), `expected builtin catalog result for ${skillId}`);
      assert.equal(String(byId.get(skillId).publisher_id || ''), 'xhub.official');
      const installHint = String(byId.get(skillId).install_hint || '');
      assert.ok(installHint.includes('baseline') || installHint.includes('Recommended default managed skill'));
    }
  } finally {
    cleanupDir(runtimeBaseDir);
  }
});
