import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import {
  resolveMemoryModelRoute,
  selectWinningMemoryModelPreference,
  validateMemoryModelPreference,
} from './memory_model_preferences.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function withEnv(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv)) {
    prev.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_memory_model_preferences_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

function makeFallbackPolicy(extra = {}) {
  return {
    on_unavailable: 'deny',
    on_remote_block: 'deny',
    on_budget_exceeded: 'deny',
    allow_downgrade_to_local: false,
    allow_job_specific_fallback: false,
    ...extra,
  };
}

function makeProfile(overrides = {}) {
  return {
    profile_id: 'pref-default',
    user_id: 'user-1',
    scope_kind: 'user_default',
    scope_ref: '',
    mode: '',
    selection_strategy: 'single_model',
    primary_model_id: 'local-medium',
    job_model_map: {},
    mode_model_map: {},
    fallback_policy: makeFallbackPolicy(),
    remote_allowed: true,
    policy_version: 'policy-v1',
    updated_at_ms: 100,
    ...overrides,
  };
}

function makeModels() {
  return [
    {
      model_id: 'local-small',
      name: 'Local Small',
      backend: 'mlx',
      kind: 'local_offline',
      enabled: 1,
      requires_grant: 0,
    },
    {
      model_id: 'local-medium',
      name: 'Local Medium',
      backend: 'mlx',
      kind: 'local_offline',
      enabled: 1,
      requires_grant: 0,
    },
    {
      model_id: 'remote-pro',
      name: 'Remote Pro',
      backend: 'openai',
      kind: 'paid_online',
      enabled: 1,
      requires_grant: 1,
    },
    {
      model_id: 'remote-fast',
      name: 'Remote Fast',
      backend: 'openai',
      kind: 'paid_online',
      enabled: 1,
      requires_grant: 1,
    },
  ];
}

run('validate + precedence resolution stay deterministic and ignore disabled higher scope', () => {
  const invalid = validateMemoryModelPreference(makeProfile({
    profile_id: 'invalid-single',
    primary_model_id: '',
  }));
  assert.equal(invalid.ok, false);
  assert.ok(invalid.errors.includes('primary_model_id'));

  const profiles = [
    makeProfile({
      profile_id: 'default-local',
      primary_model_id: 'local-small',
      updated_at_ms: 100,
    }),
    makeProfile({
      profile_id: 'mode-remote',
      scope_kind: 'mode',
      mode: 'project_code',
      primary_model_id: 'remote-fast',
      updated_at_ms: 200,
    }),
    makeProfile({
      profile_id: 'project-local',
      scope_kind: 'project',
      scope_ref: 'proj-1',
      primary_model_id: 'local-medium',
      updated_at_ms: 300,
    }),
    makeProfile({
      profile_id: 'project-mode-disabled',
      scope_kind: 'project_mode',
      scope_ref: 'proj-1',
      mode: 'project_code',
      primary_model_id: 'remote-pro',
      disabled_at_ms: 999,
      updated_at_ms: 400,
    }),
  ];

  const request = {
    user_id: 'user-1',
    project_id: 'proj-1',
    mode: 'project_code',
    job_type: 'summarize_run',
    sensitivity: 'internal',
    trust_level: 'trusted',
    budget_class: 'default',
    remote_allowed_by_policy: true,
  };

  const winnerA = selectWinningMemoryModelPreference(profiles, request);
  const winnerB = selectWinningMemoryModelPreference(profiles, request);

  assert.equal(winnerA.ok, true);
  assert.equal(winnerA.profile.profile_id, 'project-local');
  assert.deepEqual(winnerA, winnerB);

  const preferredDisabled = selectWinningMemoryModelPreference(profiles, {
    ...request,
    preferred_profile_id: 'project-mode-disabled',
  });
  assert.equal(preferredDisabled.ok, false);
  assert.equal(preferredDisabled.deny_code, 'memory_model_profile_disabled');
});

