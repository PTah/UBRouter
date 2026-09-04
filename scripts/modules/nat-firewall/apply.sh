#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

bash "$ROOT/scripts/modules/nat-firewall/plan.sh"
# shellcheck source=/dev/null
source "${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}/nat-firewall/plan.env"

# sysctl
IPV6_FWD="${IPV6_FWD:-0}"
cat >/etc/sysctl.d/99-ubrouter.conf <<EOF
# UBrouter
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.tcp_mtu_probing=1
net.ipv6.conf.all.forwarding=${IPV6_FWD}
net.ipv6.conf.default.forwarding=${IPV6_FWD}
EOF
sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-ubrouter.conf >/dev/null || true
info "nat-firewall: ip_forward=$(sysctl -n net.ipv4.ip_forward) ipv6_fwd=$(sysctl -n net.ipv6.conf.all.forwarding)"

if [[ "$FW" != "true" && "$NAT" != "true" ]]; then
  info "nat-firewall: services.firewall/nat выключены — skip nft"
  exit 0
fi

warn "nat-firewall: nft flush ruleset — сторонние цепочки (Docker/libvirt) будут сброшены"

# Knock params from answers
knock_block=""
ssh_wan_rule=""
case "$WAN_SSH" in
  allow)
    ssh_wan_rule="    iifname \"${WAN_IF}\" tcp dport 22 accept"
    ;;
  allowlist)
    ssh_wan_rule="$(python3 - "$UBROUTER_ANSWERS" <<'PY'
import sys
from pathlib import Path
import yaml
ans = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
ips = ((ans.get("firewall") or {}).get("allowlist_ssh")) or []
lines = []
for ip in ips:
    if ip:
        lines.append(f'    ip saddr {ip} tcp dport 22 accept')
if not lines:
    lines.append("    # allowlist_ssh пуст — WAN SSH закрыт")
print("\n".join(lines))
PY
)"
    ;;
  knock)
    knock_block="$(python3 - "$UBROUTER_ANSWERS" "$WAN_IF" <<'PY'
import sys
from pathlib import Path
import yaml
ans = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
wan = sys.argv[2]
fw = ans.get("firewall") or {}
kn = fw.get("knock") or {}
icmp = kn.get("icmp_lengths") or [460, 549, 626]
tcp = kn.get("tcp_ports") or [54231, 44398, 33458]
timeout = kn.get("allow_timeout") or "4h30m"
unlock = kn.get("unlock") or ["ssh"]
if isinstance(unlock, str):
    unlock = [x.strip() for x in unlock.split(",") if x.strip()]
while len(icmp) < 3:
    icmp.append(icmp[-1] if icmp else 460)
while len(tcp) < 3:
    tcp.append(tcp[-1] if tcp else 54231)
l1, l2, l3 = int(icmp[0]), int(icmp[1]), int(icmp[2])
p1, p2, p3 = int(tcp[0]), int(tcp[1]), int(tcp[2])
sets_unlock = []
add_on_success = []
if "ssh" in unlock:
    sets_unlock.append("allow_ssh_knock")
    add_on_success.append("add @allow_ssh_knock { ip saddr }")
if "rdp" in unlock:
    sets_unlock.append("allow_rdp_knock")
    add_on_success.append("add @allow_rdp_knock { ip saddr }")
if "ike" in unlock:
    sets_unlock.append("allow_ipsec_knock")
    add_on_success.append("add @allow_ipsec_knock { ip saddr }")
if not add_on_success:
    sets_unlock = ["allow_ssh_knock"]
    add_on_success = ["add @allow_ssh_knock { ip saddr }"]
success = " ".join(add_on_success)
set_defs = []
for s in ["knock_icmp_s1", "knock_icmp_s2", "knock_tcp_s1", "knock_tcp_s2"]:
    set_defs.append(f"""  set {s} {{
    type ipv4_addr
    flags timeout
    timeout 30s
  }}""")
for s in sets_unlock:
    set_defs.append(f"""  set {s} {{
    type ipv4_addr
    flags timeout
    timeout {timeout}
  }}""")
print("\n".join(set_defs))
print(f"""
  chain port_knock_wan {{
    iifname != "{wan}" return
    icmp type echo-request ip length {l1} add @knock_icmp_s1 {{ ip saddr }}
    icmp type echo-request ip length {l2} ip saddr @knock_icmp_s1 \\
      add @knock_icmp_s2 {{ ip saddr }} delete @knock_icmp_s1 {{ ip saddr }}
    icmp type echo-request ip length {l3} ip saddr @knock_icmp_s2 \\
      {success} \\
      delete @knock_icmp_s2 {{ ip saddr }}
    tcp flags syn tcp dport {p1} add @knock_tcp_s1 {{ ip saddr }}
    tcp flags syn tcp dport {p2} ip saddr @knock_tcp_s1 \\
      add @knock_tcp_s2 {{ ip saddr }} delete @knock_tcp_s1 {{ ip saddr }}
    tcp flags syn tcp dport {p3} ip saddr @knock_tcp_s2 \\
      {success} \\
      delete @knock_tcp_s2 {{ ip saddr }}
    return
  }}
""")
PY
)"
    ssh_wan_rule="    iifname \"${WAN_IF}\" ip saddr @allow_ssh_knock tcp dport 22 accept"
    # optional RDP / IKE after knock
    extra_knock="$(python3 - "$UBROUTER_ANSWERS" "$WAN_IF" <<'PY'
