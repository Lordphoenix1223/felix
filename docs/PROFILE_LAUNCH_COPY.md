# Felix profile and launch materials

These are prepared copy blocks. They should be used only after the public-release checklist passes.

## Repository description

> Felix — a privacy-first, BYOK macOS screen companion with push-to-talk, rectangle selection, Accessibility/OCR context, and verified visual guidance.

## Short profile blurb

> I’m building Felix, an open-source macOS screen companion that lets you hold a hotkey, ask about the screen, and receive grounded answers or visual guidance without continuously watching the desktop.

## README opening paragraph

> Felix is a native macOS experiment for asking focused questions about the screen. It stays in the menu bar, captures context only after an explicit trigger, combines ScreenCaptureKit with Accessibility and Vision OCR evidence, and keeps actions bounded and confirmation-aware. Felix is BYOK and does not ship provider credentials.

## Suggested topics

`macos`, `swift`, `appkit`, `screencapturekit`, `accessibility`, `vision-ocr`, `screen-reader`, `voice-interface`, `ai-assistant`, `byok`, `privacy-first`, `computer-use`

## 60-second demo script

1. Launch Felix from a normal macOS Terminal.
2. Hold the configured hotkey and ask: “what application is in front of me?”
3. Hold the selection hotkey, draw one rectangle around a visible control, and ask a short question.
4. Ask “where is the new chat button?” on a screen that actually contains one; show exactly one pointer or an honest no-match response.
5. Ask Felix to open one allowlisted site; show the bounded action and verification.
6. Show that voice output is off, keys are local, and screen context is not continuously stored.

## GitHub profile project entry

**Felix — native macOS screen companion**

Push-to-talk screen context, rectangle selection, Accessibility/OCR grounding, and safe visual guidance. Open-source v0.1; arbitrary computer control remains deliberately constrained.
