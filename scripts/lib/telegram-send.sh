#!/usr/bin/env bash
# Send text to Telegram using /etc/ubrouter/netwatch.env (or UBROUTER_TG_*).
# Usage: ubrouter-telegram-send.sh "message text"
set -euo pipefail

ENV_FILE="${NETWATCH_ENV:-/etc/ubrouter/netwatch.env}"
LOG_TAG="ubrouter-tg"

TELEGRAM_BOT_TOKEN="${UBROUTER_TG_TOKEN:-}"
TELEGRAM_CHAT_ID="${UBROUTER_TG_CHAT:-}"
HOST_LABEL="${UBROUTER_TG_LABEL:-ubrouter}"
TELEGRAM_ENABLED="${UBROUTER_TG_ENABLED:-}"

if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" != *=* ]] && continue
    key="${line%%=*}"; value="${line#*=}"
    value="${value%\"}"; value="${value#\"}"
    case "$key" in
      TELEGRAM_BOT_TOKEN) [[ -z "$TELEGRAM_BOT_TOKEN" ]] && TELEGRAM_BOT_TOKEN="$value" ;;
      TELEGRAM_CHAT_ID) [[ -z "$TELEGRAM_CHAT_ID" ]] && TELEGRAM_CHAT_ID="$value" ;;
      HOST_LABEL) HOST_LABEL="$value" ;;
      TELEGRAM_ENABLED) [[ -z "$TELEGRAM_ENABLED" ]] && TELEGRAM_ENABLED="$value" ;;
    esac
  done <"$ENV_FILE"
fi

msg="${1:-}"
[[ -n "$msg" ]] || { echo "usage: $0 message" >&2; exit 2; }

if [[ "${TELEGRAM_ENABLED}" != "1" && "${TELEGRAM_ENABLED}" != "true" && "${TELEGRAM_ENABLED}" != "yes" ]]; then
  # still allow explicit send if token set and caller forces
  if [[ "${UBROUTER_TG_FORCE:-0}" != "1" ]]; then
    logger -t "$LOG_TAG" "telegram disabled: $msg"
    exit 0
  fi
fi

if [[ -z "$TELEGRAM_BOT_TOKEN" || "$TELEGRAM_BOT_TOKEN" == "CHANGE_ME" || -z "$TELEGRAM_CHAT_ID" ]]; then
  logger -t "$LOG_TAG" "telegram not configured: $msg"
  exit 0
fi

full="${HOST_LABEL}: ${msg}"
if curl -fsS -G "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${full}" >/dev/null; then
  logger -t "$LOG_TAG" "ok: $full"
else
  logger -t "$LOG_TAG" "fail: $full"
  exit 1
fi
