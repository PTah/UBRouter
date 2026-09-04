#!/usr/bin/env bash
# Module: hardening — unattended-upgrades + fail2ban
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

if ans_true services.unattended_upgrades; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq unattended-upgrades >/dev/null || true
  systemctl enable --now unattended-upgrades 2>/dev/null || true
  info "hardening: unattended-upgrades"
else
  systemctl disable --now unattended-upgrades 2>/dev/null || true
fi

if ans_true services.fail2ban; then
  ensure_dir /etc/fail2ban/jail.d
  cat >/etc/fail2ban/jail.d/ubrouter-ssh.local <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 5
bantime = 1h
findtime = 10m
EOF
  systemctl enable --now fail2ban
  systemctl restart fail2ban || warn "fail2ban restart failed"
  info "hardening: fail2ban sshd"
else
  rm -f /etc/fail2ban/jail.d/ubrouter-ssh.local 2>/dev/null || true
  if [[ ! -d /etc/fail2ban/jail.d ]] || [[ -z "$(ls -A /etc/fail2ban/jail.d 2>/dev/null)" ]]; then
    systemctl disable --now fail2ban 2>/dev/null || true
  else
    systemctl reload fail2ban 2>/dev/null || systemctl restart fail2ban 2>/dev/null || true
  fi
  info "hardening: fail2ban off (ubrouter jail removed)"
fi

info "hardening: done"
