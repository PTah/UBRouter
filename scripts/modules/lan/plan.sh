#!/usr/bin/env bash
# Module: lan — render+apply netplan (WAN+LAN+bridge+rename)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

lan_if="$(ans_get lan.interface)"
lan_cidr="$(ans_get lan.cidr)"
[[ -n "$lan_if" ]] || die "lan.interface пуст"
[[ -n "$lan_cidr" ]] || die "lan.cidr пуст"

WORKDIR="${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}"
ensure_dir "$WORKDIR/lan"
echo "lan_if=$lan_if cidr=$lan_cidr" >"$WORKDIR/lan/plan.txt"
info "lan: plan $lan_if $lan_cidr"
