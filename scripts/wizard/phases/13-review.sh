#!/usr/bin/env bash
# Assemble answers.yaml from wizard temp fragments (best-effort draft).
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"
OUT="${UBROUTER_ANSWERS_OUT:?}"

naming="$(cat "$TMP/naming" 2>/dev/null || echo eth)"

wan_if="$(grep -E '^wan_interface:' "$TMP/roles.yaml" 2>/dev/null | awk '{print $2}' || echo eth0)"
lan_if="$(grep -E '^lan_interface:' "$TMP/roles.yaml" 2>/dev/null | awk '{print $2}' || echo eth1)"
bridge_enabled="$(grep -E '^bridge_enabled:' "$TMP/roles.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
bridge_name="$(grep -E '^bridge_name:' "$TMP/roles.yaml" 2>/dev/null | awk '{print $2}' || echo br-lan)"

wan_mode="$(grep -E '^wan_mode:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || echo dhcp)"
wan_vlan_raw="$(grep -E '^wan_vlan:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || echo null)"
wan_mtu_raw="$(grep -E '^wan_mtu:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || echo null)"
wan_ipv6="$(grep -E '^wan_ipv6:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || echo off)"
lan_v6_en="$(grep -E '^lan_ipv6_enabled:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
lan_v6_addr="$(grep -E '^lan_ipv6_address:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || echo "")"
[[ -n "$wan_vlan_raw" ]] || wan_vlan_raw=null
[[ -n "$wan_mtu_raw" ]] || wan_mtu_raw=null
[[ -n "$wan_ipv6" ]] || wan_ipv6=off
# yaml null vs number
if [[ "$wan_vlan_raw" == "null" || -z "$wan_vlan_raw" ]]; then
  wan_vlan_yaml="null"
else
  wan_vlan_yaml="$wan_vlan_raw"
fi
if [[ "$wan_mtu_raw" == "null" || -z "$wan_mtu_raw" ]]; then
  wan_mtu_yaml="null"
else
  wan_mtu_yaml="$wan_mtu_raw"
fi
lan_cidr="$(grep -E '^lan_cidr:' "$TMP/lan.yaml" 2>/dev/null | awk '{print $2}' || echo 10.0.0.1/24)"
lan_dhcp="$(grep -E '^lan_dhcp:' "$TMP/lan.yaml" 2>/dev/null | awk '{print $2}' || echo true)"
pool_s="$(grep -E '^lan_pool_start:' "$TMP/lan.yaml" 2>/dev/null | awk '{print $2}' || echo 10.0.0.1)"
pool_e="$(grep -E '^lan_pool_end:' "$TMP/lan.yaml" 2>/dev/null | awk '{print $2}' || echo 10.0.0.1)"
domain="$(grep -E '^lan_domain:' "$TMP/lan.yaml" 2>/dev/null | awk '{print $2}' || echo lan)"

svc_nat="$(grep -E '^svc_nat:' "$TMP/services.yaml" 2>/dev/null | awk '{print $2}' || echo true)"
svc_fw="$(grep -E '^svc_firewall:' "$TMP/services.yaml" 2>/dev/null | awk '{print $2}' || echo true)"
svc_dns="$(grep -E '^svc_dnsmasq:' "$TMP/services.yaml" 2>/dev/null | awk '{print $2}' || echo true)"
svc_ntp="$(grep -E '^svc_chrony:' "$TMP/services.yaml" 2>/dev/null | awk '{print $2}' || echo true)"

wan_ssh="$(grep -E '^wan_ssh:' "$TMP/firewall.yaml" 2>/dev/null | awk '{print $2}' || echo deny)"
f2b="$(grep -E '^fail2ban:' "$TMP/firewall.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
sip="$(grep -E '^sip_alg:' "$TMP/firewall.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
allowlist_ssh="$(grep -E '^allowlist_ssh:' "$TMP/firewall.yaml" 2>/dev/null | sed 's/^allowlist_ssh:[[:space:]]*//' || echo '[]')"
knock_enabled="$(grep -E '^knock_enabled:' "$TMP/firewall.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
knock_icmp="$(grep -E '^knock_icmp_lengths:' "$TMP/firewall.yaml" 2>/dev/null | sed 's/^knock_icmp_lengths:[[:space:]]*//' || echo '[460, 549, 626]')"
knock_tcp="$(grep -E '^knock_tcp_ports:' "$TMP/firewall.yaml" 2>/dev/null | sed 's/^knock_tcp_ports:[[:space:]]*//' || echo '[54231, 44398, 33458]')"
knock_to="$(grep -E '^knock_allow_timeout:' "$TMP/firewall.yaml" 2>/dev/null | awk '{print $2}' || echo 4h30m)"
knock_unlock="$(grep -E '^knock_unlock:' "$TMP/firewall.yaml" 2>/dev/null | sed 's/^knock_unlock:[[:space:]]*//' || echo '[\"ssh\"]')"
[[ -n "$allowlist_ssh" ]] || allowlist_ssh="[]"
[[ -n "$knock_icmp" ]] || knock_icmp="[460, 549, 626]"
[[ -n "$knock_tcp" ]] || knock_tcp="[54231, 44398, 33458]"
[[ -n "$knock_unlock" ]] || knock_unlock='["ssh"]'

