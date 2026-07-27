#!/bin/zsh
set -euo pipefail

# Read-only publication audit. It intentionally does not delete, rewrite, or
# upload anything. Run it from the repository root before creating a public
# GitHub repository.
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
failures=0
warnings=0
fail() { print -u2 "FAIL: $1"; failures=$((failures + 1)); }
warn() { print -u2 "WARN: $1"; warnings=$((warnings + 1)); }
ok() { print "OK: $1"; }

for required in README.md LICENSE SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md CHANGELOG.md .env.example; do
  [[ -f "$required" ]] && ok "$required exists" || fail "$required is missing"
done

if [[ -d .git ]]; then
  ok "Git metadata exists"
  if git rev-parse --verify HEAD >/dev/null 2>&1; then ok "at least one commit exists"; else fail "Git repository has no commit"; fi
else
  warn "no .git directory yet; initialize Git before publication"
fi

for local_path in .build dist .DS_Store felix-launch.log .vendor .venv-kokoro .venv-kokoro312; do
  [[ -e "$local_path" ]] && warn "local/generated path present (must remain ignored): $local_path"
done

if command -v rg >/dev/null 2>&1; then
  if rg -n --hidden -g '!.git/**' -g '!dist/**' -g '!.build/**' -g '!.vendor/**' -g '!.venv-*/**' -E 'nvapi-[A-Za-z0-9_-]{20,}|COMPOSIO_API_KEY[=:][^[:space:]#]{24,}' . >/tmp/felix-public-secrets.txt 2>/dev/null; then
    fail "possible credential value found; inspect /tmp/felix-public-secrets.txt"
  else ok "no obvious provider credential values found"; fi
else
  if grep -RIn --exclude-dir=.git --exclude-dir=dist --exclude-dir=.build --exclude-dir=.vendor --exclude-dir=.venv-kokoro --exclude-dir=.venv-kokoro312 -E 'nvapi-[A-Za-z0-9_-]{20,}|COMPOSIO_API_KEY[=:][^[:space:]#]{24,}' . >/tmp/felix-public-secrets.txt 2>/dev/null; then
    fail "possible credential value found; inspect /tmp/felix-public-secrets.txt"
  else ok "no obvious provider credential values found"; fi
fi

if grep -RIn --exclude-dir=.git --exclude=public-audit.sh -E '/Users/[^/]+/|/private/var/|/var/folders/' README.md docs CONTRIBUTING.md SECURITY.md .github scripts context.example.md >/tmp/felix-public-paths.txt 2>/dev/null; then
  fail "personal absolute path found in publication-facing material"
else ok "no personal absolute paths found in publication-facing material"; fi

if [[ -f .gitignore ]] && grep -qE '^dist/?$|^\.build/?$|^\.vendor/?$|^felix-launch\.log$|^\.DS_Store$' .gitignore; then
  ok "generated artifacts are ignored"
else fail ".gitignore does not cover generated artifacts"; fi

if (( failures > 0 )); then
  print -u2 "Publication audit failed: $failures failure(s), $warnings warning(s)."
  exit 1
fi
print "Publication audit passed with $warnings warning(s). Warnings are expected until the repository is cleaned and Git is initialized."
