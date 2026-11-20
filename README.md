# Dictator

**Hold fn to talk. Release to review your words.**

Dictator turns speech into editable text on your Mac. Dictate a reply, fix a name, then copy it into the app where you're writing. Apple Speech handles dictation on-device in supported languages.

**[Build for Mac](#build-for-mac)** · [Try your first dictation](#try-your-first-dictation) · [Privacy](#privacy)

![A sculpted fn key with a sage sound wave leading to a text cursor](docs/assets/fn-key.jpg)

[Play the shortcut illustration](docs/assets/fn-gesture.gif)

## Try your first dictation

1. Open Dictator. In setup, allow **Microphone** and **Speech Recognition** for Apple Speech. **Accessibility** enables the global shortcut and insertion.
2. Hold **fn** (Globe) and say “The blue notebook is on the shelf.” Release the key. For hands-free dictation, press **fn** twice to start and once to stop.
3. In **Home**, review the transcript and choose **Copy**. Click where you want the sentence and press **⌘V**.

![Dictator Home showing the Hold fn and talk prompt](docs/assets/home-live.png)

You can also start dictation from **Home** or change the key in **Settings → Shortcuts**. To try direct insertion, enable it in **Settings → Typing** and focus an editable field. If Dictator reports a paste but the field is empty, use **Copy** in Home and paste manually.

## Writing with Dictator

| When you want to… | Open |
| --- | --- |
| Get a name right or expand a phrase you use often | **Vocabulary** for names, snippets, and corrections. |
| Turn a rough paragraph into bullets or a shorter email | **Transforms** to review an editable draft. Apple Intelligence options require macOS 26 or later and an available on-device model. |
| Make subtitles from a recording | **Files** to transcribe audio and export text, SRT, or WebVTT. |
| Keep notes from a call | **Meeting notes** to capture a microphone, Mac audio, or both. System-audio capture requires macOS 14.2 or later. |

## Privacy

Ordinary dictation audio stays in memory. Apple Speech recognition runs on-device, and optional Parakeet and WhisperKit models run locally after download. Dictator keeps transcript history on your Mac. You can switch history off in Settings or clear saved dictations in Home. See the [guide to backing up your data](docs/PERSONAL_DATA_BACKUP.md).

## Build for Mac

Dictator targets **macOS 14 or later**. The app is available as source. There is currently no packaged GitHub release.

On a Mac with full Xcode (Swift 6.2 or later) and Homebrew installed, run these commands in Terminal. The packaging script builds and signs a local copy at `dist/Dictator.app`.

```sh
brew install xcodegen
git clone https://github.com/ruddvz/dictator.git
cd dictator
./Scripts/package-app.sh
open dist/Dictator.app
```

For development, run the test suite after generating the project with XcodeGen.

```sh
xcodegen generate
xcodebuild -project Dictator.xcodeproj -scheme Dictator -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
```

[Testing guide](docs/TESTING_PROTOCOL.md) · [Evaluation fixtures](Fixtures/eval/README.md) · [MIT license](LICENSE) · [Third-party notices](NOTICE.md)
