#!/usr/bin/env bash
# Ensure packages for base + optional features from answers (when available).
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
need_root

info "packages: resolve set from answers"
export DEBIAN_FRONTEND=noninteractive

# wait for dpkg lock (unattended-upgrades)
for i in $(seq 1 30); do
  if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
    && ! fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
    break
  fi
  warn "ждём dpkg lock ($i/30)…"
  sleep 2
done

apt-get update -qq

PKGS=(
  nftables python3-yaml
  iproute2 iptables bridge-utils
)

# answers may not be readable yet — soft
ANSWERS="${UBROUTER_ANSWERS:-/etc/ubrouter/answers.yaml}"
need_ppp=0 need_wg=0 need_ovpn=0 need_ike=0 need_l2tp=0
need_igmp=0 need_f2b=0 need_dns=0 need_ntp=0 need_curl=0 need_frr=0

if [[ -f "$ANSWERS" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/scripts/lib/answers.sh" 2>/dev/null || true
  if declare -F ans_available >/dev/null 2>&1 && ans_available; then
    export UBROUTER_ANSWERS="$ANSWERS"
    ans_true services.dnsmasq && need_dns=1 || true
    ans_true services.chrony && need_ntp=1 || true
    ans_true services.fail2ban && need_f2b=1 || true
    ans_true services.igmpproxy && need_igmp=1 || true
    [[ "$(ans_get wan.mode 2>/dev/null || true)" == "pppoe" ]] && need_ppp=1
    cj="$(ans_get_json vpn.clients 2>/dev/null || echo '[]')"
    sj="$(ans_get_json vpn.servers 2>/dev/null || echo '[]')"
    echo "$cj$sj" | grep -q wireguard && need_wg=1 || true
    echo "$cj$sj" | grep -q openvpn && need_ovpn=1 || true
    echo "$cj$sj" | grep -q ikev2 && need_ike=1 || true
    echo "$cj$sj" | grep -q l2tp && { need_l2tp=1; need_ike=1; } || true
    nw="$(ans_get monitoring.netwatch.enabled 2>/dev/null || true)"
    [[ "$nw" == "true" || "$nw" == "1" || "$nw" == "yes" ]] && need_curl=1
    tg="$(ans_get monitoring.netwatch.telegram 2>/dev/null || true)"
    [[ "$tg" == "true" || "$tg" == "1" || "$tg" == "yes" ]] && need_curl=1
    vn="$(ans_get monitoring.vpn_notify.enabled 2>/dev/null || true)"
    [[ "$vn" == "true" || "$vn" == "1" || "$vn" == "yes" ]] && need_curl=1
    ospf="$(ans_get routing.ospf.enabled 2>/dev/null || true)"
    [[ "$ospf" == "true" || "$ospf" == "1" || "$ospf" == "yes" ]] && need_frr=1
  fi
fi

# defaults for first-time / no answers yet
if [[ ! -f "$ANSWERS" ]]; then
  need_dns=1
  need_ntp=1
fi

PKGS+=(ppp pppoe)  # small; WAN may become pppoe later
[[ "$need_dns" -eq 1 ]] && PKGS+=(dnsmasq)
[[ "$need_ntp" -eq 1 ]] && PKGS+=(chrony)
[[ "$need_wg" -eq 1 ]] && PKGS+=(wireguard wireguard-tools)
[[ "$need_ovpn" -eq 1 ]] && PKGS+=(openvpn openssl)
[[ "$need_ike" -eq 1 ]] && PKGS+=(strongswan strongswan-pki strongswan-swanctl libcharon-extra-plugins)
[[ "$need_l2tp" -eq 1 ]] && PKGS+=(xl2tpd)
[[ "$need_igmp" -eq 1 ]] && PKGS+=(igmpproxy)
[[ "$need_f2b" -eq 1 ]] && PKGS+=(fail2ban python3-systemd)
[[ "$need_curl" -eq 1 ]] && PKGS+=(curl)
[[ "$need_frr" -eq 1 ]] && PKGS+=(frr frr-pythontools)
PKGS+=(python3-jsonschema)

# unique
mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | awk 'NF && !seen[$0]++')

info "packages: ${PKGS[*]}"
apt-get install -y -qq "${PKGS[@]}" >/dev/null

if ! systemctl is-enabled systemd-networkd >/dev/null 2>&1; then
  systemctl enable systemd-networkd >/dev/null 2>&1 || true
fi

info "packages: OK"
