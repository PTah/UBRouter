#!/usr/bin/env bash
# Phase 02: WAN / LAN roles
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

default_wan=eth0
default_lan=eth1
if [[ -f "$TMP/map.json" ]]; then
  default_wan="$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print(next((x["name"] for x in m if x.get("role")=="wan"), m[0]["name"] if m else "eth0"))' "$TMP/map.json")"
  default_lan="$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print(next((x["name"] for x in m if x.get("role")=="lan"), m[1]["name"] if len(m)>1 else "eth1"))' "$TMP/map.json")"
fi

wan_if="$(ask "Имя WAN-интерфейса (после naming)" "$default_wan")"
lan_mode="$(ask "LAN: 1=один порт, 2=bridge нескольких" "1")"

if [[ "$lan_mode" == "2" ]]; then
  br_name="$(ask "Имя bridge" "br-lan")"
  members="$(ask "Порты bridge через пробел" "eth1 eth2")"
  lan_if="$br_name"
  bridge_enabled=true
else
  lan_if="$(ask "Имя LAN-интерфейса" "$default_lan")"
  br_name="br-lan"
  members=""
  bridge_enabled=false
fi

# Update roles in map.json
if [[ -f "$TMP/map.json" ]]; then
  python3 - "$TMP/map.json" "$wan_if" "$lan_if" "$bridge_enabled" "$members" <<'PY'
import json, sys
from pathlib import Path
path, wan, lan, bridge, members = sys.argv[1:6]
m = json.loads(Path(path).read_text(encoding="utf-8"))
mem = members.split() if members else []
for e in m:
    if e["name"] == wan:
        e["role"] = "wan"
    elif bridge == "true" and e["name"] in mem:
        e["role"] = "bridge-member"
    elif e["name"] == lan:
        e["role"] = "lan"
Path(path).write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding="utf-8")
PY
fi

cat >"$TMP/roles.yaml" <<EOF
wan_interface: $wan_if
lan_interface: $lan_if
bridge_enabled: $bridge_enabled
bridge_name: $br_name
bridge_members: [$members]
EOF
info "WAN=$wan_if LAN=$lan_if bridge=$bridge_enabled"
