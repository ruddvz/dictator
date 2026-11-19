# Open-source dictation apps: landscape and Dictator gaps (4 November 2026)

Web research only: nothing was cloned, built or run. Star counts are approximate. Release dates marked *unverified* couldn't be confirmed from release pages, and proprietary features are vendor claims. Recheck licences before adapting anything. **GPL/AGPL: ideas only, no code. MIT/Apache: may be adapted with attribution in `NOTICE.md`.**

Already covered in earlier reports: FreeFlow, OpenWhispr, OpenTypeless, Handy, TypeWhisper, SpeakType, Blurt, Mutix, Loq, amirrsyed/hushkey.

## The app the user asked about: dimastatz/whisper-flow

- [dimastatz/whisper-flow](https://github.com/dimastatz/whisper-flow) is a **Python library with a FastAPI WebSocket server**, not an app. It takes 16 kHz PCM and returns partial and final transcripts using tumbling windows over OpenAI Whisper (`tiny.en` by default). MIT, about 1k stars, release 1.4.0 on 2026-11-01.
- **No code in it fits Dictator's native Swift app.** The one useful idea is its rule for when to finalize a partial: after a pause, once the text stops changing, or when the window hits its cap. That could guide live typing (gap 1 below).

## Projects

| Project | Licence | Stack | Engine | Standout |
|---|---|---|---|---|
| [altic-dev/FluidVoice](https://github.com/altic-dev/FluidVoice) | GPL-3 (Apache-2 before 2026-02-23) | Swift | Nemotron streaming, Parakeet, Apple, Whisper | Live words while speaking; Command Mode; Write Mode; per-app prompts; llama.cpp |
| [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) | GPL-3 | Swift | whisper.cpp, Parakeet, SenseVoice | Screen context; app/URL modes; Auto Send; double-tap shortcut; dictionary auto-learn; v2.25 (3 Nov) |
| [anomalyco/hex](https://github.com/anomalyco/hex) (was kitlangton/Hex) | MIT | Rust | *unverified* | Double-tap to lock recording |
| [matthartman/ghost-pepper](https://github.com/matthartman/ghost-pepper) | MIT | Swift | WhisperKit, Parakeet v3, Qwen3-ASR, Nemotron | Local LLM cleanup (LLM.swift + small Qwen); Vision OCR context; meeting notes as markdown |
| [Starmel/OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) | MIT | Swift | whisper.cpp, Parakeet | Mouse-button trigger; drag-drop file queue; language auto-detect |
| [Muesli-HQ/muesli](https://github.com/Muesli-HQ/muesli) | MIT | Swift | Parakeet, Nemotron, Qwen3, WhisperKit | pyannote diarization via FluidAudio; Silero VAD; Ask Meetings with citations; CLI; iCloud text sync |
| [moona3k/macparakeet](https://github.com/moona3k/macparakeet) | GPL-3 | Swift 6 | Parakeet, Nemotron, WhisperKit | Speaker labels; calendar auto-start; YouTube transcription; CLI |
| [opennookorg/betterwispr](https://github.com/opennookorg/betterwispr) | Apache-2.0 | Swift | Apple, Parakeet, Whisper | Learns from corrections; "new line" / "scratch that"; read-only MCP |
| [watzon/pindrop](https://github.com/watzon/pindrop) | MIT (archived) | Swift | WhisperKit, Parakeet, streaming engines | Trainable speaker profiles; MCP server; Ollama cleanup; pauses music while recording |
| [FrigadeHQ/yap](https://github.com/FrigadeHQ/yap) | MIT | Swift, macOS 26 | SpeechAnalyzer | Live partials; double-Esc discard; XcodeGen |
| [tornikegomareli/Talkify](https://github.com/tornikegomareli/Talkify) | MIT | Swift, macOS 26 | SpeechAnalyzer, Translation, Foundation Models | Translate while dictating; Read Aloud; drop files on the notch |
| [marswaveai/TypeNo](https://github.com/marswaveai/TypeNo) | GPL-3 | Swift | sherpa-onnx | Live preview; drop files on the menu bar icon |
| [znat/parrotflow](https://github.com/znat/parrotflow) | GPL-3 | Swift + Python | Parakeet, Whisper | Reads the target window to fix names; rule pipelines; Ollama |
| [amicalhq/amical](https://github.com/amicalhq/amical) | MIT | Electron | whisper.cpp | Ollama post-processing; active-app context |
| [thewh1teagle/vibe](https://github.com/thewh1teagle/vibe) | MIT | Tauri | whisper.cpp, Parakeet v3 | Diarization; record on phone via QR; HTTP API |
| [chidiwilliams/buzz](https://github.com/chidiwilliams/buzz) | MIT | Python/Qt | whisper.cpp | Watch folder; speaker ID |
| [cjpais/Handy](https://github.com/cjpais/Handy) | MIT | Tauri | multiple | New in v0.10 (2 Nov): auto language detect; file transcription; VAD chunking |
| [Open-Less/openless](https://github.com/Open-Less/openless) | AGPL-3 (2.0) | Tauri + Android | Qwen3-ASR | Types text as it is polished; translation hotkey |
| [voquill/voquill](https://github.com/voquill/voquill) | AGPL-3 | Tauri | Whisper | History with audio replay; style presets |
| [moinulmoin/voicetypr](https://github.com/moinulmoin/voicetypr) | AGPL-3 | Tauri | Whisper, Parakeet | LAN transcription server |
| [EpicenterHQ/epicenter](https://github.com/EpicenterHQ/epicenter) (Whispering) | AGPL-3 | Tauri | API endpoints | Transformations; git-versioned data |

## What Dictator already has (no work needed)

The research lists these as gaps, but Dictator already has them, or a version of them:

- mouse-button push-to-talk (`MouseButtonMonitor`)
- muting output while recording
- nearby-text vocabulary hints (off by default)
- a live transcript in the card
- the "press enter" voice command
- per-app profiles
- the raw vs cleaned word diff

## Gaps worth building, in order

1. **Typing the words live, as you speak.** Today words are typed only at the end. Use partials from Apple SpeechAnalyzer (macOS 26) or Nemotron streaming in FluidAudio. Finalize a phrase after a pause or once it stops changing (whisper-flow's idea, MIT). Rewrite only the unfinalized tail. Ideas from yap and Pindrop (MIT); FluidVoice is GPL.
2. **Local LLM cleanup before macOS 26.** Ghost Pepper uses LLM.swift with a small Qwen model (MIT), so Polished could work on macOS 14–15 too. It would be an optional download. Check the licences of LLM.swift, llama.cpp and the Qwen weights.
3. **Speaker labels in meeting notes.** FluidAudio already ships pyannote diarization, which Dictator currently builds with that trait off. Muesli (MIT) shows how to wire it. Recheck the model licence and the GPL trait boundary in `NOTICE.md`.
4. **Learning from corrections.** When you edit a typed word soon after dictating, offer to add it to your vocabulary or correction rules. Ideas from BetterWispr (Apache) and Pindrop (MIT).
5. **Screen context with OCR.** This adds Apple Vision OCR on the focused window, for apps where reading nearby text through Accessibility gets nothing (Electron, remote desktops), so names get spelled right. Idea from Ghost Pepper (MIT). Skip password fields and keep it off by default.
6. **Translate while dictating.** Apple's Translation framework is on-device. Talkify (MIT) has a separate shortcut for it.
7. **Auto language detection and a quick switcher.** Idea from Handy and OpenSuperWhisper (MIT).
8. **Pause media while recording.** This goes further than muting. Idea from Pindrop (MIT).
9. **Command mode.** "Open Notes" or "run <Shortcut>" by voice, through the Shortcuts app and an allow-list. Idea only: FluidVoice is GPL.
10. **Drop audio files on the menu bar icon, plus a watch folder.** Talkify and Buzz are MIT; TypeNo is GPL.
11. **Local CLI or read-only MCP for history.** Muesli and Pindrop are MIT, BetterWispr is Apache.
12. **Double-tap to lock hands-free recording.** Idea from Hex (MIT) and VoiceInk (GPL).

iOS keyboards and sync exist only in proprietary apps (Willow, Superwhisper, Spokenly, Aqua's Android app). They're out of scope for now.
