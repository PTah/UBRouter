#!/usr/bin/env bash
# Connectivity baseline / probe for safe apply + auto-rollback.
# shellcheck shell=bash
set -euo pipefail

ROOT="${UBROUTER_ROOT:-.}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

HEALTH_ROOT="${UBROUTER_HEALTH_DIR:-/var/lib/ubrouter/health}"
BASELINE_FILE="${HEALTH_ROOT}/baseline.json"
WINDOW_SEC="${UBROUTER_HEALTH_WINDOW:-60}"
INTERVAL_SEC="${UBROUTER_HEALTH_INTERVAL:-5}"

# Targets (override via env)
PING_TARGETS="${UBROUTER_HEALTH_PING:-1.1.1.1 8.8.8.8}"
HTTP_URL="${UBROUTER_HEALTH_HTTP:-http://connectivitycheck.gstatic.com/generate_204}"
DNS_NAME="${UBROUTER_HEALTH_DNS:-one.one.one.one}"

ensure_dir "$HEALTH_ROOT"

probe_ping() {
  local host="$1"
  ping -c 1 -W 2 "$host" >/dev/null 2>&1
}

probe_http() {
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsS -m 5 -o /dev/null -w '' "$HTTP_URL" >/dev/null 2>&1
}

probe_dns() {
  getent hosts "$DNS_NAME" >/dev/null 2>&1 || host "$DNS_NAME" >/dev/null 2>&1
}

probe_lan_self() {
  # At least one non-loopback IPv4 is up
  ip -4 -br addr show scope global 2>/dev/null | grep -q 'UP\|UNKNOWN' || \
    ip -4 route show default >/dev/null 2>&1
}

probe_default_route() {
  ip -4 route show default 2>/dev/null | grep -q .
}

probe_vpn_links() {
  # If no VPN ifaces — skip (return ok). If present — at least one must be UP.
  local found=0 up=0
  local iface
  while read -r iface; do
    [[ -z "$iface" ]] && continue
    found=1
    if ip -br link show "$iface" 2>/dev/null | grep -q 'UP'; then
      up=1
    fi
  done < <(ip -br link 2>/dev/null | awk '/^(wg|tun|tap|gre|ipip|vti)/ {print $1}' | sed 's/@.*//')
  if [[ "$found" -eq 0 ]]; then
    return 0
  fi
  [[ "$up" -eq 1 ]]
}

# Collect probe results as key=value lines (bash-friendly; no jq required).
collect_probes() {
  local ping_ok=0 http_ok=0 dns_ok=0 lan_ok=0 route_ok=0 vpn_ok=0
  local t
  for t in $PING_TARGETS; do
    if probe_ping "$t"; then
      ping_ok=1
      break
    fi
  done
  probe_http && http_ok=1 || true
  probe_dns && dns_ok=1 || true
  probe_lan_self && lan_ok=1 || true
  probe_default_route && route_ok=1 || true
  probe_vpn_links && vpn_ok=1 || true

  cat <<EOF
ping=$ping_ok
http=$http_ok
dns=$dns_ok
lan=$lan_ok
route=$route_ok
vpn=$vpn_ok
EOF
}

write_baseline() {
  local tmp
  tmp="$(mktemp)"
  {
    echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    collect_probes
  } >"$tmp"
  mv -f "$tmp" "$BASELINE_FILE"
  info "health baseline сохранён → $BASELINE_FILE"
  cat "$BASELINE_FILE" | sed 's/^/  /'
}

read_kv() {
  local file="$1" key="$2"
  awk -F= -v k="$key" '$1==k {print $2; exit}' "$file" 2>/dev/null || echo 0
}

# Regression: any check that was OK in baseline and is now FAIL.
is_regression() {
  local current="$1"
  local b_ping b_http b_dns b_lan b_route b_vpn
  local c_ping c_http c_dns c_lan c_route c_vpn
  b_ping="$(read_kv "$BASELINE_FILE" ping)"
  b_http="$(read_kv "$BASELINE_FILE" http)"
  b_dns="$(read_kv "$BASELINE_FILE" dns)"
  b_lan="$(read_kv "$BASELINE_FILE" lan)"
  b_route="$(read_kv "$BASELINE_FILE" route)"
  b_vpn="$(read_kv "$BASELINE_FILE" vpn)"
  c_ping="$(read_kv "$current" ping)"
  c_http="$(read_kv "$current" http)"
  c_dns="$(read_kv "$current" dns)"
  c_lan="$(read_kv "$current" lan)"
  c_route="$(read_kv "$current" route)"
  c_vpn="$(read_kv "$current" vpn)"

  # Internet: if baseline had ping OR http, need at least one of them now
  if [[ "$b_ping" == 1 || "$b_http" == 1 ]]; then
    if [[ "$c_ping" != 1 && "$c_http" != 1 ]]; then
      echo "internet (ping/http)"
      return 0
    fi
  fi
  if [[ "$b_dns" == 1 && "$c_dns" != 1 ]]; then
    echo "dns"
    return 0
  fi
  if [[ "$b_lan" == 1 && "$c_lan" != 1 ]]; then
    echo "lan"
    return 0
  fi
  if [[ "$b_route" == 1 && "$c_route" != 1 ]]; then
    echo "default-route"
    return 0
  fi
  if [[ "$b_vpn" == 1 && "$c_vpn" != 1 ]]; then
    echo "vpn"
    return 0
  fi
  return 1
}

watch_window() {
  local deadline elapsed=0 reason="" cur
  [[ -f "$BASELINE_FILE" ]] || die "нет baseline — сначала healthcheck.sh capture"
  deadline=$((SECONDS + WINDOW_SEC))
  info "health window ${WINDOW_SEC}s (interval ${INTERVAL_SEC}s)"
  while (( SECONDS < deadline )); do
    cur="$(mktemp)"
    collect_probes >"$cur"
    if reason="$(is_regression "$cur")"; then
      warn "health regress: $reason"
      cat "$cur" | sed 's/^/  /'
      rm -f "$cur"
      return 1
    fi
    rm -f "$cur"
    sleep "$INTERVAL_SEC"
    elapsed=$((elapsed + INTERVAL_SEC))
  done
  info "health window OK (${WINDOW_SEC}s)"
  return 0
}

cmd="${1:-}"
case "$cmd" in
  capture)
    write_baseline
    ;;
  probe)
    collect_probes
    ;;
  watch)
    watch_window
    ;;
  *)
    die "usage: healthcheck.sh capture|probe|watch"
    ;;
esac
