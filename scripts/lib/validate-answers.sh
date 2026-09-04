#!/usr/bin/env bash
# Soft/hard validate answers.yaml against configs/answers.schema.json
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

ANSWERS="${UBROUTER_ANSWERS:?}"
SCHEMA="${UBROUTER_SCHEMA:-$ROOT/configs/answers.schema.json}"

[[ -f "$ANSWERS" ]] || die "answers not found: $ANSWERS"
[[ -f "$SCHEMA" ]] || { warn "schema missing: $SCHEMA — skip validate"; exit 0; }

python3 - "$ANSWERS" "$SCHEMA" <<'PY'
import json, sys
from pathlib import Path

ans_path, schema_path = sys.argv[1:3]
try:
    import yaml
except ImportError:
    print("WARN: python3-yaml missing — skip schema validate", file=sys.stderr)
    raise SystemExit(0)

try:
    import jsonschema
except ImportError:
    # soft: basic structural checks without jsonschema
    data = yaml.safe_load(Path(ans_path).read_text(encoding="utf-8")) or {}
    for k in ("version", "interfaces", "wan", "lan", "services"):
        if k not in data:
            print(f"ERROR: answers missing required key: {k}", file=sys.stderr)
            raise SystemExit(1)
    print("--> validate: basic keys OK (jsonschema not installed)")
    raise SystemExit(0)

data = yaml.safe_load(Path(ans_path).read_text(encoding="utf-8")) or {}
schema = json.loads(Path(schema_path).read_text(encoding="utf-8"))
# draft 2020-12 may need referencing; use Draft202012 if available
try:
    from jsonschema import Draft202012Validator
    Draft202012Validator(schema).validate(data)
except Exception:
    jsonschema.validate(instance=data, schema=schema)
print("--> validate: schema OK")
PY
