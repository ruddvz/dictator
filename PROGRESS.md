# HushKey progress

## Completed — 2026-11-01

- Created a standalone native macOS HushKey app using an MIT-licensed upstream motion prototype and retained its required attribution in [NOTICE.md](NOTICE.md).
- Added a menu bar app, configurable in-app capture shortcut, local training across voice/whisper/silent conditions, session IDs, holdout evaluation, and a strict evidence gate for silent decoding.
- Added opt-in Accessibility insertion with a global shortcut, focus/role checks, secure-field rejection, one-insert-per-prediction behavior, and no clipboard fallback.
- Restricted the microphone reference to on-device Speech recognition and added local dataset/session export and deletion.
- Added build instructions, privacy/limitations, testing protocol, notices, CI configuration, and package script.
- Standardized the app and user-facing documentation on the HushKey name; retained required source attribution in the notices and license.
- `xcodebuild ... test`: 10 tests passed. Release `.app` packaging succeeded and ad-hoc signature verified.
- Reorganized navigation into Setup → Train → Evaluate → Use, with Settings & Data separated from per-word capture.
- Added a first-run motion readiness path, per-word training progress, a dedicated evidence screen, explicit silent-use lock reasons, and optional advanced diagnostics.
- Moved insertion, microphone, session recording, and local data controls into Settings & Data; documented the interface and file map in [docs/PRODUCT_PLAN.md](docs/PRODUCT_PLAN.md).
- Updated the XcodeGen project and verified a macOS build plus all 10 tests. Opened the packaged build and confirmed its standard Setup window is visible.
- Changed HushKey from a menu-bar-only utility to a normal windowed Mac app while retaining the menu-bar shortcut, added a custom icon, and moved packaging builds to a disposable temporary folder so Finder search has one distributable app.
- Canonical local app location: `dist/HushKey.app`. Spotlight indexing now returns this one app bundle; old visible build copies are removed and new package builds use a disposable temporary folder.
- Refreshed the visual identity around an H keycap and quiet motion trace, added a matching monochrome menu-bar mark, moved page headings to native system typography, and made Setup recovery actions open the relevant system settings.
- End-to-end audit: all 10 automated tests pass; the Release app builds, packages, and verifies. Setup now offers direct Bluetooth and Sound settings actions when no headphone-motion stream is present. Removed stale HushKey Debug/Release app bundles from Xcode DerivedData; Spotlight now resolves only the packaged app.
- Live hardware check found the AirPods are not connected and MacBook Pro Speakers are the selected output. HushKey therefore has no live motion samples and correctly stays in Setup; decoding, live capture, and insertion could not be hardware-validated in this state.

## Completed — 2026-11-01 (Dictation UX)

- Made Voice & Whisper dictation the launch screen; starting the app no longer asks for Motion permission. Motion streaming starts only when a Silent Lab screen is opened and stops when the user leaves that lab.
- Added global hold-to-talk and press-to-toggle dictation, editable phrase transcription, copy and safe phrase insertion, local recent history, on-device language selection, personal vocabulary hints/snippets, microphone selection, and shortcut controls in the menu bar and Settings.
- Fixed distinct global shortcut IDs so dictation and insertion hotkeys do not call each other's actions. Made insertion one-time per dictation to prevent duplicates.
- Moved voice recognition out of Use diagnostics. Silent Lab now has dynamic study progress, honest auto-capture lock copy, and result colors reflect every evidence check.
- Updated README and product plan with the actual flows and limits. No cloud rewrite, app-specific styles, snippets, workflow plugins, or language picker are included yet.
- `xcodebuild ... test`: 12 tests passed. Release package built; source-level build succeeded. The app's Dictation screen rendered in the on-screen window capture.

## Next item — voice dictation acceptance check

In a fresh session, confirm microphone and Speech permissions, dictate a short voice phrase and a whispered phrase, edit/copy/insert into TextEdit, then repeat with another frontmost app. Confirm local history and the new global shortcuts. No AirPods motion validation is part of this next step.

## Naming note

The private prototype keeps the requested HushKey name. A distinct public macOS silent-dictation project already uses that name: https://github.com/amirrsyed/hushkey. Choose a different public product name before any public release.
