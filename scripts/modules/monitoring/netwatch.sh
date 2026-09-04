#!/usr/bin/env bash
# UBrouter netwatch: ping hosts, optional Telegram on up/down edge.
set -euo pipefail

CONFIG="${NETWATCH_CONFIG:-/etc/ubrouter/netwatch-hosts.conf}"
ENV_FILE="${NETWATCH_ENV:-/etc/ubrouter/netwatch.env}"
STATE_DIR="${NETWATCH_STATE_DIR:-/var/lib/ubrouter/netwatch}"
LOG_TAG="ubrouter-netwatch"

TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
HOST_LABEL="ubrouter"
PING_COUNT=2
PING_TIMEOUT_SEC=1
TELEGRAM_ENABLED=0

load_env() {
  local line key value
  [[ -f "$ENV_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    case "$key" in
      TELEGRAM_BOT_TOKEN) TELEGRAM_BOT_TOKEN="$value" ;;
      TELEGRAM_CHAT_ID) TELEGRAM_CHAT_ID="$value" ;;
      HOST_LABEL) HOST_LABEL="$value" ;;
      PING_COUNT) PING_COUNT="$value" ;;
      PING_TIMEOUT_SEC) PING_TIMEOUT_SEC="$value" ;;
      TELEGRAM_ENABLED) TELEGRAM_ENABLED="$value" ;;
    esac
  done <"$ENV_FILE"
}

load_env

if [[ ! -f "$CONFIG" ]]; then
  echo "$LOG_TAG: missing $CONFIG" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

telegram_send() {
  local text="$1"
  local full="${HOST_LABEL}: ${text}"
  if [[ "${TELEGRAM_ENABLED}" != "1" && "${TELEGRAM_ENABLED}" != "true" && "${TELEGRAM_ENABLED}" != "yes" ]]; then
    logger -t "$LOG_TAG" "telegram off: $full"
    return 0
  fi
  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || "$TELEGRAM_BOT_TOKEN" == "CHANGE_ME" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    logger -t "$LOG_TAG" "telegram not configured: $full"
    return 1
  fi
  if curl -fsS -G "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${full}" >/dev/null; then
    logger -t "$LOG_TAG" "telegram ok: $full"
  else
    logger -t "$LOG_TAG" "telegram failed: $full"
    return 1
  fi
}

host_up() {
  ping -c "$PING_COUNT" -W "$PING_TIMEOUT_SEC" "$1" >/dev/null 2>&1
}

state_file() {
  echo "$STATE_DIR/$(echo "$1" | tr '/.:' '___').state"
}

read_state() {
  local f
  f="$(state_file "$1")"
  if [[ -f "$f" ]]; then
    cat "$f"
  else
    echo "unknown"
  fi
}

write_state() {
  echo "$2" >"$(state_file "$1")"
}

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue

  IFS='|' read -r enabled host label msg_down msg_up <<<"$line"
  enabled="$(echo "${enabled:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$enabled" != "yes" && "$enabled" != "1" && "$enabled" != "true" ]] && continue
  [[ -z "${host:-}" ]] && continue

  label="${label:-$host}"
  msg_down="${msg_down:-$label is down}"
  msg_up="${msg_up:-$label is up}"

  if host_up "$host"; then
    current="up"
  else
    current="down"
  fi

  prev="$(read_state "$host")"
  if [[ "$prev" == "unknown" ]]; then
    write_state "$host" "$current"
    logger -t "$LOG_TAG" "init $host ($label) = $current"
    continue
  fi

  [[ "$prev" == "$current" ]] && continue

  write_state "$host" "$current"
  if [[ "$current" == "down" ]]; then
    telegram_send "$msg_down" || true
    logger -t "$LOG_TAG" "DOWN $host ($label)"
  else
    telegram_send "$msg_up" || true
    logger -t "$LOG_TAG" "UP $host ($label)"
  fi
done <"$CONFIG"
