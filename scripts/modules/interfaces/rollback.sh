#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
info "interfaces: rollback: используйте snapshot.sh restore (модульный rollback = snapshot)"
exit 0
