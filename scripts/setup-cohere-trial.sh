#!/bin/bash
set -euo pipefail

runtime_version='0.2.4'
archive_sha256='243e96ea569583245c9732de3955111210d986c03a34b81424dacde169f9de6a'
archive_url="https://github.com/handy-computer/transcribe.cpp/releases/download/v${runtime_version}/TranscribeCpp.xcframework.zip"
script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
vendor_dir="$repository_root/Trials/CohereRuntimeTrial/Vendor"
archive_path="$vendor_dir/TranscribeCpp.xcframework.zip"
config_dir="$repository_root/Trials/CohereRuntimeTrial/Configs"
config_path="$config_dir/Local.xcconfig"

mkdir -p "$vendor_dir"

if [[ ! -f "$archive_path" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 \
    --output "$archive_path" "$archive_url"
fi

actual_sha256=$(shasum -a 256 "$archive_path" | awk '{print $1}')
if [[ "$actual_sha256" != "$archive_sha256" ]]; then
  printf 'XCFramework checksum mismatch: expected %s, got %s\n' \
    "$archive_sha256" "$actual_sha256" >&2
  exit 1
fi

# Refresh the framework from the verified archive on every setup so an old or
# locally modified extraction is never silently reused.
ditto -x -k "$archive_path" "$vendor_dir"

revision=$(git -C "$repository_root" rev-parse --short=12 HEAD)
if [[ -n "$(git -C "$repository_root" status --porcelain)" ]]; then
  revision="${revision}-dirty"
fi
mkdir -p "$config_dir"
printf 'TRIAL_BUILD_REVISION = %s\n' "$revision" >"$config_path"
printf 'TRANSCRIBE_ARTIFACT_SHA256 = %s\n' "$archive_sha256" >>"$config_path"

printf 'Ready: transcribe.cpp v%s (%s), trial revision %s\n' \
  "$runtime_version" "$archive_sha256" "$revision"
