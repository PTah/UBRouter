#!/usr/bin/env bash
# UBrouter backup: export / import state tarball.
#
# Export: collects answers, PKI, WG/OpenVPN/swanctl configs, netplan drops.
#         answers.yaml IS included (may contain secrets) — caller must protect
#         the tarball (chmod 0600). Use --no-secrets to skip answers.local.yaml.
#
# Import: extracts tarball, installs files, reloads services. Does NOT auto-apply
#         (caller runs `sudo ubrouter apply` after reviewing).
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

do_export() {
  need_root
  local out=""
  local no_pki=0
  local no_secrets=0
  local include_logs=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out) out="${2:-}"; shift 2 ;;
      --no-pki) no_pki=1; shift ;;
      --no-secrets) no_secrets=1; shift ;;
      --include-logs) include_logs=1; shift ;;
      *) die "export: unknown arg: $1" ;;
    esac
  done
  [[ -n "$out" ]] || out="/root/ubrouter-backup-$(date -u +%Y%m%dT%H%M%S).tar.gz"

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  local manifest="$tmp/MANIFEST.txt"
  : >"$manifest"

  # /etc/ubrouter — answers, state, bypass, multiwan, bypass.env, answers.local
  if [[ -d /etc/ubrouter ]]; then
    mkdir -p "$tmp/etc"
    cp -a /etc/ubrouter "$tmp/etc/"
    echo "/etc/ubrouter" >>"$manifest"
    if [[ "$no_secrets" -eq 1 && -f "$tmp/etc/ubrouter/answers.local.yaml" ]]; then
      rm -f "$tmp/etc/ubrouter/answers.local.yaml"
      info "export: skipped answers.local.yaml (--no-secrets)"
    fi
  fi

  # PKI: CA key + cert + server cert + client certs
  if [[ "$no_pki" -eq 0 && -d /var/lib/ubrouter/pki ]]; then
    mkdir -p "$tmp/var/lib/ubrouter"
    cp -a /var/lib/ubrouter/pki "$tmp/var/lib/ubrouter/"
    echo "/var/lib/ubrouter/pki" >>"$manifest"
    # Also include /root/ubrouter-vpn-clients/ if exists (PKCS#12 + .pass)
    if [[ -d /root/ubrouter-vpn-clients ]]; then
      mkdir -p "$tmp/root"
      cp -a /root/ubrouter-vpn-clients "$tmp/root/"
      echo "/root/ubrouter-vpn-clients" >>"$manifest"
    fi
  fi

  # WireGuard configs (private keys!)
  if [[ -d /etc/wireguard ]]; then
    mkdir -p "$tmp/etc"
    cp -a /etc/wireguard "$tmp/etc/"
    echo "/etc/wireguard" >>"$manifest"
  fi

  # OpenVPN client configs
  if [[ -d /etc/openvpn ]]; then
    mkdir -p "$tmp/etc"
    cp -a /etc/openvpn "$tmp/etc/"
    echo "/etc/openvpn" >>"$manifest"
  fi

  # swanctl configs + certs
  if [[ -d /etc/swanctl ]]; then
    mkdir -p "$tmp/etc"
    cp -a /etc/swanctl "$tmp/etc/"
    echo "/etc/swanctl" >>"$manifest"
  fi

  # xl2tpd
  if [[ -d /etc/xl2tpd ]]; then
    mkdir -p "$tmp/etc"
    cp -a /etc/xl2tpd "$tmp/etc/"
    echo "/etc/xl2tpd" >>"$manifest"
  fi

  # PPP peers (PPPoE) — ubrouter-only subset
  if [[ -d /etc/ppp ]]; then
    mkdir -p "$tmp/etc/ppp/peers"
    [[ -f /etc/ppp/peers/ubrouter-wan ]] && cp -a /etc/ppp/peers/ubrouter-wan "$tmp/etc/ppp/peers/"
    [[ -f /etc/ppp/pap-secrets ]] && cp -a /etc/ppp/pap-secrets "$tmp/etc/ppp/"
    [[ -f /etc/ppp/chap-secrets ]] && cp -a /etc/ppp/chap-secrets "$tmp/etc/ppp/"
    echo "/etc/ppp (ubrouter-only subset)" >>"$manifest"
  fi

  # Netplan drops
  if [[ -d /etc/netplan ]]; then
    mkdir -p "$tmp/etc/netplan"
    for f in /etc/netplan/50-ubrouter.yaml /etc/netplan/60-ubrouter-multiwan.yaml; do
      [[ -f "$f" ]] && cp -a "$f" "$tmp/etc/netplan/"
    done
    echo "/etc/netplan (ubrouter drops)" >>"$manifest"
  fi

  # nftables + dnsmasq + chrony + sysctl + fail2ban
  for f in /etc/nftables.conf /etc/dnsmasq.conf /etc/sysctl.d/99-ubrouter.conf; do
    if [[ -f "$f" ]]; then
      mkdir -p "$tmp$(dirname "$f")"
      cp -a "$f" "$tmp$f"
      echo "$f" >>"$manifest"
    fi
  done
  for d in /etc/dnsmasq.d /etc/chrony /etc/fail2ban/jail.d \
           /etc/systemd/resolved.conf.d /etc/systemd/system/dnsmasq.service.d \
           /etc/cloud/cloud.cfg.d; do
    if [[ -d "$d" ]]; then
      mkdir -p "$tmp$(dirname "$d")"
      cp -a "$d" "$tmp$d"
      echo "$d" >>"$manifest"
    fi
  done

  # systemd units ubrouter-*
  if ls /etc/systemd/system/ubrouter-*.service /etc/systemd/system/ubrouter-*.timer 2>/dev/null | grep -q .; then
    mkdir -p "$tmp/etc/systemd/system"
    cp -a /etc/systemd/system/ubrouter-*.service "$tmp/etc/systemd/system/" 2>/dev/null || true
    cp -a /etc/systemd/system/ubrouter-*.timer "$tmp/etc/systemd/system/" 2>/dev/null || true
    echo "/etc/systemd/system/ubrouter-*" >>"$manifest"
  fi
  if [[ -f /etc/systemd/system/swanctl-load.service ]]; then
    mkdir -p "$tmp/etc/systemd/system"
    cp -a /etc/systemd/system/swanctl-load.service "$tmp/etc/systemd/system/"
  fi
  if [[ -f /usr/local/sbin/ubrouter-swanctl-load.sh ]]; then
    mkdir -p "$tmp/usr/local/sbin"
    cp -a /usr/local/sbin/ubrouter-swanctl-load.sh "$tmp/usr/local/sbin/"
  fi

  # /usr/local/lib/ubrouter (helper scripts)
  if [[ -d /usr/local/lib/ubrouter ]]; then
    mkdir -p "$tmp/usr/local/lib"
    cp -a /usr/local/lib/ubrouter "$tmp/usr/local/lib/"
    echo "/usr/local/lib/ubrouter" >>"$manifest"
  fi

  # Optional logs
  if [[ "$include_logs" -eq 1 && -d /var/log/ubrouter ]]; then
    mkdir -p "$tmp/var/log"
    cp -a /var/log/ubrouter "$tmp/var/log/"
    echo "/var/log/ubrouter" >>"$manifest"
  fi

  # Metadata
  cat >"$tmp/META.json" <<EOF
{
  "ubrouter_version": "$UBROUTER_VERSION",
  "exported_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "kernel": "$(uname -r)",
  "os": "$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
}
EOF

  # Tar
  mkdir -p "$(dirname "$out")"
  tar -C "$tmp" -czf "$out" .
  chmod 0600 "$out"
  local sz
  sz="$(du -h "$out" | awk '{print $1}')"

  info "export: $out ($sz)"
  echo "  Manifest ($(wc -l <"$manifest") paths):"
  sed 's/^/    /' "$manifest"
  warn "export: содержит приватные ключи и пароли — chmod 0600, в сейф"
}

