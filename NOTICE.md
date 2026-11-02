# Notices

## MIT motion-source attribution

HushKey adapts the MIT-licensed macOS motion experiment [Subvox](https://github.com/joeblau/subvox), copyright Joe Blau (2026). Adapted areas include headphone motion capture, motion features, DTW template classification, calibration/segmentation, evaluation, session recording, and parts of the SwiftUI workflow. The original MIT license and copyright notice are retained in [LICENSE](LICENSE). HushKey-specific changes are copyright HushKey contributors (2026).

The upstream source was reviewed from commit `591d028` (2026-10-30). HushKey uses the public Core Motion API; it does not access an AirPods speech accelerometer or inward-facing microphone.

Apple references reviewed: [headphone motion API](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager) and [headphone motion sample](https://developer.apple.com/documentation/CoreMotion/getting-motion-activity-data-from-headphones).

## Ideas from Spiro-12/silent-speech (MIT)

Silent Use's "nothing" rest class, which is recognised but never typed, follows the finding in [Spiro-12/silent-speech](https://github.com/Spiro-12/silent-speech) (MIT License) that a trained still class rejects stray movement. Rejecting head-turn takes follows [nottherealsanta/speechless](https://github.com/nottherealsanta/speechless) (MIT License). No code was copied. See [docs/SILENT_SPEECH_RESEARCH.md](docs/SILENT_SPEECH_RESEARCH.md).

## WhisperKit local model support

HushKey uses the [Argmax Open Source SDK](https://github.com/argmaxinc/argmax-oss-swift) WhisperKit product (MIT License) as an optional local file-transcription engine. The repository vendors Swift Transformers Hub and Tokenizers sources under Apache License 2.0; its full notice and Apache license text are preserved in [docs/licenses/ARGMAX-NOTICES.txt](docs/licenses/ARGMAX-NOTICES.txt). The SDK's MIT license is in [docs/licenses/ARGMAX-MIT-LICENSE.txt](docs/licenses/ARGMAX-MIT-LICENSE.txt). HushKey downloads model files only after the user selects **Download model**. The upstream [WhisperKit Core ML model repository](https://huggingface.co/argmaxinc/whisperkit-coreml) currently declares MIT metadata. Review upstream code, notices, and model terms again before a public or commercial release.

## Ideas from amirrsyed/hushkey (MIT)

HushKey's Esc-to-cancel during dictation, the clipboard restore after a fallback paste, and the paired-bootstrap comparisons in the eval report follow ideas from [amirrsyed/hushkey](https://github.com/amirrsyed/hushkey) (MIT License, Copyright (c) 2026 Hushkey contributors). No code was copied; the implementations are HushKey's own.

## Parakeet dictation (FluidAudio and NVIDIA Parakeet)

HushKey's optional Parakeet dictation engine uses [FluidAudio](https://github.com/FluidInference/FluidAudio) by FluidInference, version 0.18.2 (Apache License 2.0; full text in [docs/licenses/FLUIDAUDIO-APACHE-LICENSE.txt](docs/licenses/FLUIDAUDIO-APACHE-LICENSE.txt)). HushKey calls it through the local package `Packages/HushKeyParakeet` and changes none of its code.

- FluidAudio is linked with every package trait turned off (`traits: []`). Its default `TTS` trait bundles a G2P lexicon generated from espeak-ng data under GPL-3.0-or-later; that bundle, the TTS and diarization code paths, and the NeMo text-processing binary are not built into HushKey. Recheck this if the FluidAudio version or the traits change.
- FluidAudio compiles in `fastcluster` (BSD 2-Clause, © 2011 Daniel Müllner and © Google Inc.; notice in [docs/licenses/FLUIDAUDIO-FASTCLUSTER-LICENSE.md](docs/licenses/FLUIDAUDIO-FASTCLUSTER-LICENSE.md)). HushKey doesn't call it.

The speech model is NVIDIA's **Parakeet TDT 0.6B**, either [v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) (English) or [v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (25 European languages), © NVIDIA Corporation, licensed under [Creative Commons Attribution 4.0 International (CC-BY-4.0)](https://creativecommons.org/licenses/by/4.0/). HushKey downloads FluidInference's Core ML conversions ([v2](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml), [v3](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml), also CC-BY-4.0) only after the user selects **Download model** in Settings, and keeps them in HushKey's Application Support folder. The model is not modified. Audio is recognized on this Mac and is never uploaded. Licences reviewed 2026-11-02.
