#!/bin/bash

set -u

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
failure_count=0

require_text() {
    local file="$1"
    local pattern="$2"
    local message="$3"
    if ! rg -q "$pattern" "$repository_root/$file"; then
        echo "[design] $message: $file" >&2
        failure_count=$((failure_count + 1))
    fi
}

require_text "Documentation/DATABASE_OPERATIONS.md" 'active_or_local_\*|active-or-local' "normal query view contract is missing"
require_text "Documentation/DATABASE_OPERATIONS.md" 'v3失敗.*rollback|v3.*rollback' "v3 rollback contract is missing"
require_text "Documentation/DEVICE_PAIRING_SYNC_CONFLICT_DESIGN.md" 'BEGIN IMMEDIATE' "atomic sync contract is missing"
require_text "Documentation/DEVICE_PAIRING_SYNC_CONFLICT_DESIGN.md" 'Durable ACK' "durable ACK contract is missing"
require_text "Documentation/ACQUISITION_SESSION_STORAGE_DESIGN.md" 'System of Record|正本' "acquisition system-of-record contract is missing"

if [ "$failure_count" -ne 0 ]; then
    echo "Design document validation failed with $failure_count violation(s)." >&2
    exit 1
fi

echo "Design document validation passed."
