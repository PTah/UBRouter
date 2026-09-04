#!/usr/bin/env bash
# Probe physical NICs → JSON array [{mac,name,pci,carrier}]
set -euo pipefail

python3 - <<'PY'
import json, os, glob, subprocess

def read(p):
    try:
        with open(p) as f:
            return f.read().strip()
    except OSError:
        return ""

nics = []
for path in sorted(glob.glob("/sys/class/net/*")):
    name = os.path.basename(path)
    if name == "lo" or name.startswith(("docker", "veth", "br-", "virbr", "wg", "tun", "tap")):
        continue
    # skip non-physical if no device link (virtual)
    if not os.path.exists(f"{path}/device") and not os.path.exists(f"{path}/address"):
        continue
    mac = read(f"{path}/address").lower()
    if not mac or mac == "00:00:00:00:00:00":
        continue
    carrier = read(f"{path}/carrier") or "?"
    oper = read(f"{path}/operstate") or "?"
    pci = ""
    device = f"{path}/device"
    if os.path.islink(device):
        pci = os.path.basename(os.path.realpath(device))
    nics.append({
        "name": name,
        "mac": mac,
        "pci": pci,
        "carrier": carrier,
        "operstate": oper,
    })

# Prefer PCI slot order when available
nics.sort(key=lambda x: (x["pci"] == "", x["pci"], x["name"]))
print(json.dumps(nics, ensure_ascii=False))
PY
