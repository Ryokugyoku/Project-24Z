#!/bin/bash

set -u

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$repository_root/Project 24Z"
failure_count=0

report_failure() {
    echo "[structure] $1" >&2
    failure_count=$((failure_count + 1))
}

while IFS= read -r file; do
    relative_path="${file#"$source_root/"}"

    if rg -q '^import (SwiftUI|UIKit|AppKit)$' "$file"; then
        case "$relative_path" in
            App/*|Platform/iOS/*|Platform/macOS/*) ;;
            *) report_failure "UI framework import is outside App/Platform: $relative_path" ;;
        esac
    fi

    if rg -q '^import (SwiftData|GRDB)$' "$file"; then
        case "$relative_path" in
            App/*|Data/Persistence/*) ;;
            *) report_failure "database framework import is outside App/Data/Persistence: $relative_path" ;;
        esac
    fi

    if rg -q '@Query|@Environment\(\\\.modelContext\)' "$file"; then
        report_failure "View-level persistence access is prohibited: $relative_path"
    fi
done < <(find "$source_root" -type f -name '*.swift' -print)

while IFS= read -r file; do
    relative_path="${file#"$source_root/"}"
    rg -q '^#if os\(iOS\)' "$file" || report_failure "iOS source needs a whole-file iOS guard: $relative_path"
    rg -q '^import AppKit$' "$file" && report_failure "iOS source imports AppKit: $relative_path"
done < <(find "$source_root/Platform/iOS" -type f -name '*.swift' -print)

while IFS= read -r file; do
    relative_path="${file#"$source_root/"}"
    rg -q '^#if os\(macOS\)' "$file" || report_failure "macOS source needs a whole-file macOS guard: $relative_path"
    rg -q '^import UIKit$' "$file" && report_failure "macOS source imports UIKit: $relative_path"
done < <(find "$source_root/Platform/macOS" -type f -name '*.swift' -print)

if find "$source_root" -type d \( -name Common -o -name Misc -o -name Helpers -o -name Managers \) -print -quit | rg -q .; then
    report_failure "ambiguous Common/Misc/Helpers/Managers folder exists"
fi

if [ "$failure_count" -ne 0 ]; then
    echo "Structure validation failed with $failure_count violation(s)." >&2
    exit 1
fi

echo "Structure validation passed."

"$repository_root/Scripts/validate_docc.sh" || exit 1
"$repository_root/Scripts/validate_design_documents.sh" || exit 1
"$repository_root/Scripts/validate_persistence_contracts.sh" || exit 1
