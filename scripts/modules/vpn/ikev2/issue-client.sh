#!/usr/bin/env bash
# Выпуск PKCS#12 для мобильного/десктопного клиента strongSwan (IKEv2 Certificate).
#
# Интерактивно:
#   sudo ./ubrouter ikev2-client
#   sudo bash scripts/modules/vpn/ikev2/issue-client.sh
#
# Неинтерактивно:
#   sudo bash .../issue-client.sh --name anna-android --password 'SecretPass1'
#   sudo bash .../issue-client.sh --name phone --generate-password --force
#
set -euo pipefail

ROOT="${UBROUTER_ROOT:-}"
if [[ -z "$ROOT" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # scripts/modules/vpn/ikev2 → repo root
  ROOT="$(cd "$HERE/../../../.." && pwd)"
  export UBROUTER_ROOT="$ROOT"
fi
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
need_root

PKI_DIR="${UBROUTER_PKI_DIR:-/var/lib/ubrouter/pki}"
CLIENTS_DIR="${UBROUTER_VPN_CLIENTS_DIR:-/root/ubrouter-vpn-clients}"
CA_KEY="$PKI_DIR/private/ca-key.pem"
CA_CERT="$PKI_DIR/cacerts/ca-cert.pem"

NAME=""
CN=""
SAN_EXTRA=""
PASSWORD=""
GENERATE_PASS=0
LIFETIME=825
FORCE=0
NONINTERACTIVE=0
RELOAD=1
SERVER_HINT=""
KEY_BITS=2048

usage() {
  cat <<EOF
UBrouter — выпуск PKCS#12 для IKEv2 (strongSwan VPN Client)

Usage:
  sudo $0                     # интерактивно
  sudo $0 --name NAME [opts]

Options:
  --name NAME           Имя клиента / CN (например anna-android)
  --cn CN               Subject CN (по умолчанию = name)
  --san SAN             Доп. SAN (можно несколько раз)
  --password PASS       Пароль PKCS#12 (иначе спросит / --generate-password)
  --generate-password   Сгенерировать пароль, записать в NAME.pass
  --lifetime DAYS       Срок сертификата (default: $LIFETIME)
  --key-bits N          Размер ключа RSA (default: $KEY_BITS)
  --server HOST         Подсказка сервера в HOWTO (IP/FQDN)
  --force               Перезаписать существующий .p12
  --no-reload           Не вызывать swanctl --load-all
  --non-interactive     Без вопросов (нужны --name и пароль/generate)
  -h, --help            Справка

Результат:
  $CLIENTS_DIR/<name>.p12
  $CLIENTS_DIR/<name>.pass
  $CLIENTS_DIR/<name>.howto.txt
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --cn) CN="${2:-}"; shift 2 ;;
    --san) SAN_EXTRA="${SAN_EXTRA} ${2:-}"; shift 2 ;;
    --password) PASSWORD="${2:-}"; shift 2 ;;
    --generate-password) GENERATE_PASS=1; shift ;;
    --lifetime) LIFETIME="${2:-}"; shift 2 ;;
    --key-bits) KEY_BITS="${2:-}"; shift 2 ;;
    --server) SERVER_HINT="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --no-reload) RELOAD=0; shift ;;
    --non-interactive) NONINTERACTIVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1 (см. --help)" ;;
  esac
done

if ! command -v pki >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq strongswan-pki openssl >/dev/null
fi

ensure_dir "$PKI_DIR/cacerts" 0755
ensure_dir "$PKI_DIR/certs" 0755
ensure_dir "$PKI_DIR/private" 0700
ensure_dir "$CLIENTS_DIR" 0700
chmod 700 "$PKI_DIR" "$PKI_DIR/private" "$CLIENTS_DIR"

if [[ ! -f "$CA_KEY" || ! -f "$CA_CERT" ]]; then
  die "нет CA ($CA_CERT). Сначала apply IKEv2-сервера (vpn.servers type: ikev2), затем повторите."
fi

