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

## Completed — first local Meeting Notes workflow (initial microphone-only version)

- Added a separate Meeting notes workspace with explicit microphone capture, live transcript, stop-to-save, local searchable/editable notes, text export, and confirmed deletion.
- Meeting transcripts and generated summaries/action items are stored locally; microphone audio is not written to disk. Apple Speech must support on-device recognition for the selected language. Summary/action generation uses Apple's on-device Foundation Model only, and long transcripts are reduced in bounded chunks.
- Added a shared microphone capture gate so meeting capture and dictation cannot run simultaneously. Added personal vocabulary hints to meeting recognition and updated the microphone privacy string.
- At this stage capture used the selected microphone only and could miss remote voices played directly to headphones. The later system-audio and combined-source sections below supersede that source limitation; HushKey still does not identify speakers.
- Added coverage for capture exclusivity, local note storage/deletion, chunk boundaries, and local-model note generation. `xcodebuild test`: 31 passed, 0 failed, 0 skipped. `Scripts/package-app.sh` succeeded; the packaged app passed `codesign --verify --deep --strict` with bundle ID `com.ruddvz.hushkey`.
- Opened the packaged app and inspected the Meeting notes accessibility tree. No microphone permission was accepted and no meeting recording was started, so live capture remains unverified.

## Naming note

The private prototype keeps the requested HushKey name. A distinct public macOS silent-dictation project already uses that name: https://github.com/amirrsyed/hushkey. Choose a different public product name before any public release.

## Completed — optional local system-audio meeting source

- Added a separate Meeting Notes source choice for Microphone or System audio. System output is captured through a private Core Audio tap on macOS 14.2+ and streamed into the existing on-device Speech path; the microphone is not included, and audio is not written to disk.
- Added just-in-time `NSAudioCaptureUsageDescription` text to both the source Info.plist and the XcodeGen configuration that generates the packaged bundle. The UI explains that System audio captures app output across the Mac and uses a separate macOS permission.
- Fixed the meeting start failure path so a rejected/failed capture source also stops Speech recognition and releases the shared audio-capture gate.
- Added source selection and capture-status UI, updated the privacy copy, README, product plan, competitor report, and manual acceptance protocol.
- `xcodebuild test`: 31 passed, 0 failed, 0 skipped. The release app built and passed strict signature verification; its bundle contains the system-audio usage description. A read-only UI check showed both source options and left the app on Microphone. No capture was started and no microphone or system-audio permission was granted, so physical system-audio/call behavior remains unverified.

## Completed — combined local meeting capture

- Added a **Both sides** source that combines the selected microphone and a private Core Audio system-audio tap in one drift-corrected aggregate input, then sends that stream only to on-device Speech.
- Downmixed aggregate input channels to mono before recognition so microphone and remote playback are analyzed together in a speech-compatible stream.
- Requests microphone permission only after Start meeting and retains the just-in-time system-audio permission path. A denied or unavailable input fails closed and releases the shared capture gate; System audio-only remains available.
- Updated the source picker, active capture status, permission disclosure, app privacy string, README, product plan, competitor research, and manual acceptance protocol. Added unit coverage for system-only and combined aggregate composition.
- `xcodebuild test`: 34 passed, 0 failed, 0 skipped. Synthetic audio tests confirm channel downmix and aggregate composition; this does not substitute for live call acceptance.
- Rebuilt `dist/HushKey.app`; strict code-signature verification passed and the packaged privacy string names both permission paths. Opened that exact bundle and confirmed the Meeting Notes picker exposes Microphone, System audio, and Both sides; left Microphone selected without starting capture.
- Live combined capture remains unverified because no microphone or System Audio Recording permission has been granted in this session.

## Completed — post-audit capture shutdown and insertion routing

