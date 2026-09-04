#!/usr/bin/env bash
# Module: interfaces — probe/fill MAC→name map; prepare rename via netplan (apply does render).
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

WORKDIR="${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}"
ensure_dir "$WORKDIR/interfaces"

naming="$(ans_get interfaces.naming)"
[[ -n "$naming" ]] || naming=eth
map_json="$(ans_get_json interfaces.map)"

probe="$(bash "$ROOT/scripts/lib/probe-nics.sh")"
echo "$probe" >"$WORKDIR/interfaces/probe.json"

python3 - "$naming" "$map_json" "$probe" <<'PY' >"$WORKDIR/interfaces/map.json"
import json, sys
naming, map_json, probe_json = sys.argv[1:4]
existing = json.loads(map_json) if map_json and map_json not in ("null", "[]", "") else []
nics = json.loads(probe_json)

if existing:
    # keep user map; only fill missing macs by current name match
    by_name = {n["name"]: n for n in nics}
    out = []
    for ent in existing:
        e = dict(ent)
        if not e.get("mac") and e.get("name") in by_name:
            e["mac"] = by_name[e["name"]]["mac"]
        out.append(e)
    print(json.dumps(out))
    raise SystemExit(0)

prefix = {"eth": "eth", "ether": "ether", "keep": None, "custom": "eth"}.get(naming, "eth")
out = []
for i, n in enumerate(nics):
    if prefix is None:
        name = n["name"]
    else:
        name = f"{prefix}{i}"
    role = "wan" if i == 0 else ("lan" if i == 1 else "opt")
    out.append({"mac": n["mac"], "name": name, "role": role})
print(json.dumps(out))
PY

new_map="$(cat "$WORKDIR/interfaces/map.json")"
ans_set_map_json "$new_map"
info "interfaces map (${naming}):"
python3 - "$WORKDIR/interfaces/map.json" <<'PY'
import json, sys
from pathlib import Path
for e in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")):
    print(f"  {e.get('mac')} -> {e.get('name')} ({e.get('role','')})")
PY

# Also sync wan/lan interface names if still defaults and map has roles
python3 - "$UBROUTER_ANSWERS" <<'PY'
import yaml, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}
m = (data.get("interfaces") or {}).get("map") or []
wan = next((x["name"] for x in m if x.get("role") == "wan"), None)
lan = next((x["name"] for x in m if x.get("role") == "lan"), None)
changed = False
if wan and not (data.get("wan") or {}).get("interface"):
    data.setdefault("wan", {})["interface"] = wan
    changed = True
elif wan and (data.get("wan") or {}).get("interface") in ("eth0", "", None):
    # if map says otherwise and user left default eth0 matching role wan — OK
    pass
if lan and (data.get("interfaces") or {}).get("bridge", {}).get("enabled"):
    pass
elif lan and not (data.get("lan") or {}).get("interface"):
    data.setdefault("lan", {})["interface"] = lan
    changed = True
if changed:
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
PY

info "interfaces: plan OK"
