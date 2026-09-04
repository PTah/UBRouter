#!/usr/bin/env bash
# UBrouter entrypoint — wizard and/or apply.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UBROUTER_ROOT="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

ANSWERS=""
DO_PLAN=0
DO_APPLY=0
DO_WIZARD=1
FORCE=0
SKIP_PREFLIGHT=0

usage() {
  cat <<'EOF'
UBrouter — Ubuntu 24.04 interactive router installer

Usage:
  sudo ./install.sh                          # interactive wizard + ask apply
  sudo ./install.sh --answers FILE [--plan|--apply]
  sudo ./install.sh --help

Options:
  --answers FILE   Use preseed answers (skips wizard unless --wizard)
  --wizard         Force wizard even with --answers (edit mode later)
  --plan           Generate planned configs only
  --apply          Apply answers (snapshot + healthcheck + auto-rollback)
  --force          Relax OS check to warning (Ubuntu ≠ 24.04)
  --skip-preflight Skip pre-flight checks entirely (use with care)
  --help           This help

Перед первым запуском настройте passwordless sudo для своего пользователя
(см. README / docs/00-tz.md §2.8).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --answers) ANSWERS="${2:-}"; shift 2 ;;
    --plan) DO_PLAN=1; DO_WIZARD=0; shift ;;
    --apply) DO_APPLY=1; DO_WIZARD=0; shift ;;
    --wizard) DO_WIZARD=1; shift ;;
    --force) FORCE=1; shift ;;
    --skip-preflight) SKIP_PREFLIGHT=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

need_root

# Pre-flight: OS, NICs, disk, sudo, lock. Fail-fast on common mistakes.
export UBROUTER_PREFLIGHT_FORCE="$FORCE"
export UBROUTER_SKIP_PREFLIGHT="$SKIP_PREFLIGHT"
bash "$ROOT/scripts/lib/preflight.sh"

if [[ "$DO_WIZARD" -eq 1 && -z "$ANSWERS" ]]; then
  bash "$ROOT/scripts/wizard/main.sh"
  ANSWERS="${UBROUTER_ANSWERS:-/etc/ubrouter/answers.yaml}"
fi

if [[ -n "$ANSWERS" ]]; then
  export UBROUTER_ANSWERS="$ANSWERS"
fi

if [[ "$DO_PLAN" -eq 1 || "$DO_APPLY" -eq 1 ]]; then
  [[ -n "${UBROUTER_ANSWERS:-}" ]] || die "need --answers or wizard first"
  bash "$ROOT/scripts/lib/apply.sh" "$([[ "$DO_APPLY" -eq 1 ]] && echo apply || echo plan)"
  exit 0
fi

# After wizard: ask to apply
if [[ "$DO_WIZARD" -eq 1 ]]; then
  echo
  if confirm "Применить конфигурацию сейчас?" Y; then
    bash "$ROOT/scripts/lib/apply.sh" apply
  else
    info "Answers сохранены. Позже: sudo ./install.sh --answers ${UBROUTER_ANSWERS:-/etc/ubrouter/answers.yaml} --apply"
  fi
fi
