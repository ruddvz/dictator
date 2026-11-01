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
- Updated README and product plan with the actual flows and limits. At that checkpoint, no app-aware modes, spoken correction, or context hints were implemented; the local language picker and snippets were already present.
- `xcodebuild ... test`: 12 tests passed. Release package built; source-level build succeeded. The app's Dictation screen rendered in the on-screen window capture.

## Manual voice acceptance item carried forward

In a fresh session, confirm microphone and Speech permissions, dictate a short voice phrase and a whispered phrase, edit/copy/insert into TextEdit, then repeat with another frontmost app. Confirm local history and the new global shortcuts. No AirPods motion validation is part of this next step.

## Completed — 2026-11-01 (Competitor research)

- Compared current Mac dictation and transcription products, including Wispr Flow, Superwhisper, Aqua Voice, Typeless, TypeWhisper, MacWhisper, Handy, and VoiceInk using their product documentation or repositories.
- Recorded the market baseline, HushKey's current gaps, a privacy-first opportunity set, licensing notes, and a staged roadmap in [docs/COMPETITOR_RESEARCH.md](docs/COMPETITOR_RESEARCH.md).
- Kept the next engineering task focused on validating and fixing the existing voice dictation path before adding broader features.

## Completed — 2026-11-01 (Research integration and dictation recovery)

- Added the supplied Wispr Flow vs TypeWhisper PDF to `docs/research/`, linked it with HushKey's competitor report, and included both reports in the packaged app's Settings → Research reports section.
- Added Natural, Message, Email, Code, and Automatic modes; common app mapping; explicit spoken corrections with raw transcript recovery; optional transient nearby vocabulary hints; and immediate same-field insertion undo (`⌥⇧U`).
- Changed dictation stop to request final on-device recognition with a two-second fail-safe, then lock the editor until processing completes. This avoids dropping the final phrase and prevents copying or inserting a partial transcript.
- Added unit coverage for correction behavior, mode formatting, app mapping, bounded context extraction, and old history files without the raw-text field.
- `xcodebuild ... test`: 17 tests passed. Release `.app` packaging succeeded; app signature verified; both reports are present in the bundle.
- Live microphone, whispered capture, Accessibility insertion/undo, and frontmost-app context were not manually accepted in this run. Use the checklist in [docs/TESTING_PROTOCOL.md](docs/TESTING_PROTOCOL.md); no claim of live voice validation is made.

## Next item — manual voice acceptance

Run the voice checklist with normal and whispered speech, TextEdit plus one other app, and user-approved Microphone/Speech/Accessibility permissions. Local file transcription and timed subtitle export are now implemented; compare Apple Speech and downloaded WhisperKit with consented samples after voice acceptance. Meeting workflows remain deferred.

## Completed — local dictation and file workflows

- Added the Transcribe Files workflow with Apple on-device Speech or explicitly downloaded WhisperKit models, language selection, byte-level download progress/cancel, local model removal, editable TXT, and SRT/WebVTT export.
- Added safer task handling: file selection and editing lock while a job runs, WhisperKit tasks can be cancelled, models unload after success or failure, and partial Apple Speech results are labeled as incomplete.
- Improved correction safety, filler punctuation cleanup, symbol-based snippets such as `C++` and `@name`, and duplicate snippet validation. These fixes are covered by regression tests.
- Added the supplied competitor report and local model/licensing notes to Settings and the packaged app. No TypeWhisper GPL code or remote text-processing service is included.
- `xcodebuild ... test`: 20 tests passed. Release app packaging succeeded, the app signature verifies, and the bundle contains both reports and third-party notices.
- The packaged app was launched. macOS displayed a Downloads-folder access prompt; no permission choice was made. Native UI automation was unavailable, so live microphone, whisper, insertion/undo, file-model download/offline transcription, and subtitle timing remain manual acceptance items. No AirPods validation was attempted.

## Completed — installed Wispr Flow interface review

- Used computer use to inspect the installed Wispr Flow v1.6.1337 interface without starting microphone or meeting capture, changing privacy controls, connecting a calendar, or requesting data.
- Reviewed Dictation/history, Notetaker setup and notes, Dictionary, Snippets, Style/Auto Cleanup, Transforms, and Data & Privacy. Added the observed product structure and HushKey-specific recommendations to [docs/COMPETITOR_RESEARCH.md](docs/COMPETITOR_RESEARCH.md).
- Confirmed HushKey already has the similar native sidebar/workspace pattern and a clearer local-first Dictation path. Key gaps are dedicated searchable Snippets/Vocabulary, richer searchable/recoverable history, local transforms, and meeting workflows.
- The computer-use screenshot did not show Wispr Flow unobstructed; HushKey covered it, and the native UI pipe later closed when switching back. This is a text-only accessibility-tree review, not a screenshot-backed visual audit.

## Next item — HushKey UI parity slice

In a fresh session, implement the next narrow UI slice: move Snippets and Vocabulary into a dedicated searchable local workspace, then complete the real-app microphone/shortcut/insertion acceptance before adding local transforms or meeting capture. Keep HushKey's native design and local-first privacy; do not copy Wispr Flow assets or internals.

## Naming note

The private prototype keeps the requested HushKey name. A distinct public macOS silent-dictation project already uses that name: https://github.com/amirrsyed/hushkey. Choose a different public product name before any public release.
