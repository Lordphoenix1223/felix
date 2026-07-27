#!/bin/zsh
set -u

base_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$base_dir/Felix.app"
marker="/tmp/felix-started"
log_file="/tmp/felix-launch.log"
if [[ ! -x "$app_dir/Contents/MacOS/Felix" && -x "$base_dir/dist/Felix.app/Contents/MacOS/Felix" ]]; then
  app_dir="$base_dir/dist/Felix.app"
fi
if [[ ! -x "$app_dir/Contents/MacOS/Felix" ]]; then
  echo "Felix.app is missing or not executable in $base_dir"
  exit 1
fi

# Never launch a sibling copy such as “Felix 2.app”. This launcher is deliberately
# self-verifying because a successful `open` command does not prove AppKit started.
echo "Launching Felix from $app_dir"
# Stop stale Felix copies first. Multiple copies each install global monitors
# and can duplicate one request into many browser opens/target overlays.
/usr/bin/killall Felix >/dev/null 2>&1 || true
sleep 0.4
if [[ -e "$marker" ]]; then
  /bin/mv "$marker" "$marker.stale.$$"
fi
: > "$log_file"

# LaunchServices is the preferred path because it gives macOS the normal privacy
# identity. The executable fallback is only used when the startup marker is absent.
/usr/bin/open "$app_dir" >>"$log_file" 2>&1 || true
for _ in {1..12}; do
  [[ -f "$marker" ]] && break
  sleep 0.25
done

if [[ ! -f "$marker" ]]; then
  echo "LaunchServices did not start Felix; using the canonical executable fallback."
  nohup "$app_dir/Contents/MacOS/Felix" >>"$log_file" 2>&1 </dev/null &
  for _ in {1..12}; do
    [[ -f "$marker" ]] && break
    sleep 0.25
  done
fi

if [[ -f "$marker" ]]; then
  echo "Felix reached application startup. Look for FELIX in the menu bar."
  exit 0
fi

echo "Felix did not reach application startup."
echo "Launch log: $log_file"
tail -n 20 "$log_file" 2>/dev/null || true
exit 2
