!/usr/bin/env bash
# EOIP (MikroTik-compatible): GRE + key=tunnel_id; wait-WAN; routes with metric
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

# wait-wan helper (PPPoE / DHCP lease)
cat >/usr/local/lib/ubrouter/wait-wan-ready.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Wait until we have a default route / global IPv4 (WAN ready for tunnel local=auto)
for i in $(seq 1 60); do
  if ip -4 route show default 2>/dev/null | grep -q .; then
    exit 0
  fi
  if ip -4 addr show scope global 2>/dev/null | grep -q 'inet '; then
    exit 0
  fi
  sleep 2
done
echo "wait-wan-ready: timeout" >&2
exit 1
EOF
chmod 0755 /usr/local/lib/ubrouter/wait-wan-ready.sh

python3 - "$clients_json" <<'PY'
import json, subprocess, sys, textwrap
from pathlib import Path

clients = [c for c in (json.loads(sys.argv[1] or "[]") or []) if c.get("type") == "eoip"]
desired = [c.get("name") or "eoip0" for c in clients]

def cleanup_all():
    print("--> eoip: cleanup (no tunnels in answers)")
    subprocess.call(["systemctl", "disable", "--now", "ubrouter-eoip.service"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.call(["bash", "-c", r'''
      for t in $(ip -br link 2>/dev/null | awk "{print \$1}"); do
        t=${t%:}
        case $t in eoip*) ip tunnel del "$t" 2>/dev/null || ip link del "$t" 2>/dev/null || true;; esac
      done
    '''])
    p = Path("/usr/local/lib/ubrouter/eoip-up.sh")
    if p.is_file():
        p.rename(str(p) + ".ubrouter-disabled")
    Path("/var/lib/ubrouter/vpn/managed-eoip.list").write_text("", encoding="utf-8")
    raise SystemExit(0)

if not clients:
    cleanup_all()

print("--> eoip: MikroTik-compatible GRE + key=tunnel_id")

prev = Path("/var/lib/ubrouter/vpn/managed-eoip.list")
old = prev.read_text(encoding="utf-8").split() if prev.is_file() else []
keep = set(desired)
for name in old:
    if name and name not in keep:
        subprocess.call(["ip", "tunnel", "del", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.call(["ip", "link", "del", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

script = Path("/usr/local/lib/ubrouter/eoip-up.sh")
lines = [
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    "modprobe gre || true",
    "",
]
for c in clients:
    name = c.get("name") or "eoip0"
    remote = c.get("remote")
    tid = c.get("tunnel_id") or c.get("id") or c.get("key")
    if not remote or tid in (None, "", "null"):
        print(f"WARN: eoip {name} нужен remote + tunnel_id — skip", file=sys.stderr)
        continue
    local = c.get("local") or "auto"
    mtu = int(c.get("mtu") or 1476)
    addr = c.get("address")
    mac = c.get("mac")
    routes = c.get("routes") or []
    metric = int(c.get("metric") or 200)
    via = c.get("via")
    lines.append(f"# {name} tunnel_id={tid}")
    lines.append(f"ip tunnel del {name} 2>/dev/null || true")
    if local == "auto":
        lines.append(
            f'LOCAL_IP=$(ip -4 route get {remote} 2>/dev/null | awk \'{{for(i=1;i<=NF;i++) if($i=="src"){{print $(i+1); exit}}}}\')'
        )
        lines.append(f'[[ -n "$LOCAL_IP" ]] || {{ echo "no local for {remote}"; exit 1; }}')
        loc = "$LOCAL_IP"
    else:
        loc = local
    lines.append(
        f"ip tunnel add {name} mode gre remote {remote} local {loc} key {tid} ttl 255"
    )
    if mac:
        lines.append(f'ip link set {name} address {mac} 2>/dev/null || true')
    lines.append(f"ip link set {name} mtu {mtu} up")
    if addr:
        lines.append(f"ip addr replace {addr} dev {name}")
    for r in routes:
        r = str(r).strip()
        if not r:
            continue
        if " via " in r or r.startswith("via "):
            lines.append(f"ip route replace {r} metric {metric}")
        elif via:
            lines.append(f"ip route replace {r} via {via} dev {name} metric {metric}")
        else:
            lines.append(f"ip route replace {r} dev {name} metric {metric}")
    lines.append("")

script.write_text("\n".join(lines) + "\n", encoding="utf-8")
script.chmod(0o755)

unit = Path("/etc/systemd/system/ubrouter-eoip.service")
unit.write_text(textwrap.dedent("""\
    [Unit]
    Description=UBrouter EOIP (GRE+key) tunnels
    After=network-online.target ubrouter-pppoe.service ubrouter-gre.service
    Wants=network-online.target
    After=ubrouter-pppoe.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStartPre=/usr/local/lib/ubrouter/wait-wan-ready.sh
    ExecStart=/usr/local/lib/ubrouter/eoip-up.sh
    ExecStop=/bin/bash -c 'for t in $(ip -br link 2>/dev/null | awk "{print \\$1}"); do case $t in eoip*) ip tunnel del $t 2>/dev/null||true;; esac; done'

    [Install]
    WantedBy=multi-user.target
    """), encoding="utf-8")

subprocess.check_call(["systemctl", "daemon-reload"])
subprocess.check_call(["systemctl", "enable", "ubrouter-eoip.service"])
subprocess.call(["systemctl", "restart", "ubrouter-eoip.service"])
prev.write_text("\n".join(desired) + ("\n" if desired else ""), encoding="utf-8")
print("--> eoip: tunnels applied")
PY

if systemctl is-active ubrouter-eoip.service >/dev/null 2>&1; then
  info "eoip: service active"
else
  # cleanup path disables unit — only warn if we still have eoip in answers
  if echo "$clients_json" | grep -q '"eoip"'; then
    warn "eoip: service не active — journalctl -u ubrouter-eoip"
  fi
fi
info "eoip: done"
