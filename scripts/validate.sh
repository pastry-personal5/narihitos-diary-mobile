#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

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
finish() {
  local status=$?
  if (( status == 0 )); then
    rm -rf "$log_dir"
  else
    printf 'Validation logs: %s\n' "$log_dir" >&2
  fi
}
trap finish EXIT

if ! xcrun simctl list devices available -j >"$log_dir/simulators.json" 2>"$log_dir/simulators.log"; then
  printf 'Cannot access CoreSimulator; simulator validation cannot run in this environment.\n' >&2
  tail -n 5 "$log_dir/simulators.log" >&2
  exit 2
fi

if ! test_destination=$(python3 - "$log_dir/simulators.json" "${TEST_DESTINATION:-}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    devices = json.load(source)["devices"]

iphones = [
    device
    for runtime_devices in devices.values()
    for device in runtime_devices
    if device["name"].startswith("iPhone")
]
requested = sys.argv[2]
if requested:
    fields = dict(part.split("=", 1) for part in requested.split(",") if "=" in part)
    if fields.get("platform") != "iOS Simulator" or not (fields.get("id") or fields.get("name")):
        sys.exit("TEST_DESTINATION must specify platform=iOS Simulator and an iPhone id or name.")
    matches = [
        device for device in iphones
        if (not fields.get("id") or device["udid"] == fields["id"])
        and (not fields.get("name") or device["name"] == fields["name"])
    ]
    if len(matches) != 1:
        sys.exit("TEST_DESTINATION does not identify exactly one available iPhone simulator.")
    print(requested)
else:
    booted = [device for device in iphones if device["state"] == "Booted"]
    if len(booted) != 1:
        print("Set TEST_DESTINATION to an available iPhone simulator id; "
              f"found {len(booted)} booted iPhones.", file=sys.stderr)
        for device in iphones:
            print(f"  {device['name']} ({device['udid']}) [{device['state']}]", file=sys.stderr)
        sys.exit(2)
    print(f"platform=iOS Simulator,id={booted[0]['udid']}")
PY
); then
  exit 2
fi

printf 'Simulator: %s\n' "$test_destination"

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
run_check 'lint' scripts/lint.sh
run_check 'build' xcodebuild -quiet -project NarihitosDiary.xcodeproj -scheme NarihitosDiary -destination "$test_destination" -destination-timeout "$simulator_destination_timeout_seconds" -derivedDataPath "$log_dir/DerivedData" CODE_SIGNING_ALLOWED=NO build

run_check 'tests' xcodebuild -quiet -project NarihitosDiary.xcodeproj -scheme NarihitosDiary -destination "$test_destination" -destination-timeout "$simulator_destination_timeout_seconds" -derivedDataPath "$log_dir/DerivedData" -test-timeouts-enabled YES -default-test-execution-time-allowance "$test_execution_timeout_seconds" -maximum-test-execution-time-allowance "$test_execution_timeout_seconds" CODE_SIGNING_ALLOWED=NO test
