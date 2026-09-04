#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
if ! ans_true bypass.enabled; then
  exit 0
fi
nft list table inet ubrouter_bypass >/dev/null 2>&1 || warn "nft table ubrouter_bypass отсутствует"
info "bypass-policy: verify soft OK"
exit 0
