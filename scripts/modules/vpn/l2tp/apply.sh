!/usr/bin/env bash
# L2TP client (xl2tpd) + optional IPsec transport PSK (strongSwan)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

WORKDIR="${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}"
clients_json="[]"
[[ -f "$WORKDIR/vpn/clients.json" ]] && clients_json="$(cat "$WORKDIR/vpn/clients.json")"
[[ "$clients_json" == "[]" ]] && clients_json="$(ans_get_json vpn.clients)"

LOCAL_ANSWERS=""
[[ -f /etc/ubrouter/answers.local.yaml ]] && LOCAL_ANSWERS=/etc/ubrouter/answers.local.yaml

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq xl2tpd strongswan strongswan-swanctl >/dev/null

python3 - "$clients_json" "${LOCAL_ANSWERS}" <<'PY'
import json, os, subprocess, sys, textwrap
from pathlib import Path

clients = [c for c in (json.loads(sys.argv[1] or "[]") or []) if c.get("type") == "l2tp"]
local_path = sys.argv[2] or ""
local = {}
if local_path and Path(local_path).is_file():
    import yaml
    local = yaml.safe_load(Path(local_path).read_text(encoding="utf-8")) or {}

if not clients:
    print("--> l2tp: cleanup (no clients in answers)")
    subprocess.call(["systemctl", "disable", "--now", "ubrouter-l2tp.service"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # remove our options + swanctl snippets; leave xl2tpd package installed
    for p in Path("/etc/ppp").glob("options.xl2tpd.*"):
        p.rename(str(p) + ".ubrouter-disabled")
    for p in Path("/etc/swanctl/conf.d").glob("ubrouter-l2tp-*.conf"):
        p.unlink(missing_ok=True)
    up = Path("/usr/local/lib/ubrouter/l2tp-up.sh")
    if up.is_file():
        up.rename(str(up) + ".ubrouter-disabled")
    xl = Path("/etc/xl2tpd/xl2tpd.conf")
    if xl.is_file() and "ubrouter-" in xl.read_text(encoding="utf-8", errors="ignore"):
        xl.rename(str(xl) + ".ubrouter-disabled")
        # minimal empty conf so xl2tpd can start if something else needs it
        Path("/etc/xl2tpd/xl2tpd.conf").write_text("[global]\nport = 1701\n", encoding="utf-8")
    if Path("/run/charon.vici").exists():
        subprocess.call(["swanctl", "--load-all", "--noprompt"])
    Path("/var/lib/ubrouter/vpn").mkdir(parents=True, exist_ok=True)
    Path("/var/lib/ubrouter/vpn/managed-l2tp.list").write_text("", encoding="utf-8")
    raise SystemExit(0)

# orphan LACs / options not in desired
desired_names = [c.get("name") or "l2tp0" for c in clients]
Path("/var/lib/ubrouter/vpn").mkdir(parents=True, exist_ok=True)
prev_path = Path("/var/lib/ubrouter/vpn/managed-l2tp.list")
prev = prev_path.read_text(encoding="utf-8").split() if prev_path.is_file() else []
keep = set(desired_names)
for name in prev:
    if name and name not in keep:
        op = Path(f"/etc/ppp/options.xl2tpd.{name}")
        if op.is_file():
            op.rename(str(op) + ".ubrouter-disabled")
        sc = Path(f"/etc/swanctl/conf.d/ubrouter-l2tp-{name}.conf")
        sc.unlink(missing_ok=True)

pwmap = ((local.get("vpn") or {}).get("l2tp_passwords")) or {}
pskmap = ((local.get("vpn") or {}).get("l2tp_psks")) or ((local.get("vpn") or {}).get("ikev2_psks")) or {}

Path("/etc/xl2tpd").mkdir(parents=True, exist_ok=True)
Path("/etc/ppp").mkdir(parents=True, exist_ok=True)
Path("/usr/local/lib/ubrouter").mkdir(parents=True, exist_ok=True)

# xl2tpd.conf
xl_lines = ["[global]", "port = 1701", ""]
chap = []
ipsec_conns = []
start_cmds = []

for c in clients:
    name = c.get("name") or "l2tp0"
    server = c.get("server") or c.get("remote")
    user = c.get("user") or c.get("username") or name
    if not server:
        print(f"WARN: l2tp {name} без server — skip", file=sys.stderr)
        continue
    password = c.get("password") or pwmap.get(name) or pwmap.get(user)
    if not password:
        # password_ref local:key
        ref = c.get("password_ref") or ""
        if ref.startswith("local:"):
            password = pwmap.get(ref.split(":", 1)[1])
    if not password:
        print(f"WARN: l2tp {name}: нужен password / vpn.l2tp_passwords.{name} в answers.local — skip", file=sys.stderr)
        continue
    psk = c.get("ipsec_psk") or c.get("psk")
    if not psk:
        ref = c.get("ipsec_psk_ref") or ""
        if ref.startswith("local:"):
            psk = pskmap.get(ref.split(":", 1)[1])
        else:
            psk = pskmap.get(name)

    lac = f"ubrouter-{name}"
    xl_lines += [
        f"[lac {lac}]",
        f"lns = {server}",
        "ppp debug = no",
        f"pppoptfile = /etc/ppp/options.xl2tpd.{name}",
        "length bit = yes",
        "redial = yes",
        "redial timeout = 15",
        "max redials = 0",
        "require chap = yes",
        "refuse pap = yes",
        "require authentication = yes",
        f"name = {user}",
        "autodial = yes",
        "",
    ]
    Path(f"/etc/ppp/options.xl2tpd.{name}").write_text(
        textwrap.dedent(f"""\
        ipcp-accept-local
        ipcp-accept-remote
        refuse-eap
        require-chap
        noccp
        noauth
        idle 1800
        mtu 1280
        mru 1280
        defaultroute
        usepeerdns
        debug
        lock
        connect-delay 5000
        name {user}
        password {password}
        """),
        encoding="utf-8",
    )
    Path(f"/etc/ppp/options.xl2tpd.{name}").chmod(0o600)
    chap.append(f'{user} * {password} *')
    start_cmds.append(f"echo 'c {lac}' > /var/run/xl2tpd/l2tp-control")

    if psk:
        # strongSwan transport mode for L2TP
        conf = textwrap.dedent(f"""\
        # UBrouter L2TP/IPsec {name}
        connections {{
          l2tp-{name} {{
            version = 1
            remote_addrs = {server}
            proposals = aes128-sha1-modp1024,aes256-sha256-modp2048
            local {{
              auth = psk
              id = %any
            }}
            remote {{
              auth = psk
            }}
              children {{
              l2tp {{
                mode = transport
                esp_proposals = aes128-sha1,aes256-sha256
                local_ts = 0.0.0.0/0[udp/1701]
                remote_ts = 0.0.0.0/0[udp/1701]
                start_action = start
                dpd_action = restart
              }}
            }}
          }}
        }}
        secrets {{
          ike-l2tp-{name} {{
            secret = "{psk}"
          }}
        }}
        """)
        p = Path(f"/etc/swanctl/conf.d/ubrouter-l2tp-{name}.conf")
        p.write_text(conf, encoding="utf-8")
        p.chmod(0o600)
        ipsec_conns.append(name)

Path("/etc/xl2tpd/xl2tpd.conf").write_text("\n".join(xl_lines) + "\n", encoding="utf-8")
# chap-secrets append unique
chap_path = Path("/etc/ppp/chap-secrets")
existing = chap_path.read_text(encoding="utf-8") if chap_path.is_file() else ""
for line in chap:
    if line.split()[0] not in existing:
        existing += line + "\n"
chap_path.write_text(existing, encoding="utf-8")
chap_path.chmod(0o600)

ctl = Path("/usr/local/lib/ubrouter/l2tp-up.sh")
ctl.write_text(
    "#!/usr/bin/env bash\nset -euo pipefail\n"
    "mkdir -p /var/run/xl2tpd\n"
    "systemctl start xl2tpd\n"
    "sleep 1\n"
    + "\n".join(start_cmds)
    + "\n",
    encoding="utf-8",
)
ctl.chmod(0o755)

unit = Path("/etc/systemd/system/ubrouter-l2tp.service")
unit.write_text(textwrap.dedent("""\
    [Unit]
    Description=UBrouter L2TP clients
    After=network-online.target xl2tpd.service
    Wants=network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/lib/ubrouter/l2tp-up.sh

    [Install]
    WantedBy=multi-user.target
    """), encoding="utf-8")

subprocess.call(["systemctl", "daemon-reload"])
subprocess.call(["systemctl", "enable", "xl2tpd"])
subprocess.call(["systemctl", "restart", "xl2tpd"])
if ipsec_conns:
    subprocess.call(["systemctl", "enable", "strongswan-starter"])
    subprocess.call(["systemctl", "restart", "strongswan-starter"])
    subprocess.call(["swanctl", "--load-all", "--noprompt"])
subprocess.call(["systemctl", "enable", "ubrouter-l2tp.service"])
subprocess.call(["systemctl", "restart", "ubrouter-l2tp.service"])
prev_path.write_text("\n".join(desired_names) + ("\n" if desired_names else ""), encoding="utf-8")
print("--> l2tp: clients applied")
PY

info "l2tp: done — пароли в /etc/ubrouter/answers.local.yaml → vpn.l2tp_passwords"