dhcp_tags="$(grep -E '^lan_dhcp_tags:' "$TMP/lan.yaml" 2>/dev/null | sed 's/^lan_dhcp_tags:[[:space:]]*//' || echo '[]')"
dhcp_hosts="$(grep -E '^lan_dhcp_hosts:' "$TMP/lan.yaml" 2>/dev/null | sed 's/^lan_dhcp_hosts:[[:space:]]*//' || echo '[]')"
[[ -n "$dhcp_tags" ]] || dhcp_tags="[]"
[[ -n "$dhcp_hosts" ]] || dhcp_hosts="[]"

nw_en="$(grep -E '^netwatch_enabled:' "$TMP/hardening.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
nw_tg="$(grep -E '^netwatch_telegram:' "$TMP/hardening.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
nw_int="$(grep -E '^netwatch_interval:' "$TMP/hardening.yaml" 2>/dev/null | awk '{print $2}' || echo 10)"
nw_label="$(grep -E '^netwatch_host_label:' "$TMP/hardening.yaml" 2>/dev/null | awk '{print $2}' || echo ubrouter)"
nw_hosts="$(grep -E '^netwatch_hosts:' "$TMP/hardening.yaml" 2>/dev/null | sed 's/^netwatch_hosts:[[:space:]]*//' || echo '[]')"
[[ -n "$nw_hosts" ]] || nw_hosts="[]"
vpn_notify="$(grep -E '^vpn_notify_enabled:' "$TMP/hardening.yaml" 2>/dev/null | awk '{print $2}' || echo false)"

ospf_en="$(grep -E '^ospf_enabled:' "$TMP/ospf.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
ospf_rid="$(grep -E '^ospf_router_id:' "$TMP/ospf.yaml" 2>/dev/null | awk '{print $2}' || echo null)"
ospf_redist="$(grep -E '^ospf_redistribute:' "$TMP/ospf.yaml" 2>/dev/null | awk '{print $2}' || echo true)"
ospf_nets="$(grep -E '^ospf_networks:' "$TMP/ospf.yaml" 2>/dev/null | sed 's/^ospf_networks:[[:space:]]*//' || echo '[]')"
ospf_pas="$(grep -E '^ospf_passive:' "$TMP/ospf.yaml" 2>/dev/null | sed 's/^ospf_passive:[[:space:]]*//' || echo '[]')"
[[ -n "$ospf_nets" ]] || ospf_nets="[]"
[[ -n "$ospf_pas" ]] || ospf_pas="[]"

bypass="$(grep -E '^bypass_enabled:' "$TMP/bypass.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
bypass_dom="$(grep -E '^bypass_domain_path:' "$TMP/bypass.yaml" 2>/dev/null | awk '{print $2}' || echo "")"
bypass_cidr="$(grep -E '^bypass_cidr_path:' "$TMP/bypass.yaml" 2>/dev/null | awk '{print $2}' || echo "")"
bypass_tgt="$(grep -E '^bypass_target:' "$TMP/bypass.yaml" 2>/dev/null | awk '{print $2}' || echo "")"
bypass_fo="$(grep -E '^bypass_fail_open:' "$TMP/bypass.yaml" 2>/dev/null | awk '{print $2}' || echo true)"
bypass_mark="$(grep -E '^bypass_fwmark:' "$TMP/bypass.yaml" 2>/dev/null | awk '{print $2}' || echo 0x2)"
bypass_table="$(grep -E '^bypass_table:' "$TMP/bypass.yaml" 2>/dev/null | awk '{print $2}' || echo 200)"
bypass_lan_only="$(grep -E '^bypass_lan_only:' "$TMP/bypass.yaml" 2>/dev/null | awk '{print $2}' || echo true)"
cake_lan="$(grep -E '^cake_lan:' "$TMP/qos.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
uu="$(grep -E '^unattended_upgrades:' "$TMP/hardening.yaml" 2>/dev/null | awk '{print $2}' || echo true)"

