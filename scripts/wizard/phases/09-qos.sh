#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

cake_lan=false; cake_tun=false
confirm "Cake SQM на LAN?" N && cake_lan=true
confirm "Cake SQM на туннелях?" N && cake_tun=true
cat >"$TMP/qos.yaml" <<EOF
cake_lan: $cake_lan
cake_tunnels: $cake_tun
EOF
