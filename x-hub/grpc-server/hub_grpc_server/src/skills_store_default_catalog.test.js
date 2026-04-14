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

function writeFile(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, contents, 'utf8');
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
    assert.ok(skillIds.includes('supervisor-voice'));
  } finally {
    cleanupDir(runtimeBaseDir);
  }
});

run('searchSkills surfaces supervisor voice as a builtin XT helper skill', () => {
  const runtimeBaseDir = makeTmpDir('builtin_supervisor_voice');
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
  try {
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = path.join(runtimeBaseDir, 'no-official-dist');
    const results = searchSkills(runtimeBaseDir, {
      query: 'supervisor voice',
      sourceFilter: 'builtin:catalog',
      limit: 10,
    });
    const voice = results.find((it) => String(it?.skill_id || '') === 'supervisor-voice');
    assert.ok(voice);
    assert.equal(String(voice.publisher_id || ''), 'xhub.official');
    assert.equal(String(voice.risk_level || ''), 'low');
    assert.equal(!!voice.requires_grant, false);
    assert.equal(String(voice.side_effect_class || ''), 'local_side_effect');
    assert.ok(String(voice.install_hint || '').includes('built-in') || String(voice.install_hint || '').includes('Built'));
  } finally {
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    cleanupDir(runtimeBaseDir);
  }
});

run('searchSkills surfaces source-present local model wrappers without pretending they are published packages', () => {
  const runtimeBaseDir = makeTmpDir('builtin_local_model_wrappers');
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
  try {
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = path.join(runtimeBaseDir, 'no-official-dist');
    const results = searchSkills(runtimeBaseDir, {
      query: '',
      sourceFilter: 'builtin:catalog',
      limit: 50,
    });
    const byId = new Map(results.map((it) => [String(it?.skill_id || ''), it]));
    const expected = {
      'local-embeddings': {
        capability: 'ai.embed.local',
        risk_level: 'low',
        side_effect_class: 'read_only',
      },
      'local-transcribe': {
        capability: 'ai.audio.local',
        risk_level: 'medium',
        side_effect_class: 'read_only',
      },
      'local-vision': {
        capability: 'ai.vision.local',
        risk_level: 'medium',
        side_effect_class: 'read_only',
      },
      'local-ocr': {
        capability: 'ai.vision.local',
        risk_level: 'medium',
        side_effect_class: 'read_only',
      },
      'local-tts': {
        capability: 'ai.audio.tts.local',
        risk_level: 'low',
        side_effect_class: 'local_side_effect',
      },
    };

    for (const [skillId, governance] of Object.entries(expected)) {
      assert.ok(byId.has(skillId), `expected builtin catalog result for ${skillId}`);
      const skill = byId.get(skillId);
      assert.equal(String(skill.publisher_id || ''), 'xhub.official');
      assert.equal(String(skill.package_sha256 || ''), '');
      assert.equal(String(skill.risk_level || ''), governance.risk_level);
      assert.equal(String(skill.side_effect_class || ''), governance.side_effect_class);
      assert.equal(!!skill.requires_grant, false);
      assert.ok(Array.isArray(skill.capabilities_required));
      assert.ok(skill.capabilities_required.includes(governance.capability));
      assert.ok(String(skill.install_hint || '').includes('source-present only'));
    }
  } finally {
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    cleanupDir(runtimeBaseDir);
  }
});

run('searchSkills surfaces default baseline skills with official install hints', () => {
  const runtimeBaseDir = makeTmpDir('baseline_search');
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
  try {
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = path.join(runtimeBaseDir, 'no-official-dist');
    const results = searchSkills(runtimeBaseDir, {
      query: '',
      sourceFilter: 'builtin:catalog',
      limit: 20,
    });
    const byId = new Map(results.map((it) => [String(it.skill_id || ''), it]));
    const ids = results.map((it) => String(it.skill_id || ''));
    assert.equal(new Set(ids).size, ids.length, 'expected builtin catalog search results to be deduped by skill_id');

    const expectedGovernance = {
      'find-skills': { risk_level: 'low', requires_grant: false, side_effect_class: 'read_only' },
      'agent-browser': { risk_level: 'high', requires_grant: true, side_effect_class: 'external_side_effect' },
      'self-improving-agent': { risk_level: 'medium', requires_grant: false, side_effect_class: 'read_only' },
      summarize: { risk_level: 'medium', requires_grant: false, side_effect_class: 'read_only' },
    };

    for (const skillId of ['find-skills', 'agent-browser', 'self-improving-agent', 'summarize']) {
      assert.ok(byId.has(skillId), `expected builtin catalog result for ${skillId}`);
      assert.equal(String(byId.get(skillId).publisher_id || ''), 'xhub.official');
      const installHint = String(byId.get(skillId).install_hint || '');
      assert.ok(
        installHint.includes('Install')
        || installHint.includes('Pin from the official Agent catalog')
        || installHint.includes('baseline')
        || installHint.includes('Baseline')
      );
      assert.equal(String(byId.get(skillId).risk_level || ''), expectedGovernance[skillId].risk_level);
      assert.equal(!!byId.get(skillId).requires_grant, expectedGovernance[skillId].requires_grant);
      assert.equal(String(byId.get(skillId).side_effect_class || ''), expectedGovernance[skillId].side_effect_class);
    }
  } finally {
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    cleanupDir(runtimeBaseDir);
  }
});

