# HushKey progress

## Completed — recover cancelled dictations, Insights and Languages (2026-11-02)

- **Recover:** cancelling with × or Esc (after at least 1 s of listening) keeps the audio in memory until HushKey quits. History shows "You cancelled a m:ss dictation in App" with **Recover** and Discard. Recover transcribes it with the settings of that run and saves it to History without typing it anywhere.
- **Insights** page (sidebar, after Dictation): words per minute with a gauge and "× typing speed" (against 40 wpm), words cleaned up, dictation count, total words with the monthly change and a novels or pages comparison, where you dictate (Work, Personal, Email, Code, Other), and the day streak with a 20-week heatmap. It's backed by `UsageLedger` (`usage.json` beside the history): daily counts only, no text or app names. It's seeded once from saved history (as Other), written only while history saving is on, and has its own reset. Wispr's Leaderboard is left out: it needs accounts and a server.
- **Languages:** Settings › Language opens a searchable grid sheet (language, native name, region; Save and close). There's a single choice, because on-device recognition has no auto-detect.
- Fixed while checking live: `DateInterval.contains` includes the end, so the 1st of a month also counted toward the previous month (showed a false "0% this month"). Fixed the "1 dictations" plural.
- Tests: `UsageLedgerTests` (10, including language search). `xcodebuild ... test`: 175 passed, 2 skipped, 0 failed.
- **Seen live (packaged app):** the Insights page with real data; the language sheet (tiles, search "canada", the "was English (United States)" hint, the no-match state, Close without saving kept US English); × cancel → History Recover row → Recover → row cleared → "Didn't catch that" (quiet room, so no words to save).
- **Not seen live:** a recovered dictation that contains speech landing in History; Insights updating after a new finished dictation; Save and close actually switching the recogniser language; Reset insights.
- Next: a 2-minute guided tour from the setup checklist.

## Completed — app-wide Wispr comparison and Style page (2026-11-02)

- Wrote `docs/APP_UX_ANALYSIS.md`. HushKey already matches Wispr Flow on breadth. The biggest visible gap was **Style**: Wispr sets a tone (Formal / Casual / Very casual) for each kind of app, with previews; HushKey had only modes.
- New **Style** page in the sidebar. Its tabs are Personal messages, Work messages, Email and Other, matched by the target app's bundle identifier (`DictationContext`). Three tone cards each show a live preview. `DictationTone` runs on this Mac after mode formatting and before snippets: Casual drops the final full stop; Very casual lower-cases sentence starts (keeping "I" and acronyms) and drops sentence full stops (keeping decimals, ellipses, ? and !). Code mode is never restyled. The default is Formal everywhere, so existing output is unchanged.
- The home next-step hero now suggests "Make it sound like you", which opens Style, until a tone is chosen.
- Added `DictationToneTests` (7). `xcodebuild ... test`: 163 passed, 2 skipped, 0 failed.
- **Seen live (packaged app):** the Style page and selecting Very casual, which updated the card and the check (then set back to Formal); the pill reopened at its dragged position after relaunch.
- **Not seen live:** a real dictation into Messages/Slack/Mail with a non-formal tone, and the new Style hero (it hides once a tone has been stored, which my test did).
- Wispr Flow's window was on another Space; I read its home screen and accessibility tree but didn't click through its other pages. The comparison also uses the 2026-11-01 measurements.
- Next: recover cancelled dictations from history (in memory, this session only) and a 2-minute guided tour from the setup checklist.

## Completed — pill recovery, Undo, mic menu and placement (2026-11-02)

