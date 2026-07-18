#!/bin/bash

set -u

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
repository_dir="$repository_root/Project 24Z/Data/Persistence/GRDB/Repositories"
failure_count=0

# Raw業務tableは、atomic readbackを担うこの3関数だけに限定します。近傍コメントでは拡張できません。
ruby - "$repository_dir" <<'RUBY' || failure_count=$((failure_count + 1))
root = ARGV.fetch(0)
tables = /\b(?:FROM|JOIN)\s+(?:vehicle_identification_scans|vehicle_identifiers|ecu_observations|ecu_identification_values|acquisition_sessions|acquisition_streams|clock_epochs|acquisition_gaps|log_chunks)\b/
allowlist = {
  "GRDBLocalSyncRepository.swift" => %w[applyAtomically verifyAliasGraph markSessionTransferDurable],
  "GRDBAcquisitionRepository.swift" => %w[recoverInterruptedSessions chunkCatalogReferences],
  "GRDBVehicleIdentityRepository.swift" => %w[verifyPersistedSnapshotCounts scanExists snapshotMatches],
}
failures = []
Dir.glob(File.join(root, "*.swift")).sort.each do |path|
  lines = File.readlines(path)
  lines.each_with_index do |line, index|
    function = lines[0..index].join.scan(/\bfunc\s+(\w+)\s*\(/).flatten.last
    if line.match?(tables) && !allowlist.fetch(File.basename(path), []).include?(function)
      failures << "#{path}:#{index + 1}: raw table access outside structured allowlist (#{function || 'file scope'})"
    end
  end
end
unless failures.empty?
  failures.each { |failure| warn "[persistence] #{failure}" }
  exit 1
end
RUBY

if rg -n 'markMaterializationApplied|readbackDigest:' "$repository_root/Project 24Z" "$repository_root/Project 24ZTests" --glob '*.swift'; then
    echo "[persistence] caller-supplied materialization digest API remains" >&2
    failure_count=$((failure_count + 1))
fi

if rg -n "UPDATE received_changes SET apply_state='(applied|duplicate)'|UPDATE origin_entity_materializations SET materialization_state='applied'" "$repository_root/Project 24ZTests" --glob '*.swift'; then
    echo "[persistence] tests bypass the atomic materialization contract" >&2
    failure_count=$((failure_count + 1))
fi

if [ "$failure_count" -ne 0 ]; then
    echo "Persistence contract validation failed with $failure_count violation(s)." >&2
    exit 1
fi

echo "Persistence contract validation passed."
