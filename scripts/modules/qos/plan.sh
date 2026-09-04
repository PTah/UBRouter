#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
info "qos: plan skip"
exit 0
