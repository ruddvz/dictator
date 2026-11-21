# Open-source projects

### Takeaway
This is a curated, primary-source shortlist checked 2026-11-20, not an exhaustive GitHub census. Eight distinct candidates are below; Whispering is now part of Epicenter. OpenWhispr and OpenWhisper are separate names and codebases.

### Cited Findings
| Project / official source | License and platforms | Speech recognition | Standout capability and activity evidence |
|---|---|---|---|
| [OpenWhispr](https://github.com/OpenWhispr/openwhispr) | MIT; macOS, Windows, Linux | On-device Whisper, Parakeet, Cohere and Orukeet; optional cloud/BYOK | Broad dictation, translation, AI assistant, meeting diarization/voice identification, local notes/search and team features. Release 1.12.0 (Nov 17, 2026) adds a cross-app assistant window, private notes, teams, and guided local model setup. [README](https://github.com/OpenWhispr/openwhispr/blob/main/README.md) · [release](https://github.com/OpenWhispr/openwhispr/releases/tag/v1.12.0) |
| [TypeWhisper for Mac](https://github.com/TypeWhisper/typewhisper-mac) | GPL-3.0-or-later; public macOS app; organization also lists Windows app | Local WhisperKit, Parakeet, Apple SpeechAnalyzer and other plugins; optional cloud engines | Per-app/site workflows, streaming preview, correction learning, file/subtitle transcription, plugins, API and CLI. README lists 1.8.2 as current stable; org activity shows macOS repo updated Nov 12. [README](https://github.com/TypeWhisper/typewhisper-mac) · [license](https://github.com/TypeWhisper/typewhisper-mac/blob/main/LICENSE-COMMERCIAL.md) · [org activity](https://github.com/TypeWhisper) |
| [Handy](https://github.com/cjpais/Handy) | MIT; macOS, Windows, Linux | Fully local Whisper and Parakeet; VAD; GPU acceleration where available | Simple global push-to-talk/toggle with direct paste; executable transcription hook for custom post-processing. Release 0.10.1 Nov 14, 2026. [README](https://github.com/cjpais/Handy) · [releases](https://github.com/cjpais/Handy/releases) |
| [Voquill](https://github.com/voquill/voquill) | AGPLv3; desktop on macOS, Windows, Linux; repository includes mobile apps | Local Whisper with optional GPU, or configurable cloud provider | Transcript cleanup, glossary/replacement rules, writing styles, replayable history, enterprise services and CLI. Latest desktop release 0.0.656 Nov 16, 2026. [README/license](https://github.com/voquill/voquill/blob/main/README.md) · [latest release](https://github.com/voquill/voquill/releases/latest) |
| [VoiceInk](https://github.com/Beingpax/VoiceInk) | GPL-3.0; native macOS | Local Whisper/Parakeet and optional cloud models | Modes by app/site, context-aware writing, learned dictionary and assistant. Release 2.27 Nov 11, 2026 adds ElevenLabs Scribe V3 and reports performance fixes; 2.25 added direct typing/remote desktop typing and smart punctuation. [README/license](https://github.com/Beingpax/VoiceInk) · [releases](https://github.com/Beingpax/VoiceInk/releases) |
| [OpenWhisper — juferdinand](https://github.com/juferdinand/OpenWhisper) | MIT; macOS 14+ and Linux x86_64; no Windows build | Local Whisper and Parakeet; optional text-model connections | Vocabulary correction, snippets, history and explicit audio-quality hints. Version 0.5.7 released Oct 15, 2026. [README](https://github.com/juferdinand/OpenWhisper) · [release](https://github.com/juferdinand/OpenWhisper/releases) |
| [Hushkey — amirrsyed](https://github.com/amirrsyed/hushkey) | MIT; macOS proof of concept | Local visual speech/lip-reading inference; no audio ASR and no cloud | Webcam reads lips/jaw/throat; push-to-talk, live HUD, clipboard-restoring insertion, and personal adapter training. README labels it proof of concept and warns that useful accuracy depends on personalization. [README](https://github.com/amirrsyed/hushkey) · [license](https://github.com/amirrsyed/hushkey/blob/main/LICENSE) |
| [Whispering in Epicenter](https://github.com/EpicenterHQ/epicenter/tree/main/apps/whispering) | AGPL-3.0-or-later; desktop and browser app for Mac, Windows, Linux | API-provider BYOK; optional local Speaches endpoint | Quick global-shortcut dictation, local history, AI transformations and browser app. The former standalone repo is archived and redirects users to Epicenter; its old README says it is a direct-to-provider/API-key product. [Epicenter README/license](https://github.com/EpicenterHQ/epicenter) · [archived project redirect](https://github.com/braden-w/whispering) · [feature README](https://github.com/henliao/whispering) |

### Inferences
- For a direct Mac product comparison, TypeWhisper, VoiceInk, OpenWhispr, and OpenWhisper are the closest broad feature references; Handy is a useful benchmark for keeping the core dictation path focused and offline.
- Open source does not mean the same distribution model: OpenWhispr and VoiceInk offer commercial/cloud options while their checked repositories are MIT/GPL respectively; AGPL/GPL terms should be assessed before reusing code.

### Gaps
- This is a shortlist, not every project or fork. Platform support in a repository is not proof that every OS build, permission flow, or insertion path passes acceptance testing.
- Hushkey is experimental, and its repo itself says personalization and silent-speech accuracy remain limitations; treat it as a research direction, not a proven dictation competitor.

# Names and scope

### Takeaway
Search by owner/repository, not product name alone. The spellings OpenWhispr, OpenWhisper, Whispering, and Hushkey refer to multiple unrelated projects.

### Cited Findings
- OpenWhispr is [OpenWhispr/openwhispr](https://github.com/OpenWhispr/openwhispr); it is the cross-platform MIT app with local/cloud engines and meetings.
- One OpenWhisper is [juferdinand/OpenWhisper](https://github.com/juferdinand/OpenWhisper), MIT, local Mac/Linux dictation. Another separate project is [Knuckles92/OpenWhisper](https://github.com/Knuckles92/OpenWhisper), MIT, with meeting notes, MCP history access, shared LAN/Tailscale engines and optional local or API engines. These are distinct repositories, not forks of the same listed product. [Knuckles92 README](https://github.com/Knuckles92/OpenWhisper) · [license listing](https://github.com/Knuckles92/OpenWhisper#readme)
- The other developer's Hushkey is [amirrsyed/hushkey](https://github.com/amirrsyed/hushkey), a webcam lip-reading proof of concept. It is not the former Dictator/HushKey app and does not listen to audio.
- The original standalone [braden-w/whispering](https://github.com/braden-w/whispering) was archived Feb 14, 2026 and points to [EpicenterHQ/epicenter](https://github.com/EpicenterHQ/epicenter), where Whispering now lives. A separate [henliao/whispering](https://github.com/henliao/whispering) is a fork, not the canonical upstream.

### Inferences
- The “OpenWhisper” search phrase is ambiguous enough that repo-owner attribution should be included whenever it appears in Dictator research or UI copy.
- Hushkey's unusual modality is potentially interesting for accessibility or silent environments, but the public README does not support positioning it as a mature competitor to audio dictation.

### Gaps
- No claim is made that these repositories share code, maintainers, release cadence, or feature parity. Check each upstream before adopting dependencies or APIs.

# Product implications for Dictator

### Takeaway
The biggest product lesson is dependable insertion and clear recovery first, followed by high-quality writing controls and a consistent, purpose-built UI. Broad feature counts alone do not establish polish.

### Cited Findings
- Competitors expose useful concrete interaction patterns: TypeWhisper offers per-app/site workflow matching and a “correct last dictation” path; Handy supports hold or toggle shortcuts, local VAD/model choices and a preprocessing hook; VoiceInk supports app/site modes, correction learning, direct typing and paste recovery. [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) · [Handy](https://github.com/cjpais/Handy) · [VoiceInk releases](https://github.com/Beingpax/VoiceInk/releases)
- OpenWhispr and Voquill extend beyond one-shot dictation into meetings, notes, glossaries and AI actions, while still documenting local-engine options. [OpenWhispr](https://github.com/OpenWhispr/openwhispr) · [Voquill](https://github.com/voquill/voquill)
- HeyClicky and Wispr Flow are proprietary services, so they are excluded from the open-source table. Their official pages describe screen/context-aware assistant actions and broad voice workflows for HeyClicky, and polished cross-app dictation plus meeting transcription/notes for Wispr Flow. [HeyClicky Mac](https://www.heyclicky.com/for-mac) · [HeyClicky changelog](https://www.heyclicky.com/changelog) · [Wispr Flow](https://wisprflow.ai/) · [Wispr Flow docs](https://docs.wisprflow.ai/articles/2772472373-what-is-flow)

### Inferences
- Suggested Dictator sequence: (1) make permissions, target detection, direct insert, clipboard fallback and recovery observable and reliable; (2) polish live recording/transcription feedback and correction/vocabulary tools; (3) deliver coherent per-app writing modes; (4) expand into meeting/file/API and agent features only with explicit consent and validation.
- Treat HeyClicky/Wispr Flow as UX and workflow benchmarks; implement original interaction design and independently built capabilities rather than copying proprietary code/assets.

### Gaps
- This research did not inspect Dictator source or perform live usability, performance, speech-accuracy, permission, security, or VoiceOver validation. It is product research, not a claim that Dictator now matches these products.
