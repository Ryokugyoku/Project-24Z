#!/bin/bash

set -u

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root" || exit 1

ruby <<'RUBY'
require "open3"

tracked_diff, = Open3.capture3("git", "diff", "--unified=0", "--", "*.swift")
targets = Hash.new { |hash, key| hash[key] = [] }
file = nil
new_line = 0
tracked_diff.each_line do |line|
  if line.start_with?("+++ b/")
    file = line.delete_prefix("+++ b/").strip
  elsif line =~ /^@@ -\d+(?:,\d+)? \+(\d+)/
    new_line = Regexp.last_match(1).to_i
  elsif line.start_with?("+") && !line.start_with?("+++")
    targets[file] << new_line if file
    new_line += 1
  elsif line.start_with?("-") && !line.start_with?("---")
    next
  else
    new_line += 1 if file
  end
end

untracked, = Open3.capture3("git", "ls-files", "--others", "--exclude-standard", "--", "*.swift")
untracked.lines.map(&:strip).reject(&:empty?).each do |path|
  targets[path] = (1..File.readlines(path).length).to_a
end

modifier = /(?:public|internal|private|fileprivate|package|open|nonisolated|isolated|static|class|final|indirect|override|required|convenience|distributed|mutating|nonmutating|borrowing|consuming)/
declaration = /^\s*(?:(?:#{modifier.source})\s+)*(?:class\s+\w|struct\s+\w|enum\s+\w|protocol\s+\w|actor\s+\w|typealias\s+\w|associatedtype\s+\w|func\s+\w|init\s*[?!(<]|subscript\s*[<(])/ 
failures = []
targets.each do |path, changed_lines|
  next unless path && File.file?(path)
  lines = File.readlines(path)
  lines.each_with_index do |source, index|
    next unless source.match?(declaration)
    finish = index
    depth = 0
    loop do
      fragment = lines[finish]
      depth += fragment.count("(") + fragment.count("[") - fragment.count(")") - fragment.count("]")
      break if depth <= 0 && (fragment.include?("{") || fragment.match?(/\bwhere\b/) || fragment.rstrip.end_with?("}"))
      break if finish + 1 >= lines.length || finish - index >= 40
      finish += 1
    end
    declaration_lines = ((index + 1)..(finish + 1)).to_a
    next if (declaration_lines & changed_lines).empty?
    previous = index - 1
    while previous >= 0 && (lines[previous].match?(/^\s*@/) || lines[previous].match?(/^\s*(?:#{modifier.source})(?:\s+(?:#{modifier.source}))*\s*$/))
      previous -= 1
    end
    failures << "#{path}:#{index + 1}: #{source.strip}" unless previous >= 0 && lines[previous].match?(/^\s*\/\/\//)
  end
end

if failures.any?
  failures.each { |failure| warn "[docc] missing DocC: #{failure}" }
  warn "DocC validation failed with #{failures.length} violation(s)."
  exit 1
end
puts "DocC validation passed."
RUBY
