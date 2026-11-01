#!/bin/bash
set -euo pipefail

if [[ -z "${TEST_DESTINATION:-}" ]]; then
  printf 'Set TEST_DESTINATION to an available iPhone simulator destination to run the full validation gate.\n' >&2
  exit 2
fi

simulator_destination_timeout_seconds=${SIMULATOR_DESTINATION_TIMEOUT_SECONDS:-60}
test_execution_timeout_seconds=${TEST_EXECUTION_TIMEOUT_SECONDS:-120}

require_positive_integer() {
  local name=$1
  local value=$2
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s must be a positive integer number of seconds; got %q.\n' "$name" "$value" >&2
    exit 2
  fi
}

require_positive_integer SIMULATOR_DESTINATION_TIMEOUT_SECONDS "$simulator_destination_timeout_seconds"
require_positive_integer TEST_EXECUTION_TIMEOUT_SECONDS "$test_execution_timeout_seconds"

log_dir=$(mktemp -d)
trap 'rm -rf "$log_dir"' EXIT

run_check() {
  local label=$1
  shift
  local log_file="$log_dir/${label// /-}.log"
  if "$@" >"$log_file" 2>&1; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (last 25 log lines)\n' "$label" >&2
    tail -n 25 "$log_file" >&2
    return 1
  fi
}

run_check 'project generation' scripts/generate-project.sh
run_check 'swift-format' swift-format lint --strict --recursive .
run_check 'swiftlint' swiftlint lint --strict --quiet --no-cache
run_check 'build' xcodebuild -quiet -project NarihitosDiary.xcodeproj -scheme NarihitosDiary -destination 'generic/platform=iOS Simulator' -derivedDataPath "$log_dir/DerivedData" CODE_SIGNING_ALLOWED=NO build

run_check 'tests' xcodebuild -quiet -project NarihitosDiary.xcodeproj -scheme NarihitosDiary -destination "$TEST_DESTINATION" -destination-timeout "$simulator_destination_timeout_seconds" -derivedDataPath "$log_dir/DerivedData" -test-timeouts-enabled YES -default-test-execution-time-allowance "$test_execution_timeout_seconds" -maximum-test-execution-time-allowance "$test_execution_timeout_seconds" CODE_SIGNING_ALLOWED=NO test
