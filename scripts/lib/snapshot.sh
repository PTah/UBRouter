#!/usr/bin/env bash
# Snapshot / restore helper.
set -euo pipefail
ROOT="${UBROUTER_ROOT:-.}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

SNAP_ROOT="/var/lib/ubrouter/snapshots"
ensure_dir "$SNAP_ROOT"

PATHS=(
  /etc/netplan
  /etc/nftables.conf
  /etc/nftables.d
  /etc/dnsmasq.conf
  /etc/dnsmasq.d
  /etc/chrony
  /etc/chrony.conf
  /etc/ubrouter
  /etc/wireguard
  /etc/openvpn
  /etc/igmpproxy.conf
  /etc/ppp
  /etc/fail2ban/jail.d
  /etc/sysctl.d/99-ubrouter.conf
  /etc/swanctl
  /etc/ipsec.conf
  /etc/ipsec.secrets
  /etc/xl2tpd
  /etc/systemd/resolved.conf.d/ubrouter.conf
  /etc/systemd/system/dnsmasq.service.d
  /etc/cloud/cloud.cfg.d/99-ubrouter-disable-network.cfg
  /usr/local/lib/ubrouter
  /usr/local/sbin/ubrouter-swanctl-load.sh
  /etc/hostname
  /etc/hosts
  /etc/timezone
  /etc/localtime
)

# systemd units created by UBrouter modules
UNIT_GLOBS=(
  /etc/systemd/system/ubrouter-*.service
  /etc/systemd/system/ubrouter-*.timer
  /etc/systemd/system/swanctl-load.service
)

reload_services() {
  systemctl daemon-reload 2>/dev/null || true
  if command -v netplan >/dev/null 2>&1; then
    netplan apply 2>/dev/null || warn "netplan apply failed after restore"
  fi
  if [[ -f /etc/nftables.conf ]] && command -v nft >/dev/null 2>&1; then
    nft -f /etc/nftables.conf 2>/dev/null || systemctl try-reload-or-restart nftables 2>/dev/null || true
  fi
  systemctl try-reload-or-restart dnsmasq 2>/dev/null || true
  systemctl try-reload-or-restart chrony 2>/dev/null || true
  systemctl try-reload-or-restart strongswan-starter 2>/dev/null || true
  # soft: disable units that exist now but weren't in snapshot (tracked in CREATED_UNITS)
  true
}

cmd="${1:-create}"
case "$cmd" in
  create)
    id="$(date -u +%Y%m%dT%H%M%SZ)"
    dest="$SNAP_ROOT/$id"
    ensure_dir "$dest"
    local_paths=()
    for p in "${PATHS[@]}"; do
      if [[ -e "$p" ]]; then
        parent="$(dirname "$p")"
        ensure_dir "$dest$parent"
        cp -a "$p" "$dest$parent/" 2>/dev/null || true
        local_paths+=("$p")
      fi
    done
    # units
    : >"$dest/UNITS.list"
    for g in "${UNIT_GLOBS[@]}"; do
      # shellcheck disable=SC2086
      for u in $g; do
        [[ -e "$u" ]] || continue
        parent="$(dirname "$u")"
        ensure_dir "$dest$parent"
        cp -a "$u" "$dest$parent/" 2>/dev/null || true
        local_paths+=("$u")
        echo "$u" >>"$dest/UNITS.list"
      done
    done
    # record currently enabled ubrouter units for restore cleanup
    systemctl list-unit-files 'ubrouter-*' --no-legend 2>/dev/null | awk '{print $1}' >"$dest/UNITS.enabled" || true
    printf '%s\n' "${local_paths[@]}" >"$dest/MANIFEST"
    echo "$id" >"$SNAP_ROOT/LATEST"
    info "snapshot $id (${#local_paths[@]} paths)"
    echo "$id"
    ;;
  restore)
    id="${2:-$(cat "$SNAP_ROOT/LATEST" 2>/dev/null || true)}"
    [[ -n "$id" && -d "$SNAP_ROOT/$id" ]] || die "snapshot not found: ${id:-<empty>}"
    warn "restore snapshot $id"
    # Remove ubrouter units that appeared after snapshot (best-effort)
    if [[ -f "$SNAP_ROOT/$id/UNITS.list" ]]; then
      mapfile -t kept <"$SNAP_ROOT/$id/UNITS.list" || true
      for g in "${UNIT_GLOBS[@]}"; do
        # shellcheck disable=SC2086
        for u in $g; do
          [[ -e "$u" ]] || continue
          keep=0
          for k in "${kept[@]:-}"; do
            [[ "$u" == "$k" ]] && keep=1 && break
          done
          if [[ "$keep" -eq 0 ]]; then
            base="$(basename "$u")"
            systemctl disable --now "$base" 2>/dev/null || true
            rm -f "$u"
            info "removed post-snapshot unit $u"
          fi
        done
      done
    fi
    if [[ -f "$SNAP_ROOT/$id/MANIFEST" ]]; then
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        src="$SNAP_ROOT/$id$p"
        if [[ -e "$src" ]]; then
          parent="$(dirname "$p")"
          ensure_dir "$parent"
          rm -rf "$p"
          cp -a "$src" "$p"
        fi
      done <"$SNAP_ROOT/$id/MANIFEST"
    else
      for name in netplan nftables.conf dnsmasq.conf dnsmasq.d chrony ubrouter; do
        src="$SNAP_ROOT/$id/$name"
        [[ -e "$src" ]] || continue
        case "$name" in
          netplan) dest=/etc/netplan ;;
          nftables.conf) dest=/etc/nftables.conf ;;
          dnsmasq.conf) dest=/etc/dnsmasq.conf ;;
          dnsmasq.d) dest=/etc/dnsmasq.d ;;
          chrony) dest=/etc/chrony ;;
          ubrouter) dest=/etc/ubrouter ;;
        esac
        rm -rf "$dest"
        cp -a "$src" "$dest"
      done
    fi
    reload_services
    info "restore $id complete"
    ;;
  latest)
    cat "$SNAP_ROOT/LATEST" 2>/dev/null || die "no snapshot"
    ;;
  *) die "usage: snapshot.sh create|restore [id]|latest" ;;
esac
