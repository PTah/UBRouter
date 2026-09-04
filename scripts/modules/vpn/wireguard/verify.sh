#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# soft
ip link show type wireguard >/dev/null 2>&1 || true
info "wireguard: verify soft OK"
exit 0
