#!/usr/bin/env bash
# Фаза 08 — Policy routing / selective bypass (модуль bypass-policy, 0.4.0)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

bypass=false
domain_dir="/etc/ubrouter/bypass/domains"
cidr_dir="/etc/ubrouter/bypass/cidrs"
target=""
fail_open=true
fwmark="0x2"
table="200"
lan_only=true

echo "Обход блокировок / selective routing (модуль bypass-policy)."
echo "Готовых списков в дистрибутиве нет — свои CIDR/domain файлы."
if confirm "Включить selective bypass (списки → fwmark → туннель)?" N; then
  bypass=true
  domain_dir="$(ask "Каталог/файл доменов" "$domain_dir")"
  cidr_dir="$(ask "Каталог/файл CIDR" "$cidr_dir")"
  target="$(ask "Целевой туннель (wg0/gre0/…)" "gre0")"
  fwmark="$(ask "fwmark" "$fwmark")"
  table="$(ask "routing table id" "$table")"
  confirm "Маркировать только трафик с LAN?" Y || lan_only=false
  confirm "При падении туннеля — fail-open (обычный маршрут)?" Y || fail_open=false
  info "bypass: target=$target table=$table mark=$fwmark fail_open=$fail_open"
else
  info "bypass пропущен (sudo ./ubrouter bypass после правок answers)"
fi

cat >"$TMP/bypass.yaml" <<EOF
bypass_enabled: $bypass
bypass_domain_path: ${domain_dir:-}
bypass_cidr_path: ${cidr_dir:-}
bypass_target: ${target:-}
bypass_fail_open: $fail_open
bypass_fwmark: $fwmark
bypass_table: $table
bypass_lan_only: $lan_only
EOF
