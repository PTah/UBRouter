#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require

if ! ans_true services.firewall && ! ans_true services.nat; then
  info "nat-firewall: verify skip"
  exit 0
fi
systemctl is-active --quiet nftables || die "nftables не active"
fwd="$(sysctl -n net.ipv4.ip_forward)"
[[ "$fwd" == "1" ]] || die "ip_forward != 1"
info "nat-firewall: verify OK"
exit 0
