# Screen grounding contract

## Evidence pipeline

Felix should build one immutable context snapshot per turn:

```text
activation
  -> foreground app + focused window
  -> global selection rectangle
  -> clean capture excluding Felix overlays
  -> Accessibility candidates
  -> OCR candidates
  -> candidate normalization and ranking
  -> model explanation
  -> typed pointer/action
  -> verification
```

The model may explain evidence, but it may not manufacture evidence. A pointer is valid only when it includes a matching label, a coordinate inside the selected capture, and an evidence source (`accessibility` or `ocr`). Ambiguous candidates must produce a short failure message and no overlay.

## Target ranking

1. Exact Accessibility title/identifier/help on a control role.
2. Exact OCR phrase inside the requested region.
3. Strong synonym match with a unique candidate.
4. Vision-model suggestion only for explanation, never as an unverified pointer.

Reject: Felix's own panels, “target”, “look here”, stale coordinates, duplicated candidates, and labels that only occur in prose explaining where a control might be.

## Verification contract

Before execution, re-read the target app's Accessibility element or browser DOM. If the label, role, or location changed, stop and ask again. After execution, capture a fresh state and compare the expected change. Never retry a side effect automatically unless the action is explicitly idempotent.

## Benchmark fixtures

Maintain redacted fixtures for:

- ChatGPT/Codex new-chat control;
- Chrome YouTube tab and non-YouTube tabs;
- Finder folders;
- a selected PDF or document;
- desktop wallpaper with unrelated file names;
- a missing target;
- two equally named controls;
- Felix's own overlay visible during capture;
- a screen with prompt-injection text.

Each fixture should test both a positive result and a refusal case.
