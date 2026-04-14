import assert from 'node:assert/strict';

import {
  augmentGovernanceRuntimeComponent,
  buildGovernanceRuntimeReadinessFromDenyCode,
  buildGovernanceRuntimeReadinessProjection,
  buildSupervisorRouteGovernanceRuntimeReadinessProjection,
} from './governance_runtime_readiness_projection.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('governance runtime readiness augments generate grant blockers with XT-style component fields', () => {
  const projection = buildGovernanceRuntimeReadinessProjection({
    configured: true,
    source: 'hub',
    governance_surface: 'a4_agent',
    context: 'ai_generate',
    project_id: 'proj-alpha',
    components: {
      route: {
        component: 'route',
        required: true,
        ready: true,
        deny_code: '',
        summary: 'hub_remote_route_ready',
      },
      capability: {
        component: 'capability',
        required: true,
        ready: true,
        deny_code: '',
        summary: 'capability surface ready: ai.generate.paid',
      },
      grant: {
        component: 'grant',
        required: true,
        ready: false,
        deny_code: 'trusted_automation_project_not_bound',
        summary: 'governance gate blocked: trusted_automation_project_not_bound',
      },
      checkpoint_recovery: {
        component: 'checkpoint_recovery',
        required: true,
        ready: true,
        deny_code: '',
        summary: 'checkpoint and recovery continuity ready',
      },
      evidence_export: {
        component: 'evidence_export',
        required: true,
        ready: true,
        deny_code: '',
        summary: 'evidence and export trail ready',
      },
    },
  });

  assert.equal(String(projection.state || ''), 'blocked');
  assert.equal(Boolean(projection.runtime_ready), false);
  assert.deepEqual(projection.blocked_component_keys, ['grant_ready']);
  assert.deepEqual(projection.missing_reason_codes, ['trusted_automation_not_ready']);
  assert.equal(
    String(projection.components?.grant?.xt_component_key || ''),
    'grant_ready'
  );
  assert.equal(
    String(projection.components?.grant?.state || ''),
    'blocked'
  );
  assert.deepEqual(
    projection.components?.grant?.source_deny_codes || [],
    ['trusted_automation_project_not_bound']
  );
  assert.equal(
    String(projection.components_by_xt_key?.grant_ready?.state || ''),
    'blocked'
  );
});

run('governance runtime readiness maps trusted automation capability-empty deny into capability gap', () => {
  const projection = buildGovernanceRuntimeReadinessFromDenyCode({
    rawDenyCode: 'trusted_automation_capabilities_empty_blocked',
    source: 'hub',
    context: 'deny_audit',
  });

  assert.ok(projection);
  assert.equal(String(projection?.state || ''), 'blocked');
  assert.deepEqual(projection?.blocked_component_keys || [], ['capability_ready']);
  assert.deepEqual(projection?.missing_reason_codes || [], ['capability_device_tools_unavailable']);
  assert.equal(
    String(projection?.components_by_xt_key?.capability_ready?.state || ''),
    'blocked'
  );
  assert.equal(
    String(projection?.components_by_xt_key?.grant_ready?.state || ''),
    'not_reported'
  );
});

run('governance runtime component keeps non-reported planes explicit', () => {
  const component = augmentGovernanceRuntimeComponent('evidence_export', {
    component: 'evidence_export',
    required: false,
    ready: false,
    reported: false,
    deny_code: '',
    summary: '',
  });

  assert.equal(String(component.state || ''), 'not_reported');
  assert.equal(String(component.xt_component_key || ''), 'evidence_export_ready');
  assert.deepEqual(component.missing_reason_codes || [], []);
});

run('supervisor route governance readiness maps runner grant blockers into XT keys', () => {
  const projection = buildSupervisorRouteGovernanceRuntimeReadinessProjection({
    route: {
      project_id: 'robot-shopping',
      decision: 'fail_closed',
      deny_code: 'device_permission_owner_missing',
      preferred_device_id: 'xt-runner-01',
      resolved_device_id: 'xt-runner-01',
      runner_required: true,
      xt_online: true,
      same_project_scope: true,
    },
    intent: 'directive',
    require_xt: true,
    require_runner: true,
    auth_kind: 'client',
    trust_profile_present: true,
    trusted_automation_mode: 'trusted_automation',
    trusted_automation_state: 'armed',
  });

  assert.equal(String(projection.state || ''), 'blocked');
  assert.deepEqual(projection.blocked_component_keys, ['grant_ready']);
  assert.deepEqual(projection.missing_reason_codes, ['permission_owner_not_ready']);
  assert.equal(
    String(projection.components_by_xt_key?.grant_ready?.deny_code || ''),
    'device_permission_owner_missing'
  );
  assert.equal(
    String(projection.components_by_xt_key?.route_ready?.state || ''),
    'ready'
  );
});
