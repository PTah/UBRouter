#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require

lan_if="$(ans_get lan.interface)"
if ans_true interfaces.bridge.enabled; then
  lan_if="$(ans_get interfaces.bridge.name)"
  [[ -n "$lan_if" ]] || lan_if=br-lan
fi
cidr="$(ans_get lan.cidr)"
want_ip="$(cidr_addr "$cidr")"

if ! ip link show "$lan_if" >/dev/null 2>&1; then
  warn "lan: verify: нет интерфейса $lan_if (возможен reboot после rename)"
  exit 0
fi
if ip -4 addr show dev "$lan_if" | grep -q "inet ${want_ip}/"; then
  info "lan: verify OK $lan_if $want_ip"
  exit 0
fi
warn "lan: verify: ожидали $want_ip на $lan_if"
ip -br addr show "$lan_if" || true
exit 0