guess_server() {
  local id=""
  if [[ -f /etc/swanctl/conf.d/ubrouter-ikev2-server.conf ]]; then
    id="$(grep -E '^\s*id\s*=' /etc/swanctl/conf.d/ubrouter-ikev2-server.conf 2>/dev/null | head -1 | sed 's/.*= *//' | tr -d '[:space:]' || true)"
  fi
  if [[ -z "$id" ]]; then
    id="$(bash -c 'ip -4 route get 1.1.1.1 2>/dev/null | awk "{for(i=1;i<=NF;i++) if(\$i==\"src\"){print \$(i+1); exit}}"' || true)"
  fi
  echo "${id:-vpn.example.com}"
}

if [[ "$NONINTERACTIVE" -eq 0 ]]; then
  echo
  info "Выпуск клиентского PKCS#12 для strongSwan (IKEv2 Certificate)"
  echo "  CA: $CA_CERT"
  echo "  Каталог: $CLIENTS_DIR"
  echo
  [[ -n "$NAME" ]] || NAME="$(ask "Имя клиента (файлы .p12 / CN)" "anna-android")"
  [[ -n "$CN" ]] || CN="$(ask "Certificate CN" "$NAME")"
  if [[ -z "$SAN_EXTRA" ]]; then
    extra="$(ask "Доп. SAN (пусто = только CN/name)" "")"
    [[ -n "$extra" ]] && SAN_EXTRA=" $extra"
  fi
  [[ -n "$SERVER_HINT" ]] || SERVER_HINT="$(ask "Адрес VPN-сервера (для HOWTO)" "$(guess_server)")"
  [[ -n "$LIFETIME" ]] || LIFETIME=825
  LIFETIME="$(ask "Срок сертификата (дней)" "$LIFETIME")"
  if [[ -z "$PASSWORD" && "$GENERATE_PASS" -eq 0 ]]; then
    if confirm "Сгенерировать пароль PKCS#12?" Y; then
      GENERATE_PASS=1
    else
      while true; do
        read -r -s -p "Пароль PKCS#12: " PASSWORD; echo
        read -r -s -p "Повтор пароля: " PASS2; echo
        [[ "$PASSWORD" == "$PASS2" ]] || { warn "не совпали"; continue; }
        [[ -n "$PASSWORD" ]] || { warn "пустой пароль"; continue; }
        break
      done
    fi
  fi
  if [[ -f "$CLIENTS_DIR/${NAME}.p12" && "$FORCE" -eq 0 ]]; then
    if confirm "Файл ${NAME}.p12 уже есть — перезаписать?" N; then
      FORCE=1
    else
      die "отменено (или --force)"
    fi
  fi
else
  [[ -n "$NAME" ]] || die "--non-interactive требует --name"
  [[ -n "$CN" ]] || CN="$NAME"
  [[ -n "$SERVER_HINT" ]] || SERVER_HINT="$(guess_server)"
  if [[ -z "$PASSWORD" && "$GENERATE_PASS" -eq 0 ]]; then
    die "нужен --password или --generate-password"
  fi
fi

[[ -n "$NAME" ]] || die "пустое имя клиента"
[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "имя: только A-Za-z0-9._- (получено: $NAME)"
[[ -n "$CN" ]] || CN="$NAME"

P12="$CLIENTS_DIR/${NAME}.p12"
PASSF="$CLIENTS_DIR/${NAME}.pass"
HOWTO="$CLIENTS_DIR/${NAME}.howto.txt"
UKEY="$PKI_DIR/private/${NAME}-key.pem"
UCERT="$PKI_DIR/certs/${NAME}-cert.pem"

if [[ -f "$P12" && "$FORCE" -ne 1 ]]; then
  die "уже есть $P12 (используйте --force)"
fi

if [[ "$GENERATE_PASS" -eq 1 || -z "$PASSWORD" ]]; then
  PASSWORD="$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)"
fi

info "генерация ключа/сертификата: $NAME"
pki --gen --type rsa --size "$KEY_BITS" --outform pem >"$UKEY"
chmod 600 "$UKEY"

SAN_ARGS=(--san "$NAME")
[[ "$CN" != "$NAME" ]] && SAN_ARGS+=(--san "$CN")
# shellcheck disable=SC2086
for s in $SAN_EXTRA; do
  [[ -n "$s" ]] && SAN_ARGS+=(--san "$s")
done

pki --pub --in "$UKEY" --type rsa | \
  pki --issue --lifetime "$LIFETIME" \
    --cacert "$CA_CERT" --cakey "$CA_KEY" \
    --dn "CN=$CN" "${SAN_ARGS[@]}" \
    --flag clientAuth \
    --outform pem >"$UCERT"

printf '%s\n' "$PASSWORD" >"$PASSF"
chmod 600 "$PASSF"

openssl pkcs12 -export \
  -inkey "$UKEY" -in "$UCERT" -certfile "$CA_CERT" \
  -name "$NAME" -out "$P12" \
  -passout "pass:$PASSWORD"
chmod 600 "$P12"

# install CA into swanctl if missing (harmless)
if [[ -d /etc/swanctl/x509ca ]]; then
  install -m 0644 "$CA_CERT" /etc/swanctl/x509ca/ca-cert.pem
fi
install -m 0644 "$CA_CERT" "$CLIENTS_DIR/ca-cert.pem"

cat >"$HOWTO" <<EOF
UBrouter IKEv2 — клиент $NAME
Сгенерировано: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

Файлы:
  PKCS#12: $P12
  Пароль:  $PASSF  (также ниже)
  CA:      $CLIENTS_DIR/ca-cert.pem

Пароль PKCS#12:
  $PASSWORD

Сервер (Server):
  $SERVER_HINT

Android / iOS / Windows — strongSwan VPN Client:
  1. Скопируйте $NAME.p12 на устройство (не в облако без шифрования).
  2. Приложение strongSwan → Add VPN profile → IKEv2 Certificate
     (или «Certificate» / User certificate).
  3. Импортируйте .p12, введите пароль.
  4. Server: $SERVER_HINT
  5. Client identity / User certificate: $NAME (как в профиле).
  6. Сохраните и Connect.

Проверка на роутере:
  sudo swanctl --list-sas
  sudo journalctl -u strongswan-starter -u ubrouter-swanctl-load -e
EOF
chmod 600 "$HOWTO"

# append to shared README
README="$CLIENTS_DIR/README.txt"
{
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')  $NAME  $P12  (pass: $PASSF, howto: $HOWTO)"
} >>"$README"
chmod 600 "$README" 2>/dev/null || true

if [[ "$RELOAD" -eq 1 ]] && command -v swanctl >/dev/null 2>&1; then
  if [[ -S /run/charon.vici ]]; then
    swanctl --load-all --noprompt >/dev/null 2>&1 || warn "swanctl --load-all не удался (сервер мог ещё не быть поднят)"
  fi
fi

echo
info "готово"
echo "  PKCS#12: $P12"
echo "  Пароль:  $PASSF"
echo "  HOWTO:   $HOWTO"
echo "  Передайте пользователю .p12 + пароль; на телефоне — strongSwan → IKEv2 Certificate."
