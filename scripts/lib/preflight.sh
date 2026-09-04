#!/usr/bin/env bash
# Pre-flight checks before wizard/apply: OS, NICs, disk, sudo, lock.
# Returns 0 if OK; with --force skips OS check; --skip-preflight skips all.
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

FORCE=${UBROUTER_PREFLIGHT_FORCE:-0}
SKIP=${UBROUTER_SKIP_PREFLIGHT:-0}
MIN_NICS=${UBROUTER_MIN_NICS:-2}
MIN_DISK_MB=${UBROUTER_MIN_DISK_MB:-1024}
LOCK=/var/lock/ubrouter-apply.lock

if [[ "$SKIP" -eq 1 ]]; then
  warn "preflight: skipped by --skip-preflight"
  exit 0
fi

errors=0
warnings=0

# 1) OS check — strict by default, --force relaxes to warn
pf_os() {
  if [[ ! -r /etc/os-release ]]; then
    warn "preflight: /etc/os-release не читается — не могу определить ОС"
    warnings=$((warnings+1))
    return 0
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    local msg="поддерживается Ubuntu 24.04; сейчас: ${PRETTY_NAME:-unknown}"
    if [[ "$FORCE" -eq 1 ]]; then
      warn "preflight: $msg (--force — продолжаем)"
      warnings=$((warnings+1))
    else
      echo "ERROR: preflight: $msg (или --force)" >&2
      errors=$((errors+1))
    fi
  else
    info "preflight: OS=${PRETTY_NAME}"
  fi
}

# 2) NIC count — physical NICs only (probe-nics.sh logic inline)
pf_nics() {
  local n
  n="$(python3 - <<'PY'
import os, glob
nics = []
for p in sorted(glob.glob("/sys/class/net/*")):
    name = os.path.basename(p)
    if name == "lo" or name.startswith(("docker","veth","br-","virbr","wg","tun","tap")):
        continue
    if not os.path.exists(f"{p}/device") and not os.path.exists(f"{p}/address"):
        continue
    mac = ""
    try:
        with open(f"{p}/address") as f: mac = f.read().strip()
    except OSError: pass
    if not mac or mac == "00:00:00:00:00:00": continue
    nics.append(name)
print(len(nics))
PY
)"
  if [[ -z "$n" || "$n" -lt "$MIN_NICS" ]]; then
    echo "ERROR: preflight: найдено ${n:-0} физических NIC; нужно ≥${MIN_NICS}" >&2
    echo "  (override: UBROUTER_MIN_NICS=1 ./install.sh ...)" >&2
    errors=$((errors+1))
  else
    info "preflight: физических NIC = $n"
  fi
}

# 3) Disk space on /var (snapshots, logs, work)
pf_disk() {
  local mb
  mb="$(df -m /var 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ -z "$mb" ]]; then
    warn "preflight: не удалось определить свободное место на /var"
    warnings=$((warnings+1))
    return 0
  fi
  if [[ "$mb" -lt "$MIN_DISK_MB" ]]; then
    echo "ERROR: preflight: свободно ${mb} МБ на /var; нужно ≥${MIN_DISK_MB} МБ" >&2
    errors=$((errors+1))
  else
    info "preflight: /var free=${mb} МБ"
  fi
}

# 4) Passwordless sudo (or root)
pf_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    info "preflight: запущено от root"
    return 0
  fi
  if sudo -n true 2>/dev/null; then
    info "preflight: passwordless sudo OK"
  else
    echo "ERROR: preflight: нужен root или passwordless sudo (см. README §sudoers)" >&2
    errors=$((errors+1))
  fi
}

# 5) Lock — не запущен ли уже apply
pf_lock() {
  mkdir -p "$(dirname "$LOCK")" 2>/dev/null || true
  exec 9>"$LOCK"
  if ! flock -n 9; then
    echo "ERROR: preflight: уже запущен apply (lock $LOCK занят)" >&2
    echo "  если уверены что зависло: sudo rm -f $LOCK" >&2
    errors=$((errors+1))
  fi
  # lock held by fd 9 for the lifetime of the caller process
}

# 6) python3 + pyyaml (apply needs it)
pf_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: preflight: python3 не установлен" >&2
    errors=$((errors+1))
    return 0
  fi
  if ! python3 -c 'import yaml' 2>/dev/null; then
    warn "preflight: python3-yaml не установлен — packages.sh поставит"
    warnings=$((warnings+1))
  fi
}

# 7) netplan present
pf_netplan() {
  if ! command -v netplan >/dev/null 2>&1; then
    warn "preflight: netplan не найден (обычно есть на Ubuntu Server)"
    warnings=$((warnings+1))
  fi
}

pf_os
pf_nics
pf_disk
pf_sudo
pf_python
pf_netplan
pf_lock

info "preflight: errors=$errors warnings=$warnings"
if [[ "$errors" -gt 0 ]]; then
  die "preflight: $errors ошибок — apply прерван (или --force / --skip-preflight)"
fi
exit 0
