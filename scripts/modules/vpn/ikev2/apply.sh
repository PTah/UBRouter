!/usr/bin/env bash
# Module: vpn/ikev2 — strongSwan IKEv2 server (cert) + client (EAP/PSK/pubkey)
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
servers_json="[]"
[[ -f "$WORKDIR/vpn/clients.json" ]] && clients_json="$(cat "$WORKDIR/vpn/clients.json")"
[[ -f "$WORKDIR/vpn/servers.json" ]] && servers_json="$(cat "$WORKDIR/vpn/servers.json")"
[[ "$clients_json" == "[]" ]] && clients_json="$(ans_get_json vpn.clients)"
[[ "$servers_json" == "[]" ]] && servers_json="$(ans_get_json vpn.servers)"

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq \
  strongswan strongswan-pki strongswan-swanctl \
  libcharon-extra-plugins openssl \
  >/dev/null

ensure_dir /etc/swanctl/x509ca
ensure_dir /etc/swanctl/x509
ensure_dir /etc/swanctl/private
ensure_dir /etc/swanctl/conf.d
ensure_dir /var/lib/ubrouter/pki/{cacerts,certs,private}
chmod 700 /var/lib/ubrouter/pki /var/lib/ubrouter/pki/private
ensure_dir /root/ubrouter-vpn-clients
chmod 700 /root/ubrouter-vpn-clients

# Optional secrets from answers.local
LOCAL_ANSWERS=""
[[ -f /etc/ubrouter/answers.local.yaml ]] && LOCAL_ANSWERS=/etc/ubrouter/answers.local.yaml

set +e
python3 - "$clients_json" "$servers_json" "${LOCAL_ANSWERS}" "$UBROUTER_ANSWERS" <<'PY'
import json, os, shutil, subprocess, sys, textwrap
from pathlib import Path

clients = [c for c in (json.loads(sys.argv[1] or "[]") or []) if c.get("type") == "ikev2"]
servers = [s for s in (json.loads(sys.argv[2] or "[]") or []) if s.get("type") == "ikev2"]
local_path = sys.argv[3] or ""
answers_path = sys.argv[4]

def load_yaml(path):
    if not path or not Path(path).is_file():
        return {}
    import yaml
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}

answers = load_yaml(answers_path)
local = load_yaml(local_path)
lan_cidr = ((answers.get("lan") or {}).get("cidr")) or "10.0.0.1/24"
lan_ip = lan_cidr.split("/")[0]

def run(cmd, **kw):
    print("-->", " ".join(cmd) if isinstance(cmd, list) else cmd)
    subprocess.check_call(cmd, **kw)

def swan_quote(val) -> str:
    return '"' + str(val).replace("\\", "\\\\").replace('"', '\\"') + '"'

