#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Include untracked work in progress, but never generated or ignored files.
file_list=$(mktemp)
trap 'rm -f "$file_list"' EXIT
git ls-files --cached --others --exclude-standard -z -- '*.swift' > "$file_list"
swift_files=()
while IFS= read -r -d '' file; do
  if [[ -f "$file" ]]; then
    swift_files+=("./$file")
  fi
done < "$file_list"

if (( ${#swift_files[@]} == 0 )); then
  printf 'No Swift source files found.\n' >&2
  exit 1
fi

status=0
swift-format lint --strict "${swift_files[@]}" || status=1
swiftlint lint --strict --quiet --no-cache "${swift_files[@]}" || status=1
exit "$status"
