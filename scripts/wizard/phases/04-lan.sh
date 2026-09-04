#!/usr/bin/env bash
# Фаза 04 — LAN L3 + опциональные DHCP-теги / static hosts
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
TMP="${UBROUTER_WIZARD_TMP:?}"

cidr="$(ask "Адрес шлюза LAN (CIDR)" "10.0.0.1/24")"
dhcp=false
confirm "Включить DHCP-сервер на LAN?" Y && dhcp=true
pool_s="$(ask "DHCP pool start" "10.0.0.1")"
pool_e="$(ask "DHCP pool end" "10.0.0.1")"
domain="$(ask "Domain" "lan")"

tags_yaml="[]"
hosts_yaml="[]"

if [[ "$dhcp" == "true" ]] && confirm "DHCP-теги (разные DNS/NTP разным клиентам)?" N; then
  tags_tmp="$TMP/dhcp_tags.json"
  echo "[]" >"$tags_tmp"
  while confirm "Добавить DHCP-тег?" Y; do
    tname="$(ask "Имя тега (латиница)" "Children")"
    dns="$(ask "DNS для тега (IP через пробел, или router)" "router")"
    ntp="$(ask "NTP для тега (IP / router / off)" "router")"
    python3 - "$tags_tmp" "$tname" "$dns" "$ntp" <<'PY'
import json, sys
from pathlib import Path
path, name, dns, ntp = sys.argv[1:5]
data = json.loads(Path(path).read_text(encoding="utf-8") or "[]")
dns_list = ["router"] if dns.strip().lower() == "router" else [x for x in dns.split() if x]
entry = {"name": name, "dns": dns_list}
if ntp.strip().lower() == "off":
    entry["ntp"] = []
elif ntp.strip().lower() == "router":
    entry["ntp"] = ["router"]
else:
    entry["ntp"] = [x for x in ntp.split() if x]
data.append(entry)
Path(path).write_text(json.dumps(data), encoding="utf-8")
PY
  done
  tags_yaml="$(python3 -c 'import json,sys; from pathlib import Path; print(json.dumps(json.loads(Path(sys.argv[1]).read_text())))' "$tags_tmp")"

  if confirm "Привязать MAC → IP/тег (dhcp-host)?" N; then
    hosts_tmp="$TMP/dhcp_hosts.json"
    echo "[]" >"$hosts_tmp"
    while confirm "Добавить host?" Y; do
      mac="$(ask "MAC" "aa:bb:cc:dd:ee:ff")"
      ip="$(ask "IP (пусто = только тег)" "")"
      hn="$(ask "hostname (опц.)" "")"
      tag="$(ask "tag (имя из списка выше, опц.)" "")"
      python3 - "$hosts_tmp" "$mac" "$ip" "$hn" "$tag" <<'PY'
import json, sys
from pathlib import Path
path, mac, ip, hn, tag = sys.argv[1:6]
data = json.loads(Path(path).read_text(encoding="utf-8") or "[]")
e = {"mac": mac}
if ip:
    e["ip"] = ip
if hn:
    e["hostname"] = hn
if tag:
    e["tag"] = tag
data.append(e)
Path(path).write_text(json.dumps(data), encoding="utf-8")
PY
    done
    hosts_yaml="$(python3 -c 'import json,sys; from pathlib import Path; print(json.dumps(json.loads(Path(sys.argv[1]).read_text())))' "$hosts_tmp")"
  fi
fi

cat >"$TMP/lan.yaml" <<EOF
lan_cidr: $cidr
lan_dhcp: $dhcp
lan_pool_start: $pool_s
lan_pool_end: $pool_e
lan_domain: $domain
lan_dhcp_tags: $tags_yaml
lan_dhcp_hosts: $hosts_yaml
EOF
info "LAN $cidr dhcp=$dhcp"
