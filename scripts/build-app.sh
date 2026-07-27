#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

mkdir -p /tmp/felix-swiftpm-config /tmp/felix-module-cache
SWIFT_PACKAGE_CONFIG_DIR=/tmp/felix-swiftpm-config \
SWIFT_MODULECACHE_PATH=/tmp/felix-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/felix-module-cache \
swift build -c release --disable-sandbox
app_dir="$project_dir/dist/Felix.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/Felix "$app_dir/Contents/MacOS/Felix"
cp Info.plist "$app_dir/Contents/Info.plist"
printf 'APPL????' > "$app_dir/Contents/PkgInfo"
chmod +x "$app_dir/Contents/MacOS/Felix"
codesign --force --deep --sign - "$app_dir" >/dev/null
echo "Built $app_dir"

installed_dir="${FELIX_INSTALL_DIR:-$HOME/Applications}"
installed_app="$installed_dir/Felix.app"
if [[ -d "$installed_dir" && -w "$installed_dir" ]]; then
  ditto "$app_dir" "$installed_app"
  cp Launch-Felix.command "$installed_dir/Launch-Felix.command"
  chmod +x "$installed_dir/Launch-Felix.command"
  echo "Installed canonical Felix bundle at $installed_app"
  echo "Installed one-click fallback launcher at $installed_dir/Launch-Felix.command"
else
  echo "Canonical install skipped: $installed_dir is not writable in this shell. Set FELIX_INSTALL_DIR to the user's Applications folder when packaging from a sandbox." >&2
fi
