#!/usr/bin/env bash
# Watch VPN tunnel ifaces (GRE/EOIP/WG/OVPN) — Telegram on up/down edge.
set -euo pipefail

CONF="${UBROUTER_VPN_WATCH_CONF:-/etc/ubrouter/vpn-watch.conf}"
STATE_DIR="${UBROUTER_VPN_TG_STATE:-/var/lib/ubrouter/vpn-notify}"
SEND="${UBROUTER_TG_SEND:-/usr/local/sbin/ubrouter-telegram-send.sh}"
LOG_TAG="ubrouter-vpn-watch"

[[ -f "$CONF" ]] || exit 0
mkdir -p "$STATE_DIR"

is_up() {
  local ifc="$1"
  ip link show "$ifc" 2>/dev/null | grep -q 'state UP\|state UNKNOWN'
}

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$line" ]] && continue
  # format: iface|label|type
  IFS='|' read -r ifc label typ <<<"$line"
  [[ -z "${ifc:-}" ]] && continue
  label="${label:-$ifc}"
  typ="${typ:-tunnel}"

  if is_up "$ifc"; then
    current="up"
  else
    current="down"
  fi
  sf="$STATE_DIR/if-$(echo "$ifc" | tr '/.' '__').state"
  prev="unknown"
  [[ -f "$sf" ]] && prev="$(cat "$sf")"
  if [[ "$prev" == "unknown" ]]; then
    echo "$current" >"$sf"
    logger -t "$LOG_TAG" "init $ifc ($label) = $current"
    continue
  fi
  [[ "$prev" == "$current" ]] && continue
  echo "$current" >"$sf"
  msg="VPN ${typ} ${current^^}
iface: $ifc
label: $label"
  logger -t "$LOG_TAG" "$current $ifc ($label)"
  if [[ -x "$SEND" ]]; then
    UBROUTER_TG_FORCE=1 "$SEND" "$msg" || true
  fi
done <"$CONF"
