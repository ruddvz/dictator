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
./Scripts/package-app.sh
open dist/HushKey.app
```

Run the tests:

```sh
xcodegen generate
xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test
```

HushKey opens as a normal Mac app window and also offers a menu-bar shortcut. On first launch, allow Motion when macOS asks. Connect compatible headphones, choose them as the Mac's active audio output, and check **Setup** for a live stream and sample rate. If Motion access was previously denied, change it in **System Settings → Privacy & Security → Motion** and relaunch HushKey.

The packaged app is at `dist/HushKey.app`. Xcode's intermediate files go into the hidden `.build` folder; the packaging script builds in a temporary directory and removes it so Finder search has one obvious HushKey app to open.

## Experiment flow

1. In **Setup**, confirm a live stream. Expand Motion diagnostics to see acceleration, rotation, and attitude.
2. In **Train**, select **Normal voice**, **Whisper**, or **Silent mouthing**. Select a word and hold the on-screen control or the configurable app-local shortcut (`⌥⇧M` by default; change it in **Settings & Data**). Space is never captured as a shortcut.
3. Use **New session** when you want a distinct session ID for held-out evaluation. Collect at least 10 takes for each of 5 or more words in each condition.
4. In **Evaluate**, compare acceleration, rotation, attitude, and combined features. Results include leave-one-out accuracy, the majority baseline, a 500-run label-permutation test, confusion matrix, and session-separated holdout when at least two sessions are available.
5. **Use** remains locked until the Silent condition has enough examples, beats the majority baseline with a label-permutation test (`p < 0.05`), and beats baseline on a separate-session holdout. It rejects weak matches instead of presenting nearest neighbors as text.
6. Optional auto-capture is available under **Use**. Calibrate while still, then tune the motion-energy trigger under Advanced detection thresholds. Inspect false positives during ordinary head movement, chewing, and repositioning.

The optional microphone reference uses macOS Speech only when on-device recognition is available and sets `requiresOnDeviceRecognition`; otherwise it stays off. Starting the mic is optional. Audio is written to disk only when the user starts an experiment recording while the mic is active.

## Safe text insertion

Text insertion is off by default. Enable it in **Settings & Data**, approve HushKey under **System Settings → Privacy & Security → Accessibility**, then press the displayed configurable global shortcut (`⌥⇧I` by default) while the intended text field remains focused in another app.

HushKey uses Accessibility to inspect the frontmost app and focused control, allows only supported text fields, rejects secure/password controls, rechecks the process and focus immediately before insertion, and writes through the selected-text attribute once. It does not use or modify the clipboard. Unsupported controls fail closed.

## Local data and privacy

- Templates: `~/Library/Application Support/HushKey/dataset.json`.
- Experiment sessions: `~/Documents/HushKey/Sessions/`, with motion CSV, event CSV, metadata, and optional microphone audio.
- No telemetry, upload, cloud service, or paid API is used by HushKey.
- Use **Settings & Data** to configure shortcuts, record synchronized sessions, export the dataset or sessions, and delete local files.
- Voice recognition requires the user to start the mic and is local-only; no remote recognition fallback is used.

## Project naming

HushKey is the requested working name for this private prototype. A separate public macOS silent-dictation project already uses the same name: [amirrsyed/hushkey](https://github.com/amirrsyed/hushkey). Revisit the public product name before any public release.

## Limits

Headphone motion is processed and low-rate (often about 25 Hz). Jaw movement and head motion can dominate the signal, and reseating the headphones can change the measurements. A result on a small trained vocabulary does not establish arbitrary phrase recognition. Voice, whisper, and silent-mouthing results must be evaluated separately and across sessions before drawing conclusions.

See [docs/TESTING_PROTOCOL.md](docs/TESTING_PROTOCOL.md) for the repeatable study and hardware-validation procedure. See [docs/PRODUCT_PLAN.md](docs/PRODUCT_PLAN.md) for the screen flow and file map. See [NOTICE.md](NOTICE.md) for source attribution and license boundaries.
