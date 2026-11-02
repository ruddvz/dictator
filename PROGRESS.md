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

## Completed — app reconnaissance tool review

- Used the official REA 6.8.0 CLI for bounded, read-only inventory of the installed Wispr Flow app bundle. It identified an Electron `app.asar` packaging marker; no app source, assets, user data, or native implementation were extracted or decompiled.
- Reviewed ServiceNow/StarHarness. It evolves agent harnesses using model calls and proposer-generated code, so it is not suitable for this product UI review and was not run. Its held-out evaluation principle is recorded for HushKey's acceptance work.
- Added scope and limitations to [docs/COMPETITOR_RESEARCH.md](docs/COMPETITOR_RESEARCH.md). No app source changed and no tests were run for this documentation-only update.

## Completed — personalization and searchable recovery

- Added a dedicated native Snippets & Vocabulary sidebar workspace with search, add/edit/delete flows, duplicate checks, and an advanced repair editor for legacy snippet lines. Settings now links to this workspace instead of embedding raw text editors.
- Dictation history searches all saved transcripts, matches both processed and raw text, and offers separate restore actions for each.
- Updated the vocabulary parser and added coverage for case/diacritic-insensitive deduplication and raw-history restoration.
- `xcodebuild ... test` passed. Release packaging succeeded, and `dist/HushKey.app` passes strict code-signature verification. Packaging now stages and replaces only HushKey; it no longer removes other HushKey build products or DerivedData apps.
- The native computer-use pipe still closes before UI inspection, so the new screens could not be visually checked in the live app. Microphone, shortcut and insertion acceptance also remains open.

## Completed — local text transforms

- Added a dedicated Transforms workspace with selectable writing actions, editable review drafts, explicit apply, preview staleness protection, and an undo action.
- Model-backed actions use Apple's on-device Foundation Model only when available on macOS 26+; the deterministic filler-removal path works without that model. HushKey has no cloud fallback.
- Added tests for local filler transformation, on-device model generation when available, stale-preview rejection, transcript apply, and undo. On this Mac, all 25 macOS tests passed with none skipped, including one local Apple Foundation Model generation.
- Fixed the explicit Xcode project file lists so the new service and screen are compiled; updated README, competitor research, and product plan.
- Built and strictly signature-verified `dist/HushKey.app` (version 1.0, bundle ID `com.ruddvz.hushkey`). Automated tests do not establish generated-text quality or microphone/insertion behavior. The native computer-use pipe still closes before live UI inspection; manual app acceptance is the next step.

## Completed — dictation reliability hardening

- Blocked the global insert shortcut while microphone capture, recognition, or finalization is active so it cannot insert a partial transcript.
- Made history deletion remove the stored file directly, including malformed history files; deletion and save failures now appear in the Dictation screen.
- Limited automatic spoken corrections to recognizable phrase boundaries, preserving ambiguous raw wording instead of silently corrupting it.
- Prevented raw transcript restore from being saved as a duplicate history entry and added regression coverage.
- Connected WhisperKit cancellation to its transcription callback so decoding can stop early when the user cancels.
- `xcodebuild test`: 27 tests passed, including on-device Foundation Model generation. Release packaging succeeded; `dist/HushKey.app` passes strict signature verification (version 1.0, `com.ruddvz.hushkey`).
- Live inspection returned HushKey’s Dictation accessibility tree. Further HushKey navigation failed when the computer-use native pipe closed; opening Wispr Flow timed out. No microphone, Accessibility, or AirPods permissions were changed. Live voice, insertion, and screenshot-backed UI acceptance remain open.

## Next item — manual dictation acceptance

In a fresh session, use the app with the user present to accept Microphone, Speech, and Accessibility prompts as needed; check normal and whispered dictation, active-capture insertion blocking, and one-time insertion plus undo in TextEdit and a second app. Then inspect current HushKey and Wispr Flow screens with computer use and tune any visible UX defects. Keep the AirPods motion experiment separate from this acceptance.

## Next item — live dictation acceptance

In a fresh session, verify the packaged app in TextEdit and a second supported app: microphone permission, normal speech and whisper, global shortcut behavior, history search/raw restore, insertion, duplicate prevention, and undo. Then continue with meeting capture and summaries, voice editing of selected text, and workflow automation using original HushKey code and license-compatible dependencies.

## Completed — 2026-11-01 (Flow-style UI pass, branch `feature/flow-style-ui`)

