#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
config_dir="$HOME/.felix"
config_file="$config_dir/.env"

mkdir -p "$config_dir"
if [[ ! -f "$config_file" ]]; then
  cp "$project_dir/.env.example" "$config_file"
  chmod 600 "$config_file"
fi

echo "Felix provider setup (your key is never displayed or sent to this script's output)."
echo "1) meta/llama-3.2-90b-vision-instruct — verified vision default"
echo "2) minimaxai/minimax-m3 — alternate multimodal reasoning endpoint"
echo "3) moonshotai/kimi-k2.6 — available in the catalog, but may require a separate NVIDIA function entitlement"
read -r -p 'Choose NVIDIA model [1]: ' model_choice
case "${model_choice:-1}" in
  2) nvidia_model="minimaxai/minimax-m3" ;;
  3) nvidia_model="moonshotai/kimi-k2.6" ;;
  *) nvidia_model="meta/llama-3.2-90b-vision-instruct" ;;
esac

while true; do
  printf 'NVIDIA API key (input hidden, required for real answers): '
  read -r -s nvidia_key
  printf '\n'
  if [[ "$nvidia_key" == nvapi-* && "$nvidia_key" != *[[:space:]]* ]]; then
    break
  fi
  echo "That does not look like an NVIDIA nvapi-... key. Nothing was saved; try again."
done
sed -i '' '/^NVIDIA_API_KEY=/d; /^NVIDIA_MODEL=/d' "$config_file"
printf 'NVIDIA_API_KEY=%s\n' "$nvidia_key" >> "$config_file"
printf 'NVIDIA_MODEL=%s\n' "$nvidia_model" >> "$config_file"

printf 'Composio project key (input hidden, optional; press Return to skip): '
read -r -s composio_key
printf '\n'
if [[ -n "$composio_key" ]]; then
  sed -i '' '/^COMPOSIO_API_KEY=/d' "$config_file"
  printf 'COMPOSIO_API_KEY=%s\n' "$composio_key" >> "$config_file"
fi

chmod 600 "$config_file"
echo "Saved Felix configuration to $config_file (model: $nvidia_model; key was not printed)."
echo "Run ./scripts/diagnose.sh to verify presence without revealing values."
