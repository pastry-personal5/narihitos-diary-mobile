#!/bin/bash
set -euo pipefail

xcode_preferences_path=${NDM_XCODE_PREFERENCES_PATH:-"${HOME}/Library/Preferences/com.apple.dt.Xcode.plist"}
team_listing=''

if [[ -f "$xcode_preferences_path" ]]; then
  team_listing=$(
    /usr/libexec/PlistBuddy \
      -c 'Print :IDEProvisioningTeamByIdentifier' \
      "$xcode_preferences_path" 2>/dev/null || true
  )
fi

development_team=$(
  printf '%s\n' "$team_listing" \
    | awk '/teamID = / { print $3; exit }'
)

if [[ ! "$development_team" =~ ^[A-Z0-9]{10}$ ]]; then
  development_team=''
fi

NDM_DEVELOPMENT_TEAM="$development_team" xcodegen generate --quiet
