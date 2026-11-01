# HushKey

HushKey is a native macOS dictation app with a separate experimental lab for silent mouthing. Voice and softly whispered speech use macOS on-device recognition; silent motion decoding is limited to a small, user-trained vocabulary and is not general lip reading.

## Current status

- macOS 14 or later; designed for Apple Silicon and Intel Macs.
- The app opens to Voice & Whisper dictation. Use the button, hold the configurable global shortcut (`⌥⇧D` by default), or choose press-to-toggle; then review/edit, copy, or optionally insert a complete phrase into a supported text field.
- Speech recognition uses Apple's on-device Speech framework and exposes languages supported for on-device recognition on this Mac. HushKey does not send audio to a remote service.
- Recent transcripts can be saved on this Mac (enabled by default and switchable in Settings); personal vocabulary hints and spoken-phrase snippets also stay local. HushKey does not save microphone audio during ordinary dictation.
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

HushKey opens as a normal Mac app window and also offers a menu-bar shortcut. Voice dictation does not require AirPods or Motion permission. To try the Silent Lab, open **Setup**, connect compatible headphones, choose them as the Mac's active audio output, and check for a live stream. If Motion access is denied, change it in **System Settings → Privacy & Security → Motion**.

The packaged app is at `dist/HushKey.app`. Xcode's local test/build output uses `.build`; the packaging script clears stale Debug/Release app copies and builds in a temporary directory, leaving one HushKey app to open.

## Dictation flow

1. Use **Start dictation**, hold the configurable global shortcut (`⌥⇧D` by default), or choose press-to-toggle in **Settings & Data**. The shortcut works from any app; HushKey listens only while dictation is active.
2. Stop when you’re finished. Edit the recognized phrase, then **Copy text** or enable Accessibility and choose **Insert into current app**. The insertion shortcut (`⌥⇧I` by default) inserts the current output once into the focused supported field.
3. Reload a recent transcript from the local history list. Add names or uncommon words under **Settings & Data → Personal vocabulary** to provide local recognition hints. Add `spoken cue => expanded phrase` lines to expand snippets when you stop dictating.

## Silent Lab

1. In **Setup**, confirm a live motion stream. Expand diagnostics to see acceleration, rotation, and attitude.
2. In **Train**, select **Normal voice**, **Whisper**, or **Silent mouthing** as the study condition; select a word and hold the on-screen control or the configurable app-local shortcut (`⌥⇧M` by default). Space is never captured as a shortcut.
3. Use **New session** before a separate held-out run. Collect at least 10 takes for each of 5 or more words.
4. In **Evaluate**, compare motion features. Results include leave-one-out accuracy, majority baseline, a 500-run label-permutation test, confusion matrix, and session-separated holdout.
5. **Silent Use** unlocks only when the Silent condition beats chance, passes the permutation check, and beats baseline on a separate-session holdout. It rejects weak matches instead of guessing.
6. Auto-capture is experimental. Calibrate while still, tune the motion-energy threshold, and measure false positives during ordinary head movement, chewing, and repositioning.

## Safe text insertion

Text insertion is off by default. Enable it in **Settings & Data**, approve HushKey under **System Settings → Privacy & Security → Accessibility**, then press **Insert into current app** or the displayed configurable global shortcut (`⌥⇧I` by default) while the intended text field remains focused in another app.

HushKey uses Accessibility to inspect the frontmost app and focused control, allows only supported text fields, rejects secure/password controls, rechecks the process and focus immediately before insertion, and writes through the selected-text attribute once. It does not use or modify the clipboard. Unsupported controls fail closed.

## Local data and privacy

- Templates: `~/Library/Application Support/HushKey/dataset.json`.
- Recent dictations: `~/Library/Application Support/HushKey/dictation-history.json`.
- Experiment sessions: `~/Documents/HushKey/Sessions/`, with motion CSV, event CSV, metadata, and optional microphone audio.
- No telemetry, upload, cloud service, or paid API is used by HushKey.
- Use **Settings & Data** to configure shortcuts and vocabulary hints, choose the microphone, enable/disable transcript history, record synchronized sessions, export the dataset or sessions, and delete local files. Clear recent transcripts from the Dictation screen.
- Voice recognition requires the user to start the mic and is local-only; no remote recognition fallback is used. Audio is saved only if the separate research recorder is explicitly active.

## Project naming

HushKey is the requested working name for this private prototype. A separate public macOS silent-dictation project already uses the same name: [amirrsyed/hushkey](https://github.com/amirrsyed/hushkey). Revisit the public product name before any public release.

## Limits

Headphone motion is processed and low-rate (often about 25 Hz). Jaw movement and head motion can dominate the signal, and reseating the headphones can change the measurements. A result on a small trained vocabulary does not establish arbitrary phrase recognition. Voice, whisper, and silent-mouthing results must be evaluated separately and across sessions before drawing conclusions.

HushKey does not currently include cloud transcription, LLM rewriting, app-specific writing styles, command processing, file transcription, or workflow/plugins. Speech languages depend on what macOS supports for on-device recognition on this Mac. These are separate features from the silent-motion experiment and are not implied by the current build.

See [docs/TESTING_PROTOCOL.md](docs/TESTING_PROTOCOL.md) for the repeatable study and hardware-validation procedure. See [docs/PRODUCT_PLAN.md](docs/PRODUCT_PLAN.md) for the screen flow and file map. See [NOTICE.md](NOTICE.md) for source attribution and license boundaries.
