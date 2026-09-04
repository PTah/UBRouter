#!/usr/bin/env bash
# Module: wan — DHCP / static / none / PPPoE
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

bash "$ROOT/scripts/modules/wan/plan.sh"
mode="$(ans_get wan.mode)"
iface="$(ans_get wan.interface)"

if [[ "$mode" != "pppoe" ]]; then
  info "wan: apply: L3 в netplan (модуль lan); mode=$mode"
  exit 0
fi

user="$(ans_get wan.pppoe.username)"
[[ -n "$user" ]] || die "wan.pppoe.username пуст"

pass=""
if [[ -f /etc/ubrouter/answers.local.yaml ]]; then
  pass="$(python3 "$ROOT/scripts/lib/yaml_answers.py" get /etc/ubrouter/answers.local.yaml wan.pppoe.password 2>/dev/null || true)"
fi
if [[ -z "$pass" ]]; then
  pass="$(ans_get wan.pppoe.password)"
fi
[[ -n "$pass" ]] || die "PPPoE password: задайте wan.pppoe.password в answers.local.yaml (0600)"

mtu="$(ans_get wan.pppoe.mtu)"
[[ -n "$mtu" && "$mtu" != "null" ]] || mtu="$(ans_get wan.mtu)"
[[ -n "$mtu" && "$mtu" != "null" ]] || mtu=1492
vlan="$(ans_get wan.vlan_id)"
link_if="$iface"
if [[ -n "$vlan" && "$vlan" != "null" ]]; then
  link_if="${iface}.${vlan}"
fi
svc="$(ans_get wan.pppoe.service_name 2>/dev/null || true)"
ac="$(ans_get wan.pppoe.ac_name 2>/dev/null || true)"

ensure_dir /etc/ppp/peers
ensure_dir /etc/ppp

{
  echo "plugin rp-pppoe.so $link_if"
  echo "user \"$user\""
  echo "noipdefault"
  echo "defaultroute"
  echo "replacedefaultroute"
  echo "hide-password"
  echo "lcp-echo-interval 20"
  echo "lcp-echo-failure 3"
  echo "noauth"
  echo "persist"
  echo "maxfail 0"
  echo "mtu $mtu"
  echo "mru $mtu"
  echo "unit 0"
  [[ -n "$svc" && "$svc" != "null" ]] && echo "rp_pppoe_service \"$svc\""
  [[ -n "$ac" && "$ac" != "null" ]] && echo "rp_pppoe_ac \"$ac\""
  # IPv6: request if wan.ipv6 != off
  ipv6="$(ans_get wan.ipv6 2>/dev/null || echo off)"
  if [[ "$ipv6" != "off" && -n "$ipv6" ]]; then
    echo "+ipv6"
    echo "ipv6cp-use-ipaddr"
  fi
} >/etc/ppp/peers/ubrouter-wan
chmod 0600 /etc/ppp/peers/ubrouter-wan

touch /etc/ppp/pap-secrets /etc/ppp/chap-secrets
chmod 0600 /etc/ppp/pap-secrets /etc/ppp/chap-secrets
sed -i '/# ubrouter-wan/d' /etc/ppp/pap-secrets /etc/ppp/chap-secrets 2>/dev/null || true
echo "\"$user\" * \"$pass\" *  # ubrouter-wan" >>/etc/ppp/pap-secrets
echo "\"$user\" * \"$pass\" *  # ubrouter-wan" >>/etc/ppp/chap-secrets

cat >/etc/systemd/system/ubrouter-pppoe.service <<EOF
[Unit]
Description=UBrouter PPPoE WAN
After=network-online.target
Wants=network-online.target
# ensure VLAN link exists when wan.vlan_id set
ConditionPathExists=/sys/class/net/${link_if}

[Service]
Type=forking
ExecStartPre=/bin/sleep 2
ExecStart=/usr/sbin/pppd call ubrouter-wan
ExecStop=/usr/bin/poff ubrouter-wan
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ubrouter-pppoe.service
systemctl restart ubrouter-pppoe.service || warn "PPPoE start failed — VLAN/кабель: journalctl -u ubrouter-pppoe"
info "wan: PPPoE OK peer=ubrouter-wan link=$link_if mtu=$mtu (L3 iface=ppp0)"
