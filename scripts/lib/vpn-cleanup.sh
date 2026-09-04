!/usr/bin/env bash
# Shared VPN desired-state helpers (source from vpn/*/apply.sh).
# shellcheck shell=bash

# Archive a UBrouter-managed file (keep for history/rollback).
vpn_archive_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  mv -f "$f" "${f}.ubrouter-disabled" 2>/dev/null || rm -f "$f" 2>/dev/null || true
}

# Stop+disable a systemd unit if present.
vpn_disable_unit() {
  local u="$1"
  systemctl disable --now "$u" 2>/dev/null || true
}

# Delete ip tunnels whose name matches prefix (gre / eoip / ipip / tunl).
vpn_del_tunnels_prefix() {
  local prefix="$1"
  local t
  while read -r t; do
    [[ -n "$t" ]] || continue
    case "$t" in
      ${prefix}*) ip tunnel del "$t" 2>/dev/null || true ;;
    esac
  done < <(ip -br tunnel 2>/dev/null | awk '{print $1}' || true)
  # eoip often shows as gre in tunnel list but as link name eoip*
  while read -r t; do
    [[ -n "$t" ]] || continue
    t="${t%:}"
    case "$t" in
      ${prefix}*) ip link del "$t" 2>/dev/null || ip tunnel del "$t" 2>/dev/null || true ;;
    esac
  done < <(ip -br link 2>/dev/null | awk '{print $1}' || true)
}

# Delete tunnels whose names are NOT in the space-separated keep list.
# Args: keep_names... (empty = delete all matching prefixes passed via VPN_TUNNEL_PREFIXES)
vpn_del_orphan_tunnels() {
  local prefixes="${VPN_TUNNEL_PREFIXES:-}"
  local keep=" $* "
  local t p
  [[ -n "$prefixes" ]] || return 0
  while read -r t; do
    [[ -n "$t" ]] || continue
    t="${t%:}"
    for p in $prefixes; do
      case "$t" in
        ${p}*)
          if [[ "$keep" != *" $t "* ]]; then
            ip tunnel del "$t" 2>/dev/null || ip link del "$t" 2>/dev/null || true
          fi
          ;;
      esac
    done
  done < <( { ip -br tunnel 2>/dev/null; ip -br link 2>/dev/null; } | awk '{print $1}' || true )
}

# Reconcile systemd template instances: disable those not in desired list.
# Args: unit_prefix (e.g. wg-quick@)  desired_names (space-separated)  state_file
vpn_reconcile_instances() {
  local prefix="$1"
  local desired="$2"
  local state="$3"
  local prev name
  ensure_dir "$(dirname "$state")"
  prev=""
  [[ -f "$state" ]] && prev="$(cat "$state" 2>/dev/null || true)"
  for name in $prev; do
    [[ -n "$name" ]] || continue
    case " $desired " in
      *" $name "*) ;;
      *)
        vpn_disable_unit "${prefix}${name}"
        ;;
    esac
  done
  printf '%s\n' $desired >"$state"
}

# Reload swanctl if charon is up (best-effort).
vpn_swanctl_reload() {
  if [[ -S /run/charon.vici ]]; then
    swanctl --load-all --noprompt 2>/dev/null || true
  fi
}
