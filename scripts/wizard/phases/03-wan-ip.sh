#!/usr/bin/env bash
# Фаза 03 — WAN IP + Multi-WAN (failover / load-balance)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

echo "Режим WAN:"
echo "  1) DHCP  2) Static  3) PPPoE  4) none (lab)"
choice="$(ask "Выбор" "1")"
case "$choice" in
  1) mode=dhcp ;;
  2) mode=static ;;
  3) mode=pppoe ;;
  4) mode=none ;;
  *) mode=dhcp ;;
esac

vlan="$(ask "VLAN id на WAN (пусто = нет)" "")"
mtu="$(ask "MTU (пусто = auto)" "")"

cat >"$TMP/wan.yaml" <<EOF
wan_mode: $mode
wan_vlan: ${vlan:-null}
wan_mtu: ${mtu:-null}
EOF

if [[ "$mode" == "static" ]]; then
  addr="$(ask "WAN address CIDR" "203.0.113.10/24")"
  gw="$(ask "Gateway" "203.0.113.1")"
  echo "wan_static_address: $addr" >>"$TMP/wan.yaml"
  echo "wan_static_gateway: $gw" >>"$TMP/wan.yaml"
fi

if [[ "$mode" == "pppoe" ]]; then
  user="$(ask "PPPoE username" "")"
  echo "wan_pppoe_user: $user" >>"$TMP/wan.yaml"
  svc="$(ask "PPPoE service-name (пусто=нет)" "")"
  [[ -n "$svc" ]] && echo "wan_pppoe_service: $svc" >>"$TMP/wan.yaml"
  warn "пароль PPPoE: пропишите в /etc/ubrouter/answers.local.yaml → wan.pppoe.password (chmod 0600)"
fi

echo
echo "IPv6 на WAN:"
echo "  1) off  2) dhcpv6  3) slaac"
v6c="$(ask "Выбор" "1")"
case "$v6c" in
  2) wan_ipv6=dhcpv6 ;;
  3) wan_ipv6=slaac ;;
  *) wan_ipv6=off ;;
esac
echo "wan_ipv6: $wan_ipv6" >>"$TMP/wan.yaml"

if [[ "$wan_ipv6" != "off" ]] && confirm "IPv6 адрес на LAN (ULA/GUA)?" N; then
  echo "lan_ipv6_enabled: true" >>"$TMP/wan.yaml"
  echo "lan_ipv6_address: $(ask "LAN IPv6 CIDR" "fd00::1/64")" >>"$TMP/wan.yaml"
else
  echo "lan_ipv6_enabled: false" >>"$TMP/wan.yaml"
fi

multi_mode="off"
if confirm "Добавить Multi-WAN (вторичный uplink)?" N; then
  echo "Политика Multi-WAN:"
  echo "  1) failover — один активный default (probe ping)"
  echo "  2) load-balance (LB) — ECMP равные metric на живых WAN"
  mp="$(ask "Выбор" "1")"
  case "$mp" in
    2) multi_mode=lb ;;
    *) multi_mode=failover ;;
  esac
  mw_if="$(ask "Интерфейс secondary WAN" "eth2")"
  mw_metric="$(ask "route-metric secondary (failover: запасной; LB: вес/метка)" "200")"
  echo "wan_multi_mode: $multi_mode" >>"$TMP/wan.yaml"
  echo "wan_multi_interface: $mw_if" >>"$TMP/wan.yaml"
  echo "wan_multi_metric: $mw_metric" >>"$TMP/wan.yaml"
  info "multi-WAN: mode=$multi_mode if=$mw_if metric=$mw_metric"
fi

info "WAN mode=$mode ipv6=$wan_ipv6"
