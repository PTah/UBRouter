#!/usr/bin/env bash
# Выпуск .ovpn профиля для OpenVPN-сервера UBrouter.
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

PKI="${UBROUTER_OVPN_PKI:-/var/lib/ubrouter/openvpn-pki}"
CLIENTS="${UBROUTER_VPN_CLIENTS_DIR:-/root/ubrouter-vpn-clients}"
NAME=""
SERVER=""
LISTEN=1194
PROTO=udp
FORCE=0

usage() {
  cat <<EOF
UBrouter — выпуск .ovpn для OpenVPN server

Usage:
  sudo $0 --name CLIENT [--server HOST] [--port N] [--proto udp|tcp]

Options:
  --name NAME     имя клиента (CN)
  --server HOST   публичный IP/FQDN сервера
  --port N        порт (default 1194)
  --proto PROTO   udp|tcp
  --force         перезаписать ключ/профиль
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --server) SERVER="${2:-}"; shift 2 ;;
    --port) LISTEN="${2:-}"; shift 2 ;;
    --proto) PROTO="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

if [[ -z "$NAME" ]]; then
  NAME="$(ask "Имя клиента" "phone")"
fi
if [[ -z "$SERVER" ]]; then
  SERVER="$(ask "Публичный IP/FQDN сервера" "")"
fi
[[ -n "$SERVER" ]] || die "нужен --server"

[[ -f "$PKI/ca.crt" && -f "$PKI/ca.key" && -f "$PKI/ta.key" ]] \
  || die "нет PKI OpenVPN — сначала apply с vpn.servers type=openvpn"

ensure_dir "$CLIENTS"
ckey="$PKI/client-${NAME}.key"
ccrt="$PKI/client-${NAME}.crt"
if [[ -f "$ckey" && "$FORCE" -ne 1 ]]; then
  info "ключ уже есть — используем (или --force)"
else
  openssl genrsa -out "$ckey" 2048
  chmod 0600 "$ckey"
  openssl req -new -key "$ckey" -out "$PKI/client-${NAME}.csr" -subj "/CN=${NAME}"
  openssl x509 -req -in "$PKI/client-${NAME}.csr" \
    -CA "$PKI/ca.crt" -CAkey "$PKI/ca.key" -CAcreateserial \
    -out "$ccrt" -days 825 -sha256
fi

ovpn="$CLIENTS/${NAME}.ovpn"
{
  cat <<EOF
client
dev tun
proto $PROTO
remote $SERVER $LISTEN
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM
verb 3
key-direction 1
<ca>
$(cat "$PKI/ca.crt")
</ca>
<cert>
$(cat "$ccrt")
</cert>
<key>
$(cat "$ckey")
</key>
<tls-auth>
$(cat "$PKI/ta.key")
</tls-auth>
EOF
} >"$ovpn"
chmod 0600 "$ovpn"
cat >"$CLIENTS/${NAME}.howto.txt" <<EOF
OpenVPN: импортируйте $ovpn в клиент.
Сервер: $SERVER:$LISTEN/$PROTO
EOF
info "готово: $ovpn"
