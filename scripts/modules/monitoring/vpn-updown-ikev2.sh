#!/usr/bin/env bash
# strongSwan updown → Telegram (async; must not block charon).
set -u
LOG_TAG="ubrouter-ikev2-tg"
STATE_DIR="${UBROUTER_VPN_TG_STATE:-/var/lib/ubrouter/vpn-notify}"
SEND="${UBROUTER_TG_SEND:-/usr/local/sbin/ubrouter-telegram-send.sh}"

verb="${PLUTO_VERB:-}"
case "$verb" in
  up-client|up-host|up-client-v6|up-host-v6) action="IKEv2 CONNECT" ;;
  down-client|down-host|down-client-v6|down-host-v6) action="IKEv2 DISCONNECT" ;;
  *) exit 0 ;;
esac

peer_vip="${PLUTO_PEER_CLIENT:-}"
peer_ip="${PLUTO_PEER:-}"
peer_id="${PLUTO_PEER_ID:-}"
uid="${PLUTO_UNIQUEID:-unknown}"

mkdir -p "$STATE_DIR"
stamp="$STATE_DIR/ike-${uid}.${action// /_}"
if [[ -f "$stamp" ]]; then
  exit 0
fi
find "$STATE_DIR" -type f -name 'ike-*' -mmin +5 -delete 2>/dev/null || true
: >"$stamp"

msg="${action}
id: ${peer_id:-?}
vip: ${peer_vip:-?}
peer: ${peer_ip:-?}
sa: ${uid}"

(
  if [[ -x "$SEND" ]]; then
    UBROUTER_TG_FORCE=1 "$SEND" "$msg" || true
  fi
) >/dev/null 2>&1 &
exit 0