run('loadSkillSources keeps builtin catalog authoritative when custom file tries to shadow it', () => {
  const runtimeBaseDir = makeTmpDir('builtin_shadow');
  const sourceRoot = makeTmpDir('builtin_shadow_source');
  const priorSourceRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
  try {
    writeFile(path.join(sourceRoot, 'valid-skill', 'skill.json'), JSON.stringify({
      skill_id: 'valid-skill',
      version: '1.0.0',
      name: 'Valid Skill',
      description: 'Valid builtin source entry.',
      publisher: { publisher_id: 'xhub.official' },
    }, null, 2));
    writeFile(path.join(runtimeBaseDir, 'skills_store', 'skill_sources.json'), JSON.stringify({
      schema_version: 'skill_sources.v1',
      updated_at_ms: 1700000000000,
      sources: [
        {
          source_id: 'builtin:catalog',
          type: 'catalog',
          default_trust_policy: 'manual_review',
          updated_at_ms: 1800000000000,
          discovery_index: [
            {
              skill_id: 'rogue-skill',
              version: '9.9.9',
              name: 'Rogue Skill',
              description: 'Should never override builtin catalog.',
              publisher_id: 'rogue.publisher',
            },
          ],
        },
      ],
    }, null, 2));

    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = sourceRoot;
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = path.join(sourceRoot, 'dist');

    const sources = loadSkillSources(runtimeBaseDir);
    const builtin = Array.isArray(sources.sources)
      ? sources.sources.find((it) => String(it?.source_id || '') === 'builtin:catalog')
      : null;
    assert.ok(builtin);
    assert.equal(String(builtin.default_trust_policy || ''), 'trusted_official');
    const skillIds = new Set((Array.isArray(builtin.discovery_index) ? builtin.discovery_index : []).map((it) => String(it?.skill_id || '')));
    assert.equal(skillIds.has('valid-skill'), true);
    assert.equal(skillIds.has('rogue-skill'), false);
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    cleanupDir(sourceRoot);
    cleanupDir(runtimeBaseDir);
  }
});

run('loadSkillSources merges duplicate custom source rows and prefers uploadable discovery entries', () => {
  const runtimeBaseDir = makeTmpDir('duplicate_source_rows');
  try {
    writeFile(path.join(runtimeBaseDir, 'skills_store', 'skill_sources.json'), JSON.stringify({
      schema_version: 'skill_sources.v1',
      updated_at_ms: 1700000000000,
      sources: [
        {
          source_id: 'catalog:team',
          type: 'catalog',
          default_trust_policy: 'manual_review',
          updated_at_ms: 100,
          discovery_index: [
            {
              skill_id: 'agent-browser',
              version: '0.9.0',
              name: 'Agent Browser Draft',
              publisher_id: 'team.publisher',
            },
            {
              skill_id: 'repo-status',
              version: '1.0.0',
              name: 'Repo Status',
              publisher_id: 'team.publisher',
            },
          ],
        },
        {
          source_id: 'catalog:team',
          type: 'catalog',
          default_trust_policy: 'trusted_internal',
          updated_at_ms: 200,
          discovery_index: [
            {
              skill_id: 'agent-browser',
              version: '0.9.0',
              name: 'Agent Browser Release',
              publisher_id: 'team.publisher',
              package_sha256: 'a'.repeat(64),
            },
            {
              skill_id: 'summarize-team',
              version: '1.0.0',
              name: 'Summarize Team',
              publisher_id: 'team.publisher',
            },
          ],
        },
      ],
    }, null, 2));

    const sources = loadSkillSources(runtimeBaseDir);
    const team = Array.isArray(sources.sources)
      ? sources.sources.find((it) => String(it?.source_id || '') === 'catalog:team')
      : null;
    assert.ok(team);
    assert.equal(String(team.default_trust_policy || ''), 'trusted_internal');
    const discovery = Array.isArray(team.discovery_index) ? team.discovery_index : [];
    assert.equal(discovery.filter((it) => String(it?.skill_id || '') === 'agent-browser').length, 1);
    const browser = discovery.find((it) => String(it?.skill_id || '') === 'agent-browser');
    assert.equal(String(browser?.package_sha256 || ''), 'a'.repeat(64));
    const ids = new Set(discovery.map((it) => String(it?.skill_id || '')));
    assert.equal(ids.has('repo-status'), true);
    assert.equal(ids.has('summarize-team'), true);

    const results = searchSkills(runtimeBaseDir, {
      query: 'agent-browser',
      sourceFilter: 'catalog:team',
      limit: 10,
    });
    assert.equal(results.length, 1);
    assert.equal(String(results[0]?.package_sha256 || ''), 'a'.repeat(64));
  } finally {
    cleanupDir(runtimeBaseDir);
  }
});
