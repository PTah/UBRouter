#!/usr/bin/env bash
# Shared helpers for UBrouter.
# shellcheck shell=bash

UBROUTER_VERSION="$(cat "${UBROUTER_ROOT:-.}/VERSION" 2>/dev/null || echo unknown)"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "--> $*"; }  # format: info "module: message" (no square-bracket tags)
warn() { echo "WARN: $*" >&2; }

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "нужен root (sudo)"
}

check_os_or_warn() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
      warn "поддерживается Ubuntu 24.04; сейчас: ${PRETTY_NAME:-unknown}"
    fi
  fi
}

confirm() {
  local prompt="$1"
  local default="${2:-Y}"
  local hint="[Y/n]"
  [[ "$default" == "N" || "$default" == "n" ]] && hint="[y/N]"
  local ans
  read -r -p "$prompt $hint " ans || true
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[YyДд] ]]
}

ask() {
  local prompt="$1"
  local default="${2:-}"
  local ans
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " ans || true
    echo "${ans:-$default}"
  else
    read -r -p "$prompt: " ans || true
    echo "$ans"
  fi
}

ensure_dir() {
  mkdir -p "$1"
  chmod "${2:-0755}" "$1"
}
