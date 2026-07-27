#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$project_dir/dist/Felix.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ ! -x "$lsregister" ]]; then
  echo "LaunchServices repair tool was not found at the expected macOS path." >&2
  exit 1
fi

if [[ ! -d "$app" ]]; then
  echo "Felix.app is not built at $app. Run ./scripts/build-app.sh first." >&2
  exit 1
fi

echo "Repairing Felix's LaunchServices registration (safe mode)."
# macOS 26 removed -kill. Repair only this bundle instead of touching all apps.
"$lsregister" -u "$app" 2>/dev/null || true
"$lsregister" -f -R "$app"
killall Finder 2>/dev/null || true
echo "Felix registration repaired. Run ./scripts/launch-felix.sh again."
echo "If Felix still crashes before startup, launch it from Finder using Launch-Felix.command; do not reset the machine-wide LaunchServices database."
