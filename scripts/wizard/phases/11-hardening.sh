#!/usr/bin/env bash
# Фаза 11 — Hardening + Netwatch (+ optional Telegram)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

uu=false
confirm "unattended-upgrades (security)?" Y && uu=true

nw=false
tg=false
hosts_yaml="[]"
interval=10
host_label="ubrouter"

if confirm "Netwatch (пинг узлов + оповещения)?" N; then
  nw=true
  host_label="$(ask "Метка роутера в сообщениях" "ubrouter")"
  interval="$(ask "Интервал проверки, сек" "10")"
  hosts_tmp="$TMP/netwatch_hosts.json"
  echo "[]" >"$hosts_tmp"
  info "Укажите узлы для мониторинга (IP или hostname)."
  while confirm "Добавить узел?" Y; do
    h="$(ask "host/IP" "1.1.1.1")"
    lab="$(ask "label" "$h")"
    md="$(ask "сообщение DOWN" "$lab is down")"
    mu="$(ask "сообщение UP" "$lab is up")"
    python3 - "$hosts_tmp" "$h" "$lab" "$md" "$mu" <<'PY'
import json, sys
from pathlib import Path
path, host, label, md, mu = sys.argv[1:6]
data = json.loads(Path(path).read_text(encoding="utf-8") or "[]")
data.append({"enabled": True, "host": host, "label": label, "msg_down": md, "msg_up": mu})
Path(path).write_text(json.dumps(data), encoding="utf-8")
PY
  done
  hosts_yaml="$(python3 -c 'import json,sys; from pathlib import Path; print(json.dumps(json.loads(Path(sys.argv[1]).read_text())))' "$hosts_tmp")"
  [[ "$hosts_yaml" != "[]" ]] || hosts_yaml='[{"enabled": true, "host": "1.1.1.1", "label": "Internet", "msg_down": "Internet is down", "msg_up": "Internet is up"}]'

  if confirm "Отправлять оповещения в Telegram?" N; then
    tg=true
    echo
    warn "Telegram: api.telegram.org часто недоступен без обхода."
    warn "Нужен рабочий коннект с роутера к Telegram (bypass-policy → VPN/туннель)."
    echo
    info "Секреты (bot token / chat_id) — в /etc/ubrouter/answers.local.yaml"
    if confirm "Ввести token/chat_id сейчас (запишем в answers.local)?" N; then
      token="$(ask "TELEGRAM_BOT_TOKEN" "")"
      chat="$(ask "TELEGRAM_CHAT_ID" "")"
      ensure_dir /etc/ubrouter 0750
      local_file="/etc/ubrouter/answers.local.yaml"
      if [[ ! -f "$local_file" ]]; then
        cat >"$local_file" <<EOF
# UBrouter secrets — chmod 0600, не коммитить
monitoring:
  telegram:
    bot_token: "$token"
    chat_id: "$chat"
EOF
      else
        python3 - "$local_file" "$token" "$chat" <<'PY'
import sys
from pathlib import Path
import yaml
path, token, chat = sys.argv[1:4]
p = Path(path)
data = yaml.safe_load(p.read_text(encoding="utf-8")) if p.is_file() else {}
data = data or {}
mon = data.setdefault("monitoring", {})
tg = mon.setdefault("telegram", {})
if token:
    tg["bot_token"] = token
if chat:
    tg["chat_id"] = chat
p.write_text(yaml.safe_dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False), encoding="utf-8")
PY
      fi
      chmod 0600 "$local_file"
      info "secrets → $local_file"
    fi
  fi
fi

vpn_notify=false
if confirm "Telegram-уведомления о VPN (IKEv2 connect/disconnect, GRE/EOIP/WG up/down)?" N; then
  vpn_notify=true
  if [[ "$tg" != "true" ]]; then
    warn "Нужен тот же Telegram token в answers.local (monitoring.telegram.*)."
    warn "api.telegram.org часто требует bypass/VPN с роутера."
    tg=true
  fi
fi

cat >"$TMP/hardening.yaml" <<EOF
unattended_upgrades: $uu
netwatch_enabled: $nw
netwatch_telegram: $tg
netwatch_interval: $interval
netwatch_host_label: $host_label
netwatch_hosts: $hosts_yaml
vpn_notify_enabled: $vpn_notify
EOF