- Fixed a stop-path defect where **Both sides** started the aggregate system-audio engine but Stop attempted to stop the unused microphone engine. Capture now stops by source route, so combined mode tears down the tap and aggregate device before releasing the meeting gate.
- Restricted the global insert shortcut to Dictation/Transforms or Silent Use, blocked Silent Use insertion during any active capture, and explicitly blocked dictation insertion during Meeting Notes capture. Unrelated screens can no longer paste a stale motion prediction.
- Added regression coverage for combined-source stop routing, every screen's insert destination, and the meeting-capture insertion gate. `xcodebuild test`: 36 passed, 0 failed, 0 skipped.
- Rebuilt `dist/HushKey.app`; strict code-signature verification passed. The app was already running from that bundle, but the computer-use pipe closed before the new process could be relaunched and its shutdown behavior inspected. Only one HushKey process was running.
- Live microphone/system-audio shutdown and shortcut behavior remain part of manual acceptance; source-level regression tests are not proof of real audio teardown or focused-app insertion.

## Next item — manual voice and meeting-source acceptance

In a fresh session, with the user present, verify microphone and Speech prompts, normal and whispered dictation, shortcuts, guarded insertion/undo, file engines, and all three Meeting Notes sources. For **Both sides**, confirm both just-in-time macOS prompts, simultaneous recognition of microphone speech and remote app playback, teardown on Stop, and capture-gate release. Verify the global insert shortcut cannot paste a stale Silent Lab prediction from other screens; do not treat a successful build as proof of live behavior. Then compare Apple Speech and downloaded WhisperKit models on consented local audio.

## Completed — recoverable file transcription history

- Added local file-transcription job records for engine, language/model, source filename, editable transcript, and timed subtitle cues. Source audio is never copied into HushKey's history.
- Apple Speech and WhisperKit now save completed or partial text when their transcription service finishes, even if the user leaves the Files screen. Editing a restored transcript is debounced, and the Files screen checkpoints its current draft when it closes.
- Added searchable, restorable recent jobs, per-job deletion, and delete-all confirmation. Choosing a new audio file no longer destroys the prior job.
- Added storage and lifecycle regression coverage. `xcodebuild ... test`: 38 passed, 0 failed, 0 skipped. The first build exposed that XcodeGen needed regeneration to include a new source file; regenerated project and reran successfully.
- Built `dist/HushKey.app` in Release configuration and verified its ad-hoc code signature. Resource bundle and app identifier are present.
- The native UI check timed out while selecting the packaged app in Computer Use, so Recent file transcripts/search/restore/deletion have not been visually verified. No source audio or user permission was used in this verification.

## Completed — transcript editing and recovery correctness

- Routed Dictation and Transform transcript editors through `AppModel.editCurrentDictation`, which rejects edits during capture/finalization, resets insertion and local-transform undo state, and debounces local history saves.
- Restoring the raw transcript now follows the same safe edit path. Transform previews are discarded when their source transcript changes, including while a local model is generating a preview.
- Injected the dictation-history destination into `AppModel` so the debounced persistence path can be verified against isolated local storage. History clearing now keeps in-memory and insertion state in sync with successful deletion.
- Added regression coverage for debounced manual-edit persistence, raw transcript restoration, stale transform rejection, and failed history writes. `xcodebuild test`: 40 passed, 0 failed, 0 skipped.
- Rebuilt `dist/HushKey.app` in Release configuration; `codesign --verify --deep --strict` passed.
- Computer Use could not bind to the packaged app path (`-10005`), so the running window was not visually refreshed or verified. No microphone, audio, or user permission was used.

## Completed — stable dictation history edits

- Updated the active transcript's history entry in place after repeated manual edits, local transforms, or raw restore. Each edit keeps the entry ID and creation time stable instead of filling history with duplicates.
- Editing a restored history item creates a new current entry, leaving the restored original available in Recent dictations.
- History deletion resets its active-entry state only after the file is successfully removed. Added regression coverage for repeated edits, record identity, creation-time preservation, and write failures.
- `xcodebuild test`: 40 passed, 0 failed, 0 skipped. Rebuilt `dist/HushKey.app`; strict code-signature verification passed.

## Next item — manual runtime acceptance

With the user present, verify the packaged app's transcript editing, delayed history save, raw restore, transform preview invalidation, and undo/insertion reset. Then test recent file transcripts, search, restore, and deletion with consented audio, plus the documented voice and meeting capture flows. Recheck the running app path when Computer Use can bind to it; builds and unit tests do not prove live microphone, Accessibility insertion, AirPods, or system-audio behavior.

