#!/usr/bin/env bash
# Prefer networkd; stop NetworkManager if present (Desktop / some images).
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
need_root

if systemctl list-unit-files NetworkManager.service >/dev/null 2>&1; then
  if systemctl is-active --quiet NetworkManager 2>/dev/null \
    || systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    warn "NetworkManager активен — отключаем (UBrouter = systemd-networkd + netplan)"
    systemctl disable --now NetworkManager 2>/dev/null || true
    systemctl mask NetworkManager 2>/dev/null || true
  fi
fi

systemctl enable systemd-networkd >/dev/null 2>&1 || true
systemctl start systemd-networkd >/dev/null 2>&1 || true

# Soften cloud-init network rewrites on next boot (best-effort)
if [[ -d /etc/cloud/cloud.cfg.d ]]; then
  cat >/etc/cloud/cloud.cfg.d/99-ubrouter-disable-network.cfg <<'EOF'
# UBrouter: do not let cloud-init rewrite netplan after apply
network: {config: disabled}
EOF
fi
