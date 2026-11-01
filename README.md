# HushKey

HushKey is a native macOS app for local experiments with silent mouthing and processed headphone motion. It is a research prototype for a small, user-trained vocabulary, not general dictation or hidden lip reading.

## Current status

- macOS 14 or later; designed for Apple Silicon and Intel Macs.
- Motion input uses Apple's `CMHeadphoneMotionManager`. It sees processed head motion from compatible head-tracking headphones, not an inward-facing speech sensor or the AirPods speech-detecting accelerometer.
- Setup checks live motion availability, permission, connection, and sample rate. It cannot identify the exact AirPods model. Apple documents headphone motion in [Core Motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager) and its [headphone motion sample](https://developer.apple.com/documentation/CoreMotion/getting-motion-activity-data-from-headphones); the headphones must be connected and selected as the Mac's audio output.
- Silent decoding is experimental and remains locked until the selected Silent condition reaches the minimum study size, beats the majority baseline with a label-permutation test (`p < 0.05`), and beats baseline on a separate-session holdout.
- No AirPods are required to build or run unit tests. Hardware performance has not been claimed or tested by CI.

## Build and run

Requirements: Xcode with the macOS SDK and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath build build
open build/Build/Products/Debug/HushKey.app
```

Run the tests:

```sh
xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath build test
```

HushKey appears in the menu bar. On first launch, allow Motion when macOS asks. Connect the headphones, choose them as the Mac's active audio output, and check **Sensors** for a live stream and sample rate. If Motion access was previously denied, change it in **System Settings → Privacy & Security → Motion** and relaunch HushKey.

## Experiment flow

1. In **Sensors**, confirm a live stream. The motion plots show user acceleration, rotation rate, and attitude.
2. In **Train**, select **Normal voice**, **Whisper**, or **Silent mouthing**. Select a word and hold the on-screen control or the configurable app-local shortcut (`⌥⇧M` by default). Space is never captured as a shortcut.
3. Use **New session** when you want a distinct session ID for held-out evaluation. Collect at least 10 takes for each of 5 or more words in each condition.
4. Compare acceleration, rotation, attitude, and combined features. **Evaluate** reports leave-one-out accuracy, majority-class accuracy, confusion matrix, and a 500-run label-permutation test. With at least two sessions, it also reports leave-one-session-out accuracy and its training-fold majority baseline.
5. **Decode** uses only Silent-condition templates. It rejects segments beyond the distance limit or below the confidence margin. Inference stays unavailable until the evidence checks pass; if motion does not distinguish the words, HushKey reports that instead of presenting nearest matches as useful text.
6. **Auto-detect** is optional. Calibrate while still, then tune the motion-energy trigger. Inspect false positives during ordinary head movement, chewing, and repositioning.

The microphone reference is independent of TypeWhisper. It uses macOS Speech only when on-device recognition is available and sets `requiresOnDeviceRecognition`; otherwise it stays off. Starting the mic is optional. Audio is written to disk only when the user starts an experiment recording while the mic is active.

## Safe text insertion

Text insertion is off by default. The user must enable it in **Decode**, approve HushKey under **System Settings → Privacy & Security → Accessibility**, then press the displayed configurable global shortcut (`⌥⇧I` by default) while the intended text field remains focused in another app.

HushKey uses Accessibility to inspect the frontmost app and focused control, allows only supported text fields, rejects secure/password controls, rechecks the process and focus immediately before insertion, and writes through the selected-text attribute once. It does not use or modify the clipboard. Unsupported controls fail closed. HushKey does not depend on TypeWhisper for insertion.

## Local data and privacy

- Templates: `~/Library/Application Support/HushKey/dataset.json`.
- Experiment sessions: `~/Documents/HushKey/Sessions/`, with motion CSV, event CSV, metadata, and optional microphone audio.
- No telemetry, upload, cloud service, or paid API is used by HushKey.
- Use **Sensors → Local data & privacy** to export the dataset or sessions, or delete templates and session files.
- Voice recognition requires the user to start the mic and is local-only; no remote recognition fallback is used.

## TypeWhisper boundary

HushKey does not import TypeWhisper code or its GPLv3 plugin SDK. Its transcription plugin accepts 16 kHz mono audio, so headphone motion is not a drop-in transcription plugin. TypeWhisper's local text-processing endpoints may transform text but do not insert it into the focused app; HushKey does not call those endpoints. There is no TypeWhisper cloud or paid-API dependency.

## Project naming

HushKey is the requested working name for this private prototype. A separate public macOS silent-dictation project already uses the same name: [amirrsyed/hushkey](https://github.com/amirrsyed/hushkey). Revisit the public product name before any public release.

## Limits

Headphone motion is processed and low-rate (often about 25 Hz). Jaw movement and head motion can dominate the signal, and reseating the headphones can change the measurements. A result on a small trained vocabulary does not establish arbitrary phrase recognition. Voice, whisper, and silent-mouthing results must be evaluated separately and across sessions before drawing conclusions.

See [docs/TESTING_PROTOCOL.md](docs/TESTING_PROTOCOL.md) for the repeatable study and hardware-validation procedure. See [NOTICE.md](NOTICE.md) for source attribution and license boundaries.
