#!/usr/bin/env bash
# Render /etc/netplan/50-ubrouter.yaml from answers (WAN+LAN+optional bridge+rename).
set -euo pipefail
ROOT="${UBROUTER_ROOT:?}"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/answers.sh"
ans_require
need_root

OUT="${1:-/etc/netplan/50-ubrouter.yaml}"
WORKDIR="${UBROUTER_WORKDIR:-/var/lib/ubrouter/work}"
ensure_dir "$WORKDIR/netplan"

naming="$(ans_get interfaces.naming)"
wan_if="$(ans_get wan.interface)"
wan_mode="$(ans_get wan.mode)"
wan_vlan="$(ans_get wan.vlan_id)"
wan_mtu="$(ans_get wan.mtu)"
lan_if="$(ans_get lan.interface)"
lan_cidr="$(ans_get lan.cidr)"
bridge_en=false
ans_true interfaces.bridge.enabled && bridge_en=true
br_name="$(ans_get interfaces.bridge.name)"
[[ -n "$br_name" ]] || br_name="br-lan"

map_json="$(ans_get_json interfaces.map)"
members_json="$(ans_get_json interfaces.bridge.members)"

python3 - "$OUT" "$naming" "$wan_if" "$wan_mode" "$wan_vlan" "$wan_mtu" \
  "$lan_if" "$lan_cidr" "$bridge_en" "$br_name" "$map_json" "$members_json" \
  "$UBROUTER_ANSWERS" <<'PY'
import json, sys, yaml
from pathlib import Path

(
    out,
    naming,
    wan_if,
    wan_mode,
    wan_vlan,
    wan_mtu,
    lan_if,
    lan_cidr,
    bridge_en,
    br_name,
    map_json,
    members_json,
    answers_path,
) = sys.argv[1:]

bridge_en = bridge_en == "true"
iface_map = json.loads(map_json) if map_json and map_json != "null" else []
members = json.loads(members_json) if members_json and members_json != "null" else []
if isinstance(members, str):
    members = [m for m in members.replace(",", " ").split() if m]

with open(answers_path, encoding="utf-8") as f:
    answers = yaml.safe_load(f) or {}

wan = answers.get("wan") or {}
static = wan.get("static") or {}
dns_up = (answers.get("dns") or {}).get("upstream") or ["9.9.9.9", "1.1.1.1"]
ipv6_mode = (wan.get("ipv6") or "off")
lan_cfg = answers.get("lan") or {}
lan_v6 = lan_cfg.get("ipv6") or {}
lan_v6_en = lan_v6.get("enabled") in (True, "true", "1", "yes", 1)
lan_v6_addr = lan_v6.get("address")  # e.g. fd00::1/64

ethernets = {}
# Rename by MAC when not keep
if naming and naming != "keep" and iface_map:
    for ent in iface_map:
        mac = (ent.get("mac") or "").lower()
        name = ent.get("name")
        if not mac or not name:
            continue
        ethernets[name] = {
            "match": {"macaddress": mac},
            "set-name": name,
            "dhcp4": False,
            "optional": True,
        }

def ensure_eth(name, **kw):
    e = ethernets.setdefault(name, {"dhcp4": False, "optional": True})
    e.update(kw)
    return e

def apply_wan_ipv6(dev_dict):
    if ipv6_mode == "dhcpv6":
        dev_dict["dhcp6"] = True
        dev_dict["accept-ra"] = True
    elif ipv6_mode == "slaac":
        dev_dict["dhcp6"] = False
        dev_dict["accept-ra"] = True
    else:
        # off — avoid RA surprises on WAN
        dev_dict["accept-ra"] = False
        if "dhcp6" not in dev_dict:
            dev_dict["dhcp6"] = False

# WAN
if wan_mode == "dhcp":
    w = ensure_eth(wan_if, dhcp4=True, optional=True)
    w["nameservers"] = {"addresses": list(dns_up)}
    apply_wan_ipv6(w)
elif wan_mode == "static":
    addr = static.get("address") or ""
    gw = static.get("gateway")
    w = ensure_eth(wan_if, dhcp4=False, optional=True)
    if addr:
        w["addresses"] = [addr]
    if gw:
        w["routes"] = [{"to": "default", "via": gw}]
    ns = static.get("dns") or dns_up
    w["nameservers"] = {"addresses": list(ns)}
    apply_wan_ipv6(w)
elif wan_mode == "none":
    ensure_eth(wan_if, dhcp4=False, optional=True)
elif wan_mode == "pppoe":
    # L3 on ppp0 via pppd; parent link L2 only
    w = ensure_eth(wan_if, dhcp4=False, optional=True)
    w["accept-ra"] = False
else:
    w = ensure_eth(wan_if, dhcp4=True, optional=True)
    apply_wan_ipv6(w)

if wan_mtu and wan_mtu not in ("", "null", "None"):
    try:
        ensure_eth(wan_if)["mtu"] = int(wan_mtu)
    except ValueError:
        pass

# VLAN on WAN (optional)
vlans = {}
if wan_vlan and wan_vlan not in ("", "null", "None"):
    try:
        vid = int(float(wan_vlan))
        vname = f"{wan_if}.{vid}"
        vlans[vname] = {"id": vid, "link": wan_if, "dhcp4": wan_mode == "dhcp"}
        if wan_mode == "dhcp":
            ensure_eth(wan_if, dhcp4=False)
            vlans[vname]["nameservers"] = {"addresses": list(dns_up)}
            apply_wan_ipv6(vlans[vname])
        elif wan_mode == "pppoe":
            vlans[vname]["dhcp4"] = False
            vlans[vname]["accept-ra"] = False
        wan_l3 = vname
    except ValueError:
        wan_l3 = wan_if
else:
    wan_l3 = wan_if

bridges = {}
# LAN
lan_addrs = [lan_cidr]
if lan_v6_en and lan_v6_addr:
    lan_addrs.append(lan_v6_addr)

if bridge_en:
    for m in members:
        ensure_eth(m, dhcp4=False, optional=True)
    br = {
        "interfaces": members,
        "addresses": lan_addrs,
        "dhcp4": False,
        "parameters": {"stp": False, "forward-delay": 0},
    }
    if lan_v6_en:
        br["accept-ra"] = False
    bridges[br_name] = br
    lan_dev = br_name
else:
    le = ensure_eth(lan_if, dhcp4=False, addresses=lan_addrs, optional=True)
    if lan_v6_en:
        le["accept-ra"] = False
    lan_dev = lan_if

# renderer networkd
doc = {
    "network": {
        "version": 2,
        "renderer": "networkd",
        "ethernets": ethernets,
    }
}
if bridges:
    doc["network"]["bridges"] = bridges
if vlans:
    doc["network"]["vlans"] = vlans

Path(out).parent.mkdir(parents=True, exist_ok=True)
text = yaml.safe_dump(doc, default_flow_style=False, sort_keys=False)
Path(out).write_text(text, encoding="utf-8")
Path(out).chmod(0o600)
print(out)
print(f"wan_l3={wan_l3} lan={lan_dev} ipv6={ipv6_mode} lan_v6={lan_v6_en}", file=sys.stderr)
PY

chmod 600 "$OUT"
info "netplan rendered → $OUT"
