#!/usr/bin/env bash
# Фаза 10 — IGMP / IPTV proxy (igmpproxy)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

# Defaults from earlier role answers
wan_if="$(grep -E '^wan_interface:' "$TMP/roles.yaml" 2>/dev/null | awk '{print $2}' || echo eth0)"
lan_if="$(grep -E '^lan_interface:' "$TMP/roles.yaml" 2>/dev/null | awk '{print $2}' || echo eth1)"
bridge_enabled="$(grep -E '^bridge_enabled:' "$TMP/roles.yaml" 2>/dev/null | awk '{print $2}' || echo false)"
bridge_name="$(grep -E '^bridge_name:' "$TMP/roles.yaml" 2>/dev/null | awk '{print $2}' || echo br-lan)"
if [[ "$bridge_enabled" == "true" ]]; then
  lan_default="$bridge_name"
else
  lan_default="$lan_if"
fi

enabled=false
upstream=""
downstream=""
quickleave=true
altnet=""

echo "IGMP/IPTV: проксирование multicast (igmpproxy) для IPTV от провайдера."
if confirm "Настроить IGMP/IPTV proxy (igmpproxy)?" N; then
  enabled=true
  upstream="$(ask "Upstream (сторона ISP / WAN, откуда приходит multicast)" "$wan_if")"
  downstream="$(ask "Downstream (LAN, куда раздавать IPTV)" "$lan_default")"
  confirm "quickleave (быстрее отпускать группу при уходе клиента)?" Y || quickleave=false
  altnet="$(ask "Доп. altnet CIDR на upstream (пусто = нет; иногда нужен для ISP)" "")"
  info "igmpproxy: upstream=$upstream downstream=$downstream quickleave=$quickleave"
else
  info "igmpproxy пропущен"
fi

cat >"$TMP/igmp.yaml" <<EOF
igmpproxy_enabled: $enabled
igmpproxy_upstream: ${upstream:-}
igmpproxy_downstream: ${downstream:-}
igmpproxy_quickleave: $quickleave
igmpproxy_altnet: ${altnet:-}
EOF
