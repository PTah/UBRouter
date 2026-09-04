#!/usr/bin/env bash
# Module: interfaces / apply — rename via netplan match+set-name when naming != keep
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

bash "$ROOT/scripts/modules/interfaces/plan.sh"

naming="$(ans_get interfaces.naming)"
if [[ "$naming" == "keep" ]]; then
  info "interfaces: naming=keep — rename skip"
  exit 0
fi

# Full router netplan includes set-name; apply happens in lan module.
# Here: ensure map non-empty and names will exist after netplan.
map_json="$(ans_get_json interfaces.map)"
python3 -c 'import json,sys; m=json.loads(sys.argv[1] or "[]");
import sys as s
s.exit(0 if m else 1)' "$map_json" || die "interfaces.map пуст — нечего переименовывать"

info "interfaces: apply: map готов (set-name в 50-ubrouter.yaml при lan apply)"
