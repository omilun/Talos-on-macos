#!/usr/bin/env bash
# discover-ips.sh — ARP-based IP discovery for all cluster VMs.
# Called by the Terraform external data source in the tart-vms module.
#
# Protocol (Terraform external data source):
#   stdin  — JSON object: {"node_name_underscore": "mac_address", ...}
#   stdout — JSON object: {"node_name_underscore": "ip_address", ...}
#   stderr — human-readable progress (ignored by Terraform)

set -euo pipefail

# Write stdin to a temp file so the heredoc below can read the Python script
# from a here-doc while the query JSON is available separately.
tmpinput=$(mktemp /tmp/tf-discover-XXXXXX.json)
trap 'rm -f "$tmpinput"' EXIT
cat > "$tmpinput"

python3 - "$tmpinput" << 'PYEOF'
"""
Reads a JSON map of {node: mac} from argv[1] and performs ARP-based discovery
for each MAC, returning a JSON map of {node: ip}.

macOS arp(8) strips leading zeros per octet:  c6:21:11:aa:bb:01 -> c6:21:11:aa:bb:1
We normalise both the input MAC and the ARP output before comparing.
"""
import json
import subprocess
import sys
import time

TIMEOUT = 120  # seconds per VM

def normalise_mac(mac: str) -> str:
    """Strip leading zeros from each octet (matches macOS arp -a output format)."""
    return ":".join(part.lstrip("0") or "0" for part in mac.lower().split(":"))


def discover_ip(mac: str, timeout: int = TIMEOUT) -> str:
    mac_lower = mac.lower()
    mac_norm  = normalise_mac(mac_lower)

    for _ in range(timeout // 3):
        try:
            arp_out = subprocess.check_output(
                ["arp", "-a"], text=True, stderr=subprocess.DEVNULL
            )
            for line in arp_out.splitlines():
                parts = line.split()
                if len(parts) < 4:
                    continue
                arp_mac = parts[3].lower()
                if arp_mac in (mac_lower, mac_norm):
                    ip = parts[1].strip("()")
                    if ip and ip != "incomplete":
                        return ip
        except Exception:  # noqa: BLE001
            pass

        time.sleep(3)

    return ""


with open(sys.argv[1]) as fh:
    nodes: dict[str, str] = json.load(fh)

results: dict[str, str] = {}
for node, mac in sorted(nodes.items()):
    ip = discover_ip(mac)
    results[node] = ip
    status = ip if ip else "TIMEOUT"
    print(f"[INFO]  {node:<16} mac={mac}  ip={status}", file=sys.stderr)

print(json.dumps(results))
PYEOF