def ensure_server_pki(srv: dict):
    force = bool(srv.get("force_pki"))
    pki_dir = Path("/var/lib/ubrouter/pki")
    ca_key = pki_dir / "private/ca-key.pem"
    ca_cert = pki_dir / "cacerts/ca-cert.pem"
    srv_key = pki_dir / "private/server-key.pem"
    srv_cert = pki_dir / "certs/server-cert.pem"
    ca_cn = srv.get("ca_cn") or "UBrouter VPN CA"
    server_cn = srv.get("server_cn") or "ubrouter-vpn"
    server_id = srv.get("id") or "auto"
    if server_id in ("auto", "", None):
        # best-effort public/WAN guess
        try:
            out = subprocess.check_output(
                ["bash", "-c", "ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"src\"){print $(i+1); exit}}'"],
                text=True,
            ).strip()
        except Exception:
            out = ""
        server_id = out or server_cn

    if not (ca_key.is_file() and ca_cert.is_file()) or force:
        print("=== IKEv2 PKI: CA ===")
        with open(ca_key, "w") as out:
            subprocess.check_call(
                ["pki", "--gen", "--type", "rsa", "--size", "4096", "--outform", "pem"],
                stdout=out,
            )
        ca_key.chmod(0o600)
        with open(ca_cert, "w") as out:
            subprocess.check_call(
                [
                    "pki", "--self", "--ca", "--lifetime", "3650",
                    "--in", str(ca_key), "--type", "rsa",
                    "--dn", f"CN={ca_cn}", "--outform", "pem",
                ],
                stdout=out,
            )
    if not (srv_key.is_file() and srv_cert.is_file()) or force:
        print("=== IKEv2 PKI: server ===")
        with open(srv_key, "w") as out:
            subprocess.check_call(
                ["pki", "--gen", "--type", "rsa", "--size", "4096", "--outform", "pem"],
                stdout=out,
            )
        srv_key.chmod(0o600)
        pub = subprocess.check_output(["pki", "--pub", "--in", str(srv_key), "--type", "rsa"])
        with open(srv_cert, "w") as out:
            proc = subprocess.Popen(
                [
                    "pki", "--issue", "--lifetime", "1825",
                    "--cacert", str(ca_cert), "--cakey", str(ca_key),
                    "--dn", f"CN={server_cn}", "--san", server_id, "--san", server_cn,
                    "--flag", "serverAuth", "--flag", "ikeIntermediate",
                    "--outform", "pem",
                ],
                stdin=subprocess.PIPE,
                stdout=out,
            )
            proc.communicate(pub)
            if proc.returncode:
                raise SystemExit("pki issue server failed")

    # install into swanctl
    shutil.copy2(ca_cert, "/etc/swanctl/x509ca/ca-cert.pem")
    shutil.copy2(srv_cert, "/etc/swanctl/x509/server-cert.pem")
    shutil.copy2(srv_key, "/etc/swanctl/private/server-key.pem")
    Path("/etc/swanctl/private/server-key.pem").chmod(0o600)
    return server_id, ca_key, ca_cert

def issue_clients(names, server_id: str, force=False):
    """Делегирует в issue-client.sh (единый UX для PKCS#12)."""
    root = os.environ.get("UBROUTER_ROOT", "")
    script = Path(root) / "scripts/modules/vpn/ikev2/issue-client.sh"
    if not script.is_file():
        raise SystemExit(f"нет {script}")
    for user in names:
        cmd = [
            "bash", str(script),
            "--name", str(user),
            "--server", str(server_id),
            "--generate-password",
            "--non-interactive",
            "--no-reload",
        ]
        if force:
            cmd.append("--force")
        print(f"=== IKEv2 client cert via issue-client.sh: {user} ===")
        subprocess.check_call(cmd)

def write_server_swanctl(srv: dict, server_id: str):
    name = srv.get("name") or "ikev2-server"
    pool_name = f"{name}-pool".replace("-", "_")
    addrs = srv.get("pool") or "10.67.0.10-10.67.0.200"
    if "/" in str(addrs) and "-" not in str(addrs):
        # CIDR given — use conservative range note in docs; convert poorly → keep as-is string for swanctl if range
        addrs = srv.get("pool_range") or "10.67.0.10-10.67.0.200"
    dns = srv.get("dns") or [lan_ip]
    if isinstance(dns, str):
        dns = [dns]
    local_ts = srv.get("local_ts") or "0.0.0.0/0"
    if isinstance(local_ts, list):
        local_ts = ",".join(local_ts)
    mon = (answers.get("monitoring") or {}).get("vpn_notify") or {}
    vpn_tg = mon.get("enabled") in (True, "true", "1", "yes", 1)
    events = mon.get("events") or ["ikev2", "gre", "eoip", "wireguard", "openvpn"]
    if isinstance(events, str):
        events = [x.strip() for x in events.split(",") if x.strip()]
    updown_line = ""
    if vpn_tg and ("ikev2" in events or "strongswan" in events):
        updown_line = '            updown = /usr/local/sbin/ubrouter-vpn-updown-ikev2.sh\n'
    conf = textwrap.dedent(f"""\
    # Generated by UBrouter vpn/ikev2 — server {name}
    connections {{
      {name} {{
        version = 2
        proposals = aes256-sha256-modp2048,aes256-sha256-ecp256,aes128-sha256-modp2048
        fragmentation = yes
        mobike = yes
        dpd_delay = 30s
        pools = {pool_name}
        send_cert = always

        local {{
          auth = pubkey
          certs = server-cert.pem
          id = {server_id}
        }}
        remote {{
          auth = pubkey
        }}
        children {{
          net {{
            local_ts = {local_ts}
            remote_ts = dynamic
            esp_proposals = aes256gcm16-aes128gcm16,aes256-sha256
            start_action = none
            dpd_action = clear
{updown_line}          }}
        }}
      }}
    }}

    pools {{
      {pool_name} {{
        addrs = {addrs}
        dns = {",".join(dns)}
      }}
    }}
    """)
    out = Path(f"/etc/swanctl/conf.d/ubrouter-{name}.conf")
    out.write_text(conf, encoding="utf-8")
    out.chmod(0o640)
    print(f"--> wrote {out}")

