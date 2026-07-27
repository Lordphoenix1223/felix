# Felix public-release checklist

This is the gate for publishing Felix as an honest open-source v0.1. It is not a claim that Felix is a finished Clicky replacement.

## Top 10 remaining work items

1. **Create a clean Git history.** Initialize Git in this source tree, inspect the first commit, and make sure generated files, personal logs, screenshots, local model folders, and secrets are absent.
2. **Run the publication audit.** Use `scripts/public-audit.sh`, then independently inspect the staged file list. A scanner is a backstop, not proof.
3. **Prove dependency provenance.** Record licenses for every vendored or downloaded component. Keep Kokoro weights and private virtual environments out of the public tree unless their redistribution terms are explicitly verified.
4. **Make CI reproducible.** CI must run Swift tests, shell syntax checks, the public audit, and a production build. It must not require NVIDIA, Composio, microphone, Accessibility, or Screen Recording credentials.
5. **Document a clean-Mac setup.** Explain macOS version, permissions, BYOK variables, first launch, reset/recovery, and the fact that ad-hoc signing is for development only.
6. **Separate source release from app distribution.** A downloadable app should use Developer ID signing, hardened runtime, notarization, Gatekeeper testing, and a checksum. The current local ad-hoc build is not that release artifact.
7. **Expand deterministic GUI fixtures.** Cover foreground-app priority, exact target, no target, ambiguous target, one overlay only, stale overlay cancellation, duplicate action prevention, and browser tab matching.
8. **Publish an honest capability matrix.** Label each feature working, experimental, or planned. Do not market arbitrary computer control, DaVinci editing, unrestricted clicking, or full undo as finished.
9. **Finish contributor and security operations.** Add issue templates, code of conduct, security-reporting instructions, a review policy, and a release/versioning policy. The basic documents exist; they need a final consistency pass after the repo is initialized.
10. **Prepare the GitHub presentation.** Add a strong description, topics, social preview, screenshots/GIF, a 60-second demo script, and a profile-project entry only after the source and app gates pass.

## Publish gate

Felix is **not ready to promote publicly as a working Clicky-level product today**. The source is close to publishable as an experimental v0.1, but two hard proofs are still missing: a clean Git/public-scrub pass and a real normal-Terminal/Finder GUI verification on a clean Mac. Notarized distribution is also required before distributing a polished app download.

## Required verification matrix

Run each test twice on a clean user session:

- foreground application is identified instead of the desktop wallpaper;
- selected rectangle is captured and answered;
- one exact Accessibility/OCR target produces exactly one pointer;
- missing and ambiguous targets produce no pointer;
- opening an allowlisted site happens once, not repeatedly;
- matching browser tab closes once, with no false “not visible” result;
- confirmation remains attached to the original action and expires safely;
- cancel, timeout, stale speech, and stale overlay leave Felix idle;
- no provider key is required for local tests;
- voice output stays disabled when the local preference says text-only.
