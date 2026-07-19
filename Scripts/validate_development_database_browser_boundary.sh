#!/bin/bash

set -eu

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$(mktemp -d /tmp/project24z-development-browser-gate.XXXXXX)"

cleanup() {
    case "$derived_data" in
        /tmp/project24z-development-browser-gate.*) rm -rf -- "$derived_data" ;;
        *) echo "[development-browser] refusing unsafe cleanup target: $derived_data" >&2 ;;
    esac
}
trap cleanup EXIT

while IFS= read -r file; do
    if ! rg -q 'PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER' "$file"; then
        echo "[development-browser] missing dedicated compile gate: ${file#"$repository_root/"}" >&2
        exit 1
    fi
done < <(find "$repository_root/Project 24Z" "$repository_root/Project 24ZTests" -type f -path '*Development*Database*' -name '*.swift' -print)

xcodebuild build -quiet -project "$repository_root/Project 24Z.xcodeproj" -scheme "Project 24Z" -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO
xcodebuild build -quiet -project "$repository_root/Project 24Z.xcodeproj" -scheme "Project 24Z" -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO

markers='DevelopmentDatabaseBrowser|データベース閲覧|開発専用。実データを表示します'
while IFS= read -r binary; do
    if strings "$binary" | rg -q "$markers"; then
        echo "[development-browser] development artifact remains in ${binary#"$derived_data/"}" >&2
        exit 1
    fi
done < <(find "$derived_data/Build/Products/Release" "$derived_data/Build/Products/Release-iphonesimulator" -type f -perm -111 2>/dev/null)

echo "Development Database Browser release boundary validation passed."
