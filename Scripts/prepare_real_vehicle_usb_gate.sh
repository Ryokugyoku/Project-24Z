#!/bin/bash

set -u

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
serial_candidate_count=0

while IFS= read -r endpoint; do
    case "$endpoint" in
        *.Bluetooth-Incoming-Port|*.debug-console|*.wlan-debug) continue ;;
    esac
    serial_candidate_count=$((serial_candidate_count + 1))
done < <(find /dev -maxdepth 1 -type c -name 'cu.*' -print 2>/dev/null)

echo "[usb-gate] commit=$(git -C "$repository_root" rev-parse HEAD)"
echo "[usb-gate] working_tree_changes=$(git -C "$repository_root" status --short | wc -l | tr -d ' ')"
echo "[usb-gate] macos=$(sw_vers -productVersion) build=$(sw_vers -buildVersion) architecture=$(uname -m)"
echo "[usb-gate] usb_serial_candidate_count=$serial_candidate_count"

if rg -q 'UnavailableConnectionEndpointDiscovery\(\)' "$repository_root/Project 24Z/App/Project24ZProductionComposition.swift" &&
   rg -q 'UnavailableAdapterConnectionPreparer\(\)' "$repository_root/Project 24Z/App/Project24ZProductionComposition.swift"; then
    echo "[usb-gate] production_transport=blocked"
else
    echo "[usb-gate] production_transport=REVIEW_REQUIRED"
fi

if [ "$serial_candidate_count" -eq 1 ]; then
    echo "[usb-gate] preflight=adapter_details_and_approval_required"
else
    echo "[usb-gate] preflight=blocked_expected_exactly_one_usb_serial_candidate"
fi

echo "[usb-gate] no endpoint was opened and no bytes were sent"