igmp="$(grep -E '^igmpproxy_enabled:' "$TMP/igmp.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
igmp_up="$(grep -E '^igmpproxy_upstream:' "$TMP/igmp.yaml" 2>/dev/null | awk '{print $2}' || echo "")"
igmp_down="$(grep -E '^igmpproxy_downstream:' "$TMP/igmp.yaml" 2>/dev/null | awk '{print $2}' || echo "")"
igmp_ql="$(grep -E '^igmpproxy_quickleave:' "$TMP/igmp.yaml" 2>/dev/null | awk '{print $2}' || echo true)"
igmp_alt="$(grep -E '^igmpproxy_altnet:' "$TMP/igmp.yaml" 2>/dev/null | awk '{print $2}' || echo "")"

# YAML helpers
yaml_str_or_null() {
  local v="${1:-}"
  if [[ -z "$v" ]]; then echo "null"; else echo "\"$v\""; fi
}
yaml_list_or_empty() {
  local v="${1:-}"
  if [[ -z "$v" ]]; then echo "[]"; else echo "[\"$v\"]"; fi
}

igmp_alt_yaml="$(yaml_str_or_null "$igmp_alt")"
if [[ "$igmp" != "true" ]]; then
  igmp_up_yaml="null"
  igmp_down_yaml="null"
else
  igmp_up_yaml="$(yaml_str_or_null "$igmp_up")"
  igmp_down_yaml="$(yaml_str_or_null "$igmp_down")"
fi
bypass_tgt_yaml="$(yaml_str_or_null "$bypass_tgt")"
bypass_dom_yaml="$(yaml_list_or_empty "$bypass_dom")"
bypass_cidr_yaml="$(yaml_list_or_empty "$bypass_cidr")"

hostname="$(ask "Hostname" "ubrouter")"
tz="$(ask "Timezone" "Europe/Moscow")"

# bridge members as YAML list
br_members_yaml="[]"
if [[ "$bridge_enabled" == "true" ]]; then
  raw="$(grep -E '^bridge_members:' "$TMP/roles.yaml" 2>/dev/null | sed 's/^bridge_members: *\[//;s/\]$//' || true)"
  br_members_yaml="$(python3 -c 'import sys; ms=[x for x in sys.argv[1].replace(",", " ").split() if x]; print("" + ", ".join(chr(34)+m+chr(34) for m in ms) + ": ")' "$raw")"
fi

map_yaml="[]"
map_block=""
if [[ -f "$TMP/map.json" ]]; then
  map_block="$(python3 - "$TMP/map.json" <<'PY'
import json, sys
from pathlib import Path
m = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8") or "[]")
if not m:
    sys.exit(0)
for e in m:
    mac = e.get("mac", "")
    name = e.get("name", "")
    role = e.get("role", "opt")
    print(f'    - mac: "{mac}"')
    print(f"      name: {name}")
    print(f"      role: {role}")
PY
)"
fi

if [[ -n "$map_block" ]]; then
  map_section="  map:
$map_block"
else
  map_section="  map: []"
fi

# wan static extras
wan_extra=""
if [[ "$wan_mode" == "static" ]]; then
  waddr="$(grep -E '^wan_static_address:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || true)"
  wgw="$(grep -E '^wan_static_gateway:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || true)"
  if [[ -n "$waddr" ]]; then
    wan_extra=$(cat <<WE
  static:
    address: $waddr
    gateway: $wgw
    dns: ["9.9.9.9", "1.1.1.1"]
WE
)
  fi
fi

pppoe_user="$(grep -E '^wan_pppoe_user:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || true)"
pppoe_svc="$(grep -E '^wan_pppoe_service:' "$TMP/wan.yaml" 2>/dev/null | sed 's/^wan_pppoe_service:[[:space:]]*//' || true)"
if [[ "$wan_mode" == "pppoe" && -n "$pppoe_user" ]]; then
  pppoe_svc_line=""
  [[ -n "$pppoe_svc" ]] && pppoe_svc_line=$'\n'"    service_name: \"$pppoe_svc\""
  wan_extra=$(cat <<WE
  pppoe:
    username: "$pppoe_user"
    password: null
    mtu: 1492${pppoe_svc_line}
WE
)
fi

mw_if="$(grep -E '^wan_multi_interface:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || true)"
mw_metric="$(grep -E '^wan_multi_metric:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || echo 200)"
mw_mode="$(grep -E '^wan_multi_mode:' "$TMP/wan.yaml" 2>/dev/null | awk '{print $2}' || echo failover)"
if [[ -n "$mw_if" ]]; then
  wan_extra="${wan_extra}
  multi_mode: $mw_mode
  multi:
    - interface: $mw_if
      mode: dhcp
      metric: $mw_metric"
