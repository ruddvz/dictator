# Current English speech model evidence

## What is the newest strong local model and runtime for Dictator?

### Takeaway
As of November 21, 2026, **Fluid Speech Pro (Core ML)** is the strongest new model candidate found for a current local Dictator integration: it is a November 2026 fine-tune of Parakeet v3/Ultra, has an Apple Neural Engine Core ML package, and reports strong English results. This is not the same as saying it is conclusively better than v2 or Ultra on the user's speech; the model owner has published relevant evaluation, but no Dictator-targeted, same-device comparison exists.

### Cited Findings
- The FluidSpeechPro model card says the weights were released in November 2026, are 0.63B parameters, use a FastConformer-TDT architecture based on Parakeet TDT v3 with one extra block, and are built on Parakeet v3 and Moondream Parakeet Ultra. It ranks #2 among open models on the Open ASR Leaderboard with 6.06 average WER across seven public and two private sets. [Fluid Speech Pro model card](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro)
- A separate Core ML conversion is published for Apple Silicon: 652 MB download, approximately 250 MB peak memory, Neural Engine execution, ~25 ms per 15-second window, and ~8 seconds first-load preparation followed by ~0.2 seconds subsequent loads on its tested M5 Max. It needs macOS 15+ and only reports testing on Mac so far. [Fluid Speech Pro Core ML card](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro-coreml)
- The Core ML card says its encoder uses 8-bit weights; in its comparison, this build produced 3.43 WER on 350 clips from seven sets, compared with 3.53 for the NeMo reference. 335 of 400 tested clips matched the reference exactly; its windowed FluidAudio processing versus full-clip NeMo processing accounts for many differences. The card says the leaderboard model's 6.06 average uses beam search, while this Core ML version is greedy and does not yet include clean mode. [Fluid Speech Pro Core ML card](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro-coreml)
- FluidAudio v0.18.4 is the latest official upstream release found on November 21. Parakeet Ultra is supported from v0.17.3, and v0.18.4 has ASR reliability fixes, but the Fluid Speech Pro Core ML card's Swift usage imports the **altic-dev/FluidAudio fork** and selects `.fluidParakeetPro`; it does not document use with the upstream v0.18.4 package. [FluidAudio latest release](https://github.com/FluidInference/FluidAudio/releases/latest), [Ultra release v0.17.3](https://github.com/FluidInference/FluidAudio/releases/tag/v0.17.3), [Fluid Speech Pro Core ML card](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro-coreml)
- FluidAudio's benchmark describes v2 as a little more accurate for English and reports 2.1% average WER on LibriSpeech test-clean. Its matched M5 Pro Neural Engine table reports Ultra 2.13%/3.81% WER on LibriSpeech clean/other versus v3 2.27%/4.12%, with similar RTFx; Ultra is ~630 MB. These vendor results use distinct tables/scorers from the Pro leaderboard results. [FluidAudio benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md), [Ultra details](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ParakeetUltra.md)

### Inferences
- If Dictator is constrained to upstream FluidAudio 0.18.4 with no dependency changes, Ultra is the most current directly supported Parakeet option. v2 is still the upstream guide's English accuracy recommendation, though it is an older checkpoint.
- If “latest and best English dictation now” permits adopting the newer FluidVoice conversion and its runtime support, Fluid Speech Pro is a better candidate to evaluate than raw v2/v3/Ultra. Its Core ML weights are a single ~652 MB model, so there is no need to ship or retain all candidates.
- For this user's English-only app, Dictator can restrict the Pro model to English even though upstream Pro supports 25 languages; unsupported locales should use Apple Speech.
- The current branch's proposed `ParakeetModel.englishUltra` enum would need to change if choosing Fluid Speech Pro, because the current package pins upstream FluidAudio and the Pro Core ML wrapper uses a fork-only model case.

### Gaps
- No benchmark compares Pro Core ML, Ultra Core ML, and v2 Core ML on the same Dictator clips and the user's target Mac. The very low Core ML-card WER is over 350 clips and is not directly comparable to leaderboard average WER.
- Pro's first-load and latency figures are vendor measurements on an M5 Max, not the user's Mac. A local installation test is required to establish memory, compilation time, and live dictation latency.
- No evidence here establishes that the Pro Core ML converter's model download/revision is pinned and integrity-checked in a production dependency path; Dictator must inspect the fork and pin a commit/model revision before adoption.

## How do the current Parakeet variants compare for English accuracy and speed?

### Takeaway
Ultra is a newer v3-family derivative and beats v3 in FluidAudio's matched Core ML benchmark, but it is **not proven to beat v2 for English**. The current evidence does not justify describing Ultra as the universally most accurate English model; it supports Ultra as the newest directly supported Parakeet choice and Fluid Speech Pro as the best recent candidate for additional evaluation.