def local_secret(path_keys):
    """path_keys like ['vpn','clients',0,'password'] from answers.local merge loosely."""
    cur = local
    for k in path_keys:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
    return cur

def write_client_swanctl(cli: dict, idx: int):
    name = cli.get("name") or f"ikev2-client{idx}"
    remote = cli.get("remote")
    if not remote:
        print(f"WARN: ikev2 client {name} без remote — skip", file=sys.stderr)
        return
    auth = (cli.get("auth") or "eap-mschapv2").lower()
    remote_ts = cli.get("remote_ts") or "0.0.0.0/0"
    if isinstance(remote_ts, list):
        remote_ts = ",".join(remote_ts)
    local_ts = cli.get("local_ts") or "dynamic"
    if isinstance(local_ts, list):
        local_ts = ",".join(local_ts)
    eap_id = cli.get("eap_id") or cli.get("id") or name
    password = cli.get("password")
    if not password and local:
        # answers.local.yaml: vpn.ikev2_passwords.<name> or vpn.clients passwords by name
        pwmap = ((local.get("vpn") or {}).get("ikev2_passwords")) or {}
        password = pwmap.get(name) or pwmap.get(eap_id)
    psk = cli.get("psk")
    if not psk and local:
        pskmap = ((local.get("vpn") or {}).get("ikev2_psks")) or {}
        psk = pskmap.get(name)

    secrets_block = ""
    local_auth = ""
    remote_auth = ""
    if auth in ("eap", "eap-mschapv2", "eap-mschap"):
        if not password:
            print(f"WARN: {name}: нужен password в answers или vpn.ikev2_passwords в answers.local — skip", file=sys.stderr)
            return
        local_auth = textwrap.dedent(f"""\
            local {{
              auth = eap-mschapv2
              eap_id = {swan_quote(eap_id)}
            }}
        """)
        remote_auth = "remote {\n      auth = pubkey\n      id = %any\n    }"
        secrets_block = textwrap.dedent(f"""\
            secrets {{
              eap-{name} {{
                id = {swan_quote(eap_id)}
                secret = {swan_quote(password)}
              }}
            }}
        """)
    elif auth == "psk":
        if not psk:
            print(f"WARN: {name}: нужен psk / vpn.ikev2_psks — skip", file=sys.stderr)
            return
        lid = cli.get("id") or eap_id
        local_auth = textwrap.dedent(f"""\
            local {{
              auth = psk
              id = {swan_quote(lid)}
            }}
        """)
        remote_auth = "remote {\n      auth = psk\n    }"
        secrets_block = textwrap.dedent(f"""\
            secrets {{
              ike-{name} {{
                id = {swan_quote(lid)}
                secret = {swan_quote(psk)}
              }}
            }}
        """)
    elif auth == "pubkey":
        # expect certs already in swanctl or paths in answers
        cert = cli.get("cert") or f"{name}-cert.pem"
        key = cli.get("key") or f"{name}-key.pem"
        # copy if absolute paths provided
        for src, dst_dir in (
            (cli.get("cert_file"), "/etc/swanctl/x509"),
            (cli.get("key_file"), "/etc/swanctl/private"),
            (cli.get("ca_file"), "/etc/swanctl/x509ca"),
        ):
            if src and Path(src).is_file():
                d = Path(dst_dir)
                d.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, d / Path(src).name)
                if "private" in dst_dir:
                    (d / Path(src).name).chmod(0o600)
                if dst_dir.endswith("x509"):
                    cert = Path(src).name
                if dst_dir.endswith("private"):
                    key = Path(src).name
        local_auth = textwrap.dedent(f"""\
            local {{
              auth = pubkey
              certs = {cert}
              id = {cli.get("id") or name}
            }}
        """)
        remote_auth = "remote {\n      auth = pubkey\n    }"
        # key must be in private/
        key_src = cli.get("key_file")
        if key_src and Path(key_src).is_file():
            shutil.copy2(key_src, f"/etc/swanctl/private/{key}")
            Path(f"/etc/swanctl/private/{key}").chmod(0o600)
    else:
        print(f"WARN: unknown auth={auth} for {name}", file=sys.stderr)
        return

    start = "start" if cli.get("auto_start", True) else "none"
    conf = textwrap.dedent(f"""\
    # Generated by UBrouter — IKEv2 client {name}
    connections {{
      {name} {{
        version = 2
        remote_addrs = {remote}
        proposals = aes256-sha256-modp2048,aes256-sha256-ecp256,aes128-sha256-modp2048
        fragmentation = yes
        mobike = yes
        dpd_delay = 30s
        {local_auth}
        {remote_auth}
        children {{
          net {{
            local_ts = {local_ts}
            remote_ts = {remote_ts}
            esp_proposals = aes256gcm16-aes128gcm16,aes256-sha256
            start_action = {start}
            dpd_action = restart
          }}
        }}
      }}
    }}
    {secrets_block}
    """)
    # fix indentation of embedded blocks
    out = Path(f"/etc/swanctl/conf.d/ubrouter-client-{name}.conf")
    out.write_text(conf, encoding="utf-8")
    out.chmod(0o600)
    print(f"--> wrote {out}")