fi

dns1="$(grep -E '^dns_upstream:' "$TMP/services.yaml" 2>/dev/null | sed -n 's/.*\["\([^"]*\)".*/\1/p' || echo 9.9.9.9)"
dns2="$(grep -E '^dns_upstream:' "$TMP/services.yaml" 2>/dev/null | sed -n 's/.*, *"\([^"]*\)".*/\1/p' || echo 1.1.1.1)"
[[ -n "$dns1" ]] || dns1=9.9.9.9
[[ -n "$dns2" ]] || dns2=1.1.1.1

lan_v6_addr_yaml="null"
[[ -n "$lan_v6_addr" ]] && lan_v6_addr_yaml="\"$lan_v6_addr\""

vpn_clients="[]"
vpn_servers="[]"
if [[ -f "$TMP/vpn.yaml" ]]; then
  vpn_clients="$(grep -E '^vpn_clients:' "$TMP/vpn.yaml" 2>/dev/null | sed 's/^vpn_clients:[[:space:]]*//' || echo '[]')"
  vpn_servers="$(grep -E '^vpn_servers:' "$TMP/vpn.yaml" 2>/dev/null | sed 's/^vpn_servers:[[:space:]]*//' || echo '[]')"
  [[ -n "$vpn_clients" ]] || vpn_clients="[]"
  [[ -n "$vpn_servers" ]] || vpn_servers="[]"
fi

cat >"$OUT" <<EOF
# Generated by UBrouter wizard $UBROUTER_VERSION
version: 1
host:
  timezone: $tz
  hostname: $hostname
interfaces:
  naming: $naming
  order: pci
$map_section
  bridge:
    enabled: $bridge_enabled
    name: $bridge_name
    members: $br_members_yaml
wan:
  interface: $wan_if
  mode: $wan_mode
  vlan_id: $wan_vlan_yaml
  mtu: $wan_mtu_yaml
  ipv6: $wan_ipv6
$wan_extra
lan:
  interface: $lan_if
  cidr: $lan_cidr
  domain: $domain
  dns_for_clients: router
  ntp_for_clients: router
  ipv6:
    enabled: $lan_v6_en
    address: $lan_v6_addr_yaml
  dhcp:
    enabled: $lan_dhcp
    pool_start: $pool_s
    pool_end: $pool_e
    lease: 12h
    tags: $dhcp_tags
    hosts: $dhcp_hosts
services:
  nat: $svc_nat
  firewall: $svc_fw
  dnsmasq: $svc_dns
  chrony: $svc_ntp
  fail2ban: $f2b
  sip_alg: $sip
  sqm: $cake_lan
  igmpproxy: $igmp
  unattended_upgrades: $uu
igmpproxy:
  enabled: $igmp
  upstream: $igmp_up_yaml
  downstream: $igmp_down_yaml
  quickleave: $igmp_ql
  altnet: $igmp_alt_yaml
dns:
  upstream:
    - "$dns1"
    - "$dns2"
firewall:
  wan_ssh: $wan_ssh
  allowlist_ssh: $allowlist_ssh
  icmp_wan: rate
  port_forwards: []
  knock:
    enabled: $knock_enabled
    icmp_lengths: $knock_icmp
    tcp_ports: $knock_tcp
    allow_timeout: $knock_to
    unlock: $knock_unlock
vpn:
  clients: $vpn_clients
  servers: $vpn_servers
bypass:
  enabled: $bypass
  domain_files: $bypass_dom_yaml
  cidr_files: $bypass_cidr_yaml
  target: $bypass_tgt_yaml
  fail_open: $bypass_fo
  fwmark: "$bypass_mark"
  table: $bypass_table
  mark_lan_only: $bypass_lan_only
qos:
  cake_lan: $cake_lan
  cake_tunnels: false
  bandwidth: null
monitoring:
  netwatch:
    enabled: $nw_en
    interval_sec: $nw_int
    telegram: $nw_tg
    host_label: $nw_label
    hosts: $nw_hosts
  vpn_notify:
    enabled: $vpn_notify
    telegram: true
    events: [ikev2, gre, eoip, wireguard, openvpn]
routing:
  ospf:
    enabled: $ospf_en
    router_id: $ospf_rid
    redistribute_connected: $ospf_redist
    networks: $ospf_nets
    passive_interfaces: $ospf_pas
EOF

chmod 0600 "$OUT"
echo
info "Summary записан в $OUT"
echo "----"
cat "$OUT"
echo "----"
if [[ -z "$map_block" ]]; then
  warn "interfaces.map пуст — на целевом хосте apply сам прощупает NIC (или заполните map)."
fi