run('resolve route covers single_model, job_map, and mode_profile strategies', () => {
  const models = makeModels();

  const singleRoute = resolveMemoryModelRoute({
    profiles: [
      makeProfile({
        profile_id: 'single-route',
        primary_model_id: 'local-medium',
      }),
    ],
    modelsById: models,
    request: {
      user_id: 'user-1',
      mode: 'assistant_personal',
      job_type: 'extract_observations',
      sensitivity: 'public',
      trust_level: 'trusted',
      budget_class: 'default',
      remote_allowed_by_policy: true,
    },
  });
  assert.equal(singleRoute.deny_code, undefined);
  assert.equal(singleRoute.model_id, 'local-medium');
  assert.equal(singleRoute.route_source, 'user_single_model');

  const jobMapRoute = resolveMemoryModelRoute({
    profiles: [
      makeProfile({
        profile_id: 'job-map-route',
        selection_strategy: 'job_map',
        primary_model_id: 'local-medium',
        job_model_map: {
          summarize_run: 'remote-pro',
          extract_observations: 'local-small',
        },
        updated_at_ms: 200,
      }),
    ],
    modelsById: models,
    request: {
      user_id: 'user-1',
      mode: 'project_code',
      job_type: 'summarize_run',
      sensitivity: 'internal',
      trust_level: 'trusted',
      budget_class: 'default',
      remote_allowed_by_policy: true,
    },
  });
  assert.equal(jobMapRoute.deny_code, undefined);
  assert.equal(jobMapRoute.model_id, 'remote-pro');
  assert.equal(jobMapRoute.route_source, 'user_job_map');
  assert.equal(jobMapRoute.route_reason_code, 'job_map_hit');

  const jobMapFallback = resolveMemoryModelRoute({
    profiles: [
      makeProfile({
        profile_id: 'job-map-fallback',
        selection_strategy: 'job_map',
        primary_model_id: 'local-medium',
        job_model_map: {
          summarize_run: 'remote-pro',
        },
        updated_at_ms: 201,
      }),
    ],
    modelsById: models,
    request: {
      user_id: 'user-1',
      mode: 'project_code',
      job_type: 'aggregate_longterm',
      sensitivity: 'internal',
      trust_level: 'trusted',
      budget_class: 'default',
      remote_allowed_by_policy: true,
    },
  });
  assert.equal(jobMapFallback.deny_code, undefined);
  assert.equal(jobMapFallback.model_id, 'local-medium');
  assert.equal(jobMapFallback.route_reason_code, 'job_map_primary_fallback');

  const modeRoute = resolveMemoryModelRoute({
    profiles: [
      makeProfile({
        profile_id: 'mode-profile-route',
        selection_strategy: 'mode_profile',
        primary_model_id: 'local-medium',
        mode_model_map: {
          assistant_personal: 'local-small',
          project_code: 'remote-fast',
        },
        updated_at_ms: 202,
      }),
    ],
    modelsById: models,
    request: {
      user_id: 'user-1',
      mode: 'assistant_personal',
      job_type: 'extract_observations',
      sensitivity: 'public',
      trust_level: 'trusted',
      budget_class: 'default',
      remote_allowed_by_policy: true,
    },
  });
  assert.equal(modeRoute.deny_code, undefined);
  assert.equal(modeRoute.model_id, 'local-small');
  assert.equal(modeRoute.route_source, 'user_mode_profile');
  assert.equal(modeRoute.route_reason_code, 'mode_profile_hit');
});

run('resolve route fail-closed for missing profile, invalid model, and remote blocks', () => {
  const models = makeModels();

  const missingRoute = resolveMemoryModelRoute({
    profiles: [],
    modelsById: models,
    request: {
      user_id: 'user-1',
      mode: 'assistant_personal',
      job_type: 'extract_observations',
      sensitivity: 'public',
      trust_level: 'trusted',
      budget_class: 'default',
      remote_allowed_by_policy: true,
    },
  });
  assert.equal(missingRoute.deny_code, 'memory_model_profile_missing');
  assert.equal(missingRoute.route_source, 'system_default_fallback');

  const invalidModelRoute = resolveMemoryModelRoute({
    profiles: [
      makeProfile({
        profile_id: 'invalid-model',
        primary_model_id: 'ghost-model',
      }),
    ],
    modelsById: models,
    request: {
      user_id: 'user-1',
      mode: 'assistant_personal',
      job_type: 'extract_observations',
      sensitivity: 'public',
      trust_level: 'trusted',
      budget_class: 'default',
      remote_allowed_by_policy: true,
    },
  });
  assert.equal(invalidModelRoute.deny_code, 'memory_model_invalid');
  assert.equal(invalidModelRoute.resolved_profile_id, 'invalid-model');

  const downgradedRoute = resolveMemoryModelRoute({
    profiles: [
      makeProfile({
        profile_id: 'remote-downgrade',
        primary_model_id: 'remote-pro',
        remote_allowed: false,
        fallback_policy: makeFallbackPolicy({
          on_remote_block: 'downgrade_to_local',
          allow_downgrade_to_local: true,
          local_model_id: 'local-small',
        }),
      }),
    ],
    modelsById: models,
    request: {
      user_id: 'user-1',
      mode: 'project_code',
      job_type: 'summarize_run',
      sensitivity: 'internal',
      trust_level: 'trusted',
      budget_class: 'default',
      remote_allowed_by_policy: true,
    },
  });
  assert.equal(downgradedRoute.deny_code, undefined);
  assert.equal(downgradedRoute.model_id, 'local-small');
  assert.equal(downgradedRoute.route_source, 'local_downgrade_fallback');
  assert.equal(downgradedRoute.fallback_applied, true);
  assert.equal(downgradedRoute.fallback_reason, 'memory_model_remote_blocked');

  const blockedRoute = resolveMemoryModelRoute({
    profiles: [
      makeProfile({
        profile_id: 'remote-blocked',
        primary_model_id: 'remote-pro',
        remote_allowed: false,
      }),
    ],
    modelsById: models,
    request: {
      user_id: 'user-1',
      mode: 'project_code',
      job_type: 'summarize_run',
      sensitivity: 'secret',
      trust_level: 'trusted',
      budget_class: 'default',
      remote_allowed_by_policy: true,
    },
  });
  assert.equal(blockedRoute.deny_code, 'memory_model_remote_blocked');
  assert.equal(blockedRoute.route_source, 'user_single_model');
});

