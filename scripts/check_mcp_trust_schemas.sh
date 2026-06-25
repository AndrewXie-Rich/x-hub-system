#!/usr/bin/env bash
# Validate mcp-trust-registry JSON Schemas and example payloads.
# Run from the x-hub-system repo root.
# Exit 0 = all pass. Exit 1 = any failure.

set -euo pipefail

SCHEMAS_DIR="specs/mcp-trust-registry/schemas"
EXAMPLES_DIR="$SCHEMAS_DIR/examples"

if [ ! -d "$SCHEMAS_DIR" ]; then
  echo "ERROR: schemas directory not found at $SCHEMAS_DIR"
  echo "       run this script from the x-hub-system repo root"
  exit 1
fi

pass=0
fail=0
warn=0

echo "Compiling schemas under $SCHEMAS_DIR ..."
for schema in "$SCHEMAS_DIR"/*.schema.json; do
  name=$(basename "$schema")
  if npx --yes -p ajv-cli -p ajv-formats ajv compile \
      --spec=draft2020 -c ajv-formats -s "$schema" > /dev/null 2>&1; then
    echo "  PASS  $name"
    pass=$((pass + 1))
  else
    echo "  FAIL  $name"
    npx --yes -p ajv-cli -p ajv-formats ajv compile \
      --spec=draft2020 -c ajv-formats -s "$schema" 2>&1 | sed 's/^/        /'
    fail=$((fail + 1))
  fi
done

if [ -d "$EXAMPLES_DIR" ]; then
  echo ""
  echo "Validating examples under $EXAMPLES_DIR ..."
  for schema in "$SCHEMAS_DIR"/*.schema.json; do
    base=$(basename "$schema" .schema.json)
    example="$EXAMPLES_DIR/$base.example.json"
    if [ ! -f "$example" ]; then
      echo "  WARN  no example for $base.schema.json (looked at $example)"
      warn=$((warn + 1))
      continue
    fi
    if npx --yes -p ajv-cli -p ajv-formats ajv validate \
        --spec=draft2020 -c ajv-formats -s "$schema" -d "$example" > /dev/null 2>&1; then
      echo "  PASS  $base.example.json"
      pass=$((pass + 1))
    else
      echo "  FAIL  $base.example.json"
      npx --yes -p ajv-cli -p ajv-formats ajv validate \
        --spec=draft2020 -c ajv-formats -s "$schema" -d "$example" 2>&1 | sed 's/^/        /'
      fail=$((fail + 1))
    fi
  done
else
  echo ""
  echo "WARN  examples directory not found at $EXAMPLES_DIR; skipping example validation"
  warn=$((warn + 1))
fi

echo ""
echo "Summary: $pass passed, $fail failed, $warn warnings"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
