#!/usr/bin/env bash
# Module: qos — Cake/fq_codel SQM on LAN (and optional bandwidth)
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

cake_lan=false
ans_true qos.cake_lan && cake_lan=true
ans_true services.sqm && cake_lan=true
if [[ "$cake_lan" != "true" ]]; then
  info "qos: skip — cleanup SQM"
  systemctl disable --now ubrouter-sqm.service 2>/dev/null || true
  lan_if="$(ans_get lan.interface 2>/dev/null || true)"
  if ans_true interfaces.bridge.enabled 2>/dev/null; then
    lan_if="$(ans_get interfaces.bridge.name 2>/dev/null || echo br-lan)"
  fi
  if [[ -n "${lan_if:-}" ]]; then
    tc qdisc del dev "$lan_if" root 2>/dev/null || true
  fi
  exit 0
fi

lan_if="$(ans_get lan.interface)"
if ans_true interfaces.bridge.enabled; then
  lan_if="$(ans_get interfaces.bridge.name)"
  [[ -n "$lan_if" ]] || lan_if=br-lan
fi
bw="$(ans_get qos.bandwidth)"
# bandwidth like "100mbit" optional

modprobe sch_cake 2>/dev/null || true
modprobe sch_fq_codel 2>/dev/null || true

ensure_dir /usr/local/lib/ubrouter
cat >/usr/local/lib/ubrouter/sqm-lan.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
IFACE="${lan_if}"
BW="${bw}"
ip link show "\$IFACE" >/dev/null
tc qdisc del dev "\$IFACE" root 2>/dev/null || true
if [[ -n "\$BW" && "\$BW" != "null" && "\$BW" != "" ]]; then
  if modprobe sch_cake 2>/dev/null && tc qdisc replace dev "\$IFACE" root cake bandwidth "\$BW" ethernet; then
    exit 0
  fi
fi
if modprobe sch_cake 2>/dev/null && tc qdisc replace dev "\$IFACE" root cake ethernet; then
  exit 0
fi
tc qdisc replace dev "\$IFACE" root fq_codel || true
EOF
chmod 0755 /usr/local/lib/ubrouter/sqm-lan.sh

cat >/etc/systemd/system/ubrouter-sqm.service <<'EOF'
[Unit]
Description=UBrouter SQM (cake/fq_codel) on LAN
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/lib/ubrouter/sqm-lan.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ubrouter-sqm.service
/usr/local/lib/ubrouter/sqm-lan.sh || warn "sqm apply soft-fail"
systemctl start ubrouter-sqm.service 2>/dev/null || true
info "qos: SQM on $lan_if"
