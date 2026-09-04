#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
if ! ans_true igmpproxy.enabled && ! ans_true services.igmpproxy; then
  exit 0
fi
systemctl is-active --quiet igmpproxy || warn "igmpproxy не active"
info "igmpproxy: verify soft"
exit 0
