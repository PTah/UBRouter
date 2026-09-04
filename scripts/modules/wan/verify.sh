#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
iface="$(ans_get wan.interface)"
mode="$(ans_get wan.mode)"
if [[ "$mode" == "none" || "$mode" == "pppoe" ]]; then
  info "wan: verify: skip L3 check (mode=$mode)"
  exit 0
fi
# Interface may appear after netplan — soft
if ip link show "$iface" >/dev/null 2>&1; then
  info "wan: verify: link $iface exists"
else
  warn "wan: verify: $iface ещё нет (rename после netplan/reboot?)"
fi
exit 0
