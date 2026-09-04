#!/usr/bin/env bash
# Фаза 12 — OSPF (optional FRR)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

ospf=false
rid=""
nets_yaml="[]"
passive_yaml="[]"
redist=true

if confirm "Настроить OSPF (FRR, для продвинутых)?" N; then
  ospf=true
  rid="$(ask "OSPF router-id" "10.0.0.1")"
  confirm "redistribute connected?" Y || redist=false
  nets_tmp="$TMP/ospf_nets.json"
  echo "[]" >"$nets_tmp"
  while confirm "Добавить network (prefix + area)?" Y; do
    pref="$(ask "prefix (CIDR)" "10.0.0.1/24")"
    area="$(ask "area" "0.0.0.0")"
    python3 - "$nets_tmp" "$pref" "$area" <<'PY'
import json, sys
from pathlib import Path
path, pref, area = sys.argv[1:4]
data = json.loads(Path(path).read_text(encoding="utf-8") or "[]")
data.append({"prefix": pref, "area": area})
Path(path).write_text(json.dumps(data), encoding="utf-8")
PY
  done
  nets_yaml="$(python3 -c 'import json,sys; from pathlib import Path; print(json.dumps(json.loads(Path(sys.argv[1]).read_text())))' "$nets_tmp")"
  pas="$(ask "passive-interfaces через пробел (опц.)" "")"
  if [[ -n "$pas" ]]; then
    passive_yaml="$(python3 -c 'import sys; print("[" + ", ".join(chr(34)+x+chr(34) for x in sys.argv[1:] if x) + "]")' $pas)"
  fi
fi

cat >"$TMP/ospf.yaml" <<EOF
ospf_enabled: $ospf
ospf_router_id: ${rid:-null}
ospf_redistribute: $redist
ospf_networks: $nets_yaml
ospf_passive: $passive_yaml
EOF