import sys
from pathlib import Path
import yaml
ans = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
wan = sys.argv[2]
unlock = ((ans.get("firewall") or {}).get("knock") or {}).get("unlock") or ["ssh"]
if isinstance(unlock, str):
    unlock = [x.strip() for x in unlock.split(",") if x.strip()]
lines = []
if "rdp" in unlock:
    lines.append(f'    iifname "{wan}" ip saddr @allow_rdp_knock tcp dport 3389 accept')
if "ike" in unlock:
    lines.append(f'    iifname "{wan}" ip saddr @allow_ipsec_knock udp dport {{ 500, 4500 }} accept')
print("\n".join(lines))
PY
)"
    if [[ -n "$extra_knock" ]]; then
      ssh_wan_rule="${ssh_wan_rule}
${extra_knock}"
    fi
    ;;
  *)
    ssh_wan_rule="    # WAN SSH deny"
    ;;
esac

knock_jump=""
if [[ "$WAN_SSH" == "knock" ]]; then
  knock_jump="    jump port_knock_wan"
fi

icmp_rules=""
case "$ICMP_WAN" in
  allow)
    icmp_rules="    ip protocol icmp accept"
    ;;
  deny)
    icmp_rules="    # icmp deny from WAN (LAN still ok via iif LAN)"
    ;;
  *)
    icmp_rules="    ip protocol icmp limit rate 5/second accept"
    ;;
esac

# DNAT port forwards
dnat_rules="$(python3 - "$UBROUTER_ANSWERS" <<'PY'
import sys
from pathlib import Path
import yaml
ans = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
pfs = ((ans.get("firewall") or {}).get("port_forwards")) or []
lines = []
for pf in pfs:
    proto = (pf.get("proto") or "tcp").lower()
    wp = pf.get("wan_port")
    lip = pf.get("lan_ip")
    lp = pf.get("lan_port") or wp
    if not (wp and lip and lp):
        continue
    lines.append(f"    {proto} dport {wp} dnat to {lip}:{lp}")
print("\n".join(lines))
PY
)"

fwd_dnat="$(python3 - "$UBROUTER_ANSWERS" "$WAN_IF" "$LAN_IF" <<'PY'
import sys
from pathlib import Path
import yaml
ans = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
wan_if, lan_if = sys.argv[2], sys.argv[3]
pfs = ((ans.get("firewall") or {}).get("port_forwards")) or []
lines = []
for pf in pfs:
    proto = (pf.get("proto") or "tcp").lower()
    lip = pf.get("lan_ip")
    lp = pf.get("lan_port") or pf.get("wan_port")
    if not (lip and lp):
        continue
    lines.append(
        f'    iifname "{wan_if}" oifname "{lan_if}" ip daddr {lip} {proto} dport {lp} accept'
    )
print("\n".join(lines))
PY
)"

nat_chain=""
if [[ "$NAT" == "true" ]]; then
  dnat_block=""
  if [[ -n "$dnat_rules" ]]; then
    dnat_block=$(cat <<EOF
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
${dnat_rules}
  }
EOF
)
  fi
  nat_chain=$(cat <<EOF
table ip nat {
${dnat_block}
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "${WAN_IF}" masquerade
  }
}
EOF
)
fi

# MSS clamp (PPPoE / tunnels)
mss_rules="    tcp flags syn tcp option maxseg size set rt mtu"

# IPv6 forward when enabled
ipv6_fwd_rules=""
if [[ "${IPV6_FWD:-0}" == "1" ]]; then
  ipv6_fwd_rules=$(cat <<EOF
    # IPv6
    iifname "${LAN_IF}" oifname "${WAN_IF}" meta nfproto ipv6 accept
    iifname "${WAN_IF}" oifname "${LAN_IF}" meta nfproto ipv6 ct state related,established accept
    icmpv6 type { echo-request, echo-reply, nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert, mld-listener-query, mld2-listener-report } accept
EOF
)
fi

cat >/etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
# Generated by UBrouter — baseline (flush: см. docs / warn выше)
flush ruleset

${nat_chain}

table inet filter {
${knock_block}
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iifname "lo" accept
    iifname "${LAN_IF}" accept
${knock_jump}
${icmp_rules}
    icmpv6 type { echo-request, echo-reply, nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept
    iifname "${LAN_IF}" tcp dport 22 accept
${ssh_wan_rule}
    iifname "${LAN_IF}" udp dport 53 accept
    iifname "${LAN_IF}" tcp dport 53 accept
    iifname "${LAN_IF}" udp dport 67 accept
    # IKEv2 / IPsec (NAT-T + ESP/AH without NAT)
    udp dport { 500, 4500 } accept
    meta l4proto { esp, ah } accept
    # GRE / EOIP / IPIP
    meta l4proto { gre, ipencap } accept
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
${mss_rules}
    iifname "${LAN_IF}" oifname "${WAN_IF}" accept
    iifname "${WAN_IF}" oifname "${LAN_IF}" ct state related,established accept
${fwd_dnat}
${ipv6_fwd_rules}
  }
}
EOF

if ! nft -c -f /etc/nftables.conf; then
  die "nftables config invalid (nft -c failed)"
fi

systemctl enable nftables >/dev/null 2>&1 || true
systemctl restart nftables
info "nat-firewall: apply OK"