- "We couldn't hear you" when the recording's peak level stayed under −54 dBFS (`AudioService.peakLevel`, `DictationRecovery.silenceLevel`). It and "Mic didn't start" offer a Mic picker and Sound settings.
- Cancel with × or Esc keeps the audio in memory for 5 s with a neutral "Cancelled · Undo"; Undo runs the normal retry path. Recordings under 1 s, and cancels from other paths (fn tap, toggle while starting), drop the audio at once.
- Right-click menu, optional start/stop sounds (off by default; also in Settings and the menu bar), idle dot after 5 s, drag along the bottom edge (remembered as `pillCenterFraction`), follows the pointer's screen, Meeting notes button on hover. Core Audio's private aggregate devices are hidden from mic lists.
- Tests: `PillPlacementTests`, a device-filter test, and 5 recovery tests. `xcodebuild ... test`: 156 passed, 2 skipped. One earlier run aborted in an unrelated test while `dist/HushKey.app` was still open; it passed after quitting it.
- **Seen live (packaged app):** idle dot (34 × 23 panel); hover tooltips "Dictate fn" and "Meeting notes"; right-click menu (it then showed a duplicate header and a `CADefaultDeviceAggregate` entry, both fixed after; the fixed menu wasn't reopened); × → "Cancelled · Undo" → Undo → transcribing sweep → "Didn't catch that" (quiet room); drag moved the pill left and kept it there.
- **Not seen live:** "We couldn't hear you" (needs a muted input, and I didn't change sound settings), the sounds, Esc, hold mode, and the Sound settings button (its link was checked with `open`). One start sat at "Preparing locally" while a system alert from UserNotificationCenter was in front; × cancelled it. Not investigated.

## Completed — compact recording pill and level meter (2026-11-02)

- Wrote `docs/PILL_UX_ANALYSIS.md`, a gap analysis against Wispr Flow (user screenshots plus Wispr help-center docs). Main findings: the recording pill was about 2.5× Wispr's footprint, the `VoiceRibbon` barely moved with ordinary speech, the shape jumped between preparing, listening and finishing, hold and hands-free looked the same, and hints were full sentences or slow system tooltips.
- New `PillMeter`: 13 dense level bars, full-contrast `ink` on dark. They are centre-weighted, each wobbles on its own, and they are scaled by √(speech) from `SpeechEnvelope`, rising fast and falling slowly. Silence rests as breathing dots. Waiting and transcribing sweep a highlight instead of swapping in a spinner and text.
- The recording pill is now a 28 pt capsule: × · meter · ✓ (filled sage, the finish action). While fn or the custom shortcut is held, it is the meter only (`dictationShortcutHeld` is now observed). The timer appears only after 30 s.
- A `PillHint` tooltip above the pill shows "Dictate" plus the shortcut on hover, "Cancel · esc" or "Finish · fn" over the controls, and "Waiting for microphone" or "Preparing locally" while starting. Before any words arrive, the no-target card is a one-line strip; the big faded "Listening…" is gone.
- The pill and card now use Theme tokens only (`paper`, `ink`, `ink2`, `hairline`, `well`, `signal`, `danger`); the hard-coded `#141B17` and `#9CCBB4` are removed. Updated `docs/DESIGN_SYSTEM.md`.
- Added `PillMeterTests` (4). `xcodebuild ... test`: 146 passed, 2 skipped, 0 failed (148). Packaged and opened `dist/HushKey.app`.
- **Seen live** (packaged app, screenshots through background accessibility): idle bar; click to start → "Preparing locally" hint with × · dots · dimmed ✓; listening capsule (127 × 28) with the one-line "No text box selected. Talk, then copy." strip; ✓ with no speech → "Didn't catch that" + Retry; dismiss → idle; × during listening → idle.
- **Not seen live:** the meter moving with real speech (the mic didn't pick up `say` through the speakers, so the bars stayed at rest), hover and tooltip states (background control can't hover), Esc, hold-to-talk meter-only mode, the transcribing sweep (too brief to capture), the done check, and the live-text card with words.
- Next (P1 in the analysis): "We couldn't hear you" / "Microphone unavailable" errors with Sound settings and mic-picker actions, Undo after cancel, and a right-click mic menu on the pill.

## Completed — vocabulary word list import/export (2026-11-02)

- Committed the finished v3 app-profile backup work that was left uncommitted (22e3a36) after re-running the suite.
- The Vocabulary page now has **Import…** and **Export…**. Export writes a UTF-8 `.txt`, one term per line. Import accepts `.txt`/`.csv` (lines or commas, BOM tolerated, ≤1 MB), skips case/accent duplicates and terms over 128 characters, and reports the counts. An import that would exceed the 500-term limit changes nothing.
- Added tests for merge/dedupe/skip, limit and unusable-file rejection, and export round-trip. Latest test result: 142 passed, 2 skipped, 0 failed (144 total). Release packaging and strict code-signature verification passed; opened the updated `dist/HushKey.app`.
- Vocabulary Import/Export buttons, panels, and alert still need a live click-through. Run the Vocabulary word-list step in the backup section in `docs/TESTING_PROTOCOL.md`.
- Live microphone smoke check: Microphone and Speech Recognition were already enabled in macOS Settings, so no OS prompts appeared. After restarting the packaged app, Start Dictate entered Listening. Synthetic speech was not recognized; a later live capture produced text that did not match the test phrase. Capture was stopped. Dictation accuracy and insertion remain unverified; do not treat this as acceptance.
- Next fresh-session step: live acceptance workflows (permission-gated dictation/insertion, local model use, meeting capture) with the user present.

## Completed — portable Automatic app profiles (2026-11-02)

- Personal data backup format v3 now exports and imports Automatic app profiles, including every optional override. Existing version-1 and version-2 backups remain readable; Replace preserves app profiles that older formats did not contain.
- Merge keeps local profiles with matching bundle identifiers, adds other imported profiles, and remaps imported writing-style references to the retained local style when names conflict. Invalid profile data, dangling style references, duplicates, and more than 100 profiles are rejected before data changes.
- Added coverage for v3 round-trip and validation, v1/v2 migration, merge conflict behavior, style-reference remapping, and AppModel replacement persistence across relaunch. Updated backup guide, acceptance protocol, README, product plan, and competitor research notes.
- `xcodebuild ... test`: 139 passed, 2 skipped, 0 failed. Release packaging succeeded and strict code-signature verification passed. Opened the updated `/Users/rudra/Projects/HushKey/dist/HushKey.app`.
- Next fresh-session step: complete the remaining live acceptance workflows for permission-gated dictation/insertion, local model use, and meeting capture; do not claim those hardware/permission paths from unit tests.

## Completed — app-specific Automatic dictation profiles (2026-11-02)

- Automatic profiles can now override on-device language, snippets, deterministic corrections, filler cleanup and a saved Transform style in addition to writing mode and vocabulary. Explicit dictation modes keep global preferences.
- Added a collapsed Optional app-specific overrides editor in Settings & Data. It validates local language availability and snippet/correction rules; the profile uses the frontmost app’s bundle identifier and never reads app text. Profile style references clear when their saved style is deleted or removed by backup replacement.
- Transform styles remain preview-first: a matching profile selects its style for the new transcript, while user-selected styles remain under user control.
- Added resolver tests for Automatic-only behavior, global fallbacks, legacy profile decoding, round-trip persistence and input validation.
- `xcodebuild ... test`: 137 passed, 2 skipped, 0 failed. Release packaging succeeded; strict code-signature verification passed. Opened the updated `dist/HushKey.app`.
- Live insertion acceptance still awaits user-enabled Accessibility.

## Completed — preserve open dictation during backup replacement (2026-11-02)

- Replacing a personal-data backup now keeps the open transcript in local history when transcript saving is enabled, and marks it saved only when it is actually present in the restored archive. With history saving off, the editor stays open and the transcript remains correctly unsaved without changing that privacy setting.
- If the backup already contains 50 entries and the open transcript is not among them, import remains pending and no archive is changed; the user can clear or save the draft before retrying.
- Added regression coverage for the draft surviving app-model relaunch and for a full backup refusing replacement without data loss.
- `xcodebuild ... test`: 135 passed, 2 skipped, 0 failed. Release packaging succeeded and `codesign --verify --deep --strict` passed. Opened the updated `dist/HushKey.app`; it is the only HushKey process.
- Live text insertion remains unverified until Accessibility is enabled by the user. Next fresh-session engineering item: extend per-app profiles to snippets, corrections, language, cleanup and writing style.

## Live insertion acceptance — awaiting Accessibility permission (2026-11-02)

- Opened the current packaged app at `~/Projects/HushKey/dist/HushKey.app`. Its setup screen says to allow HushKey in Accessibility settings; text insertion is off. I did not change macOS privacy permissions.
- Opened a blank TextEdit window for the acceptance check and closed it without saving or changing any user document. No live insertion was sent.
- Next: after the user enables HushKey under **System Settings → Privacy & Security → Accessibility** and turns on **Type where your cursor is**, verify one direct insertion and clipboard restoration in TextEdit, then test paste fallback in another supported app. Microphone and Speech permissions remain separate and were not requested.

## Completed — verify clipboard paste delivery before reporting success (2026-11-02)

- Paste fallback now snapshots the readable text field before dictation, revalidates the same app, field, contents, and selection before sending Cmd-V, and waits up to two seconds for the exact expected field contents before reporting success.
- A timed-out or changed target is surfaced as uncertain, keeps the transcript available, restores the clipboard only if it has not changed, and tells the user to inspect the destination before choosing an explicit retry. Retrying reuses the original field snapshot, preventing a second paste after a delayed successful delivery.
- Added regression checks for UTF-16 range replacement, delayed field updates, target edits during delivery, and the uncertainty recovery message. Updated Settings, README, and the manual acceptance protocol.
- `xcodebuild -quiet test -project HushKey.xcodeproj -scheme HushKey -destination 'platform=macOS'`: 132 passed, 2 skipped, 0 failed. Release packaging succeeded and `codesign --verify --deep --strict` passed.
- Live Accessibility paste into third-party apps still needs a user-approved acceptance session. Next: verify live insertion and clipboard restoration in TextEdit and one other supported app in a fresh session.

## Completed — packaged Files UI and subtitle export check (2026-11-02)

- Opened `/Users/rudra/Projects/HushKey/dist/HushKey.app` and verified the Files screen restored its saved local test transcript with 15 timed segments.
- Exported SRT and WebVTT from the screen to temporary files and inspected them: both contained all 15 cues with the correct format-specific timestamp separators. This checks the UI and serialization, not timing accuracy against the original media.
- The screen still offers the macOS Speech Recognition permission step. I did not start a new transcription or grant that permission, so fresh capture, recognition quality, and source-duration clamping remain unverified.
- Closed the older Debug app under the Codex outputs folder after discovering it was still running; verified the only remaining HushKey process is `/Users/rudra/Projects/HushKey/dist/HushKey.app`.
- Next fresh-session step: with the user present, authorize Speech Recognition if desired and run the documented short-file transcription, edit/reopen, subtitle timing, and recoverable save-failure checks.

## Completed — preserve unsaved file transcript drafts across navigation (2026-11-02)

- Moved the active file, transcript session metadata, and selected engine from view-local state into the app model. Recreating the Files page no longer resets an active draft and restores an older saved transcript over it.
- The latest-history auto-restore now checks whether an active workspace already exists. If saving fails on page exit, the draft remains visible on return and can be saved after storage recovers.
- Added a regression test that starts with older saved history, forces a write failure, simulates page recreation, confirms the newer draft remains, then verifies a successful retry.
- `xcodebuild test` on the MacBook Pro: **128 passed, 2 skipped, 0 failed**. Xcode reported the existing outdated CoreSimulator warning; macOS tests passed.
- Rebuilt `dist/HushKey.app`, passed `codesign --verify --deep --strict`, and opened the packaged app. Only this packaged HushKey process is running. No audio, model download, or Accessibility capture was started.
- Next fresh-session step: perform the documented live file transcription and save-failure recovery check with the user’s audio file, then continue the broader voice and meeting acceptance checklist.

## Completed — bound meeting summary reduction (2026-11-02)

- Fixed a non-terminating local Meeting Notes transform path: when chunk summaries remain over the size limit, HushKey now requires actual shrinkage and stops after at most four reduction passes.
- If the on-device model cannot condense the transcript enough, the transform returns a clear local error and leaves the transcript unchanged.
- Added regression coverage for unchanged/expanded model output and the maximum pass limit.
- `xcodebuild ... test`: 116 passed, 2 skipped, 0 failed. The existing CoreSimulator version warning remains; the macOS test run passed.
- Rebuilt `dist/HushKey.app`, passed strict signature verification, and reopened the packaged app. No capture or permission prompts were started.
- Next fresh-session step: complete consented live acceptance for microphone/Speech, Meeting Notes cancellation and summary, dictation shortcuts, selected-text editing/insertion, and file exports; record any failures here.

## Completed — persist file transcript edits before switching (2026-11-02)

- Fixed the 500 ms autosave race: restoring another file transcript or starting transcription of a newly selected file now saves the active transcript first. Clicking the already active history row is a no-op, so it cannot reload stale text over an edit.
- Empty transcript edits are saved, and the active session's original source name takes precedence over a newly selected file name. If saving fails, HushKey stays on the current session instead of switching away.
- Added regression coverage for edited outgoing snapshots, same-row no-op snapshots, and intentional empty text.
- `xcodebuild ... test`: 114 passed, 2 skipped, 0 failed. The existing CoreSimulator version warning remains; the macOS test run passed.
- Rebuilt `dist/HushKey.app`, passed strict signature verification, and reopened the packaged app. No capture or permission prompts were started.
- Next fresh-session step: complete consented live acceptance for microphone/Speech, Meeting Notes cancellation, dictation shortcuts, selected-text editing/insertion, and file exports; record any failures here.

## Completed — preserve selected-text formatting (2026-11-02)

- Fixed selected-text rewriting so it sends only the text body to the local model, then restores the selection's original leading indentation/whitespace and trailing spaces or line breaks exactly.
- Applying the preview now inserts the draft verbatim instead of trimming its boundaries. Added regression coverage for indented lines, tabs/spaces, paragraph endings, and whitespace-only selections.
- `xcodebuild ... test`: 113 passed, 2 skipped, 0 failed. The existing CoreSimulator version warning remains; the macOS test run passed.
- Rebuilt `dist/HushKey.app`, passed `codesign --verify --deep --strict`, and reopened the packaged app. No capture or privacy permission prompts were started.
- Next fresh-session step: complete consented live acceptance for microphone/Speech, Meeting Notes cancellation, dictation shortcuts, selected-text editing/insertion, and file exports; record any failures here.

## Completed — cancel Meeting Notes startup (2026-11-01)

- Meeting Notes now offers **Cancel** while preparing local recognition or audio capture. Cancellation stops pending Speech and microphone work, invalidates late system-audio microphone permission responses, and releases the shared capture gate so another audio flow can proceed.
- Added a deterministic test for a system-audio startup cancelled while its injected microphone authorization is pending; a late grant no longer starts capture or overwrites the cancellation state.
- Added a manual permission-startup cancellation check to `docs/TESTING_PROTOCOL.md`.
- `xcodebuild ... test`: 110 passed, 2 skipped, 0 failed. The test run reported the existing outdated CoreSimulator warning; macOS tests passed.
- Rebuilt and reopened `dist/HushKey.app`; strict code-signature verification passed. The packaged app is idle. Startup cancellation was not exercised live because that would require starting capture and resolving macOS permissions.
- Next fresh-session step: complete consented live acceptance for microphone/Speech, Meeting Notes source cancellation, dictation shortcuts, insertion and file exports; continue fixing any failures found.

## Completed — keep personalization replacements literal (2026-11-01)

- Fixed snippets and correction rules so every cue is matched against the original dictated text in one pass; inserted replacement text is protected from other rules and from later formatting.
- Overlapping cues at the same position now prefer the longer phrase. Existing punctuation behavior is retained.
- Added regression coverage for chained snippets/corrections, correction-to-snippet cascades, formatting of inserted phrases, filler cleanup spacing, and overlapping cues.
- `xcodebuild ... test`: 109 passed, 2 skipped, 0 failed. The test run reported an outdated CoreSimulator warning, but macOS tests completed successfully.
- Rebuilt and reopened the single `dist/HushKey.app`; strict signature verification passed. It is open on the packaged build and idle; no permission prompts were accepted and no live dictation was run.
- Next fresh-session item: restore the packaged app's microphone and Speech permissions after explicit user approval, then continue live dictation and insertion acceptance. No live audio or insertion was tested in this code-only fix.

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

## Completed — guarded named-target insertion

- Fixed the Dictation screen's Insert button: a dictation started from HushKey cannot safely target whichever app is frontmost later. HushKey now snapshots a supported destination field only when dictation starts via the global shortcut in that app.
- Before returning to insert, HushKey requires Accessibility, the same live app, exact focused field, unchanged full field text and selection, a supported non-secure text role, and a settable selected-text attribute. The target remains in memory only; no clipboard use.
- Added clear Dictation and Settings guidance, fail-closed behavior, and a unit test for changed text/selection. Updated the testing protocol and README.
- `xcodebuild -quiet -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build -destination 'platform=macOS,arch=arm64' test`: 45 passed, 0 failed, 0 skipped on the MacBook Pro. Live insertion into TextEdit/another app is still pending with the user.
- The first test build exposed a main-actor isolation error in the new pure comparison helper; it was corrected and the final suite passed. Xcode reports an outdated CoreSimulator framework, but macOS tests completed.

## Next item — live insertion acceptance

Validate named-target insertion, stale-target rejection, global shortcut insertion, and undo in TextEdit and a second app. Microphone, file-model, and meeting capture acceptance remain open.

## Completed — selected-text voice-edit implementation

- Added a dedicated hold shortcut for editing selected text in another app (`⌥⇧E` by default; `⌃⇧E` is the alternate). HushKey snapshots a supported non-secure selection, captures an on-device spoken instruction, and keeps that instruction out of dictation history.
- Added a Transform screen card with the source selection, editable instruction, local preview, explicit Apply, clear status, and discard/done controls. Apply rechecks the exact app, focused field, text, and selection; stale or secure targets fail closed. One successful replacement can be undone with `⌥⇧U` while the target stays unchanged.
- Kept selection and instruction in memory only. The voice-edit path is separate from normal dictation and requires the user to enable Accessibility insertion. It uses Apple's on-device Foundation Model for preview and has no cloud fallback.
- Added UTF-16 selection boundary and prompt-separation unit coverage. Latest test run: `47 passed, 0 failed, 0 skipped` on the MacBook Pro.
- `bash scripts/package-app.sh` succeeded. `dist/HushKey.app` passed `codesign --verify --deep --strict`; its display name is `HushKey` and bundle identifier is `com.ruddvz.hushkey`.
- Live capture/insertion in TextEdit and a second app is still unverified. After packaging, Computer Use opened the exact `dist/HushKey.app` bundle; its idle Dictation screen showed the microphone off, and the duplicate “Writing mode” label was gone. Only that HushKey instance was running. Attempts to navigate to Transforms hit the native UI pipe failure, so that screen remains visually unchecked.
- Updated README, testing protocol, product plan, and competitor roadmap to mark the implementation and keep live acceptance as the next step.

## Next item — live selected-text acceptance

In a fresh session, use the packaged app to test the selected-text shortcut, local instruction capture, preview invalidation, Apply once, undo, stale-target rejection, unsupported/secure controls, and permission refusal in TextEdit and one other app. Record actual results in `docs/TESTING_PROTOCOL.md`; then proceed with voice dictation and remaining file/meeting acceptance.

## Completed — competitor review and local app profiles

- Checked the user-supplied FreeFlow, OpenWhispr, OpenTypeless, Voibe, LumeVoice, SpeakType Reddit, and AssemblyAI sources. The linked feature matrix and roadmap distinguish repository-backed behavior from vendor claims and Reddit anecdotes; no competitor code or assets were copied.
- Added editable app profiles to **Settings & Data**. With writing mode set to Automatic, a profile selects Natural, Message, Email, or Code and adds local vocabulary hints when dictation starts from that app. Profiles match the frontmost app bundle identifier and stay in local preferences; reading nearby app text remains a separate opt-in.
- Added validation, case-insensitive profile matching, duplicate replacement, local persistence, visible last-capture profile status, and unit coverage. Updated README, product plan, and competitor roadmap.
- `xcodebuild ... test`: **48 passed, 0 failed, 0 skipped** on the MacBook Pro. The CoreSimulator framework warning remains environmental; macOS tests completed.
- An exploratory macOS UI test encountered a system Automation permission prompt and unreliable offscreen sidebar geometry. No Automation permission was granted; the UI test target was removed so normal tests and CI remain usable. Manual navigation and live audio/insertion acceptance remain open.
- Rebuilt `dist/HushKey.app`, verified its strict code signature and `com.ruddvz.hushkey` identity, closed the older `/Users/rudra/Projects/HushKey` build, and launched the packaged app. The only HushKey process now runs from this `dist` bundle.

## Next item — live end-to-end acceptance

With the user present, validate the latest packaged app in TextEdit and a second app: voice and whisper capture, profile selection, selected-text edit preview/apply/undo, guarded insertion/recovery, file transcription, and meeting sources. Record outcomes in `docs/TESTING_PROTOCOL.md`; do not treat unit tests as proof that device permissions or live capture passed.

## Completed — local transcription correction rules

- Added a Corrections section to **Snippets & Vocabulary** with add/edit/delete, search, an advanced list editor, malformed-line validation, and local preference storage.
- Rules replace case-insensitive whole words or phrases before filler cleanup, writing-mode formatting, and snippet expansion. They do not change the raw recognition; the existing Restore original recognition action still returns it.
- Added regression coverage for punctuation, whole-phrase boundaries, formatting order, malformed/duplicate rules, and the independent explicit spoken-correction setting. Updated README, acceptance protocol, product plan, and competitor roadmap.
- `xcodebuild ... test`: **49 passed, 0 failed, 0 skipped** on the MacBook Pro. The CoreSimulator version warning remains unrelated to macOS test execution.
- Rebuilt `dist/HushKey.app`; strict signature verification passed. Computer Use confirms the packaged app opens to Dictation with the microphone off and the latest bundle as the only running HushKey instance.
- Both GitHub Actions build-and-test runs for commit `66c0f63` passed on PR #1.

## Next item — live correction and voice acceptance

Navigate to Snippets & Vocabulary and validate rule creation/deletion, then dictate a real phrase to confirm correction application and raw restore. Continue the outstanding microphone, insertion, file, and meeting acceptance checks. Do not claim these paths passed until verified in the live app.

## Completed — Fog & sage palette, fn key, voice ribbon pill

- Replaced the warm paper/amber/serif look (too close to Wispr Flow) with **Fog & sage**: cool fog surfaces, charcoal ink, one sage `signal` accent, SF Pro Rounded display type. The next-step banner is now a light sage panel instead of a dark gradient. Stray reds/oranges/greens in Use, Evaluate, Vocabulary and the capture pad now use theme tokens. Tokens are in `docs/DESIGN_SYSTEM.md`.
- **fn (Globe) key is the default dictation key** (`FunctionKeyMonitor`). Hold fn to talk. Double-tap fn for hands-free; tap again to stop. fn plus any other key (arrows, F-keys, modifiers) never triggers dictation; a hold aborted that way discards the audio. Needs Accessibility access. Settings warns when access is missing or when “Press 🌐 key to” is not Do Nothing, links to the right System Settings pane, and offers Check again. Monitors re-arm when access is granted. The old ⌥⇧D style shortcuts remain as alternatives.
- New `cancelDictation()`: stops listening without transcribing, saving or inserting.
- Pill redesign: dark sage capsule with cancel ×, flowing `VoiceRibbon`, elapsed time, stop; "Writing it up" while finishing; "Typed" or "Copied to HushKey" when done. Verified live: listening state and cancel returned to idle.
- Tests: 53 passed, 0 failed (added `FunctionKeyGestureTests`).
- Not verified: fn key in another app (the debug build isn't in the Accessibility list yet), the done state with real speech, and dark mode by eye.

## Completed — pill recovery and transcript card: error state, retry, Paste again, Copy

- **Error phase** in the pill (`DictationNotice`, `HushKey/Recording/DictationRecovery.swift`): mic didn't start, couldn't transcribe, didn't catch that (empty result), couldn't type it, and "Click back into <App>". Short message, icon, stroke and dismiss × in `Theme.danger`; the full reason is in the tooltip and VoiceOver label. A stray click on the pill body does not start recording while an error shows. The pill panel is forced to dark appearance so tokens resolve to their dark values.
- **Retry**: the last dictation's microphone audio is copied into memory (`RetainedDictationAudio`, never written to disk, max 5 min; longer recordings are not kept). `MicTranscriber.transcribe(recorded:)` runs on-device recognition over it again with the same contextual hints. The audio is dropped once a transcript succeeds, and on dismiss, cancel, clear, restore or the next dictation.
- **Auto-type on finish (behaviour change)**: when insertion is on and a supported text field was focused at start, the finished text is typed into it, but only if that exact field still has focus (`TextInsertionService.insert(_:ifStillFocused:)` never switches apps). The done state now says "Typed" only when text was actually typed, otherwise "Ready in HushKey". Failure raises the error phase.
- **Transcript card** (`TranscriptCard`): a dark rounded card above the pill (#141B17, sage glyph) shows the last ~3 lines of live text while talking. With a target it appears once text arrives and collapses back to the pill after typing. With no target (insertion off or no supported field focused) it shows "No text box selected. Talk, then copy." from the start, and after finishing it stays up with the final text, a sage `PrimaryButtonStyle` Copy (NSPasteboard, only on click) and ×. Esc closes it through key monitors that run only while the card is up. × during listening hides the live text for that dictation.
- **Paste again** (`PasteAgainGate`): re-types the last dictation only while the original app and the same field have focus; otherwise the pill says "Click back into <App>" and keeps the button. Refuses while busy, without text, target or insertion, or when the dictation was already typed once.
- Tests: 65 passed, 0 failed (added `DictationRecoveryTests`: notice rules, paste-again gate, buffer copy and the 5-minute cap, card states and transcript tail).
- The pill now also starts and stops dictation from an accessibility press (VoiceOver); before, only a real mouse tap worked.
- Verified live (debug build, Finder frontmost, no text field): idle pill; the live card with hint, × and live text; after stop the card stayed up with the final text and Copy, and Copy put the text on the clipboard ("Copied" shown, `pbpaste` matched); the pill showed "Ready in HushKey"; the panel stayed anchored at the bottom while growing to 157 pt with nothing clipped.
- Not verified live: Esc closing the card, the error states (speech was always recognized), Retry, Paste again, and auto-type into a second app. Auto-type in browsers and Electron fields depends on their Accessibility support.

## Next items — each in a fresh session

1. Live fn-key acceptance: grant Accessibility to the packaged app, set Globe to Do Nothing, test hold, double-tap hands-free, fn+arrow and insertion in TextEdit plus one other app. Include the pill recovery paths: deny the mic, dictate silence → Retry, move focus before finishing → Paste again.
2. Settings rewrite: one-line label plus right-aligned control; drop the long captions.
3. Editable app profiles and dictionary/snippet import and export; local model diagnostics.

## Completed — local dictation eval harness

- Added a StarHarness-style eval with separate `dev` and `holdout` splits under [Fixtures/eval](Fixtures/eval/README.md). StarHarness itself was not run, and no remote model or service is used.
- Deterministic processor checks (43 cases: code tokens, line breaks, spoken corrections, snippets, filler cleanup) run in `xcodebuild test` and fail CI on any regression. Intended behavior that is not built yet is marked `knownGap` and reported, not gated. A split-disjointness test guards against leaked cases.
- `./Scripts/eval.sh` runs each clip through the app's `LocalFileTranscriber` (Apple on-device Speech) and any WhisperKit model already downloaded in HushKey via `WhisperKitFileTranscriber`, then through `DictationTranscriptProcessor` in Natural, Message, Email, and Code. It writes [docs/eval/report.md](docs/eval/report.md) and `report.json`. Audio scores are reported only.
- No consented recordings exist yet. The first numbers use local macOS text-to-speech clips (voice Samantha, not committed), which are cleaner than real speech, so WER is optimistic.
- First numbers, 2026-11-01:
  - Processor: dev 20/25 passed, holdout 12/18 passed, 0 regressions. The 11 known gaps are mostly Code-mode spacing (`user. id`, `print (name)`, `- - verbose`), "new line" replaced inside "new line of credit", "at" not accepted before a correction, and no capitalization after filler removal.
  - Apple Speech (en-US, on-device, 14 synthetic clips): WER dev 9.0%, holdout 7.8%; real-time factor about 0.06×. Per-mode checks: dev Natural 10/13, Message 2/2, Email 2/2, Code 4/4; holdout Natural 4/6, Message 2/2, Email 4/4, Code 2/4.
  - WhisperKit: skipped. No model is downloaded in HushKey, and the harness does not download one.
- Audio findings: Apple Speech applies "new line", "new paragraph", underscore, and parentheses itself in every mode, so Natural cannot keep "new line" literal. It also omits the comma before "actually", so spoken corrections did not trigger on audio.
- `xcodebuild test`: 37 tests, 0 failures, 1 skipped (the report test, which runs only from `Scripts/eval.sh`). In the first full run before this change, `testFoundationModelTransformRunsLocallyWhenAvailable` crashed with signal TERM. It passed when re-run alone and in later full runs, so it appears flaky.

## Next item — consented recordings and processor gaps

Record the 14 clip references as consented audio in `Fixtures/eval/<split>/audio/` with the user and rerun `./Scripts/eval.sh` for real-speech WER. Optionally download a WhisperKit model in the app to add a second engine. Then fix dev known gaps against the dev split only, and confirm holdout aggregates do not drop.

## Completed — everything merged into `feature/flow-style-ui`

- Merged into one branch in `~/Projects/HushKey`: the Fog & sage redesign with the fn key; pill recovery with the transcript card; Codex's per-app dictation profiles and local correction rules (`origin/feature/hushkey-macos-prototype` at ce524cc); and the eval harness (PR #2, `rudx/eval-harness`).
- Conflicts were resolved by keeping both sides. Dictation start now picks the per-app profile's mode and vocabulary and also records whether there is a text target. Finishing a dictation applies correction rules before the pill's recovery checks. Settings shows the app profiles editor above the fn key picker. The sidebar and page header keep Codex's accessibility identifiers (`sidebar.<screen>`, `page.header`) on the new layout.
- 73 tests ran: 72 passed, 1 skipped (eval holdout data), 0 failed. The first run after regenerating the project reported a failure that didn't reproduce on two reruns.
- Checked live in the main-checkout build: the home screen and the Settings Insertion tab render. The app profiles editor (Settings → General) and Codex's correction-rules UI were not looked at, because the background controls can't switch the Settings tabs.
- Location: `~/Documents/ChatGPT/HushKey` is a **different repository** (`amirrsyed/hushkey`, MIT, with a Swift app plus a Python backend). Codex has uncommitted work there on `ruex/voice-dictation-features`. It is not this project, so it was left untouched. Codex's work on *this* project arrives through `origin/feature/hushkey-macos-prototype`.

## Next items

1. Push `feature/flow-style-ui` and open a PR (or retarget PR #1).
2. Live acceptance: the fn key in other apps, pill error/Retry/Paste again, Esc closing the card.
3. Settings rewrite (one-line labels and right-aligned controls), including the Codex profile and correction-rule editors in Fog & sage.

## Completed — prevent cleared file history from repopulating

- Closing an audited race: clearing Recent file transcripts now suppresses save callbacks for transcription jobs that were already running. The current transcript stays available to export and is explicitly reported as excluded from the cleared archive; later jobs save normally.
- Added an AppModel storage-URL seam and regression coverage that reproduces the clear-then-completion callback sequence.
- Updated the live file-transcription checklist with the in-flight clear scenario. Runtime acceptance is still pending.

## Completed — Apple Speech file acceptance and subtitle bounds (2026-11-01)

- Used a locally generated 5.30-second synthetic speech file. Apple Speech transcribed it on this Mac without a remote fallback; the output was suitable for workflow checks, not an accuracy benchmark.
- Edited the transcript, searched Recent, switched away and back, quit and reopened HushKey, and confirmed the edited text and timed cues restore from local history.
- Exported TXT, SRT, and WebVTT through the packaged app's save panels. The source remained unchanged; the history archive contains transcript text and cues but no audio file or audio field.
- The acceptance run found the final Apple Speech cue extended to 5.46 seconds for a 5.30-second source. An initial bounded export ended at 5.302 seconds. Both Apple Speech and WhisperKit now clamp cues to the source duration and round the final boundary down to milliseconds; a regression test verifies 5.301 seconds for a 5.30195-second source. That final rounding is unit-tested but has not yet been re-exported live.
- Added a regression test for clipped, out-of-range, negative, and non-finite subtitle cues. `xcodebuild ... test`: 103 tests, 101 passed, 2 skipped, 0 failed. The signed Release app was rebuilt and opened.
- After rebuilding, the latest packaged app first stalled at “Waiting for macOS Speech permission…”. On a later retry, HushKey's setup checklist advanced to 3 of 4, but opening the sample did not complete file transcription and the app changed to Dictation/Listening. That session was stopped; no file transcript was saved. The final millisecond-bounded SRT/WebVTT export remains unverified live. The signed Release app is currently idle on Dictation; its pre-existing dictation history was left intact.

## Completed — cancellable permission startup and modal shortcut guard (2026-11-01)

- Added status-first microphone and Speech permission requests with one-shot callback handling, cancellation, and a 30-second timeout. An unanswered macOS prompt now produces a retryable error instead of leaving HushKey busy indefinitely.
- Dictation now prepares on-device Speech before opening the microphone. Startup has a visible Preparing state and can be canceled by the button, Escape, or releasing the hold shortcut while permission is pending. Canceling also stops any pending microphone request.
- File transcription uses the same bounded Speech permission request. Fn gestures are ignored while AppKit modal panels are open; an in-progress hold/hands-free gesture is stopped when a modal event arrives, and dictation startup is rejected while a panel is active.
- Added tests for callback completion, timeout, cancellation, duplicate callbacks, and modal interruption. `xcodebuild ... test`: 107 passed, 2 skipped, 0 failed.
- Rebuilt and opened `dist/HushKey.app`; signature verification passed. The machine has no valid signing identity, so packaging uses an ad-hoc signature. The new bundle now shows setup 1 of 4; microphone/Speech permission and live dictation were not re-approved or retested after repackaging.

## Next item — restore permissions, then live acceptance

After the user approves the current HushKey build's local microphone and Speech prompts, verify startup cancellation, live dictation, file transcription and the final bounded SRT/WebVTT export. Then download the Tiny model, verify offline transcription and timed exports, and exercise clearing history during a live job. Continue with insertion and meeting acceptance afterward.

## Completed — one working copy

- Codex had been working in a separate clone (`~/Documents/Codex/2026-11-01/…/outputs/HushKey`) on the retired `feature/hushkey-macos-prototype` branch. Its uncommitted fix for file history repopulating after a clear is now merged here as 6405ce5. 74 tests ran: 73 passed, 1 skipped, 0 failed.
- Added `AGENTS.md`: `~/Projects/HushKey` on `feature/flow-style-ui` is the only working copy for every agent. The old Codex clone got an untracked `AGENTS.md` telling Codex to stop working there.
- Checked `amirrsyed/hushkey`: an unrelated MIT webcam lip-reading project with the same name. Notes are in `docs/CRITIQUE_AND_ROADMAP.md`.

## Completed — borrowed ideas, data-folder safety, end-to-end status

- **Esc** cancels a listening dictation from any app; nothing is typed.
- **Paste fallback with clipboard restore:** when a field refuses direct Accessibility typing (many browsers and Electron apps), HushKey pastes, then puts the user's clipboard back unless they copied something in the meantime. It never pastes into password fields or into a different field than the one dictated from. A Settings toggle controls it; on by default.
- **Paired bootstrap** comparisons in `docs/eval/report.md`: engine against engine, and this run against the previous report. The live eval run shows apple-speech at 9.0% WER on dev and 7.8% on holdout, unchanged from the previous report.
- **Data folder moved** to `~/Library/Application Support/com.ruddvz.hushkey`. On case-insensitive disks the old `…/HushKey` is the same folder amirrsyed/hushkey uses, and its uninstaller offers to delete it. Only HushKey's own files are moved, and the real user data migrated on relaunch.
- Tests: 80 ran; 79 passed, 1 skipped, 0 failed.
- **Not verified live:** a spoken dictation through the microphone. A speaker-to-mic test gave "No speech detected" at the user's volume settings. Also unverified: the fn key and the paste fallback in other apps (the debug build lacks Accessibility access), Esc, and the pill's error/Retry/Paste again.

## Next item — live acceptance with the user

Give the build Accessibility access and set Globe to Do Nothing. Then, with the user speaking, check: fn hold and double-tap in TextEdit, Safari or Chrome, and Slack; the paste fallback and clipboard restore; Esc; Retry and Paste again. Record the results in `docs/TESTING_PROTOCOL.md`.

## Completed — Wispr-level layout pass (2026-11-01)

- **Measured Wispr Flow** (home, Dictionary, Snippets, Transforms, Notetaker, Settings, idle bar) and recorded a token table in `docs/DESIGN_SYSTEM.md`. Matched structure, spacing and type sizes; kept Fog & sage, SF Pro Rounded, MorphIcon and the voice ribbon.
- **New shared pieces** (`Components.swift`): `SettingsGroup`/`SettingsRow`/`GroupRow`, `ListGroup`/`ListRow`, `MenuPicker`, `RowToggle`, `UnderlineTabs`, `EmptyState`, `LabProgress`, `LabHero`. Buttons are now 36 pt rounded rectangles; type scale is 28/22/18/16/15/13/12. No stock `GroupBox` remains in the pages.
- **Pages:** Settings (section nav, grouped rows, privacy card, About with version), Dictation home (1040 column, 52 pt history rows), Transforms (card grid, text card with Preview, preview card), Files (hero, engine rows, recent list), Meeting notes (capture hero, note list, sectioned editor), Vocabulary (tabs with counts, hero with your own examples, hover rows), Silent Lab (shared progress strip; Setup hero with live metrics; Train word list and capture hero; Evaluate verdict card, feature chips, evidence rows; Silent Use lock hero and capture rows).
- **Pill:** one `SpeechEnvelope` drives the ribbon, bars and morph icon. The morph icon used a fixed 0.3 threshold (noise moved it; quiet mics never did) and the ribbon floor rose per sample, flattening long sentences. A dictation started with no field focused is now typed if a field has focus when it ends; otherwise the card stays with Copy (⌘C) and, if typing is off, a link to turn it on.
- Screenshot-checked side by side with Wispr: Settings, home, Transforms, Vocabulary vs Dictionary, Meeting notes vs Notetaker, idle bar. Files and Silent Lab have no Wispr equivalent and were checked on their own.
- Tests: 95 ran, 93 passed, 2 skipped, 0 failed (6 new `SpeechEnvelopeTests`).
- **Not verified live:** the pill's hover, listening, finished-card and error states, and the new "type into the field focused at the end" path. Both need a spoken dictation with Accessibility access.

## Next item — live acceptance with the user (unchanged, now including the pill)

Same as above, plus: start a dictation with no field focused, click into TextEdit while talking, and confirm it types there; with typing off, confirm the card shows Copy and the "Type for me next time" link.

## Completed — validated personal data backup (2026-11-01)

- Added versioned JSON export/import for recent dictations (including raw recognition), vocabulary, snippets, and correction rules. No audio is included.
- Imports reject unknown versions, oversized files, malformed/duplicate terms or rules, duplicate history IDs, and invalid entries before applying changes. Users choose Merge or Replace; Merge preserves local conflicts and adds missing records.
- An approved import can restore an unreadable dictation archive after preserving a recovery copy where possible. The import is staged and does not change local data until confirmation.
- Added a Settings → Data & privacy flow, a format/privacy guide, and manual acceptance steps.
- Live UI review confirmed the export and import panels open. The replace action now says “Replace backed-up data” and names the local records it leaves untouched.
- `xcodebuild ... test`: 102 tests ran, 100 passed, 2 skipped, 0 failed.
- A valid sample opened the confirmation and was canceled without changing data. Actual export/import transfer and live voice/insertion acceptance remain to be verified on the packaged app.

## Completed — protect unreadable local history archives (2026-11-01)

- Dictation, file-transcript, and meeting-note stores now distinguish missing files from unreadable archives. On decode/read failure, HushKey preserves a recovery copy when possible and refuses to overwrite the unreadable original.
- Each history page reports the problem and offers an explicit archive removal action. The backup remains in Application Support; subsequent saves resume after removal.
- Added regression coverage for backup preservation, overwrite prevention, repeated corruption with different contents, visible recovery state, explicit reset, and successful writes afterward.
- `xcodebuild ... test`: 98 tests ran, 96 passed, 2 skipped, 0 failed.
- Live microphone, Accessibility insertion, and device validation remain unverified; use the acceptance checklist above.

## Completed — prevent history deletion from undoing itself (2026-11-02)

- Deleting the active dictation cancels its delayed autosave and prevents the removed entry from returning while preserving the current transcript on screen.
- File-transcript deletion now reports success or failure. The editor leaves a failed-to-delete session active so later edits continue saving.
- Added regression tests for both cases. `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test`: 118 passed, 2 skipped, 0 failed.
- Packaged Release app at `~/Projects/HushKey/dist/HushKey.app`; strict code-signature verification passed, and the latest app bundle is open.
- Live microphone, Speech, Accessibility insertion, meeting capture, and export acceptance still need a user-approved device session. Start that as the next item in a fresh session.

## Completed — put research capture where it belongs (2026-11-02)

- Moved the research-session controls out of Settings → Data & privacy and into Silent Lab → Setup, beside live motion diagnostics. Data & privacy now only manages stored files and backup.
- Microphone audio is an explicit, saved opt-in that starts off. Session recording attaches audio only when the option is enabled and HushKey’s microphone is already running; the session metadata records the choice. Start is disabled until motion is streaming, and Stop remains available during a capture.
- Verified the packaged app’s accessibility state: Data & privacy no longer contains recording controls; Silent Lab Setup shows the audio option off and Start disabled while headphones are unavailable. No permissions were accepted and no recording was made.
- `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test`: 119 passed, 2 skipped, 0 failed. Release packaging and strict signature verification passed; only `/Users/rudra/Projects/HushKey/dist/HushKey.app` remains open.
- Next: user-approved live microphone, insertion, meeting, and export acceptance in a fresh session.

## Completed — make personalization sections match their navigation (2026-11-02)

- Vocabulary, Snippets, and Corrections now each show the selected section as the page title and a matching single add action. Removed the duplicate add button from the explanatory banner.
- Checked the packaged app’s accessibility tree across all three tabs: titles and add actions match the selected section, and empty states are clear.
- `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test`: 119 passed, 2 skipped, 0 failed. Release packaging and strict signature verification passed.
- Next: live user-approved microphone, insertion, meeting, and export acceptance; this UI-only task did not change permissions or personal data.

## Completed — include writing styles in personal backups (2026-11-02)

- Personal backup format v2 exports custom writing styles. Version-1 backups still import; Replace preserves local writing styles because older backups never contained that data.
- Merge keeps local styles on ID/name conflicts and reports capacity overflow rather than silently discarding imported styles. Imported styles appear immediately in the transform screen.
- `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test`: 121 passed, 2 skipped, 0 failed. Release package built and strict signature verification passed; only `~/Projects/HushKey/dist/HushKey.app` was opened.
- Live microphone, Speech, Accessibility insertion, meeting capture, and export acceptance still need a user-approved device session. Start that as the next item in a fresh session.

## Completed — align backup documentation with format v2 (2026-11-02)

- README, the personal-backup guide, and acceptance steps now document writing-style export/import, version-1 compatibility, Replace behavior, Merge conflict rules, and the 12-style capacity limit.
- Checked the documented behaviors against the current validator, importer, and existing passing regression tests. Documentation-only change; no build or test rerun.
- Next: complete live dictation, selected-text insertion, meeting, and file-transcription acceptance in a user-approved device session.

## Completed — restrict paste fallback to supported text controls (2026-11-02)

- Paste fallback previously accepted any focused control except a secure field, which could make an unsupported non-text control look insertable. It now uses the same explicit text-field role whitelist as direct insertion and still excludes secure/password fields.
- Added regression coverage for text fields, text areas, combo boxes, buttons, groups, and secure fields; updated the live acceptance protocol to cover fallback behavior.
- Updated Settings and README copy to disclose that fallback briefly uses the clipboard and restores it only if no newer clipboard change needs protection.
- `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test`: 121 passed, 2 skipped, 0 failed.
- Release packaging succeeded and `codesign --verify --deep --strict dist/HushKey.app` passed; the updated packaged app is open.
- Next: perform live insertion and fallback acceptance in a user-approved session; paste fallback remains unverified against third-party applications.

## Completed — keep file transcript edits when a source switch cannot save (2026-11-02)

- Choosing another audio file now waits for the active file transcript to save successfully before clearing its text, session ID, or selected source. A failed save leaves the current edit open for recovery.
- Added regression coverage for both failed-save and successful-save transitions, and added the failure case to the manual file-transcription acceptance protocol.
- `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test`: 123 passed, 2 skipped, 0 failed.
- Release package built, strict signature verification passed, and the updated app is open.
- Next: live file-transcription acceptance in a user-approved session.


## Completed — keep meeting action sentences intact across chunks (2026-11-02)

- Meeting transcripts now split at the latest complete sentence that fits within the chunk limit, preserving nearby owners, tasks, and deadlines for each local summary pass. Sentences longer than the limit still fall back to a word boundary.
- Added regression coverage for an owner/task/deadline sentence near a chunk boundary.
- `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test`: 126 passed, 2 skipped, 0 failed.
- Release package built, strict signature verification passed, and the updated app is open.
- Next: live file-transcription and meeting-capture acceptance in a user-approved session.


## Completed — prevent clearing history during active dictation (2026-11-02)

- History clearing is blocked while dictation is starting, recording, transcribing, or finalizing. The History options menu is disabled during that window, and the model guard also rejects a stale confirmation if capture starts after the dialog opens.
- Added unit coverage for each busy state and a live acceptance step to confirm a finished dictation cannot repopulate history after deletion.
- `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test`: 127 passed, 2 skipped, 0 failed. Release packaging succeeded and strict signature verification passed; the updated app is open.
- GitHub Actions did not start this commit's hosted job: GitHub reported that account payments failed or the spending limit must be increased. The local build and test run passed.
- Next: live file-transcription, meeting-capture, and history-clear acceptance in a user-approved session.


## Completed — recover interrupted meeting transcripts (2026-11-02)

- Meeting capture now checkpoints recognized text locally at least every two seconds while updates arrive; audio remains transient. Stop promotes the final checkpoint into the meeting archive and removes the temporary file only after the note is saved.
- On relaunch, HushKey offers the partial transcript with source and duration so the user can save it as a note or explicitly discard it. If saving the note fails, the checkpoint remains available.
- Added regression coverage for checkpoint/relaunch/recovery and preserving the draft when promotion fails. Updated privacy copy, product plan, and manual force-quit acceptance steps.
- `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test`: 129 passed, 2 skipped, 0 failed. Release packaging succeeded; strict signature verification passed and the updated app is open.
- Live force-quit recovery and microphone/system-audio capture still need a user-approved session. GitHub Actions hosted jobs remain unable to start due the account payment/spending-limit restriction.
- Next: live meeting crash-recovery and file-transcription acceptance in a user-approved session.
