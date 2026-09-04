#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
if ! ans_true services.dnsmasq; then
  exit 0
fi
systemctl is-active --quiet dnsmasq || die "dnsmasq не active"
info "dns-dhcp: verify OK"
exit 0
