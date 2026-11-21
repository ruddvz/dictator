# Current Speech Model Alternatives

## Which models have newer or stronger published results?

### Takeaway
The strongest current evidence does not support one universally best recognizer. For Dictator's local Mac workflow, the most relevant additions to benchmark are NVIDIA Nemotron 3.5 ASR Streaming 0.6B (native low-latency streaming) and Qwen3-ASR (broader language coverage and strong reported accuracy); Whisper large-v3 Turbo remains a practical WhisperKit option for file transcription. Keep the current default until these are measured on the same Dictator recordings and hardware.

### Cited Findings
- NVIDIA's Nov. 6, 2026 ASR table averages the same nine English Open ASR test sets: Nemotron Transcribe FP8 (4.78% WER), Qwen3-ASR-1.7B (4.94%), Parakeet TDT 0.6B v3 (5.58%), and Whisper large-v3 (6.66%). NVIDIA notes its Nemotron values were produced through its NIM HTTP API while other model results came from in-process leaderboard runs, so this is useful comparative evidence but not a perfectly matched deployment benchmark. These are offline transcript results, not live-dictation latency scores. [NVIDIA benchmark methodology and table](https://docs.nvidia.com/nim/speech/26.10.0/reference/performances/asr/performance.html)
- The much larger Nemotron 3.5 Transcribe model reports 4.71% mean WER on its nine-dataset English evaluation, but it is the 30B-A4B model; the model card documents 40 languages and code-switching examples. Treat it as an optional server/high-memory reference, not an assumed drop-in Mac default. [NVIDIA model card](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B)
- Qwen3-ASR ships 0.6B and 1.7B models, supports language detection and ASR across 30 languages plus 22 Chinese dialects, and documents offline and streaming inference. Its official implementation is Python/PyTorch with Transformers or vLLM; vLLM is not a native Swift/Apple-Neural-Engine integration. The repository is Apache-2.0. [Qwen3-ASR repository](https://github.com/QwenLM/Qwen3-ASR), [license](https://github.com/QwenLM/Qwen3-ASR/blob/main/LICENSE)
- NVIDIA's Nemotron 3.5 streaming model is a 0.6B cache-aware RNNT supporting 40 language locales and automatic language detection. NVIDIA's official NeMo-Speech.cpp supports this model, Parakeet TDT v3, and Parakeet CTC 1.1B, and provides Apple-Silicon Metal builds with GGUF quantization. This is the clearest new candidate for testing local partial transcription while the user speaks. The runtime is Apache-2.0; the model uses the separate OpenMDW-1.1 model license, whose distribution terms should be included if Dictator redistributes model materials. [NeMo-Speech.cpp models and runtime](https://github.com/NVIDIA/NeMo-Speech.cpp), [macOS Metal installation](https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/docs/install.md), [OpenMDW-1.1](https://openmdw.ai/license/1-1/)
- NVIDIA's published NeMo-Speech.cpp latency table for Nemotron Speech Streaming (English 0.6B) reports 27 ms per 160 ms chunk on an Intel i7 CPU and 2.3 ms on RTX 4090; its evaluation did not include an Apple-Silicon device. These figures are for the English Nemotron Speech Streaming model, not the 40-locale Nemotron 3.5 model, and should not be presented as Mac performance. [NVIDIA benchmark and test setup](https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/BENCHMARK.md)
- Moonshine Voice is a Swift-accessible on-device streaming alternative. Its current model page lists an English Medium Streaming model at 245M parameters and 6.65% WER, Small Streaming at 123M and 7.84%, and Tiny Streaming at 34M and 12.00%, using its Open ASR Leaderboard eight-dataset average. These results use a different dataset count from NVIDIA's nine-set results and are not directly rankable against them. Current streaming models are MIT-licensed; some older non-English non-streaming models use Moonshine Community License. [Moonshine model catalog and scoring notes](https://github.com/moonshine-ai/moonshine/blob/main/docs/models/available-models.md)
- Moonshine's changelog reports speculative streaming decoding lowering its own measured Medium-model finalization latency on a MacBook Pro from roughly 103 ms to 74 ms, while its benchmark documentation stresses that streaming does work during speech and is therefore not comparable to end-of-file Whisper latency. These are vendor measurements, not independent Dictator benchmarks. The general library is v0.1.6, while the separate Swift package's latest listed release is v0.1.5; verify SPM release compatibility before adopting it. [Moonshine changelog](https://github.com/moonshine-ai/moonshine/blob/main/CHANGELOGS.md), [benchmark methodology](https://github.com/moonshine-ai/moonshine/blob/main/docs/using/benchmarks.md), [Swift package releases](https://github.com/moonshine-ai/moonshine-swift/releases)
- Whisper's official repository says large-v3 Turbo has 809M parameters, approximately 6 GB required VRAM in its reference implementation, and about 8x relative speed versus large on an A100 with minimal accuracy degradation; the speed result is an A100 comparison, not a Mac result. Whisper's code and weights are MIT-licensed. Argmax's Swift SDK currently publishes compressed large-v3 Turbo / large-v3 models, and its v1.0.0 release renamed the package from WhisperKit to Argmax Open-Source SDK with breaking API changes. [OpenAI Whisper repository](https://github.com/openai/whisper), [Argmax Swift SDK model list](https://github.com/argmaxinc/argmax-oss-swift/blob/main/README.md), [Argmax v1.0.0 release](https://github.com/argmaxinc/argmax-oss-swift/releases)
- Canary-1B supports English, German, French, and Spanish ASR/translation, with NVIDIA-reported WER ranging from 3.06–7.97% across its MLS/Common Voice language test sets. Its model card requires NeMo/PyTorch and lists CC-BY-NC-4.0, making it a poor default for a commercial-capable Dictator distribution absent a license review. [Canary model card](https://huggingface.co/nvidia/canary-1b)

### Inferences
- A no-regression path is to add one optional experimental streaming engine, first Nemotron 3.5 Streaming or Moonshine, and compare it against Parakeet on the same recorded test set before changing defaults. Nemotron offers broader documented locale coverage; Moonshine appears to offer the shortest path to native Swift callbacks, but published WER and latency values need target-device validation.
- For English file transcription, Qwen3-ASR-1.7B and Nemotron Transcribe merit offline bake-offs; for a low-latency typing path, compare the smaller streaming models instead. Large 30B or 2.5B models should not be assumed suitable as the default local Mac engine based only on leaderboard rank.
- Model accuracy is only one layer of perceived text quality. Dictator should independently test proper names, Indian English accents, code-switching, punctuation, numbers, command words, and the safe-cleanup/correction pipeline, then report accuracy and latency per case rather than market a blanket “best” model.

### Gaps
- No cited result measures these models on Dictator's exact target Mac, microphone path, latency settings, or users' speech. In particular, NVIDIA's published NeMo-Speech.cpp benchmarks do not report Apple-Silicon measurements.
- No source establishes that Wispr Flow uses one publicly identifiable model; that proprietary-vendor question is covered separately.
- Quantized memory, model-download size, and battery impact vary by artifact and runtime. Measure the actual signed macOS build and supported Mac configurations before setting memory requirements or presenting download sizes.

## Which candidates are practical for Dictator on macOS?

### Takeaway
NVIDIA's current C++ runtime offers a credible local Metal route to new 0.6B streaming weights, while Moonshine has a Swift-facing package and small streaming models. Qwen3-ASR has compelling language and benchmark claims but requires more runtime integration work; WhisperKit/Argmax already provides the most direct file-transcription path in the current codebase.

### Cited Findings
- NVIDIA publishes a macOS Apple-Silicon Metal installer for NeMo-Speech.cpp and the runtime can pull GGUF model files; the documented model list includes Nemotron 3.5 Streaming 0.6B, English Nemotron Speech Streaming 0.6B, Parakeet TDT 0.6B v3, and Parakeet CTC 1.1B. [Installation](https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/docs/install.md), [model guide](https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/docs/asr/models.md)
- Moonshine's official quickstart shows Swift `MicTranscriber` callbacks and a macOS package; its release v0.1.6 includes macOS transcription example assets. [Swift quickstart](https://github.com/moonshine-ai/moonshine/blob/main/docs/quickstart.md), [latest library release](https://github.com/moonshine-ai/moonshine/releases)
- Qwen3-ASR's documented install is a Python 3.9+ `qwen-asr` package with Transformers or optional vLLM backend; model weights are 0.6B/1.7B, but official documentation does not provide a native Swift or Apple Neural Engine runtime. [Qwen3-ASR install and backend docs](https://github.com/QwenLM/Qwen3-ASR)
- Argmax Open-Source SDK v1.0.0 is Swift 6-compatible and provides WhisperKit models plus local transcription; that tag contains breaking API changes and renamed the package/umbrella products. [Release notes](https://github.com/argmaxinc/argmax-oss-swift/releases)

### Inferences
- Prototype Nemotron 3.5 streaming through the official runtime in a small isolated harness first; only then decide between vendoring/linking its runtime or taking the higher-maintenance Swift/FFI integration. Verify model notices and actual Mac CPU/Metal behavior; its own published streaming benchmark's hardware is not Apple Silicon.
- Evaluate Moonshine as the lower-friction Swift prototype for a clear live-preview experience, with current Dictator eval prompts and target Mac. Keep it optional if its quality is lower for the user's accents or vocabulary.
- Upgrade the existing Argmax dependency only as its own controlled change: the rename and API break can affect the currently working file-transcription flow, and a dependency update alone will not make Whisper transcription stream live.

### Gaps
- The official model/runtime pages do not establish the minimum Mac memory, sustained battery cost, or performance on the user's M-series Mac. These need direct measurement.
- No offline licensing audit has been done for converting/repackaging the specific model assets into Dictator's app. Check the exact model-card license and redistribution obligations for every selected artifact.

## How should Dictator keep model quality current?

### Takeaway
Track upstream releases, but upgrade by measured, reversible model releases rather than automatically swapping a production default whenever a new checkpoint appears.

### Cited Findings
- Hugging Face's Open ASR Leaderboard changelog was updated on 2026-11-20 and added new models; NVIDIA's NIM benchmark is updated 2026-11-06 and specifies its evaluation protocol. Leaderboards and vendor evaluation pages are moving targets, so record the date and exact model/runtime revisions with each comparison. [Open ASR leaderboard changelog](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard/blob/main/app.py), [NVIDIA benchmark](https://docs.nvidia.com/nim/speech/26.10.0/reference/performances/asr/performance.html)
- NVIDIA's own benchmark warns that per-dataset results and transcript normalization differ, and that model comparisons can vary by language, test set, and runtime. [NVIDIA ASR methodology](https://docs.nvidia.com/nim/speech/26.10.0/reference/performances/asr/performance.html)

### Inferences
- Maintain a small opt-in model evaluation suite built from user-consented, locally retained recordings plus scripted test phrases. Include each user's language/accent and Dictator-specific names; score WER/CER where appropriate, proper-noun recall, formatted text, finalization latency, peak RAM, CPU/ANE load, and energy. Pin model hashes, runtime commit, Mac model, and decoding settings so updates remain comparable.
- Review official model/runtime releases on a monthly cadence and add candidates to the evaluation harness; promote only when they improve a clearly defined quality/latency tradeoff without regressions or unacceptable license/privacy changes.
- Keep cloud ASR an explicit opt-in profile with clear data handling and cost disclosure; do not silently upload microphone audio as a quality fallback.

### Gaps
- No user recordings or ground-truth transcripts were supplied for a Dictator-specific benchmark, so the research cannot determine which model best recognizes this user's voice or terminology.
- This note does not create a recurring tracker or automation; it specifies a practical release-review cadence and measurement method.
