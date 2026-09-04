#!/usr/bin/env bash
# Module: multi-wan — secondary WANs + probe failover OR ECMP load-balance
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

multi_json="$(ans_get_json wan.multi)"
if [[ -z "$multi_json" || "$multi_json" == "null" || "$multi_json" == "[]" ]]; then
  info "multi-wan: wan.multi пуст — skip"
  systemctl disable --now ubrouter-multiwan-watch.timer 2>/dev/null || true
  exit 0
fi

python3 - "$multi_json" "$UBROUTER_ANSWERS" <<'PY'
import json, subprocess, sys, textwrap
from pathlib import Path

multi = json.loads(sys.argv[1] or "[]") or []
answers = {}
try:
    import yaml
    answers = yaml.safe_load(Path(sys.argv[2]).read_text(encoding="utf-8")) or {}
except Exception:
    pass

if not multi:
    print("--> multi-wan: nothing")
    raise SystemExit(0)

wan = answers.get("wan") or {}
primary_if = wan.get("interface") or "eth0"
primary_metric = 100
mode = (wan.get("multi_mode") or "failover").lower()
if mode not in ("failover", "lb", "loadbalance", "load-balance", "ecmp"):
    mode = "failover"
if mode in ("loadbalance", "load-balance", "ecmp"):
    mode = "lb"

# netplan drop-in for extra WANs
eth = {}
conf_lines = [
    f"# iface metric_base role",
    f"# mode={mode}",
    f"{primary_if} {primary_metric} primary",
]
for i, w in enumerate(multi):
    iface = w.get("interface")
    if not iface:
        continue
    metric = int(w.get("metric") or (100 + (i + 1) * 100))
    wmode = w.get("mode") or "dhcp"
    e = {"dhcp4": wmode == "dhcp", "optional": True}
    if wmode == "dhcp":
        e["dhcp4-overrides"] = {"route-metric": metric}
    st = w.get("static") or {}
    if wmode == "static" and st.get("address"):
        e["dhcp4"] = False
        e["addresses"] = [st["address"]]
        if st.get("gateway"):
            e["routes"] = [{"to": "default", "via": st["gateway"], "metric": metric}]
        if st.get("dns"):
            e["nameservers"] = {"addresses": list(st["dns"])}
    eth[iface] = e
    conf_lines.append(f"{iface} {metric} secondary")

Path("/etc/ubrouter").mkdir(parents=True, exist_ok=True)
Path("/etc/ubrouter/multiwan.conf").write_text("\n".join(conf_lines) + "\n", encoding="utf-8")
Path("/etc/ubrouter/multiwan.mode").write_text(mode + "\n", encoding="utf-8")

import yaml
out = Path("/etc/netplan/60-ubrouter-multiwan.yaml")
doc = {"network": {"version": 2, "renderer": "networkd", "ethernets": eth}}
out.write_text(yaml.safe_dump(doc, default_flow_style=False, sort_keys=False), encoding="utf-8")
out.chmod(0o600)
print(f"--> multi-wan: wrote {out} mode={mode}")

