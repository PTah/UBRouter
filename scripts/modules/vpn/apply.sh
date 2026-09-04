!/usr/bin/env bash
# Module: vpn — dispatcher for clients/servers from answers
# Always runs all type modules so empty lists can teardown leftovers.
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

ACTION="${1:-apply}" # plan|apply|verify from wrapper or direct

clients_json="$(ans_get_json vpn.clients)"
servers_json="$(ans_get_json vpn.servers)"

python3 - "$clients_json" "$servers_json" "$ROOT" "$ACTION" <<'PY'
import json, os, subprocess, sys
from pathlib import Path

clients = json.loads(sys.argv[1] or "[]") or []
servers = json.loads(sys.argv[2] or "[]") or []
root = sys.argv[3]
action = sys.argv[4]

def run(mod: str):
    script = os.path.join(root, "scripts", "modules", "vpn", mod, f"{action}.sh")
    if not os.path.isfile(script):
        script = os.path.join(root, "scripts", "modules", "vpn", mod, "apply.sh")
    if not os.path.isfile(script):
        print(f"WARN: no module vpn/{mod}", file=sys.stderr)
        return
    env = os.environ.copy()
    r = subprocess.run(["bash", script], env=env)
    if r.returncode != 0:
        raise SystemExit(r.returncode)

workdir = os.environ.get("UBROUTER_WORKDIR", "/var/lib/ubrouter/work")
os.makedirs(f"{workdir}/vpn", exist_ok=True)
Path(f"{workdir}/vpn/clients.json").write_text(json.dumps(clients), encoding="utf-8")
Path(f"{workdir}/vpn/servers.json").write_text(json.dumps(servers), encoding="utf-8")

types = set()
for c in clients:
    t = (c.get("type") or "").strip()
    if t:
        types.add(t)
for s in servers:
    t = (s.get("type") or "").strip()
    if t:
        types.add(t)

# Always run every type module (empty → cleanup inside module).
# tunnel-ipsec last so it sees gre/eoip/ipip state after their apply.
order = ["wireguard", "openvpn", "gre", "ipip", "l2tp", "ikev2", "eoip", "tunnel-ipsec"]

if not types:
    print("--> vpn: нет клиентов/серверов — cleanup pass")
else:
    print(f"--> vpn: types={','.join(sorted(types))}")

for t in order:
    print(f"--> vpn: {action} type={t}")
    run(t)
PY
