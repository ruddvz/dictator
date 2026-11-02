# HushKey

HushKey is a native macOS dictation app with a separate experimental lab for silent mouthing. Voice and softly whispered speech use macOS on-device recognition; silent motion decoding is limited to a small, user-trained vocabulary and is not general lip reading.

## Current status

- macOS 14 or later; designed for Apple Silicon and Intel Macs.
- The app opens to Voice & Whisper dictation. Use the button, hold the configurable global shortcut (`⌥⇧D` by default), or choose press-to-toggle; then review/edit, copy, or optionally insert a complete phrase into a supported text field. For the one-click Insert button, start with the shortcut while the destination field is focused; HushKey keeps that target in memory and rechecks it before returning to insert.
- Speech recognition uses Apple's on-device Speech framework and exposes languages supported for on-device recognition on this Mac. HushKey does not send audio to a remote service.
- Dictation includes Natural, Message, Email, Code, and Automatic modes; explicit spoken corrections with raw-transcript restore; local recognition hints, snippets, and deterministic correction rules; and a one-step guarded insertion undo. Automatic mode maps common Mac apps and supports local per-app overrides for writing mode, vocabulary, on-device language, snippets, correction rules, filler cleanup, and an optional Transform style. Explicit modes use the global preferences.
- **Transforms** offers review-first local polish, concise, professional, bullets, and action-item drafts using Apple's on-device Foundation Model when available (macOS 26+); conservative filler removal works without a model on macOS 14+. Create up to 12 local writing styles for tone, format, or translation. Every generated draft stays reviewable and can be undone; HushKey has no cloud fallback.
- **Voice edit selected text** lets you select text in another app, hold `⌥⇧E` (configurable), and speak an edit instruction. HushKey reads the selection only after that shortcut, creates an on-device preview, and rechecks the original app, field, text, and selection before Apply. The instruction and selection are not added to dictation history. This flow requires Accessibility insertion and Apple's on-device Foundation Model (macOS 26+).
- Optional local filler cleanup removes only standalone “um”, “uh”, and “erm”; it is off by default. Snippet settings report malformed lines instead of silently ignoring them.
- **Transcribe files** accepts one audio file at a time and exports editable text, SRT, or WebVTT captions. Choose Apple Speech for zero-download on-device recognition where supported, or explicitly download a WhisperKit model for offline inference after setup. Model downloads require internet; audio files are not uploaded.
- **Meeting notes** provides explicit microphone, system-audio, or combined capture, a searchable local transcript archive, editable transcripts, and TXT export. Choose **Both sides** to combine your selected microphone with Mac app audio; macOS may request separate microphone and System Audio Recording permissions. System audio requires macOS 14.2+. Meeting audio is streamed to on-device Speech and is not saved; the transcript is stored when capture stops. Summary and action-item drafts use Apple's on-device Foundation Model (macOS 26+), with no cloud fallback. HushKey does not identify speakers.
- Optional nearby-text hints are off by default. After a separate Accessibility opt-in, HushKey reads only a bounded slice around the cursor in a supported text field to extract local recognition terms; it discards the slice and does not store it.
- Recent transcripts can be saved on this Mac (enabled by default and switchable in Settings). HushKey does not save microphone audio during ordinary dictation.
- **Personal data backup** in Settings exports/imports recent dictations (processed and raw text), vocabulary, snippets, correction rules, custom writing styles, and Automatic app profiles as local JSON. Import is validated and offers Merge or Replace; version-1 and version-2 backups remain supported, and audio is not included. See the [backup guide](docs/PERSONAL_DATA_BACKUP.md).
- Motion input uses Apple's `CMHeadphoneMotionManager`. It sees processed head motion from compatible head-tracking headphones, not an inward-facing speech sensor or the AirPods speech-detecting accelerometer.
- Motion permission is requested only when you open **Silent Lab → Setup**. Setup checks live motion availability, permission, connection, and sample rate. It cannot identify the exact AirPods model. Apple documents headphone motion in [Core Motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager) and its [headphone motion sample](https://developer.apple.com/documentation/CoreMotion/getting-motion-activity-data-from-headphones); the headphones must be connected and selected as the Mac's audio output.
- Silent decoding is experimental and remains locked until the selected Silent condition reaches the minimum study size, beats the majority baseline with a label-permutation test (`p < 0.05`), and beats baseline on a separate-session holdout.
- No AirPods are required to build or run unit tests. Hardware performance has not been claimed or tested by CI.

## Build and run

Requirements: Xcode with the macOS SDK and XcodeGen.

```sh
brew install xcodegen
./Scripts/package-app.sh
open dist/HushKey.app
```

Run the tests:

```sh
xcodegen generate
xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test
```

Run the local dictation eval (dev and holdout splits, Apple on-device Speech plus any WhisperKit model already downloaded in HushKey):

```sh
./Scripts/eval.sh
```

It writes [docs/eval/report.md](docs/eval/report.md) and `report.json`. Processor checks are deterministic and also run in `xcodebuild test`; recognition scores are reported, not gated. The first run asks for Speech recognition permission for the test host. Fixtures, splits, and how to add consented recordings are described in [Fixtures/eval/README.md](Fixtures/eval/README.md).

HushKey opens as a normal Mac app window and also offers a menu-bar shortcut. Voice dictation does not require AirPods or Motion permission. To try the Silent Lab, open **Setup**, connect compatible headphones, choose them as the Mac's active audio output, and check for a live stream. If Motion access is denied, change it in **System Settings → Privacy & Security → Motion**.

The packaged app is at `dist/HushKey.app`. The packaging script builds in an isolated temporary directory and replaces only this app bundle; it leaves other Xcode build products untouched.

## Dictation flow

1. Use **Start dictation**, hold the configurable global shortcut (`⌥⇧D` by default), or choose press-to-toggle in **Settings & Data**. The shortcut works from any app; HushKey listens only while dictation is active.
2. Choose a writing mode. **Automatic** maps common email, messaging, and code apps when the global shortcut starts dictation. In **Settings & Data → App profiles**, add a bundle identifier, writing mode, and extra terms. Open **Optional app-specific overrides** to choose a local language, snippets, correction rules, filler cleanup, or a saved Transform style. Overrides apply only when Automatic dictation starts from that app; explicit modes use the global preferences. Profiles use app identity only and do not read app text. **Code** formats spoken symbols, while Message and Email support spoken line breaks. Corrections such as “scratch that” are applied only with an explicit pause cue.
3. Stop when you’re finished. Edit the recognized phrase, restore the original recognition if needed, then **Copy text** or enable Accessibility and choose **Insert into current app**. The insertion shortcut (`⌥⇧I` by default) inserts the current output once into the focused supported field. Press `⌥⇧U` immediately in that same unchanged field to undo.
4. Search recent transcripts and restore either the processed text or original recognition. Add names under **Snippets & Vocabulary → Vocabulary** for local recognition hints (or use **Import…/Export…** there to move a plain-text word list, one term per line or comma-separated, to and from other apps), common phrases under **Snippets**, and repeatable misspelling replacements under **Corrections**. Corrections apply locally to complete word or phrase matches; raw recognition remains available to restore.
5. Open **Transforms** to create and edit a local preview. Apply it only after review; undo restores the prior transcript. Model-backed actions require macOS 26+ with Apple's on-device model available. Filler removal uses local text rules and works on supported macOS 14+ systems.

## Local transforms

Choose **Polish**, **Make concise**, **Professional**, **Bullet points**, or **Action items** for a reviewable draft from Apple's on-device Foundation Model. HushKey has no remote fallback. When Apple Intelligence is unavailable or preparing, the app explains that those actions cannot run. **Remove fillers** is a deterministic local cleanup and does not require Apple Intelligence. Every draft is editable and must be explicitly applied; stale previews cannot replace a transcript that changed after generation. Undo is available until the transcript changes or is inserted.

## Meeting notes

Open **Meeting notes**, choose **Microphone**, **System audio**, or **Both sides**, then choose **Start meeting**. HushKey requests the selected source's permission only after you start capture. System audio is available on macOS 14.2+ and captures audio playing from apps across the Mac; pause unrelated playback before starting. **Both sides** combines the selected microphone with app audio in one on-device recognition stream and requires both macOS permissions. Audio is never saved. Partial transcript text is checkpointed locally during capture so an interrupted meeting can be recovered; after Stop, HushKey saves it as a searchable note and removes the temporary checkpoint. You can edit the transcript/title, create a reviewable local summary or action-item list (macOS 26+ with Apple's on-device model), delete a note after confirmation, or export transcript/all notes as text. The summary process breaks long transcripts into bounded local chunks and supports up to 120,000 characters. HushKey does not identify speakers.

