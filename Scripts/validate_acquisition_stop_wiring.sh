#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
views=(
  "$repository_root/Project 24Z/Platform/iOS/Features/Home/IOSHomeView.swift"
  "$repository_root/Project 24Z/Platform/macOS/Features/Home/MacOSHomeView.swift"
)

for view in "${views[@]}"; do
  rg -Fq 'case .stopAcquisition:' "$view"
  rg -Fq 'Task { await model.stopAcquisition() }' "$view"
  if rg -Fq 'case .stopAcquisition, .none:' "$view"; then
    echo "[stop-wiring] stopAcquisition is still a no-op in $view" >&2
    exit 1
  fi
done

composition="$repository_root/Project 24Z/App/Project24ZProductionComposition.swift"
if rg -Fq 'stopCoordinator: nil' "$composition"; then
  echo "Acquisition stop UI wiring validation passed; Production stop capability remains explicitly unavailable."
else
  rg -Fq 'AcquisitionStopCoordinator(' "$composition"
  echo "Acquisition stop UI and Production composition validation passed."
fi
