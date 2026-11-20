# Parakeet and FluidAudio model versions

## What is the newest Parakeet, and what does Dictator currently use?

### Takeaway
As of 20 November 2026, NVIDIA’s NeMo catalog still lists Parakeet TDT 0.6B v3 as its current multilingual 0.6B TDT model; I found no NVIDIA-published Parakeet v4. Newer FluidAudio-compatible derivatives exist: Parakeet Ultra is the strongest accuracy candidate, while Redux trades accuracy on English for a much smaller download.

### Cited Findings
- NVIDIA’s current NeMo model catalog lists TDT 0.6B v3 and v2, English 1.1B TDT/TDT-CTC/RNN-T/CTC models, Japanese and Vietnamese models, plus a 120M streaming EOU model; the featured-model overview calls v3 the 25-language model and v2 English-only. [NeMo checkpoints](https://docs.nvidia.com/nemo/speech/nightly/asr/asr_checkpoints.html), [featured models](https://docs.nvidia.com/nemo/speech/nightly/asr/featured_models.html)
- NVIDIA’s v3 model card says it auto-detects and transcribes 25 European languages, adds punctuation/capitalization and word/segment timestamps, and is CC-BY-4.0. [NVIDIA Parakeet TDT 0.6B v3 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- FluidAudio’s latest GitHub release as of the research date is v0.18.4, released November 19. Its release notes highlight Neural Engine fixes for Nemotron streaming on M2/M3, not a new Parakeet checkpoint. Dictator pins FluidAudio 0.18.2. [FluidAudio releases](https://github.com/FluidInference/FluidAudio/releases)
- FluidAudio added Parakeet Ultra and Redux in v0.17.3. Ultra is a post-trained v3-derived checkpoint with the same architecture/tokenizer/output conventions; Redux is a 2-bit ternary v3-derived checkpoint. They are community model derivatives, not new NVIDIA Parakeet releases. [v0.17.3 release](https://github.com/FluidInference/FluidAudio/releases/tag/v0.17.3), [Ultra model card](https://huggingface.co/moondream/parakeet-ultra), [Redux Core ML card](https://huggingface.co/FluidInference/parakeet-redux-coreml)
- FluidAudio’s current model guide marks Ultra as its recommended 25-language model, v3 as the multilingual default, Redux as the smallest download (~220 MB, macOS 15+/iOS 18+), and v2 as English-only with highest recall. Its quick start uses `AsrModels.downloadAndLoad(version: .ultra)`. [FluidAudio README](https://github.com/FluidInference/FluidAudio/blob/main/README.md)

### Inferences
- Dictator already offers NVIDIA v2 for English and NVIDIA v3 for its supported multilingual route. Adding Ultra can be an optional model choice without removing either existing model; the SDK API exists since FluidAudio v0.17.3, so the app’s 0.18.2 pin is not itself a blocker for Ultra.
- Updating FluidAudio to 0.18.4 is worth a separate compatibility review, but the latest release notes do not show a Parakeet TDT accuracy or speed improvement. Version currency alone is not evidence that dictation output will improve.

### Gaps
- NVIDIA’s catalog is a rolling “nightly” page and does not give a dated announcement proving no unreleased/newer checkpoint exists; repository/model-card state was checked on 20 November 2026.
- NVIDIA benchmark comparisons vary by model-card version and evaluation harness. Do not compare their raw leaderboard averages directly with FluidAudio’s Core ML benchmark numbers.

## Do the newer variants improve accuracy on Apple Silicon?

### Takeaway
FluidAudio reports that Ultra improves on v3 accuracy while staying near v3 speed on its M5 Pro Core ML tests. That makes Ultra the clearest candidate for a local A/B evaluation, but the published tests do not compare it against Dictator’s current English v2 on Dictator’s own speech samples.

### Cited Findings
- On FluidAudio’s M-series Mac full-corpus tests, v3 vs Ultra WER was 2.27% vs 2.13% on LibriSpeech test-clean, 4.12% vs 3.81% on test-other, and 14.81% vs 11.67% averaged across 24 FLEURS languages. It reports similar short-clip speed (about 149–152× vs 151× real-time factor) and faster 60-minute processing for Ultra (457× vs 335×); these are FluidAudio’s own benchmarks on an M5 Pro/macOS 27. [FluidAudio benchmark notes](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md), [Ultra accuracy details](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ParakeetUltra.md)
- The Ultra Core ML model is ~630 MB overall, uses an int8 encoder, supports macOS 14+, and has the same 25-language contract as v3. [FluidAudio Ultra model card](https://huggingface.co/FluidInference/parakeet-ultra-coreml)
- Redux is about 220 MB and supports 25 languages, but FluidAudio’s same-test WER is worse than v3 on English LibriSpeech (2.71% vs 2.27% clean; 5.12% vs 4.12% other). Its model notes report several minutes of first-time ANE compilation, followed by warm inference around 45–52 ms per 15-second window. [Redux Core ML card](https://huggingface.co/FluidInference/parakeet-redux-coreml), [FluidAudio Ultra/Redux benchmark](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ParakeetUltra.md)
- Moondream’s model-card evaluation also reports Ultra ahead of v3 on seven English leaderboard sets (5.80% vs 6.26% average WER), FLEURS (9.55% vs 11.62%), noisy audio (5.82% vs 6.72%), and TED-LIUM long-form (1.94% vs 2.71%). Those numbers use Photon on NVIDIA GPUs for Ultra and NeMo for the original, so they are not a Mac deployment benchmark. [Moondream Ultra model card](https://huggingface.co/moondream/parakeet-ultra)
- NVIDIA’s v2 card reports 6.05% average WER across its listed English Open-ASR-Leaderboard sets and flags that its accuracy can vary on incomplete sentences/word-for-word fragments. This score is not directly comparable with the separate Ultra results without harmonizing evaluation details. [NVIDIA v2 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)

### Inferences
- Best next step: keep v2 as the English default until Dictator’s own holdout and live-speech evaluation shows Ultra is better; expose Ultra as an optional “higher accuracy / multilingual” candidate and test it without overwriting the known-good engine.
- Do not ship Redux as the accuracy default. It is a storage-footprint option, not the strongest measured transcription option.
- Evaluate on the target Mac and real Dictator samples: spontaneous short phrases, names, technical vocabulary, quiet speech, noisy rooms, code-switching, and the exact dictation cleanup path. Record WER/CER, insertion/deletion/substitution errors, first-use compile time, warm latency, and memory. Keep the recorded audio local and opt-in.

### Gaps
- No fair head-to-head benchmark was found comparing Dictator’s v2 vs v3 vs Ultra with Dictator’s sample set, post-processing, and target Mac.
- The FluidAudio benchmark uses an M5 Pro/macOS 27, which may not match the user’s device or OS; results should not be promised as user-device performance.

## What other current FluidAudio/NVIDIA candidates are relevant?

### Takeaway
For live partial text, streaming-specific models matter more than swapping the batch Parakeet checkpoint. NVIDIA/FluidAudio now list multilingual Nemotron streaming and meeting-oriented transcription options; they are separate integration projects and should be evaluated after the app’s stable dictation route.

### Cited Findings
- NVIDIA’s NeMo guide lists Nemotron 3.5 ASR Streaming 0.6B (40 languages; controllable 80 ms–1 s latency) and Multitalker Parakeet Streaming 0.6B (English, multiple speakers) separately from batch Parakeet TDT. [NVIDIA model choice guide](https://docs.nvidia.com/nemo/speech/nightly/starthere/choosing_a_model.html), [ASR checkpoint list](https://docs.nvidia.com/nemo/speech/nightly/asr/asr_checkpoints.html)
- FluidAudio v0.18.0 added Nemotron Unified ASR 0.6B for 25 European languages with offline and streaming modes and documented 0.56/1.12/2.08-second latency presets; its release notes also describe a separate Nemotron 3.5 Transcribe Lite encoder/CTC pipeline with word timing and diarization. [FluidAudio v0.18.0 release](https://github.com/FluidInference/FluidAudio/releases/tag/v0.18.0)
- FluidAudio v0.18.4 changed Nemotron streaming encoder bundles so M2/M3 Neural Engines can compile/run the encoders instead of silently falling back to CPU; the release says an M2 Pro’s first load went from 311 seconds to 12 seconds. This is specific to Nemotron’s streaming path. [FluidAudio v0.18.4 release](https://github.com/FluidInference/FluidAudio/releases/tag/v0.18.4)

### Inferences
- If the product goal is live words while speaking, prototype an opt-in streaming engine separately and benchmark interim-token stability, latency, battery, and CPU/ANE routing. A faster batch model will not by itself make interim text stream.
- Avoid pulling in all newer models at once. Each adds download size, cold compilation, model-selection complexity, and a distinct quality/support matrix.

### Gaps
- The sources do not establish which model will outperform the current Parakeet engine on Dictator’s real-time mic input, target Mac, or languages the user dictates. That requires on-device acceptance testing.
