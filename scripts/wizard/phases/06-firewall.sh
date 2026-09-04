#!/usr/bin/env bash
# Фаза 06 — Firewall / SSH / port-knock / SIP
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

echo "SSH с WAN:"
echo "  1) deny (закрыть)"
echo "  2) allowlist (список IP)"
echo "  3) port-knock (ICMP length / TCP SYN sequence)"
ssh_pol="$(ask "Выбор" "1")"
case "$ssh_pol" in
  1) wan_ssh=deny ;;
  2) wan_ssh=allowlist ;;
  3) wan_ssh=knock ;;
  *) wan_ssh=deny ;;
esac

allowlist_yaml="[]"
knock_enabled=false
icmp_l="460,549,626"
tcp_p="54231,44398,33458"
knock_timeout="4h30m"
knock_unlock="ssh"

if [[ "$wan_ssh" == "allowlist" ]]; then
  ips="$(ask "IP через пробел (allowlist SSH)" "")"
  if [[ -n "$ips" ]]; then
    allowlist_yaml="$(python3 -c 'import sys; print("[" + ", ".join(chr(34)+x+chr(34) for x in sys.argv[1:] if x) + "]")' $ips)"
  fi
fi

if [[ "$wan_ssh" == "knock" ]]; then
  knock_enabled=true
  echo
  info "Port-knock: последовательность ICMP echo (по length) и/или TCP SYN (по портам)."
  icmp_l="$(ask "ICMP lengths через запятую (3 значения)" "460,549,626")"
  tcp_p="$(ask "TCP SYN ports через запятую (3 значения)" "54231,44398,33458")"
  knock_timeout="$(ask "Таймаут allow после knock" "4h30m")"
  echo "Что открывать после knock: 1) ssh  2) ssh+rdp  3) ssh+ike  4) ssh+rdp+ike"
  u="$(ask "Выбор" "1")"
  case "$u" in
    2) knock_unlock="ssh,rdp" ;;
    3) knock_unlock="ssh,ike" ;;
    4) knock_unlock="ssh,rdp,ike" ;;
    *) knock_unlock="ssh" ;;
  esac
fi

f2b=false; sip=false
confirm "fail2ban?" N && f2b=true
confirm "SIP ALG (Zoiper и т.п.)?" N && sip=true

# knock lengths/ports as YAML lists
icmp_yaml="$(python3 -c 'import sys; print("["+", ".join(x.strip() for x in sys.argv[1].split(",") if x.strip())+"]")' "$icmp_l")"
tcp_yaml="$(python3 -c 'import sys; print("["+", ".join(x.strip() for x in sys.argv[1].split(",") if x.strip())+"]")' "$tcp_p")"
unlock_yaml="$(python3 -c 'import sys; print("["+", ".join(chr(34)+x.strip()+chr(34) for x in sys.argv[1].split(",") if x.strip())+"]")' "$knock_unlock")"

cat >"$TMP/firewall.yaml" <<EOF
wan_ssh: $wan_ssh
fail2ban: $f2b
sip_alg: $sip
port_forwards: []
allowlist_ssh: $allowlist_yaml
knock_enabled: $knock_enabled
knock_icmp_lengths: $icmp_yaml
knock_tcp_ports: $tcp_yaml
knock_allow_timeout: $knock_timeout
knock_unlock: $unlock_yaml
EOF
info "firewall wan_ssh=$wan_ssh knock=$knock_enabled"
