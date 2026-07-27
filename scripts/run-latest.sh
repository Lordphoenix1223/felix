#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

if [[ "${FELIX_EMBEDDED_CODEX:-}" == "1" || "${CODEX_SHELL:-}" == "1" || "${__CFBundleIdentifier:-}" == "com.openai.codex" ]]; then
  echo "Run this from the normal macOS Terminal.app, not the embedded Codex terminal." >&2
  exit 4
fi

./scripts/build-app.sh
FELIX_APP_PATH="$project_dir/dist/Felix.app" ./scripts/launch-felix.sh
