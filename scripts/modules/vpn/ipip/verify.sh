#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
if ip -br tunnel 2>/dev/null | grep -qE 'ipip|tunl'; then
  info "ipip: verify soft OK"
else
  # soft: only warn if configured
  info "ipip: verify soft (туннель может подниматься позже)"
fi
exit 0
