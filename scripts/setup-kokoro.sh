#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
install_dir="$HOME/.felix/bin"
install_path="$install_dir/kokoro"
source_dir="$project_dir/.vendor/kokoro-coreml"

mkdir -p "$install_dir"

if [[ ! -d "$source_dir/.git" ]]; then
  mkdir -p "$project_dir/.vendor"
  git clone https://github.com/jud/kokoro-coreml "$source_dir"
fi

swift build --disable-sandbox -c release --package-path "$source_dir" --product kokoro
cp "$source_dir/.build/arm64-apple-macosx/release/kokoro" "$install_path"
chmod 755 "$install_path"

echo "Installed free local Kokoro voice backend at $install_path"
echo "The approximately 99 MB model downloads automatically on first speech."
echo "Default voice: af_heart; override with FELIX_KOKORO_VOICE."