# --- servers ---
for srv in servers:
    server_id, ca_key, ca_cert = ensure_server_pki(srv)
    write_server_swanctl(srv, server_id)
    names = srv.get("clients") or srv.get("users") or []
    if isinstance(names, str):
        names = names.split()
    if names:
        issue_clients(names, server_id, force=bool(srv.get("force_pki")))
    # nft UDP 500/4500 + best-effort forward/NAT for client pool
    for port in (500, 4500):
        subprocess.call(
            f"nft list table inet filter >/dev/null 2>&1 && "
            f"nft add rule inet filter input udp dport {port} accept 2>/dev/null || true",
            shell=True,
        )
    pool = srv.get("pool") or "10.67.0.10-10.67.0.200"
    # derive /24-ish for comment; use 10.67.0.0/24 when default-like pool
    vpn_net = srv.get("pool_cidr") or "10.67.0.0/24"
    if isinstance(pool, str) and pool.startswith("10.67.0."):
        vpn_net = "10.67.0.0/24"
    subprocess.call(
        f"nft list table inet filter >/dev/null 2>&1 && "
        f"nft add rule inet filter forward ip saddr {vpn_net} accept 2>/dev/null || true",
        shell=True,
    )
    subprocess.call(
        f"nft list table inet nat >/dev/null 2>&1 && "
        f"nft add rule inet nat postrouting ip saddr {vpn_net} masquerade 2>/dev/null || true",
        shell=True,
    )

# --- clients ---
for i, cli in enumerate(clients):
    write_client_swanctl(cli, i)

def is_ikev2_snippet(name: str) -> bool:
    if name.startswith("ubrouter-l2tp-") or name.startswith("ubrouter-tunnel-ipsec-"):
        return False
    return name.startswith("ubrouter-client-") or (
        name.startswith("ubrouter-") and name.endswith(".conf")
    )

