#!/usr/bin/env bash
# Phase 01: interface naming + probe MAC map
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

TMP="${UBROUTER_WIZARD_TMP:?}"

echo "Обнаруженные интерфейсы:"
probe="[]"
if [[ -f "$ROOT/scripts/lib/probe-nics.sh" ]]; then
  probe="$(bash "$ROOT/scripts/lib/probe-nics.sh" 2>/dev/null || echo '[]')"
fi
echo "$probe" >"$TMP/probe.json"

python3 - "$TMP/probe.json" <<'PY'
import json, sys
from pathlib import Path
nics = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8") or "[]")
if not nics:
    print("  (нет данных — заполните map вручную)")
else:
    print(f"  {'#':<3} {'name':<12} {'mac':<18} {'pci':<16} carrier")
    for i, n in enumerate(nics):
        print(f"  {i:<3} {n['name']:<12} {n['mac']:<18} {n.get('pci',''):<16} {n.get('carrier','?')}")
PY

echo
echo "Как именовать интерфейсы?"
echo "  1) оставить системные имена (enp*, ens*)"
echo "  2) eth0, eth1, eth2, ..."
echo "  3) ether0, ether1, ... (стиль MikroTik)"
echo "  4) custom (как eth, роли зададите сами)"
choice="$(ask "Выбор" "2")"
case "$choice" in
  1) naming=keep ;;
  2) naming=eth ;;
  3) naming=ether ;;
  4) naming=custom ;;
  *) naming=eth ;;
esac
echo "$naming" >"$TMP/naming"

python3 - "$naming" "$TMP/probe.json" "$TMP/map.json" <<'PY'
import json, sys
from pathlib import Path
naming, probe_path, out_path = sys.argv[1:4]
nics = json.loads(Path(probe_path).read_text(encoding="utf-8") or "[]")
prefix = {"eth": "eth", "ether": "ether", "keep": None, "custom": "eth"}.get(naming, "eth")
out = []
for i, n in enumerate(nics):
    name = n["name"] if prefix is None else f"{prefix}{i}"
    role = "wan" if i == 0 else ("lan" if i == 1 else "opt")
    out.append({"mac": n["mac"], "name": name, "role": role})
Path(out_path).write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
print("Предлагаемая карта MAC→name:")
for e in out:
    print(f"  {e['mac']} -> {e['name']} ({e['role']})")
PY

info "naming=$naming (карту можно поправить в answers перед apply)"