- Compared the installed Wispr Flow home screen and its floating status window with HushKey's Dictation screen (screenshot-backed this time). Wispr's source was not extracted; only visible UI was reviewed.
- Added a floating dictation pill: a non-activating bottom-of-screen panel that idles as a small bar, expands on hover with the shortcut, shows a live waveform while listening and a spinner while transcribing. Click toggles dictation without stealing focus. Toggle in Settings & Data and the menu bar.
- Redesigned Dictation as a home: greeting with keycap shortcut, one "now" card (status, writing-mode chip, target-app chip, Start/Stop, live waveform, editor, Copy/Insert/Original/Clear), a stats card (total words, wpm, day streak, dictations), a short privacy card, and day-grouped history with hover/context actions (copy, edit again, restore original, delete).
- History entries now store dictation duration (optional, backward compatible) for wpm. Added single-entry delete and copy.
- Sidebar: HushKey brand header and a "Get started" checklist (microphone, speech, insertion, first dictation) that hides when complete. Motion status badge now shows only on Silent Lab screens.
- New shared components in `HushKey/Views/Theme.swift` (card, keycap, waveform, status chip).
- `xcodebuild test`: 28 tests passed (new stats test). Debug app launched; Dictation home and idle pill verified by screenshot. Listening/transcribing pill states and the waveform were not exercised live (would need the microphone prompt).

## Completed — 2026-11-01 (Critique and multimodal roadmap)

- Added [docs/CRITIQUE_AND_ROADMAP.md](docs/CRITIQUE_AND_ROADMAP.md): critiques of Wispr Flow, TypeWhisper, and HushKey, with improvement tables; a sensor reality check (AirPods expose head motion only, jaw motion is indirect, lips are not sensed); a layered quiet-input plan led by head-gesture commands; a prioritized roadmap; and per-feature evaluation checks. Documentation only; no code changed.

## Completed — 2026-11-01 (Live pill check and app-wide restyle)

- Live microphone check found two defects, now fixed: the waveform pinned every bar at full height (it now measures speech above an adaptive noise floor), and the pill grew downward off-screen (its panel now reads the hosting view's intrinsic size and stays anchored 10 pt above the bottom). Verified listening state by screenshot.
- Reviewed every Wispr Flow page (Dictionary, Snippets, Style, Transforms, Scratchpad, Insights, Settings) in full screen; no settings changed.
- App-wide card style for all GroupBoxes and a cleaner page header; Settings split into General / Insertion / Data & privacy / About tabs, with "Enable insertion…" deep-linking to Insertion; 10-week activity heatmap in the Dictation stats card; more legible keycaps.
- `xcodebuild test`: 28 passed. Dictation, Settings, Transforms, and Snippets & Vocabulary verified by screenshot.

## Completed — 2026-11-01 (Warm editorial redesign and morphing icons)

- Surveyed every view with the dimensional-drawing method (MIT, enesozturk/dimensional-drawing; read, not installed): 18 padding values, 18 stack gaps, 7 radii, 77 caption labels, 3 page widths. Replaced them with one token set documented in [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) using S#/R#/H#/W codes.
- User chose "warm editorial" and "morphing state icons". Rebuilt the shell: custom sidebar on warm paper (no system split view or accent blue), raised page sheet, hidden title bar, animated page transitions, sidebar icon bounce, setup checklist that jumps to the right place.
- Dictation home: "Hey <first name>" greeting with amber keycaps, a dismissible next-step banner (insertion → vocabulary → Silent Lab) with an ambient waveform, serif stats with a 12-week heatmap, a composer that appears only while dictating or reviewing, and day-grouped history with sliding hover actions.
- `MorphIcon`: one 25-point line blending hush → waveform → spinner → check, used in the brand mark, Dictate button, composer, empty state, and pill. Pill adds a "Ready to insert" check moment after transcription.
- Appearance setting (System / Light / Dark, default Light). All pages share `pageLayout()` and the card `GroupBox` style.
- `xcodebuild test`: 28 passed. Light and dark home, Transforms, Vocabulary, Settings, Setup, and live listening (pill + composer) verified by screenshot. The pill's done check needs spoken input to appear and was not seen live.

## Next item — eval harness and pill acceptance

With the user present, grant Microphone/Speech and confirm the pill's listening and transcribing states in another app. Then build a held-out evaluation harness (fixed consented audio clips → transcript → WER and formatting checks, plus UI screenshot checks) in the StarHarness spirit, separate from this UI branch.

## Naming note

The private prototype keeps the requested HushKey name. A distinct public macOS silent-dictation project already uses that name: https://github.com/amirrsyed/hushkey. Choose a different public product name before any public release.
