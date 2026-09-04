#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
export UBROUTER_ROOT
bash "$ROOT/scripts/modules/vpn/apply.sh" plan
