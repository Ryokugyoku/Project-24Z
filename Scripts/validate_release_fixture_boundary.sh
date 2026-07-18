#!/bin/bash

set -eu

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
app_file="$repository_root/Project 24Z/App/Project24ZApp.swift"
fixture_file="$repository_root/Project 24Z/App/Project24ZDebugFixtureComposition.swift"
derived_data="$(mktemp -d /tmp/project24z-release-fixture-gate.XXXXXX)"

cleanup() {
    case "$derived_data" in
        /tmp/project24z-release-fixture-gate.*) rm -rf -- "$derived_data" ;;
        *) echo "[release-fixture] refusing unsafe cleanup target: $derived_data" >&2 ;;
    esac
}
trap cleanup EXIT

if ! rg -q '^#if DEBUG' "$fixture_file" || ! rg -q 'PROJECT24Z_VEHICLE_REGISTRATION_FIXTURE' "$fixture_file" || ! rg -U -q '#if DEBUG[\s\S]{0,500}Project24ZDebugFixtureComposition[\s\S]{0,500}#else' "$app_file"; then
    echo "[release-fixture] fixture composition is not DEBUG-gated" >&2
    exit 1
fi

xcodebuild build -quiet -project "$repository_root/Project 24Z.xcodeproj" -scheme "Project 24Z" -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO || exit 1
xcodebuild build -quiet -project "$repository_root/Project 24Z.xcodeproj" -scheme "Project 24Z" -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO || exit 1

markers='PROJECT24Z_VEHICLE_REGISTRATION_FIXTURE|Project24ZDebugFixtureComposition|VehicleRegistrationPreviewFixtures|fixture-'
while IFS= read -r binary; do
    if strings "$binary" | rg -q "$markers"; then
        echo "[release-fixture] fixture marker remains in ${binary#"$derived_data/"}" >&2
        exit 1
    fi
done < <(find "$derived_data/Build/Products/Release" "$derived_data/Build/Products/Release-iphonesimulator" -type f -perm -111 2>/dev/null)

echo "Release fixture boundary validation passed."