confd = Path("/etc/swanctl/conf.d")
Path("/var/lib/ubrouter/vpn").mkdir(parents=True, exist_ok=True)
state = Path("/var/lib/ubrouter/vpn/managed-ikev2.list")
prev = state.read_text(encoding="utf-8").split() if state.is_file() else []
desired = []
for s in servers:
    desired.append(s.get("name") or "ikev2-server")
for c in clients:
    desired.append(c.get("name") or "ikev2-client")
keep = set(desired)

# orphan server/client snippets not in answers
for name in prev:
    if not name or name in keep:
        continue
    for pat in (f"ubrouter-{name}.conf", f"ubrouter-client-{name}.conf"):
        p = confd / pat
        if p.is_file():
            print(f"--> ikev2: remove orphan {p.name}")
            p.unlink(missing_ok=True)

if not servers and not clients:
    print("--> ikev2: cleanup (no servers/clients in answers)")
    for p in confd.glob("ubrouter-*.conf"):
        if is_ikev2_snippet(p.name):
            p.unlink(missing_ok=True)
    state.write_text("", encoding="utf-8")
    if Path("/run/charon.vici").exists():
        subprocess.call(["swanctl", "--load-all", "--noprompt"])
    # signal bash: cleanup only — do not (re)enable IKEv2 units
    raise SystemExit(10)

state.write_text("\n".join(desired) + ("\n" if desired else ""), encoding="utf-8")
print("--> ikev2: configs ready")
PY
IKEV2_RC=$?
set -e
if [[ "${IKEV2_RC}" -eq 10 ]]; then
  info "ikev2: cleaned — PKI/certs preserved under /var/lib/ubrouter/pki"
  exit 0
fi
[[ "${IKEV2_RC}" -eq 0 ]] || exit "${IKEV2_RC}"

# Minimal charon include: prefer conf.d snippets; ensure main swanctl.conf includes them
if [[ ! -f /etc/swanctl/swanctl.conf ]] || ! grep -q 'include conf.d' /etc/swanctl/swanctl.conf 2>/dev/null; then
  cat >/etc/swanctl/swanctl.conf <<'EOF'
# UBrouter — include drop-ins
include conf.d/*.conf
EOF
  chmod 0640 /etc/swanctl/swanctl.conf
fi

# swanctl load after starter
cat >/usr/local/sbin/ubrouter-swanctl-load.sh <<'EOF'
#!/bin/bash
set -euo pipefail
i=0
while [ "$i" -lt 40 ]; do
  if [ -S /run/charon.vici ]; then
    exec /usr/sbin/swanctl --load-all --noprompt
  fi
  i=$((i + 1))
  sleep 0.25
done
echo "ubrouter-swanctl-load: vici missing" >&2
exit 1
EOF
chmod 755 /usr/local/sbin/ubrouter-swanctl-load.sh

cat >/etc/systemd/system/ubrouter-swanctl-load.service <<'EOF'
[Unit]
Description=UBrouter load swanctl (IKEv2)
After=strongswan-starter.service network-online.target
Wants=network-online.target
Requires=strongswan-starter.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ubrouter-swanctl-load.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable strongswan-starter 2>/dev/null || systemctl enable strongswan 2>/dev/null || true
systemctl restart strongswan-starter 2>/dev/null || systemctl restart strongswan 2>/dev/null || true
systemctl enable ubrouter-swanctl-load.service
systemctl restart ubrouter-swanctl-load.service || {
  warn "swanctl load failed — проверьте /etc/swanctl/conf.d/ и journalctl -u ubrouter-swanctl-load"
  swanctl --list-conns || true
}

info "ikev2: done — клиентские .p12: /root/ubrouter-vpn-clients/"
info "ikev2: новый клиент: sudo ./ubrouter ikev2-client   (или issue-client.sh --name anna-android)"
info "ikev2: проверка: swanctl --list-conns ; swanctl --list-sas"