### Cited Findings
- FluidAudio's current benchmark page explicitly says, “Use v2 if you only need English, it is a bit more accurate,” and reports v2's LibriSpeech test-clean average WER as 2.1%, overall RTFx 145.8x, on the published run. [FluidAudio benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- On FluidAudio's same M5 Pro/macOS 27/ANE test of the v3 family, Ultra beats v3 on LibriSpeech test-clean (2.13% vs 2.27%) and test-other (3.81% vs 4.12%), with 151× and 142× RTFx versus v3's 149–152× and 138×. The 60-minute Earnings-22 test reports Ultra at 13.5% WER and 457× versus v3 at 16.5% and 335×. [FluidAudio benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- Ultra's specification identifies it as Moondream post-training of NVIDIA v3 with the same architecture, tokenizer and 25-language contract, with an int8 encoder and macOS 14+ support. It is a derivative rather than a new NVIDIA Parakeet generation. [FluidAudio Parakeet Ultra documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ParakeetUltra.md)
- The official FluidAudio release page currently resolves to v0.18.4, released November 19; it includes ASR reliability fixes but no newer Parakeet checkpoint. [FluidAudio latest release](https://github.com/FluidInference/FluidAudio/releases/latest)

### Inferences
- “Newest” and “best English accuracy” are different selection rules. The upstream English-only quality guide favors v2, while the newer Ultra is better than v3 and remains near v3 speed; Fluid Speech Pro is a recent fine-tune that may provide better dictation-oriented results but has not been compared fairly to v2 on the same Core ML setup.
- To meet the user's current requirement without keeping multiple model caches, select only one production model. If choosing now, prioritize the newer Pro Core ML candidate for a short isolated integration test; if constrained to released upstream FluidAudio, choose Ultra and clearly state that v2 is still vendor-recommended for English accuracy.

### Gaps
- No fair three-way comparison for Pro/v2/Ultra on a single corpus, one device, identical decoder/normalizer, and the user's real accents, terms, noise, and short fragments.
- WER does not measure exact-once typing, first-word capture, end-of-speech delay, transient memory, warmup, or perceived quality; those need live target-device acceptance.

## Does Parakeet Unified offer a better English option in FluidAudio 0.18.4?

### Takeaway
Parakeet Unified is a first-party, English-only FastConformer-RNNT checkpoint with both native batch and streaming APIs already present in the exact FluidAudio 0.18.4 dependency. It is a particularly strong, low-friction candidate to test before adopting a fork for Fluid Speech Pro; the published full-set benchmark beats v3 in FluidAudio's shared harness, but does not directly settle whether Unified beats Ultra or v2.

### Cited Findings
- FluidAudio 0.18.4 includes the `parakeetUnified` model repository and both `UnifiedAsrManager` and `StreamingUnifiedAsrManager`; its Swift package supports macOS 14+. The v0.18.4 API takes a separate manager path rather than `AsrModelVersion`. [FluidAudio v0.18.4 model names](https://github.com/FluidInference/FluidAudio/blob/v0.18.4/Sources/FluidAudio/ModelNames.swift), [batch manager](https://github.com/FluidInference/FluidAudio/blob/v0.18.4/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedAsrManager.swift), [streaming manager](https://github.com/FluidInference/FluidAudio/blob/v0.18.4/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift), [package manifest](https://github.com/FluidInference/FluidAudio/blob/v0.18.4/Package.swift)
- The official model card identifies a ~0.6B parameter English-only FastConformer-RNNT model, with 16 kHz mono input, punctuation/capitalization, FP16 and an INT8 encoder option, CC-BY-4.0. FluidAudio source documents the default INT8 encoder as about 565 MB per encoder versus ~1.1 GB for FP16. [Parakeet Unified model card](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml), [FluidAudio Unified config at v0.18.4](https://github.com/FluidInference/FluidAudio/blob/v0.18.4/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedConfig.swift)
- FluidAudio's full LibriSpeech test-clean run on an M5 Pro/macOS 26 reports batch 2.16% mean-per-file WER / 1.68% aggregate WER / 143.6× overall real-time factor; its 2.08-second-latency streaming mode reports 2.21% / 1.79% / 65.9×. The model card also reports a 150-file streaming-tier sweep: 320 ms tier 2.37% aggregate WER, 640 ms 2.40%, 1120 ms 2.25%, and default 2080 ms 2.47%. [FluidAudio benchmark documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md), [Parakeet Unified model card](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml)
- On the same FluidAudio harness, its card compares Unified batch (2.16% mean WER, 144× overall RTFx, with punctuation) with Parakeet TDT v3 batch (2.6%, 110×, without punctuation). The docs say streaming re-encodes a 7.68-second window for each 1.04-second chunk, lowering full-recording throughput; batch overlaps only 2 seconds per window. [Parakeet Unified model card](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml), [FluidAudio benchmark documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- FluidAudio's model page warns that the INT8 Unified encoder is verified on M-series devices; it fails to load on the tested A16 iPhone even with a valid download, with FP16 as the documented workaround. [FluidAudio benchmark documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)

### Inferences
- Unified can be integrated on the current FluidAudio 0.18.4 pin without adding a new package or another model framework. It still needs an app adapter because the existing Dictator code wraps the TDT `AsrManager` API; switching recognizers is app-engine work, not just changing an enum value.
- If the goal includes visible partial words while talking, Unified is more relevant than Ultra's batch API. For a sensible latency/accuracy balance, the model card's 1120 ms tier has the best reported WER in its four-tier sweep, but its reported 1.12 seconds is model lookahead rather than a guarantee of end-to-end typed-text latency.
- A single streaming tier can be selected and downloaded; do not download all tiers. The full package contains multiple exports for different contexts, but a single app configuration can request only its chosen tier and shared decoder assets.
- These results do not establish a winner over Ultra/v2. Unified versus v3 is the explicit same-harness comparison; v2's ~2.1% figure appears on the same general test-clean suite but the docs do not show a paired run, while Ultra's 2.13% is corpus-level WER in a separate table. These should not be ranked as a definitive head-to-head.

### Gaps
- No FluidAudio table runs Unified, v2, v3 and Ultra back-to-back on the same target Mac with one scorer and the same utterance types.
- The latency-tier table is a 150-file sweep, while the full-corpus rows use all 2620 test-clean clips; their WER values are not identical evaluation samples.
- Published M5 Pro/Mac results may not match Dictator's target Mac, accents or focus/insertion path. A live Dictator adapter test and short-phrase/technical-vocabulary benchmark are still required.
