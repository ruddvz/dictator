# Notices

## MIT motion-source attribution

HushKey adapts the MIT-licensed macOS motion experiment [Subvox](https://github.com/joeblau/subvox), copyright Joe Blau (2026). Adapted areas include headphone motion capture, motion features, DTW template classification, calibration/segmentation, evaluation, session recording, and parts of the SwiftUI workflow. The original MIT license and copyright notice are retained in [LICENSE](LICENSE). HushKey-specific changes are copyright HushKey contributors (2026).

The upstream source was reviewed from commit `591d028` (2026-10-30). HushKey uses the public Core Motion API; it does not access an AirPods speech accelerometer or inward-facing microphone.

Apple references reviewed: [headphone motion API](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager) and [headphone motion sample](https://developer.apple.com/documentation/CoreMotion/getting-motion-activity-data-from-headphones).

## WhisperKit local model support

HushKey uses the [Argmax Open Source SDK](https://github.com/argmaxinc/argmax-oss-swift) WhisperKit product (MIT License) as an optional local file-transcription engine. The repository vendors Swift Transformers Hub and Tokenizers sources under Apache License 2.0; its full notice and Apache license text are preserved in [docs/licenses/ARGMAX-NOTICES.txt](docs/licenses/ARGMAX-NOTICES.txt). The SDK's MIT license is in [docs/licenses/ARGMAX-MIT-LICENSE.txt](docs/licenses/ARGMAX-MIT-LICENSE.txt). HushKey downloads model files only after the user selects **Download model**. The upstream [WhisperKit Core ML model repository](https://huggingface.co/argmaxinc/whisperkit-coreml) currently declares MIT metadata. Review upstream code, notices, and model terms again before a public or commercial release.

## Ideas from amirrsyed/hushkey (MIT)

HushKey's Esc-to-cancel during dictation, the clipboard restore after a fallback paste, and the paired-bootstrap comparisons in the eval report follow ideas from [amirrsyed/hushkey](https://github.com/amirrsyed/hushkey) (MIT License, Copyright (c) 2026 Hushkey contributors). No code was copied; the implementations are HushKey's own.
