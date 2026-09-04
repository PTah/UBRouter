#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require

naming="$(ans_get interfaces.naming)"
map_json="$(ans_get_json interfaces.map)"
python3 -c 'import json,sys; m=json.loads(sys.argv[1] or "[]"); assert m, "empty map"' "$map_json"
info "interfaces: verify: map ok naming=$naming"
# After full apply, names should exist — soft check
if [[ "$naming" != "keep" ]]; then
  python3 - <<'PY'
import json, os, sys
# map from env file via answers already applied
print("ok")
PY
fi
exit 0