Path("/usr/local/lib/ubrouter").mkdir(parents=True, exist_ok=True)
watch = Path("/usr/local/lib/ubrouter/multiwan-watch.sh")
watch.write_text(textwrap.dedent(r"""\
    #!/usr/bin/env bash
    # Probe WANs: failover (one default metric 10) or LB (ECMP equal metric on live).
    set -euo pipefail
    CONF="${UBROUTER_MWAN_CONF:-/etc/ubrouter/multiwan.conf}"
    MODE_FILE="${UBROUTER_MWAN_MODE:-/etc/ubrouter/multiwan.mode}"
    TARGET="${UBROUTER_MWAN_PROBE:-1.1.1.1}"
    STATE_DIR=/var/lib/ubrouter
    STATE="$STATE_DIR/multiwan.active"
    mkdir -p "$STATE_DIR"

    [[ -f "$CONF" ]] || exit 0
    MODE=failover
    [[ -f "$MODE_FILE" ]] && MODE="$(tr -d '[:space:]' <"$MODE_FILE")"
    [[ "$MODE" == "lb" || "$MODE" == "ecmp" ]] || MODE=failover

    gw_for() {
      local iface="$1" gw
      gw="$(ip -4 route show default dev "$iface" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')"
      if [[ -z "$gw" ]]; then
        gw="$(ip -4 route show dev "$iface" 2>/dev/null | awk '/^default|^0\.0\.0\.0\/0/{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')"
      fi
      if [[ -z "$gw" ]]; then
        gw="$(ip -4 route get "$TARGET" oif "$iface" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')"
      fi
      echo "$gw"
    }

    probe() {
      local iface="$1"
      ip link show "$iface" 2>/dev/null | grep -q 'state UP\|state UNKNOWN' || return 1
      ping -c1 -W2 -I "$iface" "$TARGET" >/dev/null 2>&1
    }

    # flush managed defaults
    while read -r iface metric role; do
      [[ -z "${iface:-}" || "$iface" =~ ^# ]] && continue
      while IFS= read -r line; do
        # shellcheck disable=SC2086
        ip route del $line 2>/dev/null || true
      done < <(ip -4 route show default 2>/dev/null | grep -E "[[:space:]]dev[[:space:]]${iface}([[:space:]]|$)")
    done < <(awk 'NF>=2 && $1 !~ /^#/ {print $1, $2, $3}' "$CONF")

    live=()
    live_gw=()
    live_metric=()
    while read -r iface metric role; do
      [[ -z "${iface:-}" || "$iface" =~ ^# ]] && continue
      if probe "$iface"; then
        gw="$(gw_for "$iface")"
        [[ -n "$gw" ]] || continue
        live+=("$iface")
        live_gw+=("$gw")
        live_metric+=("$metric")
      fi
    done < <(awk 'NF>=2 && $1 !~ /^#/ {print $1, $2, $3}' "$CONF" | sort -k2,2n)

    if [[ ${#live[@]} -eq 0 ]]; then
      echo "multiwan: no WAN answers probe $TARGET" >&2
      exit 0
    fi

    prev="$(cat "$STATE" 2>/dev/null || true)"

    if [[ "$MODE" == "lb" ]]; then
      # ECMP: equal weight on all live WANs
      nexthops=()
      for i in "${!live[@]}"; do
        nexthops+=("nexthop via ${live_gw[$i]} dev ${live[$i]} weight 1")
      done
      # shellcheck disable=SC2086
      ip route add default ${nexthops[*]} 2>/dev/null \
        || ip route replace default ${nexthops[*]} 2>/dev/null || true
      active="lb:${live[*]}"
      echo "$active" >"$STATE"
      if [[ "$prev" != "$active" ]]; then
        logger -t ubrouter-multiwan "lb: ${prev:-none} -> $active (probe $TARGET)"
        echo "multiwan: lb active=${live[*]}"
      fi
    else
      # failover: first live (lowest metric) gets metric 10; others demoted
      best="${live[0]}"
      for i in "${!live[@]}"; do
        iface="${live[$i]}"
        gw="${live_gw[$i]}"
        metric="${live_metric[$i]}"
        if [[ "$iface" == "$best" ]]; then
          ip route add default via "$gw" dev "$iface" metric 10 2>/dev/null \
            || ip route replace default via "$gw" dev "$iface" metric 10 2>/dev/null || true
        else
          ip route add default via "$gw" dev "$iface" metric $((metric + 1000)) 2>/dev/null \
            || ip route replace default via "$gw" dev "$iface" metric $((metric + 1000)) 2>/dev/null || true
        fi
      done
      echo "$best" >"$STATE"
      if [[ "$prev" != "$best" ]]; then
        logger -t ubrouter-multiwan "failover: ${prev:-none} -> $best (probe $TARGET)"
        echo "multiwan: active=$best"
      fi
    fi
    """), encoding="utf-8")
watch.chmod(0o755)

unit = Path("/etc/systemd/system/ubrouter-multiwan-watch.service")
unit.write_text(textwrap.dedent("""\
    [Unit]
    Description=UBrouter multi-WAN probe (failover/LB)
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/lib/ubrouter/multiwan-watch.sh
    """), encoding="utf-8")
timer = Path("/etc/systemd/system/ubrouter-multiwan-watch.timer")
timer.write_text(textwrap.dedent("""\
    [Unit]
    Description=UBrouter multi-WAN probe timer

    [Timer]
    OnBootSec=30s
    OnUnitActiveSec=15s
    AccuracySec=3s

    [Install]
    WantedBy=timers.target
    """), encoding="utf-8")
subprocess.call(["systemctl", "daemon-reload"])
subprocess.call(["systemctl", "enable", "--now", "ubrouter-multiwan-watch.timer"])
subprocess.call(["netplan", "generate"])
subprocess.call(["netplan", "apply"])
subprocess.call(["/usr/local/lib/ubrouter/multiwan-watch.sh"])
print(f"--> multi-wan: applied mode={mode}")
PY

info "multi-wan: done (failover или LB/ECMP — см. /etc/ubrouter/multiwan.mode)"
