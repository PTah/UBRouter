!/usr/bin/env bash
# IPIP tunnels from answers vpn.clients (type: ipip)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/vpn-cleanup.sh"
ans_require
need_root

WORKDIR="${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}"
clients_json="[]"
[[ -f "$WORKDIR/vpn/clients.json" ]] && clients_json="$(cat "$WORKDIR/vpn/clients.json")"
[[ "$clients_json" == "[]" ]] && clients_json="$(ans_get_json vpn.clients)"

ensure_dir /usr/local/lib/ubrouter
ensure_dir /var/lib/ubrouter/vpn

python3 - "$clients_json" <<'PY'
import json, subprocess, sys, textwrap
from pathlib import Path

clients = [c for c in (json.loads(sys.argv[1] or "[]") or []) if c.get("type") == "ipip"]
desired = [c.get("name") or "ipip0" for c in clients]

def cleanup_all():
    print("--> ipip: cleanup (no tunnels in answers)")
    subprocess.call(["systemctl", "disable", "--now", "ubrouter-ipip.service"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.call(["bash", "-c", r'''
      for t in $(ip -br tunnel 2>/dev/null | awk "{print \$1}"); do
        case $t in ipip*|tunl*) ip tunnel del "$t" 2>/dev/null || true;; esac
      done
    '''])
    p = Path("/usr/local/lib/ubrouter/ipip-up.sh")
    if p.is_file():
        p.rename(str(p) + ".ubrouter-disabled")
    Path("/var/lib/ubrouter/vpn/managed-ipip.list").write_text("", encoding="utf-8")
    raise SystemExit(0)

if not clients:
    cleanup_all()

prev = Path("/var/lib/ubrouter/vpn/managed-ipip.list")
old = prev.read_text(encoding="utf-8").split() if prev.is_file() else []
keep = set(desired)
for name in old:
    if name and name not in keep:
        subprocess.call(["ip", "tunnel", "del", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

script = Path("/usr/local/lib/ubrouter/ipip-up.sh")
lines = ["#!/usr/bin/env bash", "set -euo pipefail", "modprobe ipip || true", ""]
for c in clients:
    name = c.get("name") or "ipip0"
    remote = c.get("remote")
    if not remote:
        print(f"WARN: ipip {name} без remote — skip", file=sys.stderr)
        continue
    local = c.get("local") or "auto"
    mtu = int(c.get("mtu") or 1480)
    addr = c.get("address")
    routes = c.get("routes") or []
    lines.append(f"# {name}")
    lines.append(f"ip tunnel del {name} 2>/dev/null || true")
    if local == "auto":
        lines.append(
            f'LOCAL_IP=$(ip -4 route get {remote} 2>/dev/null | awk \'{{for(i=1;i<=NF;i++) if($i=="src"){{print $(i+1); exit}}}}\')'
        )
        lines.append(f'[[ -n "$LOCAL_IP" ]] || {{ echo "no local for {remote}"; exit 1; }}')
        loc = "$LOCAL_IP"
    else:
        loc = local
    lines.append(f"ip tunnel add {name} mode ipip remote {remote} local {loc} ttl 64")
    lines.append(f"ip link set {name} mtu {mtu} up")
    if addr:
        lines.append(f"ip addr replace {addr} dev {name}")
    for r in routes:
        lines.append(f"ip route replace {r} dev {name}")
    lines.append("")

script.write_text("\n".join(lines) + "\n", encoding="utf-8")
script.chmod(0o755)

unit = Path("/etc/systemd/system/ubrouter-ipip.service")
unit.write_text(textwrap.dedent("""\
    [Unit]
    Description=UBrouter IPIP tunnels
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/lib/ubrouter/ipip-up.sh
    ExecStop=/bin/bash -c 'for t in $(ip -br tunnel 2>/dev/null | awk "{print \\$1}"); do case $t in ipip*|tunl*) ip tunnel del $t 2>/dev/null||true;; esac; done'

    [Install]
    WantedBy=multi-user.target
    """), encoding="utf-8")

subprocess.check_call(["systemctl", "daemon-reload"])
subprocess.check_call(["systemctl", "enable", "ubrouter-ipip.service"])
subprocess.call(["systemctl", "restart", "ubrouter-ipip.service"])
prev.write_text("\n".join(desired) + ("\n" if desired else ""), encoding="utf-8")
print("--> ipip: tunnels applied")
PY

info "ipip: done"
