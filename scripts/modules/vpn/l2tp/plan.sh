#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
info "vpn/l2tp: plan — apply: xl2tpd (+ optional IPsec PSK)"
exit 0
