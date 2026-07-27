# Security policy

Felix is a local-first macOS utility that can read the screen and, when explicitly enabled, invoke constrained actions. Treat screen capture, Accessibility, microphone input, provider keys, Composio credentials, and local context as sensitive.

## Current safety boundary

- Screen capture begins only after an explicit activation or selection.
- Navigation pointers require matching Accessibility/OCR evidence. Model-generated generic coordinates are rejected.
- Unknown computer actions are blocked.
- External side effects require confirmation.
- Real API keys, Composio connections, personal logs, and private context are never repository content.

## Reporting

Do not open a public issue for a suspected credential leak, privacy bypass, arbitrary-action escape, or permission bypass. Send a private report to the repository owner with reproduction steps, macOS version, Felix version, and sanitized logs. Never attach screenshots containing keys, tokens, private messages, or personal data.

## Release gates

Before a public release, run secret scanning, dependency scanning, a clean-machine permission test, the screen-grounding fixture suite, and the destructive-action policy suite. A passing unit test is not evidence that macOS TCC or a real foreground app behaved correctly.
