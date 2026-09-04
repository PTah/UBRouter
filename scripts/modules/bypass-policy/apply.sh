!/usr/bin/env bash
# Module: bypass-policy — selective routing (CIDR/domain → fwmark → tunnel table)
# No bundled blocklists — user supplies files under /etc/ubrouter/bypass/
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

if ! ans_true bypass.enabled; then
  info "bypass-policy: disabled — cleanup"
  systemctl disable --now ubrouter-bypass-watch.timer 2>/dev/null || true
  systemctl disable --now ubrouter-bypass.service 2>/dev/null || true
  # tear down nft + policy routing
  if [[ -f /etc/ubrouter/bypass.env ]]; then
    # shellcheck disable=SC1091
    source /etc/ubrouter/bypass.env 2>/dev/null || true
  fi
  mark="${BYPASS_MARK:-0x2}"
  table="${BYPASS_TABLE:-200}"
  ip rule del fwmark "$mark" lookup "$table" 2>/dev/null || true
  ip rule del fwmark "$mark" lookup "$table" priority 100 2>/dev/null || true
  ip route flush table "$table" 2>/dev/null || true
  nft delete table inet ubrouter_bypass 2>/dev/null || true
  if [[ -f /etc/dnsmasq.d/zz-ubrouter-bypass.conf ]]; then
    mv -f /etc/dnsmasq.d/zz-ubrouter-bypass.conf \
      /etc/dnsmasq.d/zz-ubrouter-bypass.conf.ubrouter-disabled 2>/dev/null || true
    systemctl reload dnsmasq 2>/dev/null || systemctl restart dnsmasq 2>/dev/null || true
  fi
  if [[ -f /etc/ubrouter/bypass.env ]]; then
    mv -f /etc/ubrouter/bypass.env /etc/ubrouter/bypass.env.ubrouter-disabled 2>/dev/null || true
  fi
  exit 0
fi

target="$(ans_get bypass.target)"
[[ -n "$target" && "$target" != "null" ]] || die "bypass.target пуст (имя туннеля: gre0/wg0/…)"

# wait for tunnel iface (WG/GRE may rise after vpn module)
for _i in $(seq 1 20); do
  if ip link show "$target" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! ip link show "$target" >/dev/null 2>&1; then
  warn "bypass-policy: интерфейс $target ещё нет — маршруты могут быть пустыми до подъёма туннеля"
fi

mark="$(ans_get bypass.fwmark)"
[[ -n "$mark" && "$mark" != "null" ]] || mark="0x2"
table="$(ans_get bypass.table)"
[[ -n "$table" && "$table" != "null" ]] || table="200"
fail_open=true
ans_true bypass.fail_open || fail_open=false
lan_only=true
# optional key; default true
v="$(ans_get bypass.mark_lan_only)"
[[ "$v" == "false" ]] && lan_only=false

lan_if="$(ans_get lan.interface)"
if ans_true interfaces.bridge.enabled; then
  lan_if="$(ans_get interfaces.bridge.name)"
  [[ -n "$lan_if" ]] || lan_if=br-lan
fi

ensure_dir /etc/ubrouter/bypass/domains
ensure_dir /etc/ubrouter/bypass/cidrs
ensure_dir /usr/local/lib/ubrouter
ensure_dir /var/lib/ubrouter

# Example placeholders (empty, documented)
[[ -f /etc/ubrouter/bypass/cidrs/README ]] || cat >/etc/ubrouter/bypass/cidrs/README <<'EOF'
# Положите сюда файлы со списками CIDR (по одному на строку).
# Готовых «обходов» в дистрибутиве UBrouter нет — свои списки.
EOF
[[ -f /etc/ubrouter/bypass/domains/README ]] || cat >/etc/ubrouter/bypass/domains/README <<'EOF'
# Положите сюда файлы с доменами (по одному на строку).
# dnsmasq запишет резолвы в nft set bypass_dst.
EOF

# Copy example templates from repo if present
if [[ -d "$ROOT/configs/bypass" ]]; then
  cp -n "$ROOT/configs/bypass/"*.example /etc/ubrouter/bypass/ 2>/dev/null || true
fi

# Persist runtime config for reload/watch
cat >/etc/ubrouter/bypass.env <<EOF
UBROUTER_ROOT=$ROOT
UBROUTER_ANSWERS=${UBROUTER_ANSWERS}
BYPASS_MARK=$mark
BYPASS_TABLE=$table
BYPASS_TARGET=$target
BYPASS_FAIL_OPEN=$fail_open
BYPASS_LAN_IF=$lan_if
BYPASS_LAN_ONLY=$lan_only
EOF
chmod 0644 /etc/ubrouter/bypass.env

