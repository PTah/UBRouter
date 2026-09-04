#!/usr/bin/env bash
# Orchestrator: plan or apply modules in dependency order.
# Apply: packages → host → networkd → baseline → snapshot → modules → health → auto-rollback.
set -euo pipefail

ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

MODE="${1:-plan}" # plan | apply
ANSWERS="${UBROUTER_ANSWERS:?need UBROUTER_ANSWERS}"
[[ -f "$ANSWERS" ]] || die "answers not found: $ANSWERS"

WORKDIR="${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}"
export UBROUTER_WORKDIR="$WORKDIR"
ensure_dir "$WORKDIR"
ensure_dir /var/log/ubrouter
ensure_dir /etc/ubrouter 0750

# Persist answers path for modules
if [[ ! -f /etc/ubrouter/answers.yaml ]] || [[ "$(readlink -f "$ANSWERS" 2>/dev/null || echo "$ANSWERS")" != "$(readlink -f /etc/ubrouter/answers.yaml 2>/dev/null || true)" ]]; then
  if [[ "$MODE" == "apply" ]]; then
    cp -a "$ANSWERS" /etc/ubrouter/answers.yaml
    chmod 0600 /etc/ubrouter/answers.yaml
    export UBROUTER_ANSWERS=/etc/ubrouter/answers.yaml
  fi
fi

MODULES=(
  interfaces
  wan
  lan
  multi-wan
  nat-firewall
  dns-dhcp
  ntp
  vpn
  bypass-policy
  igmpproxy
  qos
  hardening
  monitoring
  ospf
)

# Optional: apply only selected modules (e.g. UBROUTER_ONLY_MODULES=bypass-policy)
if [[ -n "${UBROUTER_ONLY_MODULES:-}" ]]; then
  # shellcheck disable=SC2206
  MODULES=( ${UBROUTER_ONLY_MODULES} )
  info "ONLY_MODULES: ${MODULES[*]}"
fi

SNAP_ID=""

run_module() {
  local name="$1"
  local action="$2"
  local dir="$ROOT/scripts/modules/${name}"
  local script="$dir/${action}.sh"
  if [[ ! -f "$script" ]]; then
    warn "module $name: нет $action.sh — skip"
    return 0
  fi
  info "$name: $action"
  local rc
  set +e
  bash "$script" 2>&1 | tee -a "/var/log/ubrouter/${name}.log"
  rc=${PIPESTATUS[0]}
  set -e
  return "$rc"
}

do_auto_rollback() {
  local why="$1"
  warn "auto-rollback: $why"
  if [[ -n "$SNAP_ID" ]]; then
    bash "$ROOT/scripts/lib/snapshot.sh" restore "$SNAP_ID" || die "auto-rollback failed"
  else
    bash "$ROOT/scripts/lib/snapshot.sh" restore || die "auto-rollback failed (no SNAP_ID)"
  fi
}

info "UBrouter $UBROUTER_VERSION — mode=$MODE answers=$ANSWERS"

