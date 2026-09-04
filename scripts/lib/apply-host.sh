#!/usr/bin/env bash
# Apply host.hostname / host.timezone from answers.
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

hn="$(ans_get host.hostname)"
tz="$(ans_get host.timezone)"

if [[ -n "$hn" && "$hn" != "null" ]]; then
  if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$hn" || warn "hostnamectl failed"
  else
    echo "$hn" >/etc/hostname
    hostname "$hn" 2>/dev/null || true
  fi
  # ensure hosts has 127.0.1.1
  if [[ -f /etc/hosts ]] && ! grep -qE "[[:space:]]${hn}([[:space:]]|$)" /etc/hosts; then
    if grep -qE '^127\.0\.1\.1' /etc/hosts; then
      sed -i -E "s/^127\\.0\\.1\\.1.*/127.0.1.1\t${hn}/" /etc/hosts || true
    else
      printf '127.0.1.1\t%s\n' "$hn" >>/etc/hosts
    fi
  fi
  info "host: hostname=$hn"
else
  info "host: hostname skip"
fi

if [[ -n "$tz" && "$tz" != "null" ]]; then
  if [[ -e "/usr/share/zoneinfo/$tz" ]]; then
    if command -v timedatectl >/dev/null 2>&1; then
      timedatectl set-timezone "$tz" || warn "timedatectl failed"
    else
      ln -sfn "/usr/share/zoneinfo/$tz" /etc/localtime
      echo "$tz" >/etc/timezone
    fi
    info "host: timezone=$tz"
  else
    warn "host: неизвестный timezone: $tz"
  fi
fi
