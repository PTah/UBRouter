#!/usr/bin/env bash
# UBrouter doctor: diagnostics across all modules + reachability + snapshot integrity.
# Returns 0 if all green; non-zero if any critical check fails.
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"

ANSWERS="${UBROUTER_ANSWERS:-/etc/ubrouter/answers.yaml}"

crit=0
warn_count=0
ok_count=0

pass() { echo "  ✓ $*"; ok_count=$((ok_count+1)); }
soft() { echo "  ! $*"; warn_count=$((warn_count+1)); }
fail() { echo "  ✗ $*"; crit=$((crit+1)); }
hdr()  { echo; echo "── $* ──"; }

# ---------- 1. State files ----------
hdr "state"
if [[ -f /etc/ubrouter/state.json ]]; then
  pass "state.json: $(tr -d '\n' </etc/ubrouter/state.json)"
else
  soft "state.json отсутствует — apply ещё не запускался?"
fi
if [[ -f "$ANSWERS" ]]; then
  pass "answers.yaml: $ANSWERS ($(wc -l <"$ANSWERS") строк)"
else
  fail "answers.yaml не найден: $ANSWERS"
fi

# ---------- 2. Kernel forwarding ----------
hdr "kernel"
if [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" == "1" ]]; then
  pass "net.ipv4.ip_forward=1"
else
  fail "net.ipv4.ip_forward=0 (NAT не работает)"
fi
if [[ -f /etc/sysctl.d/99-ubrouter.conf ]]; then
  pass "sysctl drop-in установлен"
else
  soft "нет /etc/sysctl.d/99-ubrouter.conf"
fi

# ---------- 3. Interfaces ----------
hdr "interfaces"
if [[ ! -f "$ANSWERS" ]]; then
  soft "answers.yaml нет — пропускаем interface-check"
else
  if ans_available; then
    naming="$(ans_get interfaces.naming 2>/dev/null || echo)"
    map_json="$(ans_get_json interfaces.map 2>/dev/null || echo '[]')"
    echo "  naming=$naming map=$(echo "$map_json" | tr -d '\n ' | head -c 200)"
    # check each name exists
    python3 -c '
import json, subprocess, sys
m = json.loads(sys.argv[1] or "[]") or []
miss = []
for e in m:
    n = e.get("name")
    if not n: continue
    r = subprocess.run(["ip","link","show","dev",n], capture_output=True)
    if r.returncode != 0: miss.append(n)
print("missing:", " ".join(miss) if miss else "(none)")
' "$map_json" | while read -r line; do
      if [[ "$line" == "missing: (none)" ]]; then
        pass "все имена из map существуют"
      else
        soft "$line (возможен reboot после rename)"
      fi
    done
  fi
fi

# ---------- 4. WAN ----------
hdr "wan"
if ip -4 route show default 2>/dev/null | grep -q .; then
  pass "default route: $(ip -4 route show default | head -1)"
else
  fail "нет default route — WAN не поднялся"
fi

# ---------- 5. DNS reachability ----------
hdr "dns"
if systemctl is-active --quiet dnsmasq 2>/dev/null; then
  pass "dnsmasq active"
  leases="$(find /var/lib/misc /var/lib/dnsmasq -name 'dnsmasq.leases' 2>/dev/null | head -1)"
  if [[ -n "$leases" && -f "$leases" ]]; then
    n="$(($(wc -l <"$leases")))"
    pass "DHCP leases: $n"
  else
    soft "не найден dnsmasq.leases"
  fi
else
  soft "dnsmasq не active (возможно выключен в answers)"
fi

if command -v dig >/dev/null 2>&1; then
  if dig +time=2 +tries=1 @1.1.1.1 one.one.one.one +short >/dev/null 2>&1; then
    pass "upstream DNS (1.1.1.1) responds"
  else
    fail "upstream DNS 1.1.1.1 не отвечает"
  fi
  if [[ -f /etc/ubrouter/answers.yaml ]]; then
    if dig +time=2 +tries=1 @127.0.0.1 -p 53 one.one.one.one +short >/dev/null 2>&1; then
      pass "локальный DNS (127.0.0.1:53) отвечает"
    else
      soft "локальный DNS не отвечает (dnsmasq выключен или stub на 127.0.0.53?)"
    fi
  fi
else
  soft "dig не установлен — пропускаем DNS-resolve checks"
fi

# ---------- 6. NTP ----------
hdr "ntp"
if systemctl is-active --quiet chrony 2>/dev/null || systemctl is-active --quiet chronyd 2>/dev/null; then
  pass "chrony active"
  if command -v chronyc >/dev/null 2>&1; then
    sync_src="$(chronyc -c sources 2>/dev/null | head -1)"
    [[ -n "$sync_src" ]] && pass "chrony sources: ${sync_src:0:80}"
  fi
else
  soft "chrony не active"
fi

# ---------- 7. Firewall ----------
hdr "firewall"
if systemctl is-active --quiet nftables 2>/dev/null; then
  pass "nftables active"
else
  fail "nftables не active"
fi
if nft list ruleset 2>/dev/null | grep -q 'chain forward'; then
  pass "nft forward chain присутствует"
else
  soft "nft forward chain не найден"
fi
if nft list table inet ubrouter_bypass >/dev/null 2>&1; then
  pass "bypass nft table присутствует"
  bypass_set_count="$(nft -j list set inet ubrouter_bypass bypass_dst 2>/dev/null | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    elems = d[0].get("set", {}).get("elem", [])
    print(len(elems))
except Exception:
    print(0)' 2>/dev/null || echo 0)"
  echo "  bypass_dst set: ${bypass_set_count} CIDR/элементов"
else
  soft "bypass nft table не найден (bypass выключен?)"
fi

# ---------- 8. VPN ----------
hdr "vpn"
if ip -br link 2>/dev/null | grep -qE '^wg'; then
  wg_ifaces="$(ip -br link | awk '/^wg/ {print $1}' | tr '\n' ' ')"
  pass "WireGuard ifaces: $wg_ifaces"
  if command -v wg >/dev/null 2>&1; then
    wg show 2>/dev/null | head -20 | sed 's/^/    /'
  fi
else
  soft "нет wg* интерфейсов"
fi

if ip -br link 2>/dev/null | grep -qE '^(gre|ipip|tun|tap|eoip)'; then
  tun="$(ip -br link | awk '/^(gre|ipip|tun|tap|eoip)/ {print $1}' | tr '\n' ' ')"
  pass "tunnels: $tun"
else
  soft "нет GRE/IPIP/tun интерфейтов"
fi

if command -v swanctl >/dev/null 2>&1; then
  if systemctl is-active --quiet strongswan-starter 2>/dev/null \
    || systemctl is-active --quiet strongswan 2>/dev/null; then
    pass "strongswan active"
    sas="$(swanctl --list-sas 2>/dev/null | wc -l)"
    conns="$(swanctl --list-conns 2>/dev/null | wc -l)"
    echo "    IKEv2 conns=$conns sas=$sas"
  else
    soft "strongswan не active"
  fi
fi

# ---------- 9. Bypass policy routing ----------
hdr "bypass"
if [[ -f /etc/ubrouter/bypass.env ]]; then
  # shellcheck source=/dev/null
  . /etc/ubrouter/bypass.env 2>/dev/null || true
  if ip rule show 2>/dev/null | grep -q "fwmark ${BYPASS_MARK:-0x2}"; then
    pass "ip rule fwmark=${BYPASS_MARK:-0x2} → table ${BYPASS_TABLE:-200}"
  else
    soft "нет fwmark-rule (bypass выключен или туннель down?)"
  fi
  if ip route show table "${BYPASS_TABLE:-200}" 2>/dev/null | grep -q .; then
    pass "bypass table ${BYPASS_TABLE:-200} имеет default route"
  else
    soft "bypass table пустая"
  fi
else
  soft "bypass.env не найден (bypass выключен)"
fi

# ---------- 10. Multi-WAN ----------
hdr "multi-wan"
if [[ -f /etc/ubrouter/multiwan.conf ]]; then
  active="$(cat /var/lib/ubrouter/multiwan.active 2>/dev/null || echo '?')"
  mw_mode="$(cat /etc/ubrouter/multiwan.mode 2>/dev/null || echo failover)"
  pass "multiwan.conf: mode=$mw_mode active=$active"
  echo "    defaults:"
  ip -4 route show default 2>/dev/null | sed 's/^/      /'
else
  soft "multiwan.conf не найден (multi-WAN выключен)"
fi

# ---------- 10b. Netwatch ----------
hdr "netwatch"
if systemctl is-enabled ubrouter-netwatch.timer >/dev/null 2>&1; then
  pass "ubrouter-netwatch.timer enabled"
  [[ -f /etc/ubrouter/netwatch-hosts.conf ]] && pass "netwatch-hosts.conf OK" || soft "нет netwatch-hosts.conf"
else
  soft "netwatch выключен"
fi

# ---------- 11. Snapshots ----------
hdr "snapshots"
SNAP_ROOT=/var/lib/ubrouter/snapshots
if [[ -d "$SNAP_ROOT" ]]; then
  count="$(find "$SNAP_ROOT" -maxdepth 1 -type d -name '20*' | wc -l)"
  latest="$(cat "$SNAP_ROOT/LATEST" 2>/dev/null || echo '?')"
  pass "snapshots: $count, latest=$latest"
  if [[ -d "$SNAP_ROOT/$latest" ]]; then
    if [[ -f "$SNAP_ROOT/$latest/MANIFEST" ]]; then
      manifest_lines="$(wc -l <"$SNAP_ROOT/$latest/MANIFEST")"
      pass "latest snapshot MANIFEST: $manifest_lines paths"
    else
      soft "latest snapshot без MANIFEST (legacy layout?)"
    fi
    # quick integrity: each path in MANIFEST exists in snapshot
    missing_in_snap=0
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      [[ -e "$SNAP_ROOT/$latest$p" ]] || missing_in_snap=$((missing_in_snap+1))
    done <"$SNAP_ROOT/$latest/MANIFEST" 2>/dev/null || true
    if [[ "$missing_in_snap" -eq 0 ]]; then
      pass "snapshot integrity OK"
    else
      soft "snapshot integrity: $missing_in_snap путей отсутствует в snapshot"
    fi
  fi
  # disk usage
  sz="$(du -sh "$SNAP_ROOT" 2>/dev/null | awk '{print $1}')"
  echo "    disk usage: $sz"
else
  soft "нет snapshots (apply ещё не запускался)"
fi

# ---------- 12. Apply lock ----------
hdr "lock"
if [[ -f /var/lock/ubrouter-apply.lock ]]; then
  if fuser /var/lock/ubrouter-apply.lock >/dev/null 2>&1; then
    soft "apply lock занят (apply запущен?)"
  else
    pass "apply lock свободен"
  fi
else
  pass "apply lock свободен"
fi

# ---------- 13. systemd units ----------
hdr "units"
for u in ubrouter-pppoe ubrouter-bypass ubrouter-bypass-watch.timer \
         ubrouter-multiwan-watch.timer ubrouter-netwatch.timer ubrouter-sqm ubrouter-gre \
         ubrouter-ipip ubrouter-eoip ubrouter-l2tp ubrouter-swanctl-load \
         dnsmasq chrony nftables; do
  if systemctl list-unit-files "$u.service" 2>/dev/null | grep -q "$u" \
     || systemctl list-unit-files "$u" 2>/dev/null | grep -q "$u"; then
    state="$(systemctl is-active "$u" 2>/dev/null || echo '?')"
    enabled="$(systemctl is-enabled "$u" 2>/dev/null || echo '?')"
    echo "    $u: active=$state enabled=$enabled"
  fi
done

# ---------- Summary ----------
echo
echo "── summary ──"
echo "  OK=$ok_count  WARN=$warn_count  CRIT=$crit"
if [[ "$crit" -gt 0 ]]; then
  die "doctor: $crit критических проблем"
fi
exit 0
