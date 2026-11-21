<div align="center">
  <img src="Dictator/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" alt="Dictator app icon" width="80">
  <h1>Dictator</h1>
  <p><strong>An open-source Wispr Flow alternative for macOS.</strong><br>
  Hold <kbd>fn</kbd>. Speak naturally. Keep control of your words.</p>
  <p>
    <a href="#build-for-mac"><img alt="Build for Mac" src="https://img.shields.io/badge/Build_for-Mac-477C67?style=for-the-badge&labelColor=20312A"></a>
    <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/License-MIT-DCE6DC?style=for-the-badge&labelColor=20312A"></a>
  </p>
  <p><a href="#why-dictator">Why Dictator</a> &nbsp;·&nbsp; <a href="#how-it-works">How it works</a> &nbsp;·&nbsp; <a href="#privacy-and-speech-engines">Privacy</a></p>
</div>

<p align="center">
  <img src="docs/assets/fn-key.jpg" alt="A sculpted fn key sends a sage sound wave into a text cursor" width="512">
</p>

Dictator brings a fast, hold-to-talk voice workflow to a native Mac app. Dictate into an eligible text field, or choose the review-and-copy path when you want to check every word first.

<p align="center">
  <img src="docs/assets/home-live.png" alt="Dictator Home, ready to listen. Hold fn or choose Dictate." width="512">
</p>
<p align="center"><sub>Dictator Home, ready to listen. Hold fn or choose Dictate.</sub></p>

<p align="center"><a href="docs/assets/fn-gesture.gif">▶ Watch the hold-to-talk gesture</a> <sub>(animated illustration)</sub></p>

## Why Dictator

Dictator is built around three choices: a Mac-native **fn** shortcut, speech recognition that can run **on your device**, and control over when your words leave Dictator and enter another app. The source is MIT-licensed and open for inspection and contribution.

## How it works

1. **Set up once.** Open Dictator and allow **Microphone** and **Speech Recognition** for Apple Speech. **Accessibility** enables the global shortcut and direct insertion.
2. **Dictate.** Focus an eligible text field, hold **fn (Globe)**, and speak. Release the key. Direct insertion is enabled by default; Dictator attempts to type the result into the focused field. Password fields are always skipped.
3. **Review first, when you prefer.** Start from **Home** or turn off **Settings → Typing → Type into the focused field**. Read and edit the transcript in Dictator, then choose **Copy** and paste with **⌘V**.

For hands-free dictation, press **fn** twice to start and once to stop. If the target app does not accept insertion, use **Copy** in Home and paste manually.

## Tools for your voice workflow

- **Live dictation:** Apple Speech runs on-device for supported languages. Optional Parakeet models can be downloaded for local live dictation; they return the transcript after capture ends.
- **Vocabulary:** Add names, preferred spellings, correction rules, and reusable snippets.
- **Transforms:** Turn rough notes into bullets or a more polished message. Apple Intelligence options require macOS 26 or later and an available on-device model.
- **Audio files:** Transcribe recordings with Apple Speech or a downloaded WhisperKit model, then export text, SRT, or WebVTT subtitles.
- **Meeting notes:** Transcribe microphone audio, Mac audio, or both as the meeting happens. Dictator saves the transcript locally; source audio is not saved. Speaker identification is not included. System-audio capture requires macOS 14.2 or later.

## Privacy and speech engines

- **Apple Speech:** Dictation uses on-device recognition for supported languages. If macOS cannot recognize the selected language on-device, Dictator stops and explains why; it does not send audio to a remote recognition service.
- **Parakeet:** Optional model downloads are started by you; inference runs locally for live dictation.
- **WhisperKit:** Choose and download a model for local audio-file transcription.
- **Audio and history:** Ordinary dictation audio stays in memory while it is processed. Transcript history is stored on your Mac; turn history off in Settings or clear saved dictations in Home.

See the [personal data and backup guide](docs/PERSONAL_DATA_BACKUP.md) for storage details.

## Build for Mac

Dictator supports **macOS 14 or later**. There is no prebuilt installer or App Store release yet; build the app from the public source. You need a Mac with full **Xcode (Swift 6.2 or later)** and [Homebrew](https://brew.sh/).

```sh
brew install xcodegen
git clone https://github.com/ruddvz/dictator.git
cd dictator
./Scripts/make-signing-identity.sh
./Scripts/package-app.sh
open dist/Dictator.app
```

The signing script creates a stable local identity so macOS Accessibility permission can persist across rebuilds. After the first launch, allow Dictator under **System Settings → Privacy & Security → Accessibility** and grant the requested microphone and speech permissions.

## Development

Generate the Xcode project and run the test suite:

```sh
xcodegen generate
xcodebuild -project Dictator.xcodeproj -scheme Dictator -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
```

For the project structure, testing protocol, research notes, and product documentation, see the [documentation index](docs/README.md). The code is MIT-licensed; model and library notices are in [NOTICE.md](NOTICE.md).
