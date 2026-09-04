#!/usr/bin/env bash
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require

WORKDIR="${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}"
need_check=false
if [[ -f "$WORKDIR/vpn/clients.json" ]] && grep -q '"ikev2"' "$WORKDIR/vpn/clients.json" 2>/dev/null; then
  need_check=true
fi
if [[ -f "$WORKDIR/vpn/servers.json" ]] && grep -q '"ikev2"' "$WORKDIR/vpn/servers.json" 2>/dev/null; then
  need_check=true
fi
if ans_get_json vpn.servers 2>/dev/null | grep -q ikev2; then need_check=true; fi
if ans_get_json vpn.clients 2>/dev/null | grep -q ikev2; then need_check=true; fi

if [[ "$need_check" != "true" ]]; then
  exit 0
fi

if command -v swanctl >/dev/null 2>&1; then
  swanctl --list-conns >/dev/null 2>&1 || warn "swanctl --list-conns пусто/ошибка"
  info "ikev2: verify soft OK"
else
  warn "ikev2: swanctl не установлен"
fi
exit 0
