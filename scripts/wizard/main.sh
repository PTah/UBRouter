!/usr/bin/env bash
# Interactive wizard — phases 01..13 → answers.yaml
set -euo pipefail

ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

ensure_dir /etc/ubrouter 0750
ANSWERS_OUT="${UBROUTER_ANSWERS_OUT:-/etc/ubrouter/answers.yaml}"
export UBROUTER_ANSWERS_OUT="$ANSWERS_OUT"
TMP="$(mktemp -d /tmp/ubrouter-wizard.XXXXXX)"
export UBROUTER_WIZARD_TMP="$TMP"
trap 'rm -rf "$TMP"' EXIT

info "UBrouter wizard $UBROUTER_VERSION"
info "Ответы будут сохранены в $ANSWERS_OUT"
echo

PHASES=(
  01-interfaces
  02-wan-lan
  03-wan-ip
  04-lan
  05-services
  06-firewall
  07-vpn
  08-bypass
  09-qos
  10-igmp-iptv
  11-hardening
  12-ospf
  13-review
)

for ph in "${PHASES[@]}"; do
  script="$ROOT/scripts/wizard/phases/${ph}.sh"
  [[ -f "$script" ]] || die "нет фазы $ph"
  info "=== Фаза $ph ==="
  # shellcheck source=/dev/null
  bash "$script"
  echo
done

export UBROUTER_ANSWERS="$ANSWERS_OUT"
info "Wizard завершён: $ANSWERS_OUT"
