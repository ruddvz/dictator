# Dictator

**Private, on-device dictation for macOS.**

Dictator turns speech into editable text on your Mac. Dictate anywhere, transcribe files, capture meeting notes, and shape drafts with local tools. Audio and text processing stay on-device; optional speech models are downloaded only when you choose them.

[![CI](https://github.com/ruddvz/dictator/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ruddvz/dictator/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)](#requirements)
[![MIT License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

[Download status](#download-and-install) · [Features](#what-you-can-do) · [Privacy](#privacy-and-permissions) · [Report a problem](https://github.com/ruddvz/dictator/issues)

## Download and install

### Ready-to-use app

There is **no signed, notarized Mac app published in this repository**, and no Mac App Store listing is linked here. The [GitHub Releases page](https://github.com/ruddvz/dictator/releases) currently has no installer. Until an official release is published, the repository is source code; the build below is intended for developers and testers.

### Build from source

You’ll need a Mac, Xcode with the macOS SDK, and XcodeGen. Homebrew can install XcodeGen:

```sh
git clone https://github.com/ruddvz/dictator.git
cd dictator
brew install xcodegen
./Scripts/package-app.sh
open dist/Dictator.app
```

The first build downloads the project’s Swift package dependencies, so it needs an internet connection. The packaging script creates an ad-hoc signed local build; it is not Developer ID signed or notarized for distribution. Without a stable local signing identity, macOS may ask you to grant Accessibility access again after each rebuild.

## What you can do

- **Dictate in any app:** Apple’s on-device Speech is the default. The optional Parakeet engine also runs locally after you download its model. Choose Natural, Message, Email, Code, or Automatic writing modes; add vocabulary, snippets, and correction rules.
- **Review before inserting:** Edit or copy a transcript, or enable guarded text insertion into supported fields. Dictator checks the destination before inserting and offers a limited undo.
- **Transform text locally:** Create reviewable polish, concise, professional, bullet-point, and action-item drafts. Apple’s on-device Foundation Model is required for model-backed transforms; filler cleanup also works on macOS 14+ without it.
- **Edit selected text by voice:** Select text in another app, speak an edit instruction, review the local draft, and choose whether to apply it. This feature requires macOS 26+ and Accessibility access.
- **Transcribe files:** Work with one audio file at a time and export text, SRT, or WebVTT. Apple Speech needs no model download; WhisperKit is available as an optional local engine.
- **Capture meeting notes:** Transcribe your microphone, Mac system audio, or both. Review and export searchable local transcripts. Audio is not saved.
- **Explore Silent Lab:** Train and evaluate a small, personal vocabulary from head motion with compatible headphones. This is an experiment, not general lip reading.

## Requirements

| Feature | Requirement |
| --- | --- |
| Dictation and core app | macOS 14 or later; Apple Silicon and Intel Macs |
| System-audio meeting capture | macOS 14.2 or later |
| Apple Intelligence transforms, summaries, and voice editing | macOS 26 or later, with Apple’s on-device Foundation Model available |
| Optional speech models | Internet to download; supported languages, model availability, and performance depend on the selected engine and Mac |
| Silent Lab | Compatible head-tracking headphones connected as the Mac’s audio output |

Dictation does not require headphones. Model-based features depend on macOS, language, hardware, and Apple’s local model availability.

## First dictation

1. Open Dictator and start dictation from the app, or hold the **fn (Globe)** key. This is the default global shortcut and can be changed in **Settings → Shortcuts**.
2. Speak, then stop dictation. Review or edit the transcript.
3. Copy the text, or enable **Insert into current app** in Settings and grant Accessibility access. Insertion is limited to supported text fields.

The microphone is active only while you explicitly record. Apple Speech streams recognized words as you speak; Parakeet returns its transcript when recording ends. If Parakeet is unavailable for the selected language, Dictator falls back to Apple Speech.

## Privacy and permissions

- Dictation, file transcription, meeting transcription, and model-backed text transforms run on this Mac. Dictator has no telemetry, paid API, or remote speech-recognition fallback.
- Speech-model files are downloaded only after you request them. Model downloads need internet; your audio is processed locally.
- Ordinary dictation audio is not saved to disk. Recent transcript history is stored locally and can be disabled or cleared in Settings.
- Meeting audio is not saved; the transcript is stored locally when you stop. Silent Lab’s separate research recorder can save audio only when you explicitly enable it.
- Nearby-text hints are off by default. If enabled, Dictator reads a bounded amount of text around the cursor to find recognition terms, then discards it.
- Accessibility is needed for the default fn shortcut and for text insertion. Microphone and system-audio access are requested when you start the relevant capture. Motion access is requested only when you open **Silent Lab → Connect**.

Dictator does not identify speakers. A generated draft can change meaning; review it before applying. See the [personal-data backup guide](docs/PERSONAL_DATA_BACKUP.md) for moving local preferences and history.

## Silent Lab is experimental

Silent Lab uses processed, low-rate motion from compatible headphones. Head movement and fit changes can affect results. It requires separate training and held-out evaluation on a small, user-trained vocabulary; success there does not show that arbitrary silent speech can be recognized.

## Development

Generate the Xcode project and run the test suite:

```sh
xcodegen generate
xcodebuild -project Dictator.xcodeproj -scheme Dictator -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
```

GitHub Actions runs the same build and tests on macOS. The repository also includes a local dictation evaluation script at `./Scripts/eval.sh`; see [the evaluation guide](Fixtures/eval/README.md) for fixtures and setup.

## Help, attribution, and license

- [Report an issue](https://github.com/ruddvz/dictator/issues). Include your macOS version and steps to reproduce; avoid attaching private audio or transcript content.
- [Testing protocol](docs/TESTING_PROTOCOL.md)
- [Product plan and file map](docs/PRODUCT_PLAN.md)
- [Third-party notices and license boundaries](NOTICE.md)

Dictator is released under the [MIT License](LICENSE). Third-party components have their own terms; see the notices and license files in `docs/licenses/`.
