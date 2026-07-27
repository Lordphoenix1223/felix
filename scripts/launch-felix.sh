#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve one bundle deterministically. Never accept a sibling such as
# "Felix 2.app": that can silently start an older privacy identity.
if [[ -n "${FELIX_APP_PATH:-}" ]]; then
  app="$FELIX_APP_PATH"
elif [[ -x "$HOME/Applications/Felix.app/Contents/MacOS/Felix" ]]; then
  app="$HOME/Applications/Felix.app"
else
  app="$project_dir/dist/Felix.app"
fi

if [[ ! -x "$app/Contents/MacOS/Felix" ]]; then
  echo "Felix.app is not built yet. Run ./scripts/build-app.sh first." >&2
  exit 1
fi

if [[ "${FELIX_EMBEDDED_CODEX:-}" == "1" || "${CODEX_SHELL:-}" == "1" || "${__CFBundleIdentifier:-}" == "com.openai.codex" ]]; then
  echo "Embedded Codex launch detected; use Launch-Felix.command from Finder or a normal Terminal.app session."
  exit 4
fi

# Spotlight is not a Felix dependency. Older recovery logic incorrectly made
# an unrelated indexing state a hard launch blocker; retain it only as context.
spotlight_status="$(/usr/bin/mdutil -s / 2>/dev/null || true)"
if [[ "$spotlight_status" == *"server is disabled"* || "$spotlight_status" == *"Indexing disabled"* ]]; then
  echo "Note: Spotlight indexing is disabled; Felix does not require Spotlight and will still launch."
fi

echo "Launching Felix from $app"
echo "Do not paste NVIDIA JSON into this terminal. Felix reads ~/.felix/.env itself."
log_file="$project_dir/felix-launch.log"
rm -f /tmp/felix-started

# Avoid leaving an older menu-bar instance competing with the new bundle.
# This is intentionally a normal graceful termination; if no Felix process
# exists, continue without treating that as an error.
/usr/bin/killall Felix >/dev/null 2>&1 || true
sleep 0.5

# Launch through LaunchServices. Directly executing the Mach-O from a host
# process is the failure mode observed in the Codex embedded environment.
/usr/bin/open -n "$app" >/tmp/felix-open.log 2>&1 || true
sleep 3

# In some macOS/Codex environments LaunchServices returns success while
# refusing an ad-hoc bundle with kLSNoExecutableErr. If no Felix process and
# no startup marker exist, use the executable only as a controlled fallback.
# This makes the failure observable and keeps normal Terminal/Finder launches
# independent of the embedded Codex process coalition.
if [[ ! -f /tmp/felix-started ]] && ! /usr/bin/pgrep -x Felix >/dev/null 2>&1; then
  echo "LaunchServices did not start Felix; trying the verified executable fallback."
  nohup "$app/Contents/MacOS/Felix" >>"$log_file" 2>&1 </dev/null &
  sleep 3
fi

if [[ -f /tmp/felix-started ]]; then
  echo "Felix reached application startup. Look for the FELIX menu item."
else
  echo "Felix did not reach application startup, so no menu item can appear."
  echo "Last launch output:"
  cat /tmp/felix-open.log 2>/dev/null || true
  tail -n 20 "$log_file" 2>/dev/null || true
  echo "Full log: $log_file"
  echo "If this repeats, use Launch-Felix.command from Finder and inspect the newest Felix crash report; do not reset the machine-wide LaunchServices database."
  exit 2
fi