# nft mark + set
nft delete table inet ubrouter_bypass 2>/dev/null || true
if [[ "$lan_only" == "true" ]]; then
  nft -f - <<EOF
table inet ubrouter_bypass {
  set bypass_dst {
    type ipv4_addr
    flags interval
    auto-merge
  }
  chain prerouting {
    type filter hook prerouting priority -150; policy accept;
    iifname "${lan_if}" ip daddr @bypass_dst meta mark set ${mark}
  }
  chain output {
    type route hook output priority -150; policy accept;
    ip daddr @bypass_dst meta mark set ${mark}
  }
}
EOF
else
  nft -f - <<EOF
table inet ubrouter_bypass {
  set bypass_dst {
    type ipv4_addr
    flags interval
    auto-merge
  }
  chain prerouting {
    type filter hook prerouting priority -150; policy accept;
    ip daddr @bypass_dst meta mark set ${mark}
  }
  chain output {
    type route hook output priority -150; policy accept;
    ip daddr @bypass_dst meta mark set ${mark}
  }
}
EOF
fi

install -m 0755 "$ROOT/scripts/lib/bypass-reload.sh" /usr/local/lib/ubrouter/bypass-reload.sh
install -m 0644 "$ROOT/scripts/lib/yaml_answers.py" /usr/local/lib/ubrouter/yaml_answers.py

# Watch / fail-open
cat >/usr/local/lib/ubrouter/bypass-watch.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source /etc/ubrouter/bypass.env
export UBROUTER_ROOT UBROUTER_ANSWERS
TARGET="${BYPASS_TARGET}"
MARK="${BYPASS_MARK}"
TABLE="${BYPASS_TABLE}"
FAIL_OPEN="${BYPASS_FAIL_OPEN:-true}"
PROBE="${UBROUTER_BYPASS_PROBE:-1.1.1.1}"

tunnel_ok=0
if ip link show "$TARGET" >/dev/null 2>&1; then
  state="$(cat /sys/class/net/$TARGET/operstate 2>/dev/null || echo unknown)"
  if [[ "$state" == "up" || "$state" == "unknown" ]]; then
    ip rule add fwmark "$MARK" lookup "$TABLE" priority 100 2>/dev/null || true
    ip route replace default dev "$TARGET" table "$TABLE" 2>/dev/null || true
    # reachability via marked path (not just operstate)
    if ip route get "$PROBE" mark "$MARK" >/dev/null 2>&1 \
      && ping -c1 -W2 -m "$MARK" "$PROBE" >/dev/null 2>&1; then
      tunnel_ok=1
    elif ping -c1 -W2 -I "$TARGET" "$PROBE" >/dev/null 2>&1; then
      tunnel_ok=1
    elif [[ "${UBROUTER_BYPASS_REQUIRE_PING:-0}" != "1" ]]; then
      # soft: route exists via tunnel → accept (some peers block ICMP)
      if ip route get "$PROBE" mark "$MARK" 2>/dev/null | grep -q "dev $TARGET"; then
        tunnel_ok=1
      fi
    fi
  fi
fi

if [[ "$tunnel_ok" -eq 1 ]]; then
  bash /usr/local/lib/ubrouter/bypass-reload.sh >/dev/null 2>&1 || true
  exit 0
fi

if [[ "$FAIL_OPEN" == "true" ]]; then
  ip rule del fwmark "$MARK" lookup "$TABLE" 2>/dev/null || true
  logger -t ubrouter-bypass "fail-open: $TARGET unreachable — fwmark rule removed"
else
  logger -t ubrouter-bypass "fail-closed: $TARGET unreachable — keeping policy (may blackhole)"
fi
EOF
chmod 0755 /usr/local/lib/ubrouter/bypass-watch.sh

cat >/etc/systemd/system/ubrouter-bypass.service <<'EOF'
[Unit]
Description=UBrouter bypass-policy reload
After=network-online.target nftables.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/ubrouter/bypass-reload.sh
ExecStartPost=/usr/local/lib/ubrouter/bypass-watch.sh

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/ubrouter-bypass-watch.service <<'EOF'
[Unit]
Description=UBrouter bypass tunnel watch (fail-open)
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/ubrouter/bypass-watch.sh
EOF

cat >/etc/systemd/system/ubrouter-bypass-watch.timer <<'EOF'
[Unit]
Description=UBrouter bypass watch timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=20s
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable ubrouter-bypass.service
systemctl enable --now ubrouter-bypass-watch.timer
bash /usr/local/lib/ubrouter/bypass-reload.sh
bash /usr/local/lib/ubrouter/bypass-watch.sh || true

info "bypass-policy: target=$target table=$table mark=$mark fail_open=$fail_open"
info "bypass-policy: списки: /etc/ubrouter/bypass/{cidrs,domains}/ — своих файлов"
