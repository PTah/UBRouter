#!/usr/bin/env bash
# Answers.yaml helpers (requires python3-yaml).
# shellcheck shell=bash

ans_require() {
  [[ -n "${UBROUTER_ANSWERS:-}" && -f "$UBROUTER_ANSWERS" ]] || die "UBROUTER_ANSWERS not set"
  [[ -n "${UBROUTER_ROOT:-}" ]] || die "UBROUTER_ROOT not set"
}

# Soft check for optional contexts (packages.sh): returns 1 instead of exit
ans_available() {
  [[ -n "${UBROUTER_ANSWERS:-}" && -f "${UBROUTER_ANSWERS}" && -n "${UBROUTER_ROOT:-}" ]]
}

ans_get() {
  local key="$1"
  ans_require
  python3 "$UBROUTER_ROOT/scripts/lib/yaml_answers.py" get "$UBROUTER_ANSWERS" "$key"
}

ans_get_json() {
  local key="$1"
  ans_require
  python3 "$UBROUTER_ROOT/scripts/lib/yaml_answers.py" get-json "$UBROUTER_ANSWERS" "$key"
}

ans_true() {
  local v
  v="$(ans_get "$1")"
  [[ "$v" == "true" || "$v" == "True" || "$v" == "1" || "$v" == "yes" ]]
}

ans_set_map_json() {
  local map_json="$1"
  ans_require
  python3 "$UBROUTER_ROOT/scripts/lib/yaml_answers.py" set-map "$UBROUTER_ANSWERS" "$map_json"
}

# Parse "10.0.0.1/24" → ip and prefix
cidr_addr() { echo "${1%%/*}"; }
cidr_prefix() {
  local c="$1"
  if [[ "$c" == */* ]]; then echo "${c##*/}"; else echo 24; fi
}

# IPv4 network base approx for DHCP (host part zeroed naively for /24 only helpers)
lan_network_guess() {
  local cidr="$1"
  local ip prefix
  ip="$(cidr_addr "$cidr")"
  prefix="$(cidr_prefix "$cidr")"
  if [[ "$prefix" == "24" ]]; then
    echo "${ip%.*}.0/24"
  else
    echo "$cidr"
  fi
}