## Silent Lab

1. In **Setup**, confirm a live motion stream. Expand diagnostics to see acceleration, rotation, and attitude.
2. In **Train**, select **Normal voice**, **Whisper**, or **Silent mouthing** as the study condition; select a word and hold the on-screen control or the configurable app-local shortcut (`⌥⇧M` by default). Space is never captured as a shortcut.
3. Use **New session** before a separate held-out run. Collect at least 10 takes for each of 5 or more words.
4. In **Evaluate**, compare motion features. Results include leave-one-out accuracy, majority baseline, a 500-run label-permutation test, confusion matrix, and session-separated holdout.
5. **Silent Use** unlocks only when the Silent condition beats chance, passes the permutation check, and beats baseline on a separate-session holdout. It rejects weak matches instead of guessing.
6. Auto-capture is experimental. Calibrate while still, tune the motion-energy threshold, and measure false positives during ordinary head movement, chewing, and repositioning.

## Safe text insertion

Text insertion is off by default. Enable it in **Settings & Data**, approve HushKey under **System Settings → Privacy & Security → Accessibility**, then use the configurable global shortcut (`⌥⇧I` by default) in a supported text field. For the Dictation screen's named-target Insert button, start dictation with its global shortcut while that field is focused.

HushKey uses Accessibility to inspect the frontmost app and focused control, allows only supported text fields, rejects secure/password controls, and rechecks the process, field contents, and selection before insertion. Direct typing uses the selected-text attribute. If typing is declined and **Paste fallback** is enabled, HushKey temporarily places the text on the clipboard, waits up to two seconds for the same field to expose the exact expected text, then restores the prior clipboard if nothing else changed it meanwhile; otherwise it leaves the newer clipboard contents intact. A paste that cannot be verified is reported as uncertain, and the transcript stays available. Check the target field before choosing **Paste again**, because it may already have received the text. Unsupported controls fail closed. Undo is available only while the same field stays focused and its contents remain unchanged.

