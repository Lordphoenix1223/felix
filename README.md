# Felix

Felix is a small, open-source, macOS-first screen lens:

1. Hold Option, or choose **Select a region** from the FELIX menu.
2. Drag over anything on screen.
3. Speak a question.
4. Felix sees the selected region, answers in text by default, and can optionally act through verified local actions or Composio.

Felix is deliberately BYOK and local-first. The application itself has no payment wall and no bundled credentials. It works in demo mode without any API key and uses NVIDIA's OpenAI-compatible API when `NVIDIA_API_KEY` is present. Verified local actions (such as opening allowlisted sites and matching browser tabs) can execute after confirmation; unknown Composio actions remain blocked unless their connector and policy are available.

The intended interaction is a fast, one-shot “screen conversation”: hold Option and drag a visible rectangle, or use **Option-F** / **Select a region** as a fallback. The rectangle stays visible while Felix listens; a separate pointer overlay can mark the model's returned target without moving your real mouse. After release, Felix reasons over the crop plus your project context, shows a concise answer, and asks before taking an external action. This release is text-only and never speaks. This is a bounded screen lens, not yet a general-purpose autonomous desktop controller.

## Repository map

- `Sources/Felix/`: native AppKit application and provider/action adapters.
- `Tests/FelixTests/`: deterministic routing, safety, and targeting tests.
- `docs/SCREEN_GROUNDING.md`: the evidence contract for screen-aware pointers.
- `docs/OPEN_SOURCE_READINESS.md`: the public-release checklist and exclusions.
- `ROADMAP.md`: product gaps and engineering order.
- `scripts/`: repeatable setup, diagnostics, build, and launch helpers.

## What is implemented

- Global Option-key activation.
- A full-screen selection overlay with a visible crosshair and editable rectangle selection.
- Cropped screenshot capture of only the selected region.
- Multi-monitor selection overlays.
- Local speech recognition using Apple's Speech framework. Felix only listens after explicit Option/selection activation and resets recognition between turns.
- Immediate LISTENING / THINKING / SPEAKING status, live partial transcript, and Cancel/Stop controls.
- Text-only responses in this build. Speech output is hard-disabled; the response card is the source of truth.
- Accessibility context from the focused/frontmost UI element when Accessibility permission is granted.
- Local Vision OCR over the captured image.
- Persistent local conversation memory with a forget control.
- Native, readable menu-bar popover with live Felix state and current-screen voice entry.
- NVIDIA multimodal chat adapter with a strict internal action envelope.
- Composio v3.1 session, tool search, and guarded execution adapter.
- A tiny allowlisted local action surface: copy selection context and open an explicit HTTP(S) URL.
- A safety hold for unknown actions; verified local actions require explicit confirmation.
- Demo mode that explains missing configuration instead of failing silently.

## The agent model

Felix has an agent-shaped decision loop, but it is intentionally bounded:

1. Capture only the user-drawn rectangle.
2. Add the optional `FELIX_CONTEXT_FILE` and request-specific Composio tool candidates.
3. Ask the NVIDIA vision model for a concise answer plus an optional structured action.
4. Render the answer in the response card; no voice output is produced.
5. Show a confirmation dialog before any Composio side effect.
6. Execute only the confirmed allowlisted tool call and render a short result.

The current version has a rectangle selection overlay and an independent drawn pointer/halo; it does not move the real mouse, click unknown webpages, or execute arbitrary shell commands. Composio is the action boundary. That constraint is deliberate: “anything on any page” is not a safe or reliable promise without a separate browser/desktop control layer.

For location questions, Felix may draw a pointer only when the foreground app's Accessibility tree or OCR contains a matching control with coordinates. If evidence is missing or ambiguous, Felix says it could not verify the target and draws nothing. A generic model phrase such as “look here” is never sufficient evidence.

## Requirements

- macOS 13 or newer.
- Swift 6 toolchain. Full Xcode is recommended for packaging and signing, but Swift Package Manager can build the executable with the command-line tools.
- Screen Recording permission.
- Accessibility permission for the global Option shortcut.
- Microphone and Speech Recognition permission for voice input.

## Run

```bash
./scripts/setup-config.sh
./scripts/build-app.sh
./scripts/launch-felix.sh
```

Do not paste an NVIDIA `curl` payload, Python dictionary, or HTTP headers directly into zsh. Those are data, not shell commands; Felix performs the request internally after reading `~/.felix/.env`.

For the packaged build, use the single canonical bundle at `~/Applications/Felix.app`. The build script syncs this installed copy from `dist/Felix.app`; do not launch older Felix copies elsewhere under `~/Documents/Codex`.

Felix looks for configuration in `~/.felix/.env` first. That is the recommended location for Finder-launched use. During development it also accepts `.env` beside the bundle or in the current working directory.

The app starts as a menu-bar application. Hold Option and drag over a region. Felix then listens for one spoken question. If speech recognition is unavailable, a small text prompt is used as a fallback.

On macOS 26, if double-clicking `Felix.app` is rejected by LaunchServices before the app starts, double-click `Launch-Felix.command` in the same Applications folder. It starts the same signed Felix binary through a normal Terminal session and avoids that operating-system registration bug.

