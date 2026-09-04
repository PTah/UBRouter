!/usr/bin/env bash
# GRE tunnels from answers vpn.clients (type: gre)
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
ensure_dir /etc/ubrouter/gre.d
ensure_dir /var/lib/ubrouter/vpn

python3 - "$clients_json" <<'PY'
import json, os, subprocess, sys, textwrap
from pathlib import Path

clients = [c for c in (json.loads(sys.argv[1] or "[]") or []) if c.get("type") == "gre"]
desired = []
for c in clients:
    n = c.get("name") or "gre0"
    if n:
        desired.append(n)

def sh(cmd):
    subprocess.call(["bash", "-c", cmd])

def cleanup_all():
    print("--> gre: cleanup (no tunnels in answers)")
    subprocess.call(["systemctl", "disable", "--now", "ubrouter-gre.service"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sh(r'''
      for t in $(ip -br tunnel 2>/dev/null | awk "{print \$1}"); do
        case $t in gre*) ip tunnel del "$t" 2>/dev/null || true;; esac
      done
      for t in $(ip -br link 2>/dev/null | awk "{print \$1}"); do
        t=${t%:}
        case $t in gre*) ip link del "$t" 2>/dev/null || ip tunnel del "$t" 2>/dev/null || true;; esac
      done
    ''')
    for p in (Path("/usr/local/lib/ubrouter/gre-up.sh"),):
        if p.is_file():
            p.rename(str(p) + ".ubrouter-disabled")
    Path("/var/lib/ubrouter/vpn/managed-gre.list").write_text("", encoding="utf-8")
    raise SystemExit(0)

if not clients:
    cleanup_all()

# drop orphans not in desired
prev = Path("/var/lib/ubrouter/vpn/managed-gre.list")
old = prev.read_text(encoding="utf-8").split() if prev.is_file() else []
keep = set(desired)
for name in set(old) | set(
    t.split(":")[0]
    for t in subprocess.check_output(
        ["bash", "-c", "ip -br tunnel 2>/dev/null | awk '{print $1}'; ip -br link 2>/dev/null | awk '{print $1}'"],
        text=True,
    ).split()
    if t.startswith("gre")
):
    if name not in keep and name.startswith("gre"):
        subprocess.call(["ip", "tunnel", "del", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.call(["ip", "link", "del", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

script = Path("/usr/local/lib/ubrouter/gre-up.sh")
lines = ["#!/usr/bin/env bash", "set -euo pipefail", "modprobe gre || true", ""]
for c in clients:
    name = c.get("name") or "gre0"
    remote = c.get("remote")
    if not remote:
        print(f"WARN: gre {name} без remote — skip", file=sys.stderr)
        continue
    local = c.get("local") or "auto"
    key = c.get("key")
    mtu = int(c.get("mtu") or 1436)
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
    key_arg = f" key {key}" if key not in (None, "", "null") else ""
    lines.append(f'ip tunnel add {name} mode gre remote {remote} local {loc} ttl 64{key_arg}')
    lines.append(f"ip link set {name} mtu {mtu} up")
    if addr:
        lines.append(f"ip addr replace {addr} dev {name}")
    for r in routes:
        lines.append(f"ip route replace {r} dev {name}")
    lines.append("")

script.write_text("\n".join(lines) + "\n", encoding="utf-8")
script.chmod(0o755)

unit = Path("/etc/systemd/system/ubrouter-gre.service")
unit.write_text(textwrap.dedent("""\
    [Unit]
    Description=UBrouter GRE tunnels
    After=network-online.target ubrouter-pppoe.service
    Wants=network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStartPre=/bin/bash -c 'for i in $(seq 1 30); do ip -4 route show default | grep -q . && exit 0; sleep 2; done; exit 0'
    ExecStart=/usr/local/lib/ubrouter/gre-up.sh
    ExecStop=/bin/bash -c 'for t in $(ip -br tunnel | awk \"{print \\$1}\"); do case $t in gre*) ip tunnel del $t;; esac; done'

    [Install]
    WantedBy=multi-user.target
    """), encoding="utf-8")

subprocess.check_call(["systemctl", "daemon-reload"])
subprocess.check_call(["systemctl", "enable", "ubrouter-gre.service"])
subprocess.call(["systemctl", "restart", "ubrouter-gre.service"])
prev.write_text("\n".join(desired) + ("\n" if desired else ""), encoding="utf-8")
print("--> gre: tunnels applied")
PY

info "gre: done"