For a voice edit, select text in another app and hold the dedicated selected-text shortcut (`⌥⇧E` by default). Say an instruction, release, then review the preview in **Transforms**. Apply is explicit and fails closed if the original app, field contents, or selection changed. Spoken edit instructions are not saved in dictation history.

## Local data and privacy

- Templates: `~/Library/Application Support/HushKey/dataset.json`.
- Recent dictations: `~/Library/Application Support/HushKey/dictation-history.json`.
- File transcription history: `~/Library/Application Support/HushKey/file-transcription-history.json` (up to 50 searchable jobs with edited text and timed cues; source audio is not copied).
- Experiment sessions: `~/Documents/HushKey/Sessions/`, with motion CSV, event CSV, metadata, and optional microphone audio.
- No telemetry, remote text processing, or paid API is used by HushKey. WhisperKit model files are fetched only after the user asks to download a model; the selected file is then processed locally.
- Use **Settings & Data** to configure shortcuts and vocabulary hints, choose the microphone, enable/disable transcript history, record synchronized sessions, export the dataset or sessions, and delete local files. Clear recent transcripts from the Dictation screen.
- Voice recognition requires the user to start the mic and is local-only; no remote recognition fallback is used. Audio is saved only if the separate research recorder is explicitly active.
- WhisperKit models are stored at `~/Library/Application Support/HushKey/WhisperKitModels/`; choose **Remove model** in **Transcribe files** to reclaim the downloaded model files.
- Nearby-text hints require an explicit opt-in and Accessibility permission. HushKey extracts terms transiently; it does not save the surrounding text.

## Project naming

HushKey is the requested working name for this private prototype. A separate public macOS silent-dictation project already uses the same name: [amirrsyed/hushkey](https://github.com/amirrsyed/hushkey). Revisit the public product name before any public release.

## Limits

Headphone motion is processed and low-rate (often about 25 Hz). Jaw movement and head motion can dominate the signal, and reseating the headphones can change the measurements. A result on a small trained vocabulary does not establish arbitrary phrase recognition. Voice, whisper, and silent-mouthing results must be evaluated separately and across sessions before drawing conclusions.

HushKey includes local text transforms and a preview-first selected-text voice-edit workflow, but they are not a claim of full Wispr Flow or TypeWhisper parity. A generated draft can change meaning and must be reviewed. HushKey does not include workflow/plugin automation. Live acceptance of selected-text editing, microphone capture, file models, and meeting sources remains important; Apple Speech, WhisperKit, and Apple Foundation Model availability depends on the chosen local engine, supported OS, and device readiness. These are separate features from the silent-motion experiment and are not implied by its results.

## Research reports

- [Wispr Flow vs TypeWhisper report (PDF)](docs/research/Wispr_Flow_vs_TypeWhisper_Research_Report_2026-11-01.pdf)
- [HushKey competitor landscape and product opportunities](docs/COMPETITOR_RESEARCH.md)
- [Report index and how findings map to HushKey](docs/research/README.md)

HushKey does not rebrand or bundle TypeWhisper code. TypeWhisper's upstream repository uses GPLv3 and states that rebranded distributions require a separate commercial license; HushKey implements its own local features and keeps the source project's license boundary. See [NOTICE.md](NOTICE.md) and the report index for attribution and scope.

See [docs/TESTING_PROTOCOL.md](docs/TESTING_PROTOCOL.md) for the repeatable study and hardware-validation procedure. See [docs/PRODUCT_PLAN.md](docs/PRODUCT_PLAN.md) for the screen flow and file map. See [NOTICE.md](NOTICE.md) for source attribution and license boundaries.
