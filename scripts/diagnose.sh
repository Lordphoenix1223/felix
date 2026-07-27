#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/Felix.app"
config_file="$HOME/.felix/.env"

echo "Felix diagnostic"
echo "project: $project_dir"
echo "macOS: $(sw_vers -productVersion)"
echo "swift: $(swift --version | head -1)"
echo "developer dir: $(xcode-select -p 2>/dev/null || echo unavailable)"

spotlight_status="$(mdutil -s / 2>&1 || true)"
if [[ "${CODEX_CI:-}" == "1" ]]; then
  echo "spotlight: unavailable from the Codex sandbox; verify in standalone Terminal"
elif [[ "$spotlight_status" == *"disabled"* ]]; then
  echo "spotlight: DISABLED (LaunchServices cannot scan local app bundles)"
  echo "fix: sudo mdutil -i on / && sudo mdutil -E /"
else
  echo "spotlight: $spotlight_status"
fi

if [[ -x "$app_dir/Contents/MacOS/Felix" ]]; then
  echo "bundle: present"
  codesign --verify --deep --strict "$app_dir"
  echo "signature: valid"
else
  echo "bundle: missing (run ./scripts/build-app.sh)"
fi

if [[ -f "$config_file" ]]; then
  echo "config: $config_file present"
  for key in NVIDIA_API_KEY COMPOSIO_API_KEY; do
    if grep -Eq "^[[:space:]]*$key=[^[:space:]]+" "$config_file"; then
      if [[ "$key" == "NVIDIA_API_KEY" ]] && ! grep -Eq '^[[:space:]]*NVIDIA_API_KEY=nvapi-[^[:space:]]+$' "$config_file"; then
        echo "$key: malformed (expected an nvapi-… token; value hidden)"
      else
        echo "$key: present (value hidden)"
      fi
    else
      echo "$key: absent"
    fi
  done
else
  echo "config: missing; Felix will run in demo mode"
fi

echo "permissions: approve Screen Recording, Accessibility, Microphone, and Speech Recognition in System Settings"