## Completed — meeting note deletion persistence

- Meeting note deletion now writes the candidate note list before changing the visible list or selection. If storage fails, the note stays visible and the service reports that deletion failed.
- Injected the notes file URL into the service for isolated storage verification and added a regression test that forces a failed write.
- xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test: 41 passed, 0 failed, 0 skipped.

## Next item — manual runtime acceptance

With the user present, verify transcript editing and recovery plus the voice, file, and meeting capture flows in the packaged app. Confirm failed meeting-note deletion leaves the note visible. Builds and unit tests do not prove live microphone, Accessibility insertion, or system-audio behavior.

## Completed — stable speech vocabulary hint priority

- Replaced unordered Set-based hint selection with deterministic, case/diacritic-insensitive deduplication and a fixed priority: personal terms, mode hints, enabled nearby-text hints, then Silent Lab vocabulary.
- Applied the same prioritized list to Dictation and Meeting Notes; the 100-hint cap is centralized and enforced at the Speech boundary.
- Updated Personalization to explain hint priority and the per-capture limit. Added overflow coverage for stable order, deduplication, and priority when the 100-term limit is reached.
- xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test: 42 passed, 0 failed, 0 skipped.
- Release build succeeded and passed strict ad-hoc code-signature verification at .build/Build/Products/Release/HushKey.app. scripts/package-app.sh refreshed dist/HushKey.app from that source and the packaged bundle also passed signature verification with HushKey display name and com.ruddvz.hushkey identifier.
- Computer Use opened that Release app and confirmed the Dictation screen shows the microphone off until explicitly started. The UI pipe closed during navigation, so other screens were not visually checked.

## Next item — manual runtime acceptance

With the user present, verify the packaged app's Dictation and Meeting Notes flows, including the hint behavior, and complete the remaining voice, file, and insertion checks in docs/TESTING_PROTOCOL.md. Recheck the running app path when Computer Use can bind; source tests do not prove live microphone, Accessibility insertion, or System Audio Recording behavior.

## Completed — alternative research and local writing styles

- Reviewed FreeFlow, OpenWhispr, OpenTypeless, SpeakType (the separate project linked by the Reddit post), and the Voibe, LumeVoice, and AssemblyAI roundups. The sourced comparison distinguishes repository-backed features from vendor claims and Reddit anecdotes, and ranks HushKey's next opportunities.
- Added [the alternatives research addendum](docs/COMPETITOR_RESEARCH_ADDENDUM_2026-11-01.md) and linked it from Settings, the research index, and the packaged app. No competitor source code or assets were copied.
- Added up to 12 user-defined writing styles to Transforms, including local persistence, name/instruction validation, duplicate-name rejection, edit/delete, confirmation, and preview-first local execution. A style can specify tone, formatting, or translation; only Apple's on-device Foundation Model is used, with no cloud fallback.
- Updated README, product plan, competitor notes, and the local style acceptance checklist.
- `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test`: 44 passed, 0 failed, 0 skipped; the custom-style model test ran successfully on this Mac.
- Refreshed `dist/HushKey.app`, confirmed the research addendum is bundled, and passed strict code-signature verification. The bundle display name and identifier remain HushKey / `com.ruddvz.hushkey`.
- GitHub Actions run 62 passed.
- Computer Use opened the new `dist/HushKey.app` and exposed its Dictation accessibility state. Navigating to Transforms and trying to quit the older build both hit a native UI-pipe failure. The new Transforms screen remains visually unchecked, and two HushKey processes remain running: the older `.build` copy and the latest `dist` app. Microphone, permissions, insertion, and meeting workflows were not exercised.

## Next item — manual voice acceptance, then selected-text editing

In a fresh session, follow the non-AirPods voice acceptance checks in docs/TESTING_PROTOCOL.md with user-approved microphone/Speech and Accessibility access, fix any runtime failures, then design a preview-first selected-text edit that rechecks the original app and selection before replacing anything.
