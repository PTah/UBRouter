#!/usr/bin/env bash
# Module: nat-firewall — sysctl forward + nftables NAT baseline
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

WORKDIR="${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}"
ensure_dir "$WORKDIR/nat-firewall"

wan_if="$(ans_get wan.interface)"
lan_if="$(ans_get lan.interface)"
if ans_true interfaces.bridge.enabled; then
  lan_if="$(ans_get interfaces.bridge.name)"
  [[ -n "$lan_if" ]] || lan_if=br-lan
fi

# PPPoE: L3 on ppp0 (not parent eth / vlan)
wan_mode="$(ans_get wan.mode)"
if [[ "$wan_mode" == "pppoe" ]]; then
  wan_if="ppp0"
fi

nat=true
fw=true
ans_true services.nat || nat=false
ans_true services.firewall || fw=false
wan_ssh="$(ans_get firewall.wan_ssh)"
[[ -n "$wan_ssh" ]] || wan_ssh=deny
icmp_wan="$(ans_get firewall.icmp_wan)"
[[ -n "$icmp_wan" ]] || icmp_wan=rate

ipv6_mode="$(ans_get wan.ipv6)"
[[ -n "$ipv6_mode" ]] || ipv6_mode=off
ipv6_fwd=0
[[ "$ipv6_mode" != "off" ]] && ipv6_fwd=1
ans_true lan.ipv6.enabled 2>/dev/null && ipv6_fwd=1

cat >"$WORKDIR/nat-firewall/plan.env" <<EOF
WAN_IF=$wan_if
LAN_IF=$lan_if
NAT=$nat
FW=$fw
WAN_SSH=$wan_ssh
ICMP_WAN=$icmp_wan
IPV6_MODE=$ipv6_mode
IPV6_FWD=$ipv6_fwd
EOF
info "nat-firewall: plan wan=$wan_if lan=$lan_if nat=$nat fw=$fw ipv6=$ipv6_mode"
