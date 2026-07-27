# Open-source readiness plan

Felix should not be published merely because it builds. The minimum credible release is a reproducible, privacy-safe screen lens with honest feature boundaries.

## Keep in the public repository

- Swift/AppKit shell and menu-bar lifecycle
- ScreenCaptureKit and still-capture fallback
- Accessibility and Vision OCR extraction
- rectangle selection and pointer overlay
- deterministic local answer/action routing
- provider adapters and `.env.example`
- typed action schemas and policy checks
- synthetic screen fixtures and regression tests
- clean build, install, signing, and permission documentation

## Keep out

- NVIDIA, Composio, or any other real credentials
- Composio connection identifiers and personal user IDs
- `felix-launch.log`, crash reports, private context files, screenshots, and memory databases
- personal prompts, private project context, or account-specific fixtures
- proprietary model weights or copied code without compatible licensing

## Required before publishing

1. Initialize a fresh Git repository and verify the first commit with a secret scanner.
2. Add a license, security policy, contribution guide, code of conduct, changelog, and issue templates.
3. Replace account-specific absolute paths in docs and scripts with `$HOME`-relative or discovered paths.
4. Add a clean-machine setup flow that explains Screen Recording, Accessibility, Microphone, and Speech Recognition without requiring Xcode.
5. Add a fixture harness for foreground app, Accessibility tree, OCR, pointer selection, and browser metadata.
6. Add negative tests: no match, ambiguous match, stale overlay, stale speech callback, duplicate action, missing key, timeout, cancelled action, and prompt injection in screen text.
7. Add a release workflow that runs Swift tests, shell syntax checks, secret scanning, dependency scanning, and artifact checks.
8. Publish a capability matrix that separates working, experimental, and planned features.

## What the research changes

OpenClicky demonstrates the useful product shape: menu-bar residency, push-to-talk, screen context, local adapters, and a drawn cursor. BrowserGym and OSWorld demonstrate that the difficult part is grounding and verification, not generating a more confident sentence. Recent GUI-grounding work also shows that a planner plus a separate grounded target resolver is more reliable than asking one multimodal model to both reason and click. Felix should therefore keep a deterministic evidence layer in front of the model and a verification layer after every action.

## Public release definition

Do not call Felix a Clicky replacement until these workflows pass on a clean Mac twice each:

- identify the foreground app;
- answer a selected-region question;
- find one exact accessible control and draw exactly one pointer;
- refuse to draw when the target is missing or ambiguous;
- open one allowlisted site exactly once;
- close one matching browser tab exactly once;
- cancel a plan without executing it;
- recover from timeout, speech cancellation, and stale overlay state.
