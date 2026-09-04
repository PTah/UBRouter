#!/usr/bin/env bash
# Выпуск WireGuard peer + обновление server conf
set -euo pipefail
ROOT="${UBROUTER_ROOT:-}"
if [[ -z "$ROOT" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$HERE/../../../.." && pwd)"
  export UBROUTER_ROOT="$ROOT"
fi
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
need_root

SERVER=""
NAME=""
ALLOWED="0.0.0.0/0"
CLIENT_IP=""
QR=0

usage() {
  cat <<EOF
UBrouter — WireGuard peer

Usage:
  sudo $0 --server wg-server --name phone [--ip 10.66.0.2/32] [--allowed 0.0.0.0/0] [--qr]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) SERVER="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --ip) CLIENT_IP="${2:-}"; shift 2 ;;
    --allowed) ALLOWED="${2:-}"; shift 2 ;;
    --qr) QR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown: $1" ;;
  esac
done

[[ -z "$SERVER" ]] && SERVER="$(ask "Имя WG server interface" "wg-server")"
[[ -z "$NAME" ]] && NAME="$(ask "Имя peer" "phone")"
srv_conf="/etc/wireguard/${SERVER}.conf"
[[ -f "$srv_conf" ]] || die "нет $srv_conf — сначала apply WG server"
srv_pub="$(cat /etc/wireguard/${SERVER}.pub 2>/dev/null || true)"
[[ -n "$srv_pub" ]] || die "нет pubkey сервера /etc/wireguard/${SERVER}.pub"

if [[ -z "$CLIENT_IP" ]]; then
  CLIENT_IP="$(ask "IP клиента (CIDR /32)" "10.66.0.2/32")"
fi

ensure_dir /root/ubrouter-vpn-clients
priv="$(wg genkey)"
pub="$(printf '%s' "$priv" | wg pubkey)"
psk="$(wg genpsk)"

# append peer to server
{
  echo ""
  echo "# peer $NAME"
  echo "[Peer]"
  echo "PublicKey = $pub"
  echo "PresharedKey = $psk"
  echo "AllowedIPs = $CLIENT_IP"
} >>"$srv_conf"

# endpoint hint
endpoint="$(ask "Endpoint сервера (IP:port, пусто=пропустить)" "")"
listen="$(grep -E '^ListenPort' "$srv_conf" | awk '{print $3}' || echo 51820)"

client="/root/ubrouter-vpn-clients/${NAME}.conf"
{
  echo "[Interface]"
  echo "PrivateKey = $priv"
  echo "Address = $CLIENT_IP"
  echo "DNS = 1.1.1.1"
  echo ""
  echo "[Peer]"
  echo "PublicKey = $srv_pub"
  echo "PresharedKey = $psk"
  echo "AllowedIPs = $ALLOWED"
  echo "PersistentKeepalive = 25"
  [[ -n "$endpoint" ]] && echo "Endpoint = $endpoint"
} >"$client"
chmod 0600 "$client"

systemctl restart "wg-quick@${SERVER}" || warn "restart wg-quick@$SERVER failed"
info "peer $NAME → $client"
if [[ "$QR" -eq 1 ]] && command -v qrencode >/dev/null 2>&1; then
  qrencode -t ansiutf8 <"$client"
elif [[ "$QR" -eq 1 ]]; then
  warn "qrencode не установлен (apt install qrencode)"
fi