do_import() {
  need_root
  local file=""
  local yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) yes=1; shift ;;
      *) file="$1"; shift ;;
    esac
  done
  [[ -n "$file" && -f "$file" ]] || die "import: укажите путь к tar.gz"
  if [[ "$yes" -ne 1 ]]; then
    echo "import: будут перезаписаны /etc/ubrouter, /etc/wireguard, /etc/swanctl, /var/lib/ubrouter/pki, ..."
    confirm "Продолжить?" N || die "отменено"
  fi

  # Pre-import snapshot of current state (so we can roll back)
  info "import: pre-import snapshot"
  if [[ -x "$ROOT/scripts/lib/snapshot.sh" ]]; then
    bash "$ROOT/scripts/lib/snapshot.sh" create >/dev/null || warn "import: snapshot failed (continue)"
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  tar -C "$tmp" -xzf "$file"

  if [[ -f "$tmp/META.json" ]]; then
    info "import: backup metadata:"
    sed 's/^/    /' "$tmp/META.json"
  fi

  # Restore files preserving absolute paths
  if [[ -d "$tmp/etc/ubrouter" ]]; then
    rm -rf /etc/ubrouter
    mkdir -p /etc
    cp -a "$tmp/etc/ubrouter" /etc/
    info "import: /etc/ubrouter"
  fi

  # /var/lib/ubrouter/pki
  if [[ -d "$tmp/var/lib/ubrouter/pki" ]]; then
    mkdir -p /var/lib/ubrouter
    rm -rf /var/lib/ubrouter/pki
    cp -a "$tmp/var/lib/ubrouter/pki" /var/lib/ubrouter/
    chmod 700 /var/lib/ubrouter/pki /var/lib/ubrouter/pki/private 2>/dev/null || true
    info "import: /var/lib/ubrouter/pki"
  fi

  # /root/ubrouter-vpn-clients
  if [[ -d "$tmp/root/ubrouter-vpn-clients" ]]; then
    rm -rf /root/ubrouter-vpn-clients
    cp -a "$tmp/root/ubrouter-vpn-clients" /root/
    chmod 700 /root/ubrouter-vpn-clients
    info "import: /root/ubrouter-vpn-clients"
  fi

  # /etc/wireguard, /etc/openvpn, /etc/swanctl, /etc/xl2tpd
  for d in etc/wireguard etc/openvpn etc/swanctl etc/xl2tpd; do
    if [[ -d "$tmp/$d" ]]; then
      rm -rf "/$d"
      mkdir -p "/$(dirname "$d")"
      cp -a "$tmp/$d" "/$(dirname "$d")/"
      info "import: /$d"
    fi
  done

  # /etc/ppp subset
  if [[ -d "$tmp/etc/ppp" ]]; then
    mkdir -p /etc/ppp/peers
    [[ -f "$tmp/etc/ppp/peers/ubrouter-wan" ]] && cp -a "$tmp/etc/ppp/peers/ubrouter-wan" /etc/ppp/peers/
    [[ -f "$tmp/etc/ppp/pap-secrets" ]] && cp -a "$tmp/etc/ppp/pap-secrets" /etc/ppp/ && chmod 0600 /etc/ppp/pap-secrets
    [[ -f "$tmp/etc/ppp/chap-secrets" ]] && cp -a "$tmp/etc/ppp/chap-secrets" /etc/ppp/ && chmod 0600 /etc/ppp/chap-secrets
    info "import: /etc/ppp (ubrouter subset)"
  fi

  # /etc/netplan ubrouter drops
  if [[ -d "$tmp/etc/netplan" ]]; then
    for f in "$tmp"/etc/netplan/*; do
      [[ -f "$f" ]] && cp -a "$f" /etc/netplan/ 2>/dev/null || true
    done
    info "import: /etc/netplan (ubrouter drops)"
  fi

  # Individual config files
  for f in /etc/nftables.conf /etc/dnsmasq.conf /etc/sysctl.d/99-ubrouter.conf; do
    rel=".$f"
    if [[ -f "$tmp/$rel" ]]; then
      mkdir -p "/$(dirname "$f")"
      cp -a "$tmp/$rel" "$f"
      info "import: $f"
    fi
  done

  # Directories
  for d in /etc/dnsmasq.d /etc/chrony /etc/fail2ban/jail.d \
           /etc/systemd/resolved.conf.d /etc/systemd/system/dnsmasq.service.d \
           /etc/cloud/cloud.cfg.d; do
    rel=".$d"
    if [[ -d "$tmp/$rel" ]]; then
      rm -rf "$d"
      mkdir -p "/$(dirname "$d")"
      cp -a "$tmp/$rel" "$d"
      info "import: $d"
    fi
  done

  # systemd units
  if [[ -d "$tmp/etc/systemd/system" ]]; then
    for u in "$tmp"/etc/systemd/system/ubrouter-*.service "$tmp"/etc/systemd/system/ubrouter-*.timer \
             "$tmp"/etc/systemd/system/swanctl-load.service; do
      [[ -f "$u" ]] && cp -a "$u" /etc/systemd/system/
    done
    info "import: /etc/systemd/system/ubrouter-*"
  fi
  if [[ -d "$tmp/usr/local/lib/ubrouter" ]]; then
    mkdir -p /usr/local/lib
    rm -rf /usr/local/lib/ubrouter
    cp -a "$tmp/usr/local/lib/ubrouter" /usr/local/lib/
    info "import: /usr/local/lib/ubrouter"
  fi
  if [[ -f "$tmp/usr/local/sbin/ubrouter-swanctl-load.sh" ]]; then
    mkdir -p /usr/local/sbin
    cp -a "$tmp/usr/local/sbin/ubrouter-swanctl-load.sh" /usr/local/sbin/
  fi

  # Reload
  systemctl daemon-reload
  sysctl --system >/dev/null 2>&1 || true
  if command -v netplan >/dev/null 2>&1; then
    netplan generate 2>/dev/null || warn "import: netplan generate failed"
  fi

  info "import: OK. Теперь:"
  echo "    sudo ubrouter status      # проверить состояние"
  echo "    sudo ubrouter doctor      # диагностика"
  echo "    sudo ubrouter apply       # применить (если нужно пересобрать юниты/конфиги)"
  warn "import: для rename интерфейсов может понадобиться reboot"
}

# ── dispatch ──
cmd="${1:-}"
case "$cmd" in
  export)
    shift
    do_export "$@"
    ;;
  import)
    shift
    do_import "$@"
    ;;
  *)
    cat <<'EOF'
Usage:
  ubrouter export [--out FILE] [--no-pki] [--no-secrets] [--include-logs]
  ubrouter import  FILE [--yes]

export:
  Collects state into a tar.gz. Default output:
    /root/ubrouter-backup-YYYYmmddTHHMMSS.tar.gz
  --out FILE        Custom output path
  --no-pki          Skip /var/lib/ubrouter/pki (CA key, server cert)
  --no-secrets      Skip /etc/ubrouter/answers.local.yaml (secrets)
  --include-logs    Also include /var/log/ubrouter/ (large)

import:
  Extracts tarball and installs files. Reloads services.
  Requires --yes (otherwise prompts).
  Pre-import snapshot is taken automatically (so you can `ubrouter rollback`).
EOF
    exit 1
    ;;
esac
