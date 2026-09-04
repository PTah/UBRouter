#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

nat=false; fw=false; dns=false; ntp=false
confirm "NAT masquerade?" Y && nat=true
confirm "Firewall baseline (nftables)?" Y && fw=true
confirm "DNS/DHCP через dnsmasq?" Y && dns=true
confirm "NTP через chrony?" Y && ntp=true
up1="$(ask "Upstream DNS #1" "9.9.9.9")"
up2="$(ask "Upstream DNS #2" "1.1.1.1")"

cat >"$TMP/services.yaml" <<EOF
svc_nat: $nat
svc_firewall: $fw
svc_dnsmasq: $dns
svc_chrony: $ntp
dns_upstream: ["$up1", "$up2"]
EOF
info "services nat=$nat fw=$fw dns=$dns ntp=$ntp"
