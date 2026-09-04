#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
if ! ans_true services.chrony; then
  exit 0
fi
if systemctl is-active --quiet chrony || systemctl is-active --quiet chronyd; then
  info "ntp: verify OK"
  exit 0
fi
die "chrony не active"
