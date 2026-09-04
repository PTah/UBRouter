#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
systemctl is-active xl2tpd >/dev/null 2>&1 && info "l2tp: xl2tpd active" || warn "l2tp: xl2tpd не active"
exit 0
