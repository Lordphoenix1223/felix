# Felix roadmap and engineering notes

This is an internal pre-release roadmap. It is not a claim of Clicky parity. Every feature should be backed by a reproducible workflow and a fixture-backed test before it is marketed.

## What “near the camera” means on macOS

The macOS Dock is normally the bottom or side launcher. The surface near the camera/notch is the menu bar. Felix now uses an `NSStatusItem`, which is the native AppKit primitive for a menu-bar control. Clicking the Felix symbol exposes a “Talk about current screen” action; responses appear in a floating panel near the top of the screen.

Apple reference: [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem).

Felix should not try to draw inside the camera notch or impersonate a system control. The stable product behavior is a small menu-bar status item plus a floating, notch-adjacent voice bubble.

## NVIDIA model choice

Felix currently defaults to `meta/llama-3.2-90b-vision-instruct`, a configurable NVIDIA multimodal endpoint. NVIDIA model availability and quotas change, so `NVIDIA_MODEL` remains configurable and the setup script asks users to choose the model rather than assuming a universal endpoint.

## Implemented in this pass

- Multi-monitor rectangle overlays across every `NSScreen`.
- Persistent local conversation memory in Application Support, capped to recent turns.
- Recent conversation memory is included in the model context, not uploaded as a separate database.
- Floating response/status panel near the top-center of the main display.
- Menu-bar entry to ask Felix about the current screen without drawing a rectangle first.
- Swift Package Manager build/test path; Xcode does not need to stay open.
- Immediate listening feedback, partial transcript, Apple on-device recognition preference, and a visible engine label.
- Cancel/Stop/X interruption, stale-turn cancellation, bounded request timeout, and shorter voice response budget.
- Persistent selection rectangle plus a separate drawn pointer overlay that never moves the user's real mouse.
- Lazy Composio sessions so an invalid optional integration cannot block screen Q&A at startup.
- Clear provider errors instead of misclassifying every provider failure as a Composio failure.

These ten UX/reliability decisions are the current quality floor: (1) show system status immediately, (2) show live speech, (3) prefer private on-device transcription, (4) keep the selected target visible, (5) make interruption obvious, (6) cancel stale turns, (7) keep optional integrations lazy, (8) bound network latency, (9) keep spoken answers short, and (10) explain the real failing subsystem. They follow Apple's feedback/popover guidance and Nielsen Norman's visibility, user-control, error-prevention, and recognition-over-recall heuristics.

## Upgrade sequence

### 1. Make capture semantically precise

The current rectangle sends a rectangular crop. The next version should send three synchronized signals:

1. The crop image.
2. A mask representing the actual selection shape.
3. Accessibility/OCR text found inside the region.

For accessible apps, `AXUIElement` can expose UI hierarchy, position, role, text, and actions. Apple documents it as the mechanism assistive applications use to communicate with and control accessible apps: [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h).

Fallback order:

1. Accessibility text and element metadata.
2. Local Vision OCR.
3. Vision model interpretation of the image.

Do not claim exact semantic selection when only a bounding box was captured.

### 2. Replace one-shot memory with a durable local context model

The current JSON store is intentionally simple and private. The next step is a small local database with:

- conversations
- turns
- decisions
- people/projects
- source references
- user-approved facts

Only retrieved, relevant memory should be sent to NVIDIA. Felix should show which memory it used and provide “forget this” controls. A local SQLite/SwiftData store is preferable to a server for the first open-source release.

### 3. Upgrade capture to ScreenCaptureKit

The current `CGDisplayCreateImage` path is adequate for a still crop. ScreenCaptureKit is the better long-term capture layer because Apple provides display, app, and window objects plus fine-grained filters: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit).

Use it when Felix needs:

- window-aware capture
- excluding Felix itself
- multiple displays with stable coordinates
- live cursor/selection previews
- future audio/video context

Keep still-image capture as the low-memory fallback.

### 4. Add controlled browser and desktop actions

There are three action tiers:

- Tier 0: speak, summarize, remember, draft. No confirmation required.
- Tier 1: copy, open, navigate, create a local note. Confirm on first use per session.
- Tier 2: send, publish, delete, edit records, spend money, or change permissions. Always confirm immediately before execution.

Composio remains the integration/action layer for connected services. `AXUIElement` is the local macOS control layer. Felix should not begin with unconstrained mouse/keyboard injection; that is fragile, hard to explain, and dangerous when the model misunderstands a screen.

### 5. Make the voice surface feel like a product

The desired interaction is:

1. Click Felix in the menu bar near the camera/notch.
2. See a small popover with microphone state, recent answer, and “Talk about current screen.”
3. Speak naturally.
4. Watch live status: Listening → Thinking → Speaking → Waiting for confirmation.
5. Interrupt speech or cancel the action from the popover.

The current panel is the first slice of that experience. The next implementation should add a real popover, waveform/microphone indicator, cancel button, and a short transcript.

## Time and effort estimate

- Current v0.1 plus this upgrade slice: already implemented.
- Semantic capture and OCR: roughly 1–2 focused days.
- Real popover and interruption controls: roughly 1 day.
- Local memory v1 with retrieval and forget controls: roughly 2–4 days.
- Safe browser/desktop action layer: roughly 4–7 days for a narrow, testable allowlist; much longer for broad arbitrary control.
- Reliable distribution, permissions, signing, and regression testing: roughly 2–5 days.

The hard part is not calling the model. The hard part is trustworthy context selection, action boundaries, permissions, cancellation, and not acting on the wrong thing.

## No-Xcode workflow

Felix can be edited, tested, built, packaged, and ad-hoc signed with Swift Package Manager and the scripts in this repository:

```bash
swift test --disable-sandbox
./scripts/build-app.sh
./scripts/diagnose.sh
```

Xcode can remain closed. Its toolchain is still selected by `xcode-select`, but the Xcode application does not need to consume memory during development.
