<div align="center">
  <img src="Dictator/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" alt="Dictator app icon" width="88">
  <h1>Dictator</h1>
  <p><strong>Hold fn. Say it. Release to review.</strong><br>
  Your voice becomes editable text, ready for wherever you write on your Mac.</p>
  <p>
    <a href="#build-for-mac"><img alt="Build for macOS" src="https://img.shields.io/badge/Build_for-macOS-477C67?style=for-the-badge&labelColor=20312A"></a>
  </p>
  <p><a href="#how-it-works">How it works</a> &nbsp;·&nbsp; <a href="#private-by-design">Privacy</a> &nbsp;·&nbsp; <a href="#build-for-mac">Build for Mac</a></p>
</div>

<p align="center">
  <img src="docs/assets/fn-key.jpg" alt="A sculpted fn key sends a sage sound wave into a text cursor" width="512">
</p>

Dictator is a native macOS voice-to-text app. Speak naturally, review your words, and continue in the app where you were already writing.

<p align="center">
  <img src="docs/assets/home-live.png" alt="Dictator Home, ready to listen. Hold fn or choose Dictate." width="512">
</p>
<p align="center"><sub>Dictator Home, ready to listen. Hold fn or choose Dictate.</sub></p>

<p align="center"><a href="docs/assets/fn-gesture.gif">▶ Play the fn shortcut illustration</a> <sub>(animated illustration)</sub></p>

## How it works

1. **Set up once.** Open Dictator and allow **Microphone** and **Speech Recognition** for Apple Speech. **Accessibility** enables the global shortcut and direct insertion.
2. **Speak.** Hold **fn (Globe)** and say “The blue notebook is on the shelf.” Release the key. For hands-free dictation, press **fn** twice to start and once to stop.
3. **Review and continue.** Read or edit the transcript in Dictator. Choose **Copy**, then paste with **⌘V** into your email, document, chat, or any other app.

You can also start from **Home** or choose another shortcut in **Settings → Shortcuts**. Direct insertion is available in **Settings → Typing** when an editable field is focused. If an app does not receive inserted text, use **Copy** in Home and paste manually.

## A small toolkit for getting words right

<table>
  <tr>
    <td width="50%" valign="top"><strong>Vocabulary</strong><br>Teach Dictator names, preferred spellings, corrections, and reusable snippets.</td>
    <td width="50%" valign="top"><strong>Transforms</strong><br>Shape a draft into bullets, a shorter note, or a more polished message. Apple Intelligence options require macOS 26+ and an available on-device model.</td>
  </tr>
  <tr>
    <td width="50%" valign="top"><strong>Audio files</strong><br>Transcribe recordings and export plain text, SRT, or WebVTT subtitles.</td>
    <td width="50%" valign="top"><strong>Meeting notes</strong><br>Capture microphone audio, Mac audio, or both. System-audio capture requires macOS 14.2+.</td>
  </tr>
</table>

## Private by design

- **On-device by default:** Apple Speech recognizes dictation locally in supported languages.
- **Audio stays temporary:** ordinary dictation audio is held in memory while Dictator processes it.
- **Local model choices:** optional Parakeet and WhisperKit models run on your Mac after download.
- **Your history, your Mac:** transcript history is stored locally. Turn it off in Settings or clear saved dictations in Home.

See the [personal data and backup guide](docs/PERSONAL_DATA_BACKUP.md) for storage details.

## Build for Mac

Dictator supports **macOS 14 or later**. The repository contains the app source and packaging script; there is no prebuilt installer to download yet. To create a local `Dictator.app`, use a Mac with **full Xcode (Swift 6.2 or later)** and Homebrew:

```sh
brew install xcodegen
git clone https://github.com/ruddvz/dictator.git
cd dictator
./Scripts/package-app.sh
open dist/Dictator.app
```

For development, generate the Xcode project and run the test suite:

```sh
xcodegen generate
xcodebuild -project Dictator.xcodeproj -scheme Dictator -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
```

## Explore the project

[Testing guide](docs/TESTING_PROTOCOL.md) · [Evaluation fixtures](Fixtures/eval/README.md) · [MIT license](LICENSE) · [Third-party notices](NOTICE.md)
