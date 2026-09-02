#!/usr/bin/env bash
# Validate JSON Schemas and example payloads for all standalone spinoff specs.
# Run from the x-hub-system repo root.
# Exit 0 = all pass. Exit 1 = any failure.

set -euo pipefail

checks=(
  "skill-trust manifest|specs/skill-trust-registry/schemas/manifest.schema.json|specs/skill-trust-registry/schemas/examples/manifest.example.json"
  "skill-trust attestation|specs/skill-trust-registry/schemas/attestation.schema.json|specs/skill-trust-registry/schemas/examples/attestation.example.json"
  "skill-trust pin|specs/skill-trust-registry/schemas/pin.schema.json|specs/skill-trust-registry/schemas/examples/pin.example.json"
  "skill-trust policy|specs/skill-trust-registry/schemas/policy.schema.json|specs/skill-trust-registry/schemas/examples/policy.example.json"
  "skill-trust recall|specs/skill-trust-registry/schemas/recall.schema.json|specs/skill-trust-registry/schemas/examples/recall.example.json"
  "skill-trust receipt|specs/skill-trust-registry/schemas/receipt.schema.json|specs/skill-trust-registry/schemas/examples/receipt.example.json"
  "hub receipt envelope|specs/hub-receipt/schema/receipt-envelope.schema.json|specs/hub-receipt/schema/examples/envelope.example.json"
  "agent-2fa challenge|specs/agent-2fa/schemas/challenge.schema.json|specs/agent-2fa/schemas/examples/challenge.example.json"
  "agent-2fa authorization|specs/agent-2fa/schemas/authorization.schema.json|specs/agent-2fa/schemas/examples/authorization.example.json"
  "agent-2fa policy|specs/agent-2fa/schemas/policy.schema.json|specs/agent-2fa/schemas/examples/policy.example.json"
  "agent-2fa receipt claims|specs/agent-2fa/schemas/receipt-claims.schema.json|specs/agent-2fa/schemas/examples/receipt-claims.example.json"
)

pass=0
fail=0

echo "Validating standalone spinoff schemas and examples ..."

for entry in "${checks[@]}"; do
  IFS='|' read -r label schema example <<< "$entry"

  if [ ! -f "$schema" ]; then
    echo "  FAIL  $label schema missing: $schema"
    fail=$((fail + 1))
    continue
  fi

  if npx --yes -p ajv-cli -p ajv-formats ajv compile \
      --spec=draft2020 -c ajv-formats -s "$schema" > /dev/null 2>&1; then
    echo "  PASS  $label schema"
    pass=$((pass + 1))
  else
    echo "  FAIL  $label schema"
    npx --yes -p ajv-cli -p ajv-formats ajv compile \
      --spec=draft2020 -c ajv-formats -s "$schema" 2>&1 | sed 's/^/        /'
    fail=$((fail + 1))
    continue
  fi

  if [ ! -f "$example" ]; then
    echo "  FAIL  $label example missing: $example"
    fail=$((fail + 1))
    continue
  fi

  if npx --yes -p ajv-cli -p ajv-formats ajv validate \
      --spec=draft2020 -c ajv-formats -s "$schema" -d "$example" > /dev/null 2>&1; then
    echo "  PASS  $label example"
    pass=$((pass + 1))
  else
    echo "  FAIL  $label example"
    npx --yes -p ajv-cli -p ajv-formats ajv validate \
      --spec=draft2020 -c ajv-formats -s "$schema" -d "$example" 2>&1 | sed 's/^/        /'
    fail=$((fail + 1))
  fi
done

echo ""
echo "Summary: $pass passed, $fail failed"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
