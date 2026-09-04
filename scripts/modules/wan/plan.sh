#!/usr/bin/env bash
# Module: wan — validate WAN mode
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require

mode="$(ans_get wan.mode)"
iface="$(ans_get wan.interface)"
[[ -n "$iface" ]] || die "wan.interface пуст"
case "$mode" in
  dhcp|static|none|pppoe|ipoe) info "wan: plan mode=$mode if=$iface" ;;
  *) die "неизвестный wan.mode=$mode" ;;
esac

WORKDIR="${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}"
ensure_dir "$WORKDIR/wan"
{
  echo "mode=$mode"
  echo "interface=$iface"
} >"$WORKDIR/wan/plan.txt"
