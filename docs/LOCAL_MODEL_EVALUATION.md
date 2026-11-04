# Local speech engines and model decision

Reviewed 4 November 2026 against the current project configuration and upstream model documentation.

## What HushKey uses

- **Live voice dictation:** Apple `SFSpeechRecognizer` is the default and requires on-device recognition support for the selected locale. The optional Parakeet TDT 0.6B engine runs locally after the person downloads an English or multilingual model; Apple Speech is used when Parakeet is not installed or does not support the selected locale. Apple Speech shows live words; Parakeet returns the final transcript after capture ends.
- **Audio files:** choose Apple Speech for the same no-download, on-device-only behavior, or choose WhisperKit and explicitly download one selected Core ML model. WhisperKit audio inference uses bounded incremental file loading, returns timed segments, and runs locally after setup. HushKey stores downloaded files under `~/Library/Application Support/com.ruddvz.hushkey/WhisperKitModels/` and has a remove control.

## Why WhisperKit is the downloadable option

Argmax's current open-source SDK includes WhisperKit, supports macOS 14 and later, and documents Apple Silicon on-device inference and direct local audio-file transcription. The current app exposes Tiny, Base, Small, and the compressed Large Turbo model; the large variant is approximately 626 MB according to the upstream README. The upstream recommends Tiny for debugging and the compressed Large Turbo model for higher multilingual accuracy. These are upstream recommendations, not HushKey benchmarks. [Argmax SDK README](https://github.com/argmaxinc/argmax-oss-swift), [WhisperKit model list](https://github.com/argmaxinc/argmax-oss-swift#model-selection)

The M1 Pro is within the upstream's stated Apple Silicon platform, but HushKey has not measured its speed, memory use, or accuracy on this Mac. The app deliberately has not chosen a “best” model. A model download needs internet; after it is installed, selected-file inference does not send audio to Hugging Face or another service. Model downloads are user-started.

For live Parakeet dictation, HushKey currently requires a microphone peak of at least 0.45 and model confidence of at least 0.35 before it types a result automatically. Below either provisional threshold, it saves the transcript in HushKey for review. A local diagnostic using the downloaded model returned empty text and 0.10 confidence for synthetic silence, a quiet tone, and quiet noise. These signals do not establish recognition quality for real quiet speech or human voices; no consented quiet-room corpus has been measured yet.

The SDK is MIT licensed and its current model repository declares MIT metadata. Argmax OSS also includes vendored Swift Transformers files with Apache 2.0 notices. Attribution links are in [NOTICE.md](../NOTICE.md). Each third-party model or repository must still be checked individually before distribution.

## Other option considered

Apple's newer `SpeechAnalyzer` and `SpeechTranscriber` support local downloadable language assets, but Apple's current availability begins at macOS 26. HushKey currently supports macOS 14, so this cannot replace the existing compatibility path without raising the app's minimum OS or maintaining two generations of the Speech API. [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [WWDC25 on SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)

## Remaining evidence needed

Run a consented, locally stored sample set through Apple Speech and each downloadable WhisperKit model on the target M1 Pro. Record language, audio duration, first-run model download size/time, cold and warm inference time, peak memory, word error rate, and subtitle alignment. Until then, HushKey provides engine choice and does not claim one engine is more accurate or faster.