if [[ "$MODE" == "apply" ]]; then
  need_root

  # #8: обрыв SSH не должен убивать apply — systemd-run (transient unit)
  if [[ -z "${UBROUTER_IN_APPLY_UNIT:-}" ]] && command -v systemd-run >/dev/null 2>&1; then
    info "apply через systemd-run (SSH-safe); лог: journalctl -u ubrouter-apply.service -f"
    systemctl reset-failed ubrouter-apply.service 2>/dev/null || true
    systemctl stop ubrouter-apply.service 2>/dev/null || true
    exec systemd-run \
      --unit=ubrouter-apply \
      --property=Type=oneshot \
      --property=RemainAfterExit=yes \
      --collect \
      --wait \
      --same-dir \
      --setenv=UBROUTER_IN_APPLY_UNIT=1 \
      --setenv=UBROUTER_ROOT="$ROOT" \
      --setenv=UBROUTER_ANSWERS="$ANSWERS" \
      --setenv=UBROUTER_WORKDIR="$WORKDIR" \
      --setenv=UBROUTER_ONLY_MODULES="${UBROUTER_ONLY_MODULES:-}" \
      --setenv=UBROUTER_HEALTH_WINDOW="${UBROUTER_HEALTH_WINDOW:-}" \
      --setenv=PATH="$PATH" \
      /bin/bash "$ROOT/scripts/lib/apply.sh" apply
  fi

  bash "$ROOT/scripts/lib/packages.sh"
  bash "$ROOT/scripts/lib/prefer-networkd.sh"
  bash "$ROOT/scripts/lib/apply-host.sh"

  # schema validate (soft fail only if UBROUTER_SCHEMA_STRICT=0)
  if [[ "${UBROUTER_SKIP_SCHEMA:-0}" != "1" ]]; then
    if ! bash "$ROOT/scripts/lib/validate-answers.sh"; then
      if [[ "${UBROUTER_SCHEMA_STRICT:-1}" == "1" ]]; then
        die "answers schema validation failed"
      else
        warn "answers schema validation failed — continue (UBROUTER_SCHEMA_STRICT=0)"
      fi
    fi
  fi

  # #9: PPPoE / rename — длиннее окно healthcheck
  if [[ -z "${UBROUTER_HEALTH_WINDOW:-}" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT/scripts/lib/answers.sh"
    ans_require
    wan_mode="$(ans_get wan.mode || true)"
    naming="$(ans_get interfaces.naming || true)"
    win=90
    [[ "$wan_mode" == "pppoe" ]] && win=180
    if [[ -n "$naming" && "$naming" != "keep" && "$win" -lt 120 ]]; then
      win=120
    fi
    export UBROUTER_HEALTH_WINDOW="$win"
    info "health window=${UBROUTER_HEALTH_WINDOW}s (wan=$wan_mode naming=$naming)"
  fi

  bash "$ROOT/scripts/lib/healthcheck.sh" capture
  SNAP_ID="$(bash "$ROOT/scripts/lib/snapshot.sh" create | tail -n1)"
  export UBROUTER_SNAPSHOT="$SNAP_ID"
  info "snapshot=$SNAP_ID"
fi

for m in "${MODULES[@]}"; do
  if [[ "$MODE" == "plan" ]]; then
    run_module "$m" plan || true
  else
    run_module "$m" plan || { do_auto_rollback "plan failed: $m"; die "aborted"; }
    run_module "$m" apply || { do_auto_rollback "apply failed: $m"; die "aborted"; }
    if [[ -f "$ROOT/scripts/modules/${m}/verify.sh" ]]; then
      if ! run_module "$m" verify; then
        do_auto_rollback "verify failed: $m"
        die "apply aborted after auto-rollback (module $m verify)"
      fi
    fi
  fi
done

if [[ "$MODE" == "apply" ]]; then
  # install CLI into /usr/local when running from a checkout
  if [[ -f "$ROOT/ubrouter" && -d "$ROOT/scripts" ]]; then
    bash "$ROOT/scripts/lib/install-cli.sh" || warn "install-cli soft fail"
  fi

  cat >/etc/ubrouter/state.json <<EOF
{
  "version": "${UBROUTER_VERSION}",
  "applied_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_snapshot_id": "${SNAP_ID}"
}
EOF

  if [[ -z "${UBROUTER_ONLY_MODULES:-}" ]]; then
    if ! bash "$ROOT/scripts/lib/healthcheck.sh" watch; then
      do_auto_rollback "health window failed"
      die "apply rolled back: healthcheck failed within ${UBROUTER_HEALTH_WINDOW:-60}s"
    fi
    info "готово (apply). snapshot=$SNAP_ID health=OK"
  else
    info "готово (apply only: ${UBROUTER_ONLY_MODULES}). snapshot=$SNAP_ID (health window skip)"
  fi
  naming="$(bash -c 'source "'"$ROOT"'/scripts/lib/answers.sh"; ans_require; ans_get interfaces.naming' 2>/dev/null || true)"
  if [[ -n "$naming" && "$naming" != "keep" ]]; then
    warn "interfaces.naming=$naming — если имена NIC не сменились: reboot, затем снова apply при необходимости"
  fi
else
  info "готово (plan)."
fi