run('HubDB persists, lists, aliases, and resolves memory model preference winners', () => {
  const dbPath = makeTmp('db', '.db');
  cleanupDbArtifacts(dbPath);

  withEnv({
    HUB_MEMORY_AT_REST_ENABLED: 'false',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_MEMORY_RETENTION_AUTO_JOB_ENABLED: 'false',
  }, () => {
    const db = new HubDB({ dbPath });
    try {
      const createdDefault = db.upsertMemoryModelPreferences({
        profile_id: 'pref-default',
        user_id: 'user-db',
        scope_kind: 'user_default',
        selection_strategy: 'single_model',
        primary_model_id: 'mlx/qwen2.5-7b-instruct',
        fallback_policy: makeFallbackPolicy(),
        remote_allowed: false,
        policy_version: 'policy-1',
        updated_at_ms: 100,
      });
      assert.equal(createdDefault.profile_id, 'pref-default');
      assert.equal(createdDefault.remote_allowed, false);

      const createdProject = db.upsertMemoryModelPreferences({
        profile_id: 'pref-project',
        user_id: 'user-db',
        scope_kind: 'project',
        scope_ref: 'proj-db',
        selection_strategy: 'job_map',
        primary_model_id: 'mlx/qwen2.5-7b-instruct',
        job_model_map: {
          summarize_run: 'openai/gpt-4.1',
        },
        fallback_policy: makeFallbackPolicy({
          on_remote_block: 'downgrade_to_local',
          allow_downgrade_to_local: true,
          local_model_id: 'mlx/qwen2.5-7b-instruct',
        }),
        remote_allowed: true,
        policy_version: 'policy-2',
        updated_at_ms: 200,
      });
      assert.equal(createdProject.profile_id, 'pref-project');
      assert.equal(createdProject.job_model_map.summarize_run.model_id, 'openai/gpt-4.1');

      const fetchedByAlias = db.getMemoryModelPreferences('pref-project');
      assert.equal(fetchedByAlias.profile_id, 'pref-project');

      const listed = db.listMemoryModelPreferences({
        user_id: 'user-db',
        include_disabled: true,
      });
      assert.deepEqual(listed.map((item) => item.profile_id), ['pref-project', 'pref-default']);

      const winner = db.resolveMemoryModelPreferencesWinner({
        user_id: 'user-db',
        project_id: 'proj-db',
        mode: 'project_code',
      });
      assert.equal(winner.ok, true);
      assert.equal(winner.profile.profile_id, 'pref-project');

      db.upsertMemoryModelPreferences({
        profile_id: 'pref-project',
        user_id: 'user-db',
        scope_kind: 'project',
        scope_ref: 'proj-db',
        selection_strategy: 'job_map',
        primary_model_id: 'mlx/qwen2.5-7b-instruct',
        job_model_map: {
          summarize_run: 'openai/gpt-4.1',
        },
        fallback_policy: makeFallbackPolicy(),
        remote_allowed: true,
        policy_version: 'policy-3',
        updated_at_ms: 300,
        disabled_at_ms: 301,
      });

      const afterDisable = db.resolveMemoryModelPreferencesWinner({
        user_id: 'user-db',
        project_id: 'proj-db',
        mode: 'project_code',
      });
      assert.equal(afterDisable.ok, true);
      assert.equal(afterDisable.profile.profile_id, 'pref-default');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});
