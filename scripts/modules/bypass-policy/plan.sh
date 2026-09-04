#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
if ans_true bypass.enabled; then
  info "bypass-policy: plan enabled target=$(ans_get bypass.target)"
else
  info "bypass-policy: plan disabled"
fi
exit 0
