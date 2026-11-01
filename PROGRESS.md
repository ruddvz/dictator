# HushKey progress

## Completed — 2026-11-01

- Created a standalone native macOS app project from the MIT-licensed Subvox motion prototype and retained its attribution.
- Added a menu bar app, configurable in-app capture shortcut, local training across voice/whisper/silent conditions, session IDs, holdout evaluation, and a strict evidence gate for silent decoding.
- Added opt-in Accessibility insertion with a global shortcut, focus/role checks, secure-field rejection, one-insert-per-prediction behavior, and no clipboard fallback.
- Restricted the microphone reference to on-device Speech recognition and added local dataset/session export and deletion.
- Added build instructions, privacy/limitations, testing protocol, notices, CI configuration, and package script.
- `xcodebuild ... test`: 10 tests passed. Release `.app` packaging succeeded and ad-hoc signature verified.

## Next item — hardware feasibility

In a fresh session, connect the user's AirPods as the Mac's active audio output, grant Motion permission, verify a live sample stream, and run the study in [docs/TESTING_PROTOCOL.md](docs/TESTING_PROTOCOL.md). The current Mac showed an AirPods Pro device entry, but MacBook Pro Speakers were the active output; HushKey has not been tested with live AirPods motion. The exact AirPods generation remains unverified.

## Naming note

The private prototype keeps the requested HushKey name. A distinct public macOS silent-dictation project already uses that name: https://github.com/amirrsyed/hushkey. Choose a different public product name before any public release.
