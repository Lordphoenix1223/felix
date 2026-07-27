# Contributing to Felix

Felix is an experimental v0.1. Contributions are welcome once a change has a focused scope, a regression test, and a clear privacy/safety impact. Felix is not presented as a finished Clicky replacement.

## Development rules

1. Keep provider adapters replaceable and BYOK. Never add a real key to source, fixtures, screenshots, logs, or pull requests.
2. Keep screen context ephemeral by default. Tests must use synthetic fixtures or redacted captures.
3. Prefer Accessibility-tree actions and browser DOM actions over pixel guesses.
4. Every pointer must cite its evidence source and coordinates. No evidence means no pointer.
5. Every side effect needs a typed action, a policy decision, a visible confirmation, cancellation, and post-action verification.
6. Add a regression test before fixing a repeated-answer, duplicate-overlay, duplicate-action, or stale-permission bug.

## Validation

```bash
SWIFT_MODULECACHE_PATH=/tmp/felix-swift-cache \
CLANG_MODULE_CACHE_PATH=/tmp/felix-clang-cache \
swift test --disable-sandbox
./scripts/build-app.sh
./scripts/diagnose.sh
```

The final GUI check must be performed from a normal macOS Terminal or Finder, not inferred from a sandboxed Codex process.