To use NVIDIA, generate a key from NVIDIA Build and set the resulting single NVIDIA key as `NVIDIA_API_KEY` in `~/.felix/.env`. No separate vision, OCR, speech, or embedding key is required: Felix uses the selected NVIDIA vision model for image reasoning, Apple Vision for local OCR, and Apple Speech for local transcription. Felix now defaults to [`meta/llama-3.2-90b-vision-instruct`](https://build.nvidia.com/meta/llama-3.2-90b-vision-instruct), because the Kimi catalog entry can still return a provider-side “Function not found for account” error even when the model appears in `/v1/models`. Availability and quotas can change.

Kokoro remains an optional future voice backend, but this release does not speak even when it is installed. That is intentional until interruption, cancellation, and state-reset behavior are reliable.

To enable integrations, create a Composio project key and set `COMPOSIO_API_KEY` and `COMPOSIO_USER_ID`. Felix creates a scoped Composio tool-router session for that user, searches tools from the spoken request, and only executes after the model marks the action as requiring confirmation and the user presses the confirmation button.

## First-use checklist

1. Run `./scripts/setup-config.sh`; choose the NVIDIA model and enter the key when prompted. The key is hidden and stored at `~/.felix/.env` with mode 600.
2. Build with `./scripts/build-app.sh`.
3. From Finder, double-click `Launch-Felix.command` (or use `./scripts/launch-felix.sh` from a normal Terminal, never Codex's embedded terminal).
4. Felix requests the available permissions and offers an **OPEN PERMISSIONS** button for anything macOS still requires.
5. Hold Option, draw a visible rectangle, and ask a short question.

For a deterministic normal-Terminal launch from Codex, run:

```bash
osascript -e 'tell application "Terminal" to do script "exec $HOME/Applications/Felix.app/Contents/MacOS/Felix"'
```

Quit an older Felix instance first if one is already running. This avoids the macOS 26 AppKit startup crash observed when a menu-bar app is launched inside Codex's embedded process environment.

macOS 26 can abort AppKit GUI initialization when Felix is launched from Codex's embedded shell. Launch Felix from a normal Terminal session instead; the `Launch-Felix.command` helper below makes that a double-click.

If you are using Codex's embedded terminal, double-click `Launch-Felix.command` in Finder. It opens a normal Terminal session and asks macOS LaunchServices to open Felix through the normal GUI path.

If NVIDIA is blank or malformed, the UI and capture path can still be exercised, but the response is demo text rather than model reasoning. Felix recognizes NVIDIA's `nvapi-…` key shape and reports a setup error instead of making a doomed request. No provider key can be shipped in an open-source repository.

If the launcher reports that Felix did not reach application startup, launch the canonical bundle from Finder and inspect the newest Felix crash report. Do not delete the machine-wide LaunchServices database; that can damage unrelated application associations.

```bash
./scripts/reset-launchservices.sh
./scripts/launch-felix.sh
```

The repair script only unregisters and re-registers Felix's bundle. It does not perform a machine-wide reset.

## Open-source release plan

The open release should keep the inspectable core: Swift/AppKit, ScreenCaptureKit capture, Vision OCR, Accessibility-tree extraction, rectangle and pointer overlays, local routing, provider adapters, action schemas, fixtures, and end-to-end tests. It should ship with `.env.example`, no credentials, no telemetry by default, local-only conversation storage, and a clear permission screen.

It should not include anyone else's API key, Composio connection, private context files, personal logs, or bundled proprietary model weights. Provider integrations should be optional adapters with explicit scopes. The default action policy should remain allowlisted, confirmation-based, interruptible, and auditable; “full computer control” should be an opt-in experimental profile, not the default.

The next community milestones should be measured rather than marketed: clean-screen capture that excludes Felix's own UI, exact Accessibility/OCR target selection, browser DOM context, one plan/execute/verify loop, pause/stop, action history, and fixture-based tests for each supported workflow. BrowserGym and OSWorld are useful external references because computer use fails at grounding, dynamic state, and long-horizon verification—not merely at generating better prose. Felix should publish a small macOS workflow suite and pass/fail traces before claiming Clicky parity.

## Open-source key model

Real keys never belong in the repository. Open-source projects generally do this:

- Commit `.env.example` with blank values.
- Ignore `.env`.
- Read keys from environment variables or the macOS Keychain.
- Fail gracefully when keys are absent.
- Let each user bring their own provider account and accept the provider's terms and quotas.

Do not publish, pool, rotate, or share an “unlimited” key. If “Creo Unlimited” refers to a paid or subscription credential, it cannot legally or safely be bundled into an open-source project. Leave the configuration blank and let users provide their own key.

## Safety boundary

Felix can answer without a key in demo mode. It never silently performs side-effecting actions. Drafting and reading are lower-risk; sending, deleting, publishing, changing records, or creating external objects require an explicit confirmation button. The screenshot is cropped locally before it is sent to NVIDIA.

## Current limitations

- The rectangle overlay now opens on every display, but the crop sent to the vision model is still rectangular by design. Felix supplements it with OCR and Accessibility context.
- The local action layer is intentionally allowlisted. Felix does not inject arbitrary mouse clicks, keystrokes, shell commands, or browser actions.
- Felix declares `LSUIElement=true` and also sets accessory activation in Swift. The app must be launched through Finder or normal macOS LaunchServices; Codex's embedded GUI launch context is not a valid startup test on macOS 26.
- Apple speech recognition is used for the no-cost local voice path. A later provider adapter can add Whisper or another STT service.
- Composio tool discovery is intentionally scoped to the current request instead of loading every integration into the model context.

## Honest v0.2 performance boundary

Some common requests now bypass NVIDIA entirely. “What application am I using?” is answered from the frontmost macOS application, and a “where/find/show” request is answered locally when OCR or Accessibility already produced an exact target. This removes a remote round trip from the two most latency-sensitive guidance flows. Other visual questions still require the configured NVIDIA endpoint and can still be limited by that provider's latency, availability, and quota.

Felix is not yet a genuine Clicky-equivalent desktop agent. The next required product work is a persistent streaming transcription pill, a structured plan/execute/verify loop, browser DOM actions, safe action history with undo, durable recurring automations, and a real end-to-end GUI test harness. Those are product requirements, not claims that the current recovery build already satisfies.
