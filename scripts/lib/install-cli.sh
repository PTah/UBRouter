#!/usr/bin/env bash
# Install UBrouter tree to /usr/local/lib/ubrouter + wrapper in sbin.
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
need_root

DEST="${UBROUTER_INSTALL_ROOT:-/usr/local/lib/ubrouter}"

# Avoid self-rm when already running from installed tree
ROOT_R="$(readlink -f "$ROOT" 2>/dev/null || echo "$ROOT")"
DEST_R="$(readlink -f "$DEST" 2>/dev/null || echo "$DEST")"
if [[ "$ROOT_R" == "$DEST_R" ]]; then
  info "install-cli: ROOT==DEST ($DEST) — skip copy, refresh sbin wrapper only"
  cat >/usr/local/sbin/ubrouter <<EOF
#!/usr/bin/env bash
export UBROUTER_ROOT="$DEST"
exec "$DEST/ubrouter" "\$@"
EOF
  chmod 755 /usr/local/sbin/ubrouter
  exit 0
fi

ensure_dir "$DEST/scripts" 0755
ensure_dir "$DEST/configs" 0755

info "install CLI → $DEST"
rm -rf "$DEST/scripts"
cp -a "$ROOT/scripts" "$DEST/scripts"
cp -a "$ROOT/VERSION" "$DEST/VERSION"
cp -a "$ROOT/ubrouter" "$DEST/ubrouter"
[[ -f "$ROOT/install.sh" ]] && cp -a "$ROOT/install.sh" "$DEST/install.sh"
if [[ -d "$ROOT/configs" ]]; then
  rm -rf "$DEST/configs"
  cp -a "$ROOT/configs" "$DEST/configs"
fi
chmod 755 "$DEST/ubrouter"
find "$DEST/scripts" -type f -name '*.sh' -exec chmod 755 {} +

cat >/usr/local/sbin/ubrouter <<EOF
#!/usr/bin/env bash
export UBROUTER_ROOT="$DEST"
exec "$DEST/ubrouter" "\$@"
EOF
chmod 755 /usr/local/sbin/ubrouter
info "OK  /usr/local/sbin/ubrouter → $DEST"
